import Foundation
import AppKit

/// Dead-simple auto-update against GitHub Releases: check the latest release,
/// and if it's newer than this build, offer a one-click download-and-swap. No
/// Sparkle, no appcast, no signing infrastructure — the app downloads the
/// prebuilt `.app` zip itself (so macOS doesn't quarantine it) and a tiny
/// detached script swaps it in after we quit.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let repo = "kevinhufnagl/betterbob"

    struct Release: Equatable {
        let version: String        // e.g. "1.1"
        let notes: String
        let zipURL: URL
        let pageURL: URL
    }

    enum Phase: Equatable {
        case idle, checking, downloading, installing, upToDate
        case failed(String)
    }

    @Published private(set) var available: Release?
    @Published private(set) var phase: Phase = .idle

    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Newer strictly by numeric version components ("v" prefix tolerated), so
    /// 1.10 > 1.9 (not a lexical compare).
    nonisolated static func isNewer(_ remote: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let r = parts(remote), c = parts(current)
        for i in 0..<max(r.count, c.count) {
            let a = i < r.count ? r[i] : 0
            let b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: - Checking

    func start() {
        Task { await checkNow() }
        // A daily check is plenty; the unauthenticated GitHub API allows 60/hr.
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { await self?.checkNow() }
        }
    }

    func checkNow() async {
        if case .downloading = phase { return }
        if case .installing = phase { return }
        phase = .checking
        do {
            let release = try await fetchLatest()
            if let release, Self.isNewer(release.version, than: currentVersion) {
                available = release
                phase = .idle
                Notifier.updateAvailable(version: release.version)
            } else {
                available = nil
                phase = .upToDate
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func fetchLatest() async throws -> Release? {
        let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        // 404 = no releases yet; treat as "up to date", not an error.
        if let http = resp as? HTTPURLResponse, http.statusCode == 404 { return nil }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = root["tag_name"] as? String else { return nil }
        let page = (root["html_url"] as? String).flatMap(URL.init) ?? URL(string: "https://github.com/\(Self.repo)/releases")!
        let assets = (root["assets"] as? [[String: Any]]) ?? []
        let zip = assets.compactMap { $0["browser_download_url"] as? String }
            .first { $0.lowercased().hasSuffix(".zip") }
            .flatMap(URL.init)
        guard let zip else { return nil }   // a release with no .app zip is not installable
        return Release(version: tag, notes: root["body"] as? String ?? "", zipURL: zip, pageURL: page)
    }

    // MARK: - Install (download → unzip → swap → relaunch)

    func install() {
        guard let release = available else { return }
        phase = .downloading
        Task {
            do {
                try await downloadAndSwap(release)
                // downloadAndSwap terminates the app on success; we won't get here.
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func openReleasePage() {
        if let url = available?.pageURL { NSWorkspace.shared.open(url) }
    }

    /// Hide the banner until the next check (this session).
    /// Version the user dismissed from the popover banner. That exact version
    /// stays hidden (in the popover — Settings still shows it) until a newer
    /// release appears or it gets installed.
    @Published private(set) var dismissedVersion: String? =
        UserDefaults.standard.string(forKey: "dismissedUpdateVersion")

    func dismiss(_ release: Release) {
        UserDefaults.standard.set(release.version, forKey: "dismissedUpdateVersion")
        dismissedVersion = release.version
    }

    private func downloadAndSwap(_ release: Release) async throws {
        let fm = FileManager.default
        // 1. Download the zip.
        let (tmpZip, _) = try await URLSession.shared.download(from: release.zipURL)
        let work = fm.temporaryDirectory.appendingPathComponent("betterbob-update-\(release.version)", isDirectory: true)
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("update.zip")
        try fm.moveItem(at: tmpZip, to: zip)

        phase = .installing
        // 2. Unzip with ditto (preserves the bundle + its ad-hoc signature).
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        guard let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw NSError(domain: "Updater", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No .app found in the update."])
        }

        // 3. Write a detached swap script that waits for us to quit, replaces the
        //    installed bundle, and relaunches it.
        let target = Bundle.main.bundlePath
        let script = work.appendingPathComponent("swap.sh")
        let body = """
        #!/bin/bash
        trap '' HUP
        PID="$1"; NEW="$2"; TARGET="$3"
        while /bin/kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        sleep 0.3
        /bin/rm -rf "$TARGET"
        /usr/bin/ditto "$NEW" "$TARGET"
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
        /usr/bin/open "$TARGET"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try run("/bin/chmod", ["+x", script.path])

        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path, pid, newApp.path, target]
        try p.run()   // survives our termination (reparented to launchd)

        // 4. Quit so the script can replace us.
        NSApp.terminate(nil)
    }

    private func run(_ launchPath: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(domain: "Updater", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(launchPath) failed (\(p.terminationStatus))."])
        }
    }
}
