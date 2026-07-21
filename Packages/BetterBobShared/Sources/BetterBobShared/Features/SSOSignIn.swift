#if os(macOS)
import AppKit
#endif
import WebKit
import SwiftUI

/// Embedded-browser sign-in for SSO tenants (Okta & co.). The user signs in as
/// they would in Safari; after every page load the app copies the `hibob.com`
/// cookies into the URLSession store and probes the API — the moment Okta lands
/// back on app.hibob.com with a valid session, the window closes and we're in.
///
/// With autofill credentials stored it can also run **headless**: the same flow
/// off-screen, filling *and* clicking through the steps, so a "Re-login" button
/// just shows a spinner until it's done (falling back to the visible window if
/// it can't finish).
/// Which second factor the automatic flow drives to at Okta's "choose a method"
/// step. Two are typed codes (inline field); the push one is approved on the
/// phone (no code).
public enum SignInFactor: String, CaseIterable, Identifiable {
    case googleAuthenticator = "ga"
    case oktaVerifyCode = "ovc"
    case oktaVerifyPush = "ovp"

    public var id: String { rawValue }
    public var isPush: Bool { self == .oktaVerifyPush }

    /// Short label for the popover button group.
    public var shortLabel: String {
        switch self {
        case .googleAuthenticator: return "Google"
        case .oktaVerifyCode: return "Okta code"
        case .oktaVerifyPush: return "Okta push"
        }
    }
    public var icon: String {
        switch self {
        case .googleAuthenticator: return "key.fill"
        case .oktaVerifyCode: return "123.rectangle.fill"
        case .oktaVerifyPush: return "bell.badge.fill"
        }
    }
}

@MainActor
public final class SSOSignInController: NSObject, ObservableObject, WKNavigationDelegate {
    public static let shared = SSOSignInController()

    /// How the sign-in window drives itself.
    /// - `manual`: visible window, fields autofilled but the user clicks through.
    /// - `assisted`: the browser stays hidden and auto-fills + advances email and
    ///   password on its own, then stops at the authenticator step and waits for
    ///   the code the user types into a small native prompt. No code is ever
    ///   derived from a stored secret, and no browser window is shown.
    private enum Drive { case manual, assisted }
    private var drive: Drive = .manual
    /// The factor the assisted flow drives to (set by `presentAssisted`).
    private var factor: SignInFactor = .googleAuthenticator

    #if os(macOS)
    private var window: NSWindow?
    #else
    /// Published while a sign-in runs — the iOS app root presents it in a sheet.
    @Published public private(set) var sheetWebView: WKWebView?
    #endif
    private var webView: WKWebView?
    /// The one-time code the user typed into the inline field (assisted mode).
    /// Injected into the OTP field; never sourced from the Keychain.
    private var enteredCode: String?
    /// When we first sat on the code step with a code to submit — used to
    /// notice a rejected code (still on the code step well after injecting).
    private var codeStepSince: Date?
    private var onSuccess: (() -> Void)?
    private var onFinish: ((Bool) -> Void)?
    private var autofillTimer: Timer?
    private var deadline: Date?

    // MARK: - Entry points

    /// Visible sign-in window; autofills fields but leaves the buttons to you.
    public func present(onSuccess: @escaping () -> Void) {
        teardown()
        self.onSuccess = onSuccess
        self.drive = .manual
        makeSession(visible: true)
        load()
        #if os(macOS)
        NSApp.setActivationPolicy(.regular)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        #endif
        startAutofill()
    }

    /// Assisted sign-in: the browser auto-fills + advances email and password
    /// on its own, then stops at the authenticator step and waits. On macOS it
    /// runs hidden (transparent, off-list) with the one-time code coming from
    /// the inline field the app shows (driven by `BobState.awaitingOTP`); on
    /// iOS there is no hidden-window trick, so the same drive runs in a
    /// visible sheet and the user finishes the OTP right in the page. Generous
    /// deadline since a human is in the loop.
    public func presentAssisted(factor: SignInFactor, onFinish: @escaping (Bool) -> Void) {
        teardown()
        self.onFinish = onFinish
        self.drive = .assisted
        self.factor = factor
        self.enteredCode = nil
        self.deadline = Date().addingTimeInterval(300)
        makeSession(visible: false)   // browser stays invisible the whole time
        load()
        startAutofill()
    }

