import BetterBobShared
import SwiftUI

/// First-run sign-in, restaged for the phone: Bob up top, one glass card per
/// sign-in path, native full-width glass buttons. Drives the exact same
/// engine calls as the Mac onboarding (Keychain save, factor choice, SSO).
struct OnboardingScreen: View {
    @ObservedObject var state: BobState
    var onDone: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var editing = false
    @State private var didAppear = false

    private var canSetUp: Bool { !email.isEmpty && !password.isEmpty }
    private var hasSaved: Bool { Keychain.has(.password) }

    var body: some View {
        ZStack {
            DashboardBG().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    hero
                        .opacity(didAppear ? 1 : 0)
                        .offset(y: didAppear ? 0 : 14)
                    if state.autoLoginInProgress {
                        GlassCard { AutoLoginInline(state: state, fillWidth: true) }
                    } else {
                        autoSection
                            .opacity(didAppear ? 1 : 0)
                            .offset(y: didAppear ? 0 : 18)
                        browserSection
                            .opacity(didAppear ? 1 : 0)
                            .offset(y: didAppear ? 0 : 22)
                    }
                    Text("Your details are stored only in the Keychain and used only against HiBob's login form — never sent anywhere else.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            load()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.1)) {
                didAppear = true
            }
        }
        .onChange(of: state.signedIn) { _, signedIn in if signedIn { onDone() } }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            AnimatedBob().frame(width: 120, height: 120)
            Text("Hi, I'm Bob")
                .font(.largeTitle.bold())
            Text("Let's get you signed in to HiBob. Pick how you'd like to clock in — you can change this later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    // MARK: Automatic sign-in

    private var autoSection: some View {
        GlassGroupedSection(
            header: "Sign in automatically",
            footer: "Bob fills your email and password, then stops at the authenticator step — you type the current code or approve a push. Your code is never stored."
        ) {
            if hasSaved && !editing {
                savedRows
            } else {
                editorRows
            }
        }
    }

    @ViewBuilder private var savedRows: some View {
        GlassRow(showDivider: false) {
            LabeledContent("Email") {
                Text(email.isEmpty ? "Not set" : email).foregroundStyle(.secondary)
            }
        }
        GlassRow {
            LabeledContent("Password") {
                Text("••••••••").foregroundStyle(.secondary)
            }
        }
        GlassRow {
            VStack(spacing: 10) {
                SignInFactorGroup(state: state)
                HStack {
                    Button("Edit") { editing = true }
                        .buttonStyle(.glass)
                    Button("Forget", role: .destructive) { forget() }
                        .buttonStyle(.glass)
                }
                .font(.callout)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private var editorRows: some View {
        GlassRow(showDivider: false) {
            TextField("Email", text: $email, prompt: Text("you@company.com"))
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        GlassRow {
            SecureField("Password", text: $password, prompt: Text("HiBob / Okta password"))
                .textContentType(.password)
        }
        GlassRow {
            VStack(spacing: 8) {
                Button {
                    state.setupAutoLogin(email: email, password: password)
                    editing = false
                } label: {
                    Label("Save & choose a method", systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!canSetUp)
                if hasSaved {
                    Button("Cancel") { load() }
                        .font(.callout)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Browser sign-in

    private var browserSection: some View {
        Button {
            state.startSSOSignIn()
        } label: {
            Label("Sign in with a browser", systemImage: "safari")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }

    // MARK: Engine plumbing (same as the Mac onboarding)

    private func load() {
        email = UserDefaults.standard.string(forKey: "lastAccountEmail") ?? ""
        password = Keychain.get(.password) ?? ""
        editing = false
    }

    private func forget() {
        Keychain.set(nil, for: .password)
        UserDefaults.standard.removeObject(forKey: "lastAccountEmail")
        Prefs.shared.autofillEnabled = false
        Prefs.shared.autoReloginOnExpiry = false
        email = ""
        password = ""
        editing = true
    }
}
