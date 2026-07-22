import Foundation
import AppKit

/// Dead-simple auto-update against GitHub Releases: check the latest release,
/// and if it's newer than this build, silently download it and swap the new
/// bundle onto disk while we keep running — the running process keeps its
/// loaded image, so nothing restarts and the new version simply runs on the
/// next launch. No Sparkle, no appcast, no signing infrastructure — the app
/// downloads the prebuilt `.app` zip itself (so macOS doesn't quarantine it).
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

    /// The release that has been swapped onto disk and applies on next launch.
    @Published private(set) var installed: Release?
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
        // Every 2 hours — 12 checks/day, well inside the unauthenticated
        // GitHub API limit of 60/hr.
        timer = Timer.scheduledTimer(withTimeInterval: 2 * 3600, repeats: true) { [weak self] _ in
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
                // Already swapped onto disk? Nothing to redo until something newer.
                if let installed, !Self.isNewer(release.version, than: installed.version) {
                    phase = .upToDate
                    return
                }
                try await downloadAndInstall(release)
                installed = release
                phase = .upToDate
                if Prefs.shared.notifyAppUpdate {
                    Notifier.updateInstalled(version: release.version)
                }
            } else {
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

    // MARK: - Install (download → unzip → swap in place)

    func openReleasePage() {
        if let url = installed?.pageURL { NSWorkspace.shared.open(url) }
    }

    /// Version whose "restart to apply" banner the user dismissed from the
    /// popover. That exact version stays hidden (in the popover — Settings
    /// still shows it) until a newer release lands or the app restarts.
    @Published private(set) var dismissedVersion: String? =
        UserDefaults.standard.string(forKey: "dismissedUpdateVersion")

    func dismiss(_ release: Release) {
        UserDefaults.standard.set(release.version, forKey: "dismissedUpdateVersion")
        dismissedVersion = release.version
    }

    /// Quit and reopen the (already swapped) bundle so the new version starts.
    func relaunch() {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("betterbob-relaunch.sh")
        let body = """
        #!/bin/bash
        trap '' HUP
        PID="$1"; TARGET="$2"
        while /bin/kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        sleep 0.3
        /usr/bin/open "$TARGET"
        """
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try run("/bin/chmod", ["+x", script.path])
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script.path,
                           String(ProcessInfo.processInfo.processIdentifier),
                           Bundle.main.bundlePath]
            try p.run()   // survives our termination (reparented to launchd)
            NSApp.terminate(nil)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func downloadAndInstall(_ release: Release) async throws {
        let fm = FileManager.default
        phase = .downloading
        // 1. Download the zip.
        let (tmpZip, _) = try await URLSession.shared.download(from: release.zipURL)
        let work = fm.temporaryDirectory.appendingPathComponent("betterbob-update-\(release.version)", isDirectory: true)
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("update.zip")
        try fm.moveItem(at: tmpZip, to: zip)

        phase = .installing
        // 2. Unzip with ditto (preserves the bundle + its signature — that
        //    signature stability is what keeps Keychain/Location grants alive).
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        guard let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw NSError(domain: "Updater", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No .app found in the update."])
        }

        // 3. Swap the bundle on disk while we keep running: move the current
        //    bundle aside, move the new one into its place, and roll back if
        //    that second move fails so the app never vanishes from disk.
        let target = URL(fileURLWithPath: Bundle.main.bundlePath)
        let old = work.appendingPathComponent("old.app")
        try fm.moveItem(at: target, to: old)
        do {
            try fm.moveItem(at: newApp, to: target)
        } catch {
            try? fm.moveItem(at: old, to: target)
            throw error
        }
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])
        // Keep old.app around (the running process may still fault in pages
        // from it); the system clears the temp dir on its own. Just drop the zip.
        try? fm.removeItem(at: zip)
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
