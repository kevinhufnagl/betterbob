import SwiftUI
#if os(macOS)
import AppKit
#endif

/// First-run welcome window: Bob greets the user and walks them through signing
/// in, leading with automatic sign-in and clearly contrasting it with the
/// factor choice. Presented as a plain AppKit window (like the SSO window) so
/// it centres nicely and doesn't tangle with the main window scene.
@MainActor
public final class OnboardingController {
    public static let shared = OnboardingController()

    /// Whether the user has already been through (or dismissed) onboarding.
    public static var completed: Bool {
        get { UserDefaults.standard.bool(forKey: "hasOnboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "hasOnboarded") }
    }

    #if os(macOS)
    private var window: NSWindow?

    func present() {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: OnboardingView(state: BobState.shared) { [weak self] in
            self?.window?.close()
        })
        let win = NSWindow(contentViewController: host)
        win.title = "Welcome to BetterBob"
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 480, height: 660))
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cleanup() }
        }
        window = win
        NSApp.setActivationPolicy(.regular)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func cleanup() {
        OnboardingController.completed = true
        window = nil
        // Drop back to menu-bar-only mode only when onboarding was the sole
        // window (first run). If the main window is still open — e.g. onboarding
        // was opened from Settings' "Sign-in setup…" — stay regular, or going
        // accessory would order that window out and look like it closed.
        let mainWindowOpen = NSApp.windows.contains {
            $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible
        }
        if BobState.shared.signedIn && !mainWindowOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    #endif
}

public struct OnboardingView: View {
    @ObservedObject var state: BobState

    public init(state: BobState, onDone: @escaping () -> Void) {
        self.state = state
        self.onDone = onDone
    }
    @ObservedObject private var prefs = Prefs.shared
    var onDone: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var editing = false
    // Advanced: the stored authenticator secret for fully automatic sign-in.
    @State private var advancedOpen = false
    @State private var secretDraft = ""
    @State private var editingSecret = false
    @State private var hasSecret = false
    @Environment(\.colorScheme) private var scheme

