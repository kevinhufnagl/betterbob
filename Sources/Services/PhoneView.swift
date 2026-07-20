import Foundation
import Combine
import SystemConfiguration

// App-side glue for the phone stats page: watches the Settings toggle and
// token, runs the StatsServer while enabled, and snapshots BobState for it.
// Kept out of StatsServer.swift so the server stays compilable standalone.

@MainActor
final class PhoneView: ObservableObject {
    static let shared = PhoneView()

    @Published private(set) var running = false
    @Published private(set) var port: UInt16?
    private var server: StatsServer?
    private var cancellables = Set<AnyCancellable>()

    /// Start observing prefs; the server itself only runs while enabled.
    func start() {
        Prefs.shared.$phoneViewEnabled
            .combineLatest(Prefs.shared.$phoneViewToken)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .sink { [weak self] enabled, token in self?.apply(enabled: enabled, token: token) }
            .store(in: &cancellables)
    }

    /// The URL the QR code carries — Bonjour hostname, so no IP hunting.
    var url: String? {
        guard running, let port else { return nil }
        return "http://\(LocalNet.hostName()):\(port)/\(Prefs.shared.phoneViewToken)"
    }

    /// Numeric fallback for phones that don't resolve .local names.
    var ipURL: String? {
        guard running, let port, let ip = LocalNet.ipv4() else { return nil }
        return "http://\(ip):\(port)/\(Prefs.shared.phoneViewToken)"
    }

    private func apply(enabled: Bool, token: String) {
        guard enabled, !token.isEmpty else {
            server?.stop()
            server = nil
            running = false
            port = nil
            return
        }
        // "New link" is just a token swap on the live listener — restarting
        // would race the old socket's teardown and lose the stable port.
        if let server {
            server.updateToken(token)
            return
        }
        // The action handler re-checks the pref on every call, so flipping
        // "allow actions" applies instantly without a server restart.
        let server = StatsServer(token: token,
                                 provider: { PhoneView.snapshot() },
                                 onAction: { PhoneView.perform($0) })
        server.onStateChange = { [weak self] running, port in
            self?.running = running
            self?.port = port
        }
        server.start()
        self.server = server
    }

    /// Runs a phone-initiated punch through the exact same BobState calls the
    /// popover buttons use. Returns false when actions are switched off.
    static func perform(_ action: String) -> Bool {
        guard Prefs.shared.phoneViewActionsEnabled else { return false }
        let state = BobState.shared
        switch action {
        case "clockIn": state.clockIn()
        case "clockOut": state.clockOut()
        case "startBreak": state.startManualBreak()
        case "endBreak": state.endBreak()
        default: return false
        }
        return true
    }

    private static func stateName(_ s: ClockState) -> String {
        switch s {
        case .working: return "working"
        case .onBreak: return "break"
        case .clockedOut: return "out"
        }
    }

    /// Same numbers the Today pane shows, flattened for the page.
    static func snapshot() -> StatsSnapshot {
        let state = BobState.shared
        let now = Date()
        let v = TodayVals(state, now: now)
        return StatsSnapshot(
            name: state.profile?.name.split(separator: " ").first.map(String.init) ?? "",
            state: stateName(state.clockState),
            projected: stateName(state.projectedClockState),
            actionsEnabled: Prefs.shared.phoneViewActionsEnabled,
            workedSeconds: Int(v.worked),
            asOf: Int(now.timeIntervalSince1970),
            targetSeconds: Int(v.targetSecs),
            breakSeconds: Int(v.breakTotal),
            breakEndsAt: state.autoBreakEnds.map { Int($0.timeIntervalSince1970) },
            entries: state.entries.map { e in
                StatsSnapshot.Entry(kind: e.kind == .breakTime ? "break" : "work",
                                    start: Int(e.start.timeIntervalSince1970),
                                    end: e.end.map { Int($0.timeIntervalSince1970) })
            })
    }
}

enum LocalNet {
    /// "kevins-macbook-pro.local" — mDNS name every iPhone resolves.
    static func hostName() -> String {
        if let name = SCDynamicStoreCopyLocalHostName(nil) as String? {
            return name.lowercased() + ".local"
        }
        let host = ProcessInfo.processInfo.hostName.lowercased()
        return host.hasSuffix(".local") ? host : host + ".local"
    }

    /// The Mac's LAN IPv4, preferring Wi-Fi/Ethernet (en0) over the rest.
    static func ipv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var fallback: String?
        var cursor = list
        while let p = cursor {
            defer { cursor = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if String(cString: p.pointee.ifa_name) == "en0" { return ip }
            if fallback == nil { fallback = ip }
        }
        return fallback
    }
}
