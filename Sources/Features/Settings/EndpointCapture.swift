import AppKit
import WebKit

/// Developer tool: drives the already-authenticated embedded browser through
/// the attendance page and records every API call the HiBob SPA makes —
/// method, URL, request body, and response body — so the real endpoints and
/// JSON shapes can be pinned in BobAPI/BobParsing. Captures traffic only;
/// never reads cookies or auth headers. Output is written to
/// ~/Desktop/betterbob-endpoints.json for inspection.
@MainActor
final class EndpointCaptureController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = EndpointCaptureController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var captured: [[String: Any]] = []

    private static let hookJS = """
    (function () {
      function post(rec) {
        try { window.webkit.messageHandlers.capture.postMessage(rec); } catch (e) {}
      }
      function interesting(url) { return url.indexOf('/api/') !== -1; }

      function headersToObj(h) {
        const o = {};
        try {
          if (!h) return o;
          if (h.forEach) { h.forEach((v, k) => { o[k] = v; }); return o; }
          if (Array.isArray(h)) { h.forEach(p => { o[p[0]] = p[1]; }); return o; }
          for (const k in h) { o[k] = h[k]; }
        } catch (e) {}
        return o;
      }

      const origFetch = window.fetch;
      window.fetch = async function (input, init) {
        const url = (typeof input === 'string') ? input : input.url;
        const method = (init && init.method) || (input && input.method) || 'GET';
        const reqBody = (init && init.body) ? String(init.body) : null;
        const reqHeaders = headersToObj(init && init.headers);
        const res = await origFetch.apply(this, arguments);
        if (interesting(url)) {
          let body = '';
          try { body = await res.clone().text(); } catch (e) {}
          post({ via: 'fetch', method: method, url: url, status: res.status,
                 requestHeaders: reqHeaders,
                 requestBody: reqBody, responseBody: body.slice(0, 400000) });
        }
        return res;
      };

      const origOpen = XMLHttpRequest.prototype.open;
      const origSend = XMLHttpRequest.prototype.send;
      const origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__cap = { method: method, url: url, requestHeaders: {} };
        return origOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.setRequestHeader = function (k, v) {
        if (this.__cap) this.__cap.requestHeaders[k] = v;
        return origSetHeader.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function (body) {
        const xhr = this;
        if (xhr.__cap) {
          xhr.__cap.requestBody = body ? String(body) : null;
          xhr.addEventListener('load', function () {
            if (interesting(xhr.__cap.url)) {
              post({ via: 'xhr', method: xhr.__cap.method, url: xhr.__cap.url,
                     status: xhr.status, requestHeaders: xhr.__cap.requestHeaders,
                     requestBody: xhr.__cap.requestBody,
                     responseBody: (xhr.responseText || '').slice(0, 400000) });
            }
          });
        }
        return origSend.apply(this, arguments);
      };
    })();
    """

    func present() {
        captured.removeAll()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // reuse the signed-in session

        let userContent = WKUserContentController()
        userContent.add(self, name: "capture")
        userContent.addUserScript(WKUserScript(
            source: Self.hookJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false))
        config.userContentController = userContent

        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 720),
                            configuration: config)
        web.navigationDelegate = self

        let win = NSWindow(contentRect: web.frame,
                           styleMask: [.titled, .closable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Capturing HiBob endpoints — click around the attendance page, then close"
        win.contentView = web
        win.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dump() }
        }
        window = win
        webView = web

        web.load(URLRequest(url: URL(string: "https://app.hibob.com/attendance/my-attendance")!))
        // After the attendance page has fired its calls, visit the time-off
        // page too so its balance endpoints get captured in the same run.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak web] in
            web?.load(URLRequest(url: URL(string: "https://app.hibob.com/time-off/my-time-off")!))
        }
        NSApp.setActivationPolicy(.regular)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        captured.append(dict)
        dump() // incremental — readable while the window is still open
    }

    private func dump() {
        let jsonPath = ("~/Desktop/betterbob-endpoints.json" as NSString).expandingTildeInPath
        if let data = try? JSONSerialization.data(withJSONObject: captured,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: jsonPath))
        }

        // Human/agent-readable digest: one block per unique method+path.
        var seen = Set<String>()
        var lines: [String] = ["# HiBob endpoints captured by BetterBob", ""]
        for call in captured {
            let method = call["method"] as? String ?? "?"
            let url = call["url"] as? String ?? "?"
            let path = URL(string: url)?.path ?? url
            let key = method + " " + path
            guard seen.insert(key).inserted else { continue }
            let status = call["status"] as? Int ?? 0
            lines.append("## \(method) \(path)   (\(status))")
            if let q = URL(string: url)?.query { lines.append("query: \(q)") }
            if let req = call["requestBody"] as? String, !req.isEmpty {
                lines.append("request: \(req.prefix(800))")
            }
            if let resp = call["responseBody"] as? String, !resp.isEmpty {
                lines.append("response: \(resp.prefix(1500))")
            }
            lines.append("")
        }
        let mdPath = ("~/Desktop/betterbob-endpoints.md" as NSString).expandingTildeInPath
        try? lines.joined(separator: "\n").write(toFile: mdPath, atomically: true, encoding: .utf8)
        NSLog("BetterBob: captured \(captured.count) calls (\(seen.count) unique) → \(mdPath)")
    }
}