    private var canSetUp: Bool { !email.isEmpty && !password.isEmpty }
    private var hasSaved: Bool { Keychain.has(.password) }

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                autoCard
                advancedToggle
                if advancedOpen { advancedCard }
                Text("Your details are stored only in your Mac's login Keychain and used only against HiBob's login form — never sent anywhere else.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .padding(24)
        }
        .frame(width: 480, height: 660)
        .background(background)
        .onAppear(perform: load)
        .onChange(of: state.signedIn) { _, signedIn in if signedIn { onDone() } }
    }

    private var background: some View {
        LinearGradient(colors: [Color.accentColor.opacity(scheme == .dark ? 0.12 : 0.08), .clear],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .background(.regularMaterial)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            AnimatedBob().frame(width: 76, height: 76)
            Text("Hi, I'm Bob").font(.system(size: 20, weight: .bold))
            Text("Let's get you signed in to HiBob. Pick how you'd like to clock in — you can change this later in Settings.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .padding(.top, 8)
    }

    // MARK: Automatic sign-in (recommended, first)

    private var autoCard: some View {
        OnboardingCard(
            symbol: "wand.and.rays", tint: .accentColor,
            title: "Sign in with your password", badge: "Recommended", tag: "One code",
            blurb: "Save your HiBob password. When the session expires Bob fills it in and you just type the current authenticator code — no code re-typing on every screen."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Works with a password plus any second factor — a typed authenticator code or an Okta Verify push.",
                      systemImage: "info.circle")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if hasSaved && !editing {
                    savedSummary
                } else {
                    editor
                }

                if state.autoLoginInProgress {
                    AutoLoginInline(state: state, fillWidth: true)
                } else if let err = state.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // Saved credentials: a compact summary + one-click sign-in.
    private var savedSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow("envelope.fill", email.isEmpty ? "No email set" : email)
            summaryRow("key.fill", "Password ••••••••")
            summaryRow("keyboard", hasSecret ? "Codes come from your stored secret"
                                             : "You type the code at sign-in")
            if !state.autoLoginInProgress {
                VStack(spacing: 8) {
                    // Signing in again only makes sense while signed out.
                    if !state.signedIn {
                        SignInFactorGroup(state: state)
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        Button("Edit") { editing = true }.controlSize(.small)
                        Button("Forget", role: .destructive) { forget() }.controlSize(.small)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// Remove the stored credentials and turn automatic sign-in off.
    private func forget() {
        Keychain.set(nil, for: .password)
        Keychain.set(nil, for: .totpSecret)
        hasSecret = false
        state.objectWillChange.send()
        UserDefaults.standard.removeObject(forKey: "lastAccountEmail")
        Prefs.shared.autofillEnabled = false
        Prefs.shared.autoReloginOnExpiry = false
        email = ""; password = ""
        editing = true
    }

    // MARK: Advanced — fully automatic (stored authenticator secret)

    /// A quiet toggle line, so the option stays out of the way until sought.
    private var advancedToggle: some View {
        Button {
            withAnimation(Motion.quick) { advancedOpen.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(advancedOpen ? 90 : 0))
                Text("Advanced")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }

    private var advancedCard: some View {
        OnboardingCard(
            symbol: "lock.rotation", tint: .orange,
            title: "Fully automatic", badge: nil, tag: "No prompts",
            blurb: "Also store your authenticator secret (the Base32 string or otpauth:// link behind the QR code) and Bob generates the codes himself — sign-ins, including after the session expires, need no prompt at all."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if hasSecret && !editingSecret {
                    summaryRow("lock.rotation",
                               TOTP.code(secretBase32: Keychain.get(.totpSecret) ?? "")
                                   .map { "Secret saved — current code \($0)" }
                               ?? "Invalid stored secret",
                               mono: true)
                    HStack(spacing: 8) {
                        Spacer()
                        Button("Replace") { editingSecret = true }.controlSize(.small)
                        Button("Remove", role: .destructive) {
                            Keychain.set(nil, for: .totpSecret)
                            hasSecret = false
                            secretDraft = ""
                            // fullyAutomatic is Keychain-derived — nudge the
                            // shared state so factor groups elsewhere re-read.
                            state.objectWillChange.send()
                        }.controlSize(.small)
                    }
                } else {
                    field("Secret") {
                        VStack(alignment: .leading, spacing: 4) {
                            SecureField("Base32 secret or otpauth:// link", text: $secretDraft)
                                .textFieldStyle(.roundedBorder)
                            if !secretDraft.isEmpty {
                                if let code = TOTP.code(secretBase32: secretDraft) {
                                    Text("Current code: \(code)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Not a valid Base32 secret")
                                        .font(.system(size: 10)).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        if hasSecret {
                            Button("Cancel") { editingSecret = false; secretDraft = "" }
                                .controlSize(.small)
                        }
                        Button("Save secret") {
                            Keychain.set(TOTP.base32Secret(from: secretDraft), for: .totpSecret)
                            hasSecret = Keychain.has(.totpSecret)
                            editingSecret = false
                            secretDraft = ""
                            state.objectWillChange.send()
                        }
                        .controlSize(.small).buttonStyle(.borderedProminent)
                        .disabled(TOTP.code(secretBase32: secretDraft) == nil)
                    }
                }
                if hasSecret {
                    // Hands-free expiry re-login is only possible with a
                    // stored secret — the checkbox appears alongside it.
                    Toggle(isOn: $prefs.autoReloginOnExpiry) {
                        Text("Sign back in automatically when the session expires")
                            .font(.system(size: 11))
                    }
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif
                }
                Label("This weakens two-factor sign-in: the secret sits in this Mac's Keychain next to your password, so anyone who can unlock this Mac can generate your codes. Prefer the typed code or the push unless you really want zero prompts.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func summaryRow(_ symbol: String, _ text: String, mono: Bool = false, tint: Color = .secondary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint).frame(width: 16)
            Text(text)
                .font(.system(size: 12, design: mono ? .monospaced : .default))
                .foregroundStyle(text.hasPrefix("No ") || text.hasPrefix("Invalid") ? .secondary : .primary)
        }
    }

    // New / editing credentials: the input fields + save-and-sign-in.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Email") {
                TextField("you@company.com", text: $email)
                    .textFieldStyle(.roundedBorder).textContentType(.username)
            }
            field("Password") {
                SecureField("HiBob / Okta password", text: $password).textFieldStyle(.roundedBorder)
            }
            Label("Bob saves your password, then you pick how to sign in. He fills your email + password automatically and stops at the authenticator step so you type the current code (or approve a push). Your code is never stored.",
                  systemImage: "keyboard")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !state.autoLoginInProgress {
                HStack(spacing: 8) {
                    Button {
                        state.setupAutoLogin(email: email, password: password)
                        editing = false
                    } label: {
                        Label("Save & choose a method", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large).buttonStyle(.borderedProminent)
                    .disabled(!canSetUp)
                    if hasSaved { Button("Cancel") { load(); editing = false }.controlSize(.large) }
                }
            }
        }
    }

    private func load() {
        email = UserDefaults.standard.string(forKey: "lastAccountEmail") ?? ""
        password = Keychain.get(.password) ?? ""
        editing = false
        hasSecret = Keychain.has(.totpSecret)
        editingSecret = false
        secretDraft = ""
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .medium))
                .frame(width: 70, alignment: .leading).padding(.top, 5)
            content()
        }
    }
}

/// A titled option card for the onboarding window.
private struct OnboardingCard<Content: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let badge: String?
    let tag: String
    let blurb: String
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint == .secondary ? Color.primary : tint)
                    .frame(width: 26, height: 26)
                    .background((tint == .secondary ? Color.primary : tint).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title).font(.system(size: 14, weight: .bold))
                if let badge {
                    Text(badge.uppercased())
                        .font(.system(size: 8, weight: .heavy)).kerning(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(tint == .secondary ? Color.primary : tint))
                }
                Spacer()
                Text(tag)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7))
            }
            Text(blurb)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(scheme == .dark ? 0.5 : 0.85),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
    }
}
