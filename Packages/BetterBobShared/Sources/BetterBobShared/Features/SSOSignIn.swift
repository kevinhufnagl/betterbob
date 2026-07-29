#if os(macOS)
import AppKit
#else
import UIKit
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
        case .oktaVerifyCode: return "Okta Verify code"
        case .oktaVerifyPush: return "Okta Verify push"
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
    /// A generated code (stored authenticator secret) was rejected — stop
    /// generating and fall back to the typed prompt for this run.
    private var autoOTPFailed = false
    private var onSuccess: (() -> Void)?
    private var onFinish: ((Bool) -> Void)?
    private var autofillTimer: Timer?
    private var deadline: Date?
    /// Stall tracking: the last step token and when it first appeared.
    private var lastStep: String?
    private var lastStepSince: Date?
    /// True once the run has moved past the identifier stage. Okta's FastPass
    /// probe — the fieldless page whose "Back to sign in" link the driver
    /// clicks to escape — only ever appears before that, so afterwards any
    /// fieldless page is something else (a push wait, a KMSI prompt) and must
    /// not be clicked away: that restarts the flow and fires a second push.
    private var pastIdentifier = false
    /// A specific reason the last assisted run failed (e.g. the chosen factor
    /// isn't enrolled), so the caller can show it instead of a generic message.
    public private(set) var lastFailureReason: String?

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

    /// Assisted sign-in: the browser runs hidden and auto-fills + advances
    /// email and password on its own, then stops at the authenticator step
    /// and waits. The one-time code comes only from the inline field the app
    /// shows (driven by `BobState.awaitingOTP`). macOS hides the browser in a
    /// transparent floating window; iOS parks it behind the app's content —
    /// either way nothing is shown. Generous deadline since a human is in
    /// the loop.
    public func presentAssisted(factor: SignInFactor, onFinish: @escaping (Bool) -> Void) {
        teardown()
        self.onFinish = onFinish
        self.drive = .assisted
        self.factor = factor
        self.enteredCode = nil
        self.autoOTPFailed = false
        self.lastFailureReason = nil
        self.lastStep = nil
        self.lastStepSince = nil
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
        // Request desktop content: the autofill driver's selectors are
        // written against the desktop HiBob/Okta pages the Mac app sees —
        // the mobile variants have different markup and stall the flow at
        // the gateway step.
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        // Assisted mode runs hidden — its autofill JS focuses fields to fill
        // them, which would raise the software keyboard over the app. A web
        // view that refuses first responder fills silently without it. The
        // visible sheet uses a normal web view so the user can type.
        let web = visible
            ? WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
            : NoKeyboardWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        web.navigationDelegate = self
        webView = web
        if visible {
            // Manual mode: the sheet the app root presents.
            sheetWebView = web
        } else {
            // Assisted mode: iOS has no transparent floating windows and
            // WebKit suspends views that aren't in a window at all — so park
            // the web view full-size INSIDE the app's window, behind all
            // content. It renders and runs Okta's scripts, but the app's own
            // UI covers it completely; only the inline OTP card is visible.
            attachHiddenBehindContent(web)
        }
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

    #if os(iOS)
    /// Insert the web view at the very back of the app's key window: in the
    /// hierarchy (so WebKit keeps it alive and executing), laid out full-size
    /// (so the autofill JS's visibility checks pass), but entirely covered by
    /// the app's own content.
    private func attachHiddenBehindContent(_ web: WKWebView) {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { ($0.activationState == .foregroundActive ? 0 : 1)
                    < ($1.activationState == .foregroundActive ? 0 : 1) }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ??
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first
        guard let window else { return }
        // Keep a desktop-sized layout viewport — the view is fully covered by
        // the app's content, so its footprint doesn't matter visually.
        web.frame = CGRect(x: 0, y: 0,
                           width: max(window.bounds.width, 1024),
                           height: max(window.bounds.height, 768))
        web.isUserInteractionEnabled = false
        web.accessibilityElementsHidden = true
        window.insertSubview(web, at: 0)
    }
    #endif

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
        webView?.removeFromSuperview()   // the hidden assisted host, if any
        sheetWebView = nil
        #endif
        webView = nil
        enteredCode = nil
        codeStepSince = nil
        pastIdentifier = false
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
                        if driven, let raw = result as? String {
                            let parts = raw.components(separatedBy: "||")
                            let step = parts[0]
                            // The chooser also reports the rows it offered —
                            // kept out of the status line, used in the failure.
                            let offered = parts.first { $0.hasPrefix("rows:") }
                                .map { String($0.dropFirst("rows:".count)) } ?? ""
                            let hint = parts.dropFirst()
                                .filter { !$0.hasPrefix("rows:") }
                                .joined(separator: " — ")
                            if step != self.lastStep {
                                self.lastStep = step
                                self.lastStepSince = Date()
                            }
                            // Anything past the identifier form means the
                            // FastPass probe is behind us — see pastIdentifier.
                            if ["password", "select", "code", "push"].contains(step) {
                                self.pastIdentifier = true
                            }
                            // A stalled drive names the page it's stuck on —
                            // that detail is the whole diagnosis when a
                            // teammate's flow differs from the known one.
                            let stalled = Date().timeIntervalSince(self.lastStepSince ?? Date()) > 18
                                && !BobState.shared.awaitingOTP && !BobState.shared.pushPending
                            BobState.shared.autoLoginStatus = stalled && !hint.isEmpty
                                ? self.friendlyStatus(step) + " — stuck at \(hint)"
                                : self.friendlyStatus(step)
                            if self.drive == .assisted {
                                if self.factor.isPush {
                                    BobState.shared.pushPending = (step == "push")
                                }
                                // Even on the push route, Okta sometimes lands
                                // on a code field (newer choosers add a second
                                // code-vs-push screen; org policy can force
                                // it). Surface the inline code card then — the
                                // Okta Verify app shows codes too — instead of
                                // hanging on a push that never comes.
                                self.trackCodeStep(step)

                                // The chooser only lists the factors the account
                                // has enrolled, so the requested one may have no
                                // row at all to click. The driver re-picks an
                                // unmoved chooser twice
                                // ~10s apart; once those are spent it really is
                                // a dead end. Say which methods Okta listed —
                                // the user can switch to one of them — instead
                                // of spinning out the deadline in silence, which
                                // reads as a hang.
                                let stuckFor = Date().timeIntervalSince(self.lastStepSince ?? Date())
                                if step == "select", stuckFor > 30 {
                                    let listed = offered.isEmpty ? "" : " Okta offered: \(offered)."
                                    self.lastFailureReason =
                                        "Couldn't get past Okta's authenticator chooser with \(self.factor.shortLabel).\(listed) Try one of the other methods next to the sign-in button."
                                    self.finish(false); return
                                }
                                // Same for a page that never resolves: the
                                // FastPass probe with no escape link, or a
                                // spinner that stays. The deadline would take
                                // another few silent minutes over it.
                                if step == "loading" || step == "fastpass", stuckFor > 90 {
                                    self.lastFailureReason =
                                        "Okta's sign-in page stopped responding\(hint.isEmpty ? "" : " at \(hint)"). Try signing in manually once."
                                    self.finish(false); return
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
        // While a stored secret is supplying the code, the flow is hands-free —
        // no prompt. It appears only if generation fails or gets rejected.
        let autoCode = factor == .googleAuthenticator && enteredCode == nil
            && !autoOTPFailed && Keychain.has(.totpSecret)
        BobState.shared.awaitingOTP = atCode && !autoCode
        guard atCode, enteredCode != nil || autoCode else { codeStepSince = nil; return }
        if codeStepSince == nil {
            codeStepSince = Date()
        } else if Date().timeIntervalSince(codeStepSince!) > 8 {
            // A correct code navigates away within a couple of seconds; still
            // being here means Okta rejected it.
            codeStepSince = nil
            if autoCode {
                autoOTPFailed = true
                BobState.shared.otpError = "The generated code was rejected — type the current one from your app."
            } else {
                enteredCode = nil
                BobState.shared.otpSubmitting = false
                BobState.shared.otpError = "That code didn't work — check it and try again."
            }
        }
    }

    /// Map a step token from the page into a user-friendly status line.
    private func friendlyStatus(_ step: String) -> String {
        switch step {
        case "gateway":  return "Connecting to Okta…"
        // HiBob served its own password page — the email didn't route to
        // Okta, which means the saved address is off (or not SSO-mapped).
        case "gateway-pw": return "HiBob asked for a password instead of Okta — check the email in Sign-in setup"
        case "email":    return "Entering your email…"
        case "password": return "Entering your password…"
        case "select":   return "Choosing your authenticator…"
        // Okta Verify on this Mac is being asked to vouch for you — that's the
        // Touch ID prompt the app raises. Named so it doesn't read as a hang.
        case "fastpass": return "Waiting for Okta Verify on this Mac…"
        // The user types the code into the inline field — there is no seed.
        case "code":     return "Enter the code from your authenticator app"
        case "push":     return "Approve the sign-in in Okta Verify…"
        default:         return "Loading…"
        }
    }

    /// Fill whichever Okta step is showing from the Keychain; when `click`, also
    /// press the step's submit button (once per page) to advance on its own. The
    /// authenticator code is never derived from a stored secret — it is only ever
    /// the value the user typed into the native prompt (assisted mode).
    private func autofillJS(click: Bool) -> String? {
        let pw = Keychain.get(.password) ?? ""
        // Fully automatic (Advanced): with a stored authenticator secret and
        // no typed code, generate the current TOTP. fill() writes a field
        // only once, so each page gets exactly one attempt — trackCodeStep
        // flips autoOTPFailed if Okta rejects it and the prompt takes over.
        let generated = (drive == .assisted && factor == .googleAuthenticator
                         && enteredCode == nil && !autoOTPFailed)
            ? Keychain.get(.totpSecret).flatMap { TOTP.code(secretBase32: $0) } : nil
        let otp = drive == .assisted ? (enteredCode ?? generated ?? "") : ""
        let email = BobState.shared.accountEmail
            ?? UserDefaults.standard.string(forKey: "lastAccountEmail") ?? ""
        guard !(pw.isEmpty && otp.isEmpty && email.isEmpty) else { return nil }
        // A live Okta Verify on this Mac makes the FastPass probe worth waiting
        // out (~34s) instead of escaping it at ~5s mid Touch ID prompt.
        return Self.autofillScript(email: email, password: pw, otp: otp, factor: factor,
                                   click: click, allowBack: !pastIdentifier,
                                   probeTicks: SignInFactorGroup.oktaVerifyInstalled ? 28 : 4)
    }

    /// The page driver itself, as a pure function of its inputs so its step
    /// classification can be unit-tested against a stub DOM (see Tests).
    nonisolated static func autofillScript(email: String, password pw: String, otp: String,
                                           factor: SignInFactor, click: Bool,
                                           allowBack: Bool, probeTicks: Int = 4) -> String {
        func lit(_ s: String) -> String {
            (try? String(data: JSONEncoder().encode(s), encoding: .utf8)) ?? "\"\""
        }
        let factorToken = factor.rawValue
        return """
        (function(){
          var factor = \(lit(factorToken));
          var allowBack = \(allowBack ? "true" : "false");
          var probeTicks = \(probeTicks);
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
          var onHibob = location.hostname.indexOf('hibob.com') >= 0;
          var email = document.querySelector('input[name=identifier], input[type=email], input[autocomplete=username]');
          var pw = document.querySelector('input[type=password]');
          var otp = pw ? null : document.querySelector('input[autocomplete=one-time-code], input[inputmode=numeric], input[type=tel], input[name*=passcode i], input[name*=otp i], input[name*=code i]');
          var present = !!(email || pw || otp);
          // A friendly step name for the UI status line.
          var bodyText = (document.body ? document.body.innerText : '').toLowerCase();
          var step;
          if (onHibob) step = (pw && shown(pw)) ? 'gateway-pw' : 'gateway';
          else if (pw) step = 'password';
          else if (otp) step = 'code';
          else if (email) step = 'email';
          else if (bodyText.indexOf('security method') >= 0 || bodyText.indexOf('verify it') >= 0
                   || bodyText.indexOf('authenticator') >= 0) step = 'select';
          else step = 'loading';
          // Push factor, nothing left to fill: are we on the "we sent a push,
          // approve on your phone" screen? Read that off the page rather than
          // off __bbFactorPicked alone — Okta skips the chooser entirely when
          // push is the only enrolled method, and a full page load drops the
          // flag anyway. A push wait mistaken for the FastPass probe below
          // gets "Back to sign in" clicked ~5s in, which restarts the whole
          // flow and sends a second push. Never over a chooser, though: the
          // newer widgets show a second, method-level one, and calling that
          // 'push' would strand the flow with nothing left to advance it.
          var chooserish = bodyText.indexOf('security method') >= 0
              || bodyText.indexOf('authenticator') >= 0;
          var pushSent = /push notification sent|sent a push|we sent you a push|open okta verify|didn'?t receive a push/.test(bodyText);
          if (factor === 'ovp' && !present && !onHibob && !chooserish
              && (pushSent || window.__bbFactorPicked)) step = 'push';
          // Okta's own device flow (FastPass / "signing in with Okta Verify")
          // gets its own token. With Okta Verify installed on this Mac that
          // probe is LIVE — the app raises a Touch ID prompt and the user needs
          // a moment to notice it and touch the sensor — so it earns a friendly
          // status line and a much longer leash before the escape link below.
          // Checked ahead of the chooser copy: the probe page can carry the
          // word "authenticator" and would otherwise read as 'select'.
          if (!present && !onHibob && !pushSent
              && /okta fastpass|signing in with okta|verifying your identity/.test(bodyText)) {
            step = 'fastpass';
          }
          // Compact page hint carried on every return — surfaced in the
          // status line when a step stalls, naming the exact stuck page.
          var hintBtns = [].slice.call(document.querySelectorAll('button, input[type=submit], [role=button]'))
            .filter(shown)
            .map(function(x){ return (x.value || x.textContent || '').trim().replace(/\\s+/g,' ').slice(0, 24); })
            .filter(function(t){ return t; })
            .slice(0, 3).join(', ');
          var heading = document.querySelector('h1, h2, .o-form-title, [data-se=o-form-explain], .okta-form-title');
          var headingText = heading ? heading.textContent.trim().replace(/\\s+/g,' ').slice(0, 40) : '';
          var pageHint = '||' + location.hostname + (headingText ? ' · ' + headingText : '')
              + (hintBtns ? '||' + hintBtns : '');
          var justFilled = false, ready = false;
          // Never fill HiBob's own password/code fields — the account is
          // Okta-managed; a fresh device's gateway shows the native form next
          // to the SSO button, and filling it just errors and loops the flow.
          [[email, \(lit(email))], [onHibob ? null : pw, \(lit(pw))], [onHibob ? null : otp, \(lit(otp))]].forEach(function(p){
            var r = fill(p[0], p[1]);
            if (r === 1) justFilled = true;
            if (r === 2) ready = true;
          });
          if (!\(click ? "true" : "false")) return step + pageHint;
          // Self-heal a stalled step: the per-step submit guard fires once,
          // and a click that lands before the SPA enables its button is lost
          // for good. If the step hasn't changed in ~7s, clear the guard so
          // the next tick may click again.
          if (window.__bbLastStep === step) {
            window.__bbSameTicks = (window.__bbSameTicks || 0) + 1;
            if (window.__bbSameTicks >= 6) { window.__bbSubmitted = null; window.__bbSameTicks = 0; }
          } else {
            window.__bbLastStep = step; window.__bbSameTicks = 0;
          }
          // The chooser needs the same self-heal, but its guard is per distinct
          // row rather than per step, so the block above can't reach it. Still
          // sitting on 'select' ~10s after a row was picked means either the
          // click was lost or Okta came back to the chooser — a verification
          // that never completed (an Okta Verify prompt wanting a fingerprint
          // the hidden view can't finish, an expired push). That return lands
          // in the SAME document, so the signature still matches and the row
          // would never be clicked again: a dead end. Expire it — slower than
          // the submit guard and only twice, because each re-pick can send
          // another push, and never while the page says one is already out.
          if (step === 'select') {
            window.__bbSelectTicks = (window.__bbSelectTicks || 0) + 1;
            if (window.__bbSelectTicks >= 8 && window.__bbFactorSig && !pushSent) {
              window.__bbSelectTicks = 0;
              window.__bbRepicks = (window.__bbRepicks || 0) + 1;
              if (window.__bbRepicks <= 2) { window.__bbFactorSig = null; }
            }
          } else {
            window.__bbSelectTicks = 0;
          }
          if (onHibob) {
            // HiBob's gateway: click "Continue with Okta" if it's there —
            // regardless of whether the native form is also showing. Only an
            // email-routing gateway (no SSO button) advances with the email.
            if (!window.__bbSsoClicked) {
              var all = [].slice.call(document.querySelectorAll('button, input[type=submit], [role=button], a'));
              var t = all.find(function(x){
                if (!shown(x)) return false;
                var s2 = (x.value || x.textContent || '').toLowerCase();
                return s2.indexOf('okta') >= 0 || s2.indexOf('continue with') >= 0 || s2.indexOf('sso') >= 0;
              });
              if (t) { window.__bbSsoClicked = true; t.click(); return step + pageHint; }
            }
            if (email && email.value && !justFilled) {
              var esig = 'gw:' + email.value;
              if (window.__bbSubmitted !== esig) { window.__bbSubmitted = esig; clickSubmit(email); }
            }
            return step + pageHint;
          }
          // Only submit on a later tick — once the field already holds the value
          // (ready) and we didn't just type it (justFilled). Clicking in the same
          // tick as filling submits before the widget registers the value → the
          // "username cannot be blank" error.
          // Okta's post-auth "Stay signed in?" prompt (KMSI) is fieldless, so
          // no branch below would touch it — click Stay to finish and keep the
          // session. Two matchers, both safe on the working English flow:
          //  1. the exact English label (proven), and
          //  2. a language-agnostic fallback GATED on an explicit decline
          //     button being present ("Nicht angemeldet bleiben", "Don't stay
          //     signed in", …) — a control unique to this screen, so it can't
          //     fire on the chooser, push-wait, or FastPass spinner. When it's
          //     there, click the visible button that is NEITHER the decline
          //     NOR a known secondary/escape link: that's Stay, in any language.
          if (!onHibob && !present && !window.__bbStayClicked) {
            var choices = [].slice.call(document.querySelectorAll('button, input[type=submit], [role=button]')).filter(shown);
            var negRE = /\\b(don'?t|do not|no)\\b|nicht|kein|niet|non/i;
            var secRE = /back to sign|zur(ü|ue)ck|verify with|another way|different|help|hilfe|resend|erneut|cancel|abbrechen/i;
            var label = function(x){ return (x.value || x.textContent || '').trim(); };
            var stay = choices.find(function(x){ return label(x).toLowerCase() === 'stay signed in'; });
            if (!stay && choices.some(function(x){ return negRE.test(label(x)); })) {
              stay = choices.find(function(x){
                var t = label(x);
                return t && !negRE.test(t) && !secRE.test(t);
              });
            }
            if (stay) { window.__bbStayClicked = true; stay.click(); return step + pageHint; }
          }
          // Okta FastPass interstitial: a fieldless page probing the local Okta
          // Verify app. Its own "Back to sign in" link drops to the normal
          // identifier form, so click it once the page has clearly stalled.
          // How long that takes depends on whether Okta Verify is installed:
          // without it the probe can never resolve and ~5s is plenty, but with
          // it the app is raising a Touch ID prompt and clicking away at 5s
          // cancels the very sign-in the user is in the middle of approving —
          // which is what stranded this flow. Hence probeTicks.
          if ((step === 'loading' || step === 'fastpass') && !present) {
            window.__bbStuckTicks = (window.__bbStuckTicks || 0) + 1;
            if (window.__bbStuckTicks >= probeTicks && !window.__bbBackClicked && allowBack) {
              var back = [].slice.call(document.querySelectorAll('a, button, [role=button]')).find(function(x){
                return shown(x) && /back to sign ?in|back to log ?in|zur(ü|ue)ck zur anmeldung/.test((x.textContent || x.value || '').trim().toLowerCase());
              });
              if (back) { window.__bbBackClicked = true; back.click(); }
            }
          } else {
            window.__bbStuckTicks = 0;
          }
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
            // Push factor stranded on a code field: Okta's newer widgets land
            // there when the chooser's second screen defaults to a typed code.
            // Route back through "Verify with something else" once — the
            // chooser comes back and the push row gets picked below.
            if (factor === 'ovp' && otp && !otp.value && !window.__bbAltOnce) {
              var alt = [].slice.call(document.querySelectorAll('a, button, [role=button]')).find(function(x){
                var s = (x.textContent || x.value || '').trim().toLowerCase();
                return shown(x) && /verify with something else|use another|another way|different method/.test(s);
              });
              if (alt) { window.__bbAltOnce = true; alt.click(); }
            }
          } else if (step === 'select') {
            // Okta "choose a security method" step → pick the requested factor's
            // row (never Security Key / biometric). Newer widgets show this
            // TWICE — the authenticator, then a code-vs-push method screen — so
            // the guard is per distinct choice, not once per flow. Strictly the
            // chooser step: boxText below falls back to the enclosing form,
            // which on Okta's widget is often the WHOLE page, so on any other
            // screen these matchers would grade unrelated buttons.
            var btns = [].slice.call(document.querySelectorAll('a, button, input[type=submit], [role=button]'));
            function boxText(x){
              return ((x.closest('.authenticator-row, .authenticator-button, li, form') || x.parentElement || x).textContent || '').toLowerCase();
            }
            // Rank rows rather than demanding an exact phrase. The first chooser
            // lists authenticators by NAME only — "Okta Verify", "Google
            // Authenticator" — and only a second screen names push vs code, so
            // a push run must be willing to click a row that says nothing about
            // pushes. Higher wins; 0 means "not this factor's row".
            function rank(c){
              if (c.indexOf('security key') >= 0 || c.indexOf('biometric') >= 0) return 0;
              var code = c.indexOf('enter a code') >= 0;
              var push = c.indexOf('push') >= 0 || c.indexOf('notification') >= 0;
              var ov = c.indexOf('okta verify') >= 0;
              if (factor === 'ga') return (c.indexOf('google authenticator') >= 0 && !push) ? 3 : 0;
              if (factor === 'ovc') return (code && !push) ? 3 : ((ov && !push) ? 2 : (ov ? 1 : 0));
              // Push: an explicit push row first, then a bare "Okta Verify" one.
              return (push && !code) ? 3 : ((ov && !code) ? 2 : (ov ? 1 : 0));
            }
            var b = null, bestRank = 0, offered = [];
            btns.forEach(function(x){
              if (!shown(x)) return;
              var own = (x.textContent || x.value || '').trim().replace(/\\s+/g,' ');
              // Secondary links: escapes and re-sends, never a method row.
              if (/resend|something else|another way|different method|back to sign|back to log/i.test(own)) return;
              if (own) offered.push(own.slice(0, 28));
              var r = rank(boxText(x));
              if (r > bestRank) { bestRank = r; b = x; }
            });
            // Name what Okta actually offered, so a chooser that has no row for
            // the requested factor says so instead of just sitting there.
            if (offered.length) pageHint += '||rows:' + offered.slice(0, 6).join(' / ');
            var pick = b ? ((b.textContent || b.value || '').trim() + '@' + location.pathname) : '';
            if (b && window.__bbFactorSig !== pick) {
              window.__bbFactorSig = pick;
              window.__bbFactorPicked = true;
              b.click();
            }
          }
          return step + pageHint;
        })();
        """
    }

    // MARK: - Delegates

    public nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.attemptCompletion() }
    }

    /// Sync the web session into the API cookie store and finish if it's real.
    /// Runs after every navigation AND when the app returns to the foreground:
    /// on iOS the completing redirect often lands while the app is backgrounded
    /// (you're in Okta Verify approving the push), so `didFinish` alone can miss
    /// it and the driver would re-run the whole flow into a second push. A
    /// foreground re-check catches that first, already-valid session instead.
    func attemptCompletion() {
        guard let web = webView else { return }
        Task { @MainActor in
            let store = web.configuration.websiteDataStore.httpCookieStore
            for cookie in await store.allCookies() where cookie.domain.contains("hibob.com") {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
            // Cheap — only succeeds once the session is real.
            if await BobState.shared.probeSession() { self.finish(true) }
        }
    }

    /// Called when the app returns to the foreground so a sign-in that completed
    /// while backgrounded is picked up immediately.
    public func resumeCheck() { attemptCompletion() }

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
#else
/// A WKWebView that never becomes first responder, so JS `focus()` in the
/// hidden assisted-login page can't raise the software keyboard. WebKit's
/// inner content view is what normally takes focus; blocking it here (plus
/// the host's `isUserInteractionEnabled = false`) keeps the keyboard down.
final class NoKeyboardWebView: WKWebView {
    override var canBecomeFirstResponder: Bool { false }
    override func becomeFirstResponder() -> Bool { false }

    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        // The private WKContentView is the real focus target — deny it too.
        subview.isUserInteractionEnabled = false
    }
}
#endif
