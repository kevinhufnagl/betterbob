import AppKit
import WebKit

/// Embedded-browser sign-in for SSO tenants (Okta & co.). The user signs in as
/// they would in Safari; after every page load the app copies the `hibob.com`
/// cookies into the URLSession store and probes the API — the moment Okta lands
/// back on app.hibob.com with a valid session, the window closes and we're in.
///
/// With autofill credentials stored it can also run **headless**: the same flow
/// off-screen, filling *and* clicking through the steps, so a "Re-login" button
/// just shows a spinner until it's done (falling back to the visible window if
/// it can't finish).
@MainActor
final class SSOSignInController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = SSOSignInController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var onSuccess: (() -> Void)?
    private var onFinish: ((Bool) -> Void)?
    private var autofillTimer: Timer?
    private var headless = false
    private var deadline: Date?

    // MARK: - Entry points

    /// Visible sign-in window; autofills fields but leaves the buttons to you.
    func present(onSuccess: @escaping () -> Void) {
        teardown()
        self.onSuccess = onSuccess
        self.headless = false
        makeSession(visible: true)
        load()
        NSApp.setActivationPolicy(.regular)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startAutofill()
    }

    /// Auto-drive sign-in: a normal (visible) window that fills *and* clicks
    /// through the steps itself, closing on success. It must be visible — WebKit
    /// throttles an off-screen web view, so Okta's JS sign-in widget never
    /// renders there. `onFinish(true)` once the session is live, `(false)` on
    /// timeout.
    func presentHeadless(onFinish: @escaping (Bool) -> Void) {
        teardown()
        self.onFinish = onFinish
        self.headless = true
        self.deadline = Date().addingTimeInterval(90)
        // EXPERIMENT: on-screen but fully transparent — invisible to the user,
        // but (hopefully) still rendered by WebKit since it's on a screen.
        makeSession(visible: false)
        load()
        startAutofill()
    }

    /// Copy the persisted web-view session cookies into the URLSession store the
    /// API client uses. The web store survives relaunches, but those cookies are
    /// only otherwise mirrored during a sign-in flow — so at startup the app
    /// looked signed out even though the session was still valid.
    static func syncWebCookies() async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        for cookie in cookies where cookie.domain.contains("hibob.com") {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    /// Wipe the embedded browser's cookies on sign-out, so the next sign-in
    /// starts fresh instead of silently reusing the old Okta session.
    static func clearWebCookies() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast) {}
    }

    // MARK: - Session plumbing

    private func makeSession(visible: Bool) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: config)
        web.navigationDelegate = self
        let win = NSWindow(contentRect: web.frame,
                           styleMask: visible ? [.titled, .closable, .resizable] : [.borderless],
                           backing: .buffered, defer: false)
        win.title = "Sign in to HiBob"
        win.contentView = web
        win.isReleasedWhenClosed = false
        win.delegate = self
        if !visible {
            // Fully transparent, but kept floating on top so it's never occluded
            // by the main window — WebKit suspends an occluded/off-screen view, so
            // it must stay visible-to-the-window-server to keep rendering Okta.
            win.alphaValue = 0
            win.ignoresMouseEvents = true
            win.level = .floating
            win.center()
            win.orderFrontRegardless()
        }
        window = win
        webView = web
    }

    private func load() {
        webView?.load(URLRequest(url: BobAPI.base.appendingPathComponent("login")))
    }

    /// Close the window/timer only — no callbacks.
    private func closeWindow() {
        stopAutofill()
        window?.orderOut(nil)
        window?.close()
        window = nil
        webView = nil
        deadline = nil
    }

    /// Start-of-run cleanup: also cancel any in-flight run so its loading state
    /// resets (e.g. the user hit manual sign-in mid auto-login).
    private func teardown() {
        let pending = onFinish
        onSuccess = nil
        onFinish = nil
        closeWindow()
        pending?(false)
    }

    private func finish(_ success: Bool) {
        let onS = onSuccess, onF = onFinish
        onSuccess = nil
        onFinish = nil
        closeWindow()
        if success { onS?() }
        onF?(success)
    }

    // MARK: - Autofill / auto-drive

    private func startAutofill() {
        autofillTimer?.invalidate()
        // Headless always needs the timer (to drive + time out); visible only if
        // there's something to fill.
        let haveCreds = Keychain.has(.password) || Keychain.has(.totpSecret)
        guard headless || (Prefs.shared.autofillEnabled && haveCreds) else { return }
        autofillTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, let web = self.webView else { timer.invalidate(); return }
                if self.headless, let dl = self.deadline, Date() > dl {
                    self.finish(false); return
                }
                if self.headless || Prefs.shared.autofillEnabled,
                   let js = self.autofillJS(click: self.headless) {
                    web.evaluateJavaScript(js) { result, _ in
                        if self.headless, let step = result as? String {
                            BobState.shared.autoLoginStatus = self.friendlyStatus(step)
                        }
                    }
                }
            }
        }
    }

    private func stopAutofill() { autofillTimer?.invalidate(); autofillTimer = nil }

    /// Map a step token from the page into a user-friendly status line.
    private func friendlyStatus(_ step: String) -> String {
        switch step {
        case "gateway":  return "Connecting to Okta…"
        case "email":    return "Entering your email…"
        case "password": return "Entering your password…"
        case "select":   return "Choosing your authenticator…"
        case "code":     return "Entering your one-time code…"
        default:         return "Loading…"
        }
    }

    /// Fill whichever Okta step is showing from the Keychain; when `click`, also
    /// press the step's submit button (once per page) to advance on its own.
    private func autofillJS(click: Bool) -> String? {
        let pw = Keychain.get(.password) ?? ""
        let secret = Keychain.get(.totpSecret) ?? ""
        let otp = secret.isEmpty ? "" : (TOTP.code(secretBase32: secret) ?? "")
        let email = BobState.shared.accountEmail
            ?? UserDefaults.standard.string(forKey: "lastAccountEmail") ?? ""
        guard !(pw.isEmpty && otp.isEmpty && email.isEmpty) else { return nil }
        func lit(_ s: String) -> String {
            (try? String(data: JSONEncoder().encode(s), encoding: .utf8)) ?? "\"\""
        }
        return """
        (function(){
          // Returns: 0 nothing, 1 filled just now, 2 already had a value.
          function fill(el, val){
            if(!el || !val) return 0;
            if(el.value) return 2;
            try { el.focus(); } catch(e) {}
            var d = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
            if (d && d.set) { d.set.call(el, val); } else { el.value = val; }
            el.dispatchEvent(new Event('input', {bubbles:true}));
            el.dispatchEvent(new Event('change', {bubbles:true}));
            // Some Okta widgets only enable the Verify/Next button after the
            // field blurs (validation), so nudge that too.
            el.dispatchEvent(new Event('blur', {bubbles:true}));
            return 1;
          }
          function shown(el){ return el && !el.disabled && el.offsetParent !== null; }
          // Advance the current Okta step. Button markup varies by Okta version,
          // so try, in order: an explicit submit control, a primary/labelled
          // button, the form's own submit, then a synthetic Enter on the field.
          function clickSubmit(field){
            var form = field && field.closest ? field.closest('form') : null;
            var scope = form || document;
            var b = scope.querySelector('input[type=submit], button[type=submit], [data-type=save], [data-se=save], [data-se=save-btn], .o-form-button-bar input[type=submit]');
            if (!shown(b)) {
              var cands = [].slice.call(scope.querySelectorAll('button, input[type=submit], input[type=button], [role=button]'));
              b = cands.find(function(x){
                if (!shown(x)) return false;
                var s = (x.value || x.textContent || '').trim().toLowerCase();
                return /^(verify|next|sign in|signin|log in|login|log on|continue|submit|done)$/.test(s)
                    || /button-primary|btn-primary|\\bprimary\\b/.test(x.className || '');
              });
            }
            if (shown(b)) { b.click(); return; }
            if (form && form.requestSubmit) { try { form.requestSubmit(); return; } catch(e) {} }
            if (field) {
              ['keydown','keypress','keyup'].forEach(function(t){
                field.dispatchEvent(new KeyboardEvent(t, {key:'Enter', code:'Enter', keyCode:13, which:13, bubbles:true}));
              });
            }
          }
          var email = document.querySelector('input[name=identifier], input[type=email], input[autocomplete=username]');
          var pw = document.querySelector('input[type=password]');
          var otp = pw ? null : document.querySelector('input[autocomplete=one-time-code], input[inputmode=numeric], input[type=tel], input[name*=passcode i], input[name*=otp i], input[name*=code i]');
          var present = !!(email || pw || otp);
          // A friendly step name for the UI status line.
          var bodyText = (document.body ? document.body.innerText : '').toLowerCase();
          var step;
          if (pw) step = 'password';
          else if (otp) step = 'code';
          else if (email) step = 'email';
          else if (location.hostname.indexOf('hibob.com') >= 0) step = 'gateway';
          else if (bodyText.indexOf('security method') >= 0 || bodyText.indexOf('verify it') >= 0
                   || bodyText.indexOf('authenticator') >= 0) step = 'select';
          else step = 'loading';
          var justFilled = false, ready = false;
          [[email, \(lit(email))], [pw, \(lit(pw))], [otp, \(lit(otp))]].forEach(function(p){
            var r = fill(p[0], p[1]);
            if (r === 1) justFilled = true;
            if (r === 2) ready = true;
          });
          if (!\(click ? "true" : "false")) return step;
          // Only submit on a later tick — once the field already holds the value
          // (ready) and we didn't just type it (justFilled). Clicking in the same
          // tick as filling submits before the widget registers the value → the
          // "username cannot be blank" error.
          if (present) {
            if (ready && !justFilled) {
              // Okta's widget is a single page — track the submit per step (which
              // field + its value) rather than once per page, or the guard set on
              // the username step blocks the password/code Verify clicks.
              var field = pw || otp || email;
              var sig = (pw ? 'pw' : otp ? 'otp' : 'email') + ':' + (field ? field.value : '');
              if (window.__bbSubmitted !== sig) {
                window.__bbSubmitted = sig;
                clickSubmit(field);
              }
            }
          } else if (!window.__bbSsoClicked && location.hostname.indexOf('hibob.com') >= 0) {
            // HiBob's own gateway: click "Continue with Okta". Never touch links
            // on the SAML/Okta redirect pages — a stray click sends us to okta.com
            // marketing; they navigate on their own.
            var all = [].slice.call(document.querySelectorAll('button, input[type=submit]'));
            var t = all.find(function(x){
              var s = (x.value || x.textContent || '').toLowerCase();
              return s.indexOf('okta') >= 0 || s.indexOf('continue with') >= 0;
            });
            if (t) { window.__bbSsoClicked = true; t.click(); }
          } else if (!window.__bbFactorPicked) {
            // Okta "choose a security method" step → pick Google Authenticator
            // (TOTP). Click only within that row, so we never pick Security Key.
            var btns = [].slice.call(document.querySelectorAll('a, button, input[type=submit], [role=button]'));
            var b = btns.find(function(x){
              var box = x.closest('.authenticator-row, li, form') || x.parentElement || x;
              var c = (box.textContent || '').toLowerCase();
              return c.indexOf('google authenticator') >= 0
                  && c.indexOf('security key') < 0 && c.indexOf('biometric') < 0;
            });
            if (b) { window.__bbFactorPicked = true; b.click(); }
          }
          return step;
        })();
        """
    }

    // MARK: - Delegates

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            let store = webView.configuration.websiteDataStore.httpCookieStore
            let cookies = await store.allCookies()
            for cookie in cookies where cookie.domain.contains("hibob.com") {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
            // Probe after every load — cheap, only succeeds once the session is real.
            if await BobState.shared.probeSession() {
                self.finish(true)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Only relevant for the visible window closed by the user.
        if !headless { stopAutofill() }
    }
}
