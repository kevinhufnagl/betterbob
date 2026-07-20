import SwiftUI
import AppKit

/// First-run welcome window: Bob greets the user and walks them through signing
/// in, leading with automatic sign-in and clearly contrasting it with the
/// browser option. Presented as a plain AppKit window (like the SSO window) so
/// it centres nicely and doesn't tangle with the main window scene.
@MainActor
final class OnboardingController {
    static let shared = OnboardingController()
    private var window: NSWindow?

    /// Whether the user has already been through (or dismissed) onboarding.
    static var completed: Bool {
        get { UserDefaults.standard.bool(forKey: "hasOnboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "hasOnboarded") }
    }

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
        // Signed in during onboarding → drop back to the menu-bar-only mode.
        if BobState.shared.signedIn { NSApp.setActivationPolicy(.accessory) }
    }
}

struct OnboardingView: View {
    @ObservedObject var state: BobState
    var onDone: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var secret = ""
    @State private var editing = false
    @Environment(\.colorScheme) private var scheme

    private var canSetUp: Bool { !email.isEmpty && !password.isEmpty }
    private var hasSaved: Bool { Keychain.has(.password) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                autoCard
                browserCard
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
            title: "Sign in automatically", badge: "Recommended", tag: "Hands-off",
            blurb: "Save your HiBob password and 6-digit authenticator code. Bob signs you in on his own — after sleep, on restart, or whenever the session expires."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Best when your login is a password + authenticator code. For Okta Verify push approvals, use the browser option below.",
                      systemImage: "info.circle")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if hasSaved && !editing {
                    savedSummary
                } else {
                    editor
                }

                if state.autoLoginInProgress {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(state.autoLoginStatus.isEmpty ? "Signing you in…" : state.autoLoginStatus)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                    .animation(.easeInOut(duration: 0.15), value: state.autoLoginStatus)
                } else if let err = state.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Browser sign-in

    private var browserCard: some View {
        OnboardingCard(
            symbol: "safari", tint: .secondary,
            title: "Sign in with a browser", badge: nil, tag: "Every time",
            blurb: "Sign in through HiBob's normal login page in a secure window — including Okta Verify push. Quick to start, but you'll sign in again each time the session expires (for example, after a weekend)."
        ) {
            Button {
                state.startSSOSignIn()
                onDone()
            } label: {
                Label("Open browser sign-in", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large).buttonStyle(.bordered)
        }
    }

    // Saved credentials: a compact summary + one-click sign-in.
    private var savedSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow("envelope.fill", email.isEmpty ? "No email set" : email)
            summaryRow("key.fill", "Password ••••••••")
            if secret.isEmpty {
                summaryRow("lock.rotation", "No authenticator code")
            } else if let code = TOTP.code(secretBase32: secret) {
                summaryRow("lock.rotation", "Code \(code)", mono: true)
            } else {
                summaryRow("exclamationmark.triangle.fill", "Invalid authenticator secret", tint: .orange)
            }
            if !state.autoLoginInProgress {
                HStack(spacing: 8) {
                    Button { state.startAutoSignIn() } label: {
                        Label("Sign in automatically", systemImage: "wand.and.rays")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large).buttonStyle(.borderedProminent)
                    Button("Edit") { editing = true }.controlSize(.large)
                }
                .padding(.top, 2)
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
            field("Auth code") {
                VStack(alignment: .leading, spacing: 3) {
                    SecureField("Base32 secret or otpauth:// URL", text: $secret)
                        .textFieldStyle(.roundedBorder)
                    if !secret.isEmpty {
                        if let code = TOTP.code(secretBase32: secret) {
                            Text("Current code: \(code)")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        } else {
                            Text("Not a valid base32 secret")
                                .font(.system(size: 10)).foregroundStyle(.orange)
                        }
                    }
                }
            }
            if !state.autoLoginInProgress {
                HStack(spacing: 8) {
                    Button {
                        state.setupAutoLogin(email: email, password: password, secret: secret)
                    } label: {
                        Label("Set up & sign in", systemImage: "checkmark.circle.fill")
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
        secret = Keychain.get(.totpSecret) ?? ""
        editing = false
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