    /// Copy the persisted web-view session cookies into the URLSession store the
    /// API client uses. The web store survives relaunches, but those cookies are
    /// only otherwise mirrored during a sign-in flow — so at startup the app
    /// looked signed out even though the session was still valid.
    public static func syncWebCookies() async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        for cookie in cookies where cookie.domain.contains("hibob.com") {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    /// Wipe the embedded browser's cookies on sign-out, so the next sign-in
    /// starts fresh instead of silently reusing the old Okta session.
    public static func clearWebCookies() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast) {}
    }

    // MARK: - Session plumbing

    private func makeSession(visible: Bool) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        #if os(iOS)
        // One hosting strategy for both modes on iOS: a visible sheet. The
        // autofill timer still drives assisted mode inside it.
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 720),
                            configuration: config)
        web.navigationDelegate = self
        webView = web
        sheetWebView = web
        #else
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
        #endif
    }

    private func load() {
        webView?.load(URLRequest(url: BobAPI.base.appendingPathComponent("login")))
    }

    /// Close the window/timer only — no callbacks.
    private func closeWindow() {
        stopAutofill()
        #if os(macOS)
        window?.orderOut(nil)
        window?.close()
        window = nil
        #else
        sheetWebView = nil
        #endif
        webView = nil
        enteredCode = nil
        codeStepSince = nil
        deadline = nil
        BobState.shared.awaitingOTP = false
        BobState.shared.pushPending = false
        BobState.shared.otpSubmitting = false
        BobState.shared.otpError = nil
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
        // A driven flow (silent/assisted) always needs the timer, to advance the
        // steps and to time out; a manual window only if there's something to fill.
        let driven = drive != .manual
        guard driven || (Prefs.shared.autofillEnabled && Keychain.has(.password)) else { return }
        autofillTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, let web = self.webView else { timer.invalidate(); return }
                // The deadline guards only the automated drive to the code step;
                // once we're waiting on the user's code we wait as long as it
                // takes (they can cancel), so a slow human never times out.
                // Don't time out while waiting on a human — a code to type or a
                // push to approve on the phone.
                let waiting = BobState.shared.awaitingOTP || BobState.shared.pushPending
                if driven, !waiting, let dl = self.deadline, Date() > dl {
                    self.finish(false); return
                }
                if driven || Prefs.shared.autofillEnabled,
                   let js = self.autofillJS(click: driven) {
                    web.evaluateJavaScript(js) { result, _ in
                        if driven, let step = result as? String {
                            BobState.shared.autoLoginStatus = self.friendlyStatus(step)
                            if self.drive == .assisted {
                                if self.factor.isPush {
                                    BobState.shared.pushPending = (step == "push")
                                } else {
                                    self.trackCodeStep(step)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func stopAutofill() { autofillTimer?.invalidate(); autofillTimer = nil }

    /// Drive the inline field's state from the page's current step. Reveals the
    /// field's "ready" hint at the code step, and if a submitted code leaves us
    /// still on that step ~8s later, treats it as rejected so the user can retry.
    private func trackCodeStep(_ step: String) {
        let atCode = step == "code"
        BobState.shared.awaitingOTP = atCode
        guard atCode, enteredCode != nil else { codeStepSince = nil; return }
        if codeStepSince == nil {
            codeStepSince = Date()
        } else if Date().timeIntervalSince(codeStepSince!) > 8 {
            // A correct code navigates away within a couple of seconds; still
            // being here means Okta rejected it.
            enteredCode = nil
            codeStepSince = nil
            BobState.shared.otpSubmitting = false
            BobState.shared.otpError = "That code didn't work — check it and try again."
        }
    }

    /// Map a step token from the page into a user-friendly status line.
    private func friendlyStatus(_ step: String) -> String {
        switch step {
        case "gateway":  return "Connecting to Okta…"
        case "email":    return "Entering your email…"
        case "password": return "Entering your password…"
        case "select":   return "Choosing your authenticator…"
        // The user types the code into the inline field — there is no seed.
        case "code":     return "Enter the code from your authenticator app"
        case "push":     return "Approve the sign-in in Okta Verify on your phone…"
        default:         return "Loading…"
        }
    }

    /// Fill whichever Okta step is showing from the Keychain; when `click`, also
    /// press the step's submit button (once per page) to advance on its own. The
    /// authenticator code is never derived from a stored secret — it is only ever
    /// the value the user typed into the native prompt (assisted mode).
    private func autofillJS(click: Bool) -> String? {
        let pw = Keychain.get(.password) ?? ""
        let otp = drive == .assisted ? (enteredCode ?? "") : ""
        let email = BobState.shared.accountEmail
            ?? UserDefaults.standard.string(forKey: "lastAccountEmail") ?? ""
        guard !(pw.isEmpty && otp.isEmpty && email.isEmpty) else { return nil }
        func lit(_ s: String) -> String {
            (try? String(data: JSONEncoder().encode(s), encoding: .utf8)) ?? "\"\""
        }
        let factorToken = factor.rawValue
        return """
        (function(){
          var factor = \(lit(factorToken));
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
          // Push factor: once we've selected it and there's no field left, we're
          // on the "we sent a push, approve on your phone" screen — waiting.
          if (factor === 'ovp' && window.__bbFactorPicked && !present) step = 'push';
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
            // Okta "choose a security method" step → pick the requested factor's
            // row (never Security Key / biometric). Each factor is its own row,
            // matched by the row's text.
            var btns = [].slice.call(document.querySelectorAll('a, button, input[type=submit], [role=button]'));
            function boxText(x){
              return ((x.closest('.authenticator-row, .authenticator-button, li, form') || x.parentElement || x).textContent || '').toLowerCase();
            }
            var b = btns.find(function(x){
              if (!shown(x)) return false;
              var c = boxText(x);
              if (c.indexOf('security key') >= 0 || c.indexOf('biometric') >= 0) return false;
              if (factor === 'ga') return c.indexOf('google authenticator') >= 0 && c.indexOf('push') < 0;
              if (factor === 'ovc') return c.indexOf('okta verify') >= 0 && c.indexOf('enter a code') >= 0;
              if (factor === 'ovp') return c.indexOf('okta verify') >= 0
                  && (c.indexOf('push') >= 0 || c.indexOf('notification') >= 0);
              return false;
            });
            if (b) { window.__bbFactorPicked = true; b.click(); }
          }
          return step;
        })();
        """
    }

    // MARK: - Delegates

    public nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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

    // MARK: - Inline one-time-code entry (assisted mode)

    /// Inject the code the user typed into the inline field. Clears the OTP
    /// field first so a re-entered code overwrites a previously rejected one;
    /// the next autofill tick fills and submits it.
    public func submitCode(_ code: String) {
        enteredCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        codeStepSince = nil   // restart the rejection grace for this attempt
        let clear = """
        (function(){
          var o = document.querySelector('input[autocomplete=one-time-code], input[inputmode=numeric], input[type=tel], input[name*=passcode i], input[name*=otp i], input[name*=code i]');
          if (o) {
            var d = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
            if (d && d.set) { d.set.call(o, ''); } else { o.value = ''; }
            o.dispatchEvent(new Event('input', {bubbles:true}));
          }
          window.__bbSubmitted = null;
        })();
        """
        webView?.evaluateJavaScript(clear)
    }

    /// Cancel an in-progress sign-in (inline Cancel button).
    public func cancel() { finish(false) }
}

#if os(macOS)
extension SSOSignInController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        // A visible manual window the user closed.
        if drive == .manual { stopAutofill() }
    }
}
#endif
