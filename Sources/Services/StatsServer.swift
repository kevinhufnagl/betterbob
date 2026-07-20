import Foundation
import Network

// A tiny local-network HTTP server for the phone stats page. Deliberately
// self-contained (Foundation + Network only, no app types beyond the snapshot
// it serves) so it can be compiled standalone with a fake provider and
// exercised with curl — the app itself is never launched to verify it.

/// Everything the phone page needs, captured on the main actor at request
/// time. Times are epoch seconds; the page extrapolates the ticking counter
/// from `asOf` so phone-clock drift doesn't matter.
struct StatsSnapshot {
    var name: String
    /// "working" | "break" | "out"
    var state: String
    /// State after queued punches — drives which buttons the page offers,
    /// same as the popover's projectedClockState.
    var projected: String
    /// Whether the page may offer clock in/out/break buttons.
    var actionsEnabled: Bool
    var workedSeconds: Int
    var asOf: Int
    var targetSeconds: Int
    var breakSeconds: Int
    var breakEndsAt: Int?
    var entries: [Entry]

    struct Entry {
        var kind: String   // "work" | "break"
        var start: Int
        var end: Int?
    }
}

/// Pure HTTP plumbing — parseable, routable, encodable without a socket in
/// sight, so Tests/main.swift can cover it.
enum StatsHTTP {
    /// Method and path of a request head ("GET /x?q=1 HTTP/1.1…" →
    /// ("GET", "/x")). Anything malformed returns nil.
    static func requestLine(_ head: String) -> (method: String, path: String)? {
        guard let line = head.split(separator: "\r\n", omittingEmptySubsequences: false).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        return (String(parts[0]), String(parts[1].prefix(while: { $0 != "?" && $0 != "#" })))
    }

    enum Route: Equatable { case page, json, action(String), notFound }

    /// The token is the whole access control: no token match, no content —
    /// and no hint that anything lives here. Actions are POST-only so a
    /// pasted link or a browser prefetch can never punch the clock.
    static func route(method: String, path: String, token: String) -> Route {
        guard !token.isEmpty else { return .notFound }
        var p = path
        while p.hasSuffix("/") && p.count > 1 { p.removeLast() }
        if method == "GET" {
            if p == "/\(token)" { return .page }
            if p == "/\(token)/stats.json" { return .json }
        }
        if method == "POST", p.hasPrefix("/\(token)/action/") {
            let name = String(p.dropFirst("/\(token)/action/".count))
            if !name.isEmpty && !name.contains("/") { return .action(name) }
        }
        return .notFound
    }

    static func jsonEscape(_ s: String) -> String {
        var out = ""
        for c in s.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if c.value < 0x20 { out += String(format: "\\u%04x", c.value) }
                else { out.unicodeScalars.append(c) }
            }
        }
        return out
    }

    static func json(_ s: StatsSnapshot) -> String {
        let entries = s.entries.map { e in
            "{\"kind\":\"\(jsonEscape(e.kind))\",\"start\":\(e.start),\"end\":\(e.end.map(String.init) ?? "null")}"
        }.joined(separator: ",")
        return "{\"name\":\"\(jsonEscape(s.name))\",\"state\":\"\(jsonEscape(s.state))\","
            + "\"projected\":\"\(jsonEscape(s.projected))\",\"actions\":\(s.actionsEnabled),"
            + "\"worked\":\(s.workedSeconds),\"asOf\":\(s.asOf),\"target\":\(s.targetSeconds),"
            + "\"breakTotal\":\(s.breakSeconds),\"breakEndsAt\":\(s.breakEndsAt.map(String.init) ?? "null"),"
            + "\"entries\":[\(entries)]}"
    }

    static func response(status: String, contentType: String, body: Data) -> Data {
        let head = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\n"
            + "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

/// The listener. One short-lived connection per request (Connection: close) —
/// at phone-page traffic volumes there is nothing to keep alive.
final class StatsServer {
    /// Read on the connection queue; change it via updateToken(_:).
    private(set) var token: String
    private let provider: @MainActor () -> StatsSnapshot
    /// Performs a clock action ("clockIn", …) and reports acceptance. Nil, or
    /// returning false, means actions are off — the page gets a 403.
    private let onAction: (@MainActor (String) -> Bool)?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "betterbob.stats-server")
    /// Called on the main queue with (running, boundPort).
    var onStateChange: ((Bool, UInt16?) -> Void)?

    init(token: String,
         provider: @escaping @MainActor () -> StatsSnapshot,
         onAction: (@MainActor (String) -> Bool)? = nil) {
        self.token = token
        self.provider = provider
        self.onAction = onAction
    }

    /// Swap the URL token without touching the listener — the port stays put
    /// and old links 404 immediately. Used by Settings' "New link".
    func updateToken(_ new: String) {
        queue.async { self.token = new }
    }

    func start(preferredPort: UInt16 = 4747) {
        // Attempts 0–1 bind the preferred port (a rebind right after a stop
        // can fail while the old socket tears down, hence one delayed retry);
        // attempt 2 takes any free port — better than not starting at all.
        // A taken port only shows up as .failed *after* start, never at init.
        startListener(preferred: preferredPort, attempt: 0)
    }

    private func startListener(preferred: UInt16, attempt: Int) {
        stop()
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = attempt < 2
            ? NWEndpoint.Port(rawValue: preferred).flatMap { try? NWListener(using: params, on: $0) }
            : (try? NWListener(using: params))
        guard let listener else {
            DispatchQueue.main.async { self.onStateChange?(false, nil) }
            return
        }
        listener.stateUpdateHandler = { [weak self] state in
            let report: Bool?
            switch state {
            case .ready: report = true
            case .failed, .cancelled: report = false
            default: report = nil
            }
            guard let report else { return }
            let boundPort = listener.port?.rawValue
            DispatchQueue.main.async { [weak self] in
                // Reports from a superseded listener (async .cancelled after a
                // restart) must not clobber the current one's state.
                guard let self, self.listener === listener else { return }
                if !report && attempt < 2 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.4 : 0)) {
                        guard self.listener === listener else { return }  // stopped meanwhile
                        self.startListener(preferred: preferred, attempt: attempt + 1)
                    }
                } else {
                    self.onStateChange?(report, report ? boundPort : nil)
                }
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        // Detach the handler (also breaks the listener↔handler retain cycle),
        // then nil `listener` so any in-flight report fails the identity
        // check in the state handler. onStateChange stays — start() re-arms.
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveHead(conn, buffer: Data())
    }

    /// Collect until the header terminator; GETs are tiny so this is usually
    /// a single receive. Hard 16 KB cap against garbage.
    private func receiveHead(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf += data }
            if error != nil || buf.count > 16384 { conn.cancel(); return }
            if buf.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(conn, head: String(decoding: buf, as: UTF8.self))
            } else if complete {
                conn.cancel()
            } else {
                self.receiveHead(conn, buffer: buf)
            }
        }
    }

    private func respond(_ conn: NWConnection, head: String) {
        guard let (method, path) = StatsHTTP.requestLine(head) else {
            send(conn, StatsHTTP.response(status: "400 Bad Request",
                                          contentType: "text/plain", body: Data("Bad request".utf8)))
            return
        }
        switch StatsHTTP.route(method: method, path: path, token: token) {
        case .page:
            send(conn, StatsHTTP.response(status: "200 OK",
                                          contentType: "text/html; charset=utf-8",
                                          body: Data(StatsPage.html.utf8)))
        case .json:
            sendSnapshot(conn)
        case .action(let name):
            guard let onAction else {
                send(conn, StatsHTTP.response(status: "403 Forbidden",
                                              contentType: "text/plain", body: Data("Actions disabled".utf8)))
                return
            }
            Task { @MainActor in
                let accepted = onAction(name)
                if accepted {
                    // Fresh snapshot straight back, so the page updates
                    // without waiting for the next poll.
                    self.sendSnapshot(conn)
                } else {
                    self.queue.async {
                        self.send(conn, StatsHTTP.response(status: "403 Forbidden",
                                                           contentType: "text/plain",
                                                           body: Data("Actions disabled".utf8)))
                    }
                }
            }
        case .notFound:
            send(conn, StatsHTTP.response(status: "404 Not Found",
                                          contentType: "text/plain", body: Data("Not found".utf8)))
        }
    }

    private func sendSnapshot(_ conn: NWConnection) {
        let provider = provider
        Task { @MainActor in
            let body = StatsHTTP.json(provider())
            self.queue.async {
                self.send(conn, StatsHTTP.response(status: "200 OK",
                                                   contentType: "application/json",
                                                   body: Data(body.utf8)))
            }
        }
    }

    private func send(_ conn: NWConnection, _ data: Data) {
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }
}
