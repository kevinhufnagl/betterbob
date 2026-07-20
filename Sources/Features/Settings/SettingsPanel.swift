import SwiftUI
import AppKit

struct SettingsPanel: View {
    @ObservedObject var state: BobState
    @ObservedObject var prefs: Prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(title: "Settings",
                       subtitle: state.signedIn ? state.accountEmail : "Not signed in")

            SettingsGroup(title: "Account") { accountContent }
            SettingsGroup(title: "Automatic sign-in") { AutoSignInCard(state: state, prefs: prefs) }
            SettingsGroup(title: "Automatic break") { autoBreakContent }
            SettingsGroup(title: "Daily limit") { dailyLimitContent }
            if state.signedIn {
                SettingsGroup(title: "Reasons") {
                    defaultReasonContent
                    Divider().opacity(0.12)
                    wifiReasonContent
                }
            }
            SettingsGroup(title: "Notifications") { notificationsContent }
            SettingsGroup(title: "Menu bar") { menuBarContent }
            SettingsGroup(title: "General") { generalContent }
            SettingsGroup(title: "Updates") { UpdatesCard() }
            if let err = state.lastError {
                SettingsGroup(title: "Diagnostics") { diagnosticsContent(err) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Account

    @ViewBuilder
    private var accountContent: some View {
        Group {
            if state.signedIn {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Signed in as \(state.accountEmail ?? "—")")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Sign out") { state.signOut() }
                        .controlSize(.small)
                }
            } else {
                Button {
                    OnboardingController.shared.present()
                } label: {
                    Label("Sign in…", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .disabled(state.autoLoginInProgress)

                Text("Opens the sign-in window where you choose automatic sign-in (password + authenticator code, stored in your Keychain) or a browser sign-in (Okta Verify push included). You can change how it's set up any time below.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("The session lives in your login Keychain / cookie store and is used only against app.hibob.com — the same internal API the HiBob website itself uses with your own session. Nothing is sent anywhere else.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Auto-break

    @ViewBuilder
    private var autoBreakContent: some View {
        Group {
            Toggle("Insert a break automatically", isOn: $prefs.autoBreakEnabled)
                .font(.system(size: 12))

            Group {
                HStack {
                    Text("After uninterrupted work of").font(.system(size: 12))
                    Spacer()
                    PillStepper(value: $prefs.thresholdMinutes, range: 60...600, step: 15) {
                        Fmt.hm(TimeInterval($0 * 60))
                    }
                }
                HStack {
                    Text("Break length").font(.system(size: 12))
                    Spacer()
                    PillStepper(value: $prefs.breakMinutes, range: 5...120, step: 5) {
                        Fmt.hm(TimeInterval($0 * 60))
                    }
                }
            }
            .disabled(!prefs.autoBreakEnabled)

            Text("A break you take yourself resets the counter — the auto-break only fires after truly uninterrupted work. If your Mac was asleep at the mark, the break is inserted retroactively at the right time.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Daily limit

    @ViewBuilder
    private var dailyLimitContent: some View {
        Group {
            HStack {
                Text("Warn when a day tops").font(.system(size: 12))
                Spacer()
                PillStepper(value: $prefs.maxDayMinutes, range: 360...960, step: 30) {
                    Fmt.hm(TimeInterval($0 * 60))
                }
            }
            Text("Days over the limit show up red on Today and the month calendar, and Bob notifies you the moment you cross it while clocked in. Unlike a missing break there's nothing to auto-fix — only clocking out earlier helps.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Reasons

    @ViewBuilder
    private var defaultReasonContent: some View {
        Group {
            HStack(spacing: 8) {
                Text("Always tag work as").font(.system(size: 12))
                Picker("", selection: $prefs.defaultReasonName) {
                    Text("Off").tag("")
                    ForEach(state.reasonOptions, id: \.name) { opt in
                        Text(opt.name).tag(opt.name)
                    }
                }
                .labelsHidden().frame(maxWidth: 200)
                Spacer()
            }
            Text("Applied to an untagged open work entry automatically. A matching Wi-Fi rule below overrides it; otherwise this is used. Works on its own — no Wi-Fi needed.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var wifiReasonContent: some View {
        Group {
            Toggle("Set a reason automatically based on the Wi-Fi network",
                   isOn: $prefs.wifiAutoReasonEnabled)
                .font(.system(size: 12))

            Group {
                HStack(spacing: 6) {
                    Image(systemName: "wifi").font(.system(size: 10)).foregroundStyle(.secondary)
                    if let ssid = WiFiMonitor.shared.currentSSID() {
                        Text("Current network:").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(ssid).font(.system(size: 11, weight: .semibold, design: .monospaced))
                    } else {
                        Text("Current network not readable — grant Location access")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                        Button("Grant") { WiFiMonitor.shared.requestAccess() }.controlSize(.mini)
                    }
                    Spacer()
                }

                ForEach($prefs.wifiRules) { $rule in
                    HStack(spacing: 8) {
                        TextField("Network name (SSID)", text: $rule.ssid)
                            .textFieldStyle(.roundedBorder).font(.system(size: 12))
                        Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                        Picker("", selection: $rule.reasonName) {
                            Text("Choose reason").tag("")
                            ForEach(state.reasonOptions, id: \.name) { opt in
                                Text(opt.name).tag(opt.name)
                            }
                        }
                        .labelsHidden().frame(maxWidth: 180)
                        Button {
                            prefs.wifiRules.removeAll { $0.id == rule.id }
                        } label: { Image(systemName: "trash").font(.system(size: 11)) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        WiFiMonitor.shared.requestAccess()
                        prefs.wifiRules.append(WiFiRule(ssid: WiFiMonitor.shared.currentSSID() ?? "",
                                                        reasonName: ""))
                    } label: {
                        Label("Add rule", systemImage: "plus")
                    }
                    .controlSize(.small)
                    if prefs.wifiRules.isEmpty {
                        Text("No rules yet.").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }

                if !WiFiMonitor.shared.hasAccess {
                    Text("macOS needs Location access to read the Wi-Fi network name — “Add rule” prefills the current one and will ask for it. Your location is never used or stored.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(!prefs.wifiAutoReasonEnabled)

            Text("On a matching network, the open work entry gets that reason — overriding the default above. Only applied if you haven't set a reason yourself.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Notifications / General

    @ViewBuilder
    private var notificationsContent: some View {
        Group {
            Toggle("Auto-break started / ended", isOn: $prefs.notifyAutoBreak)
                .font(.system(size: 12))
            Toggle("Daily target reached", isOn: $prefs.notifyTargetReached)
                .font(.system(size: 12))
            Toggle("Worked past the daily max", isOn: $prefs.notifyOverMax)
                .font(.system(size: 12))
            Toggle("Timesheet deadline approaching", isOn: $prefs.notifyDeadline)
                .font(.system(size: 12))
            Toggle("Something failed (sign-in, HiBob unreachable)", isOn: $prefs.notifyFailures)
                .font(.system(size: 12))
        }
    }

    @ViewBuilder
    private var menuBarContent: some View {
        Group {
            Text("Show next to the icon").font(.system(size: 12, weight: .semibold))
            menuTextRow("While working", $prefs.menuBarTextWorking,
                        Prefs.MenuBarTextWorking.allCases) { $0.label }
            menuTextRow("While on a break", $prefs.menuBarTextBreak,
                        Prefs.MenuBarTextBreak.allCases) { $0.label }
            menuTextRow("While clocked out", $prefs.menuBarTextOut,
                        Prefs.MenuBarTextOut.allCases) { $0.label }
            Divider().opacity(0.12)
            Toggle("Show a play/pause badge on the icon while clocked in",
                   isOn: $prefs.showStateBadge)
                .font(.system(size: 12))
            Toggle("Tint the icon by status (green working / orange break)",
                   isOn: $prefs.colorMenuBarIcon)
                .font(.system(size: 12))
        }
    }

    private func menuTextRow<M: Identifiable & Hashable>(
        _ label: String, _ selection: Binding<M>, _ options: [M],
        _ title: @escaping (M) -> String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12))
            Spacer()
            Picker("", selection: selection) {
                ForEach(options) { Text(title($0)).tag($0) }
            }
            .labelsHidden().frame(maxWidth: 200)
        }
    }

    @ViewBuilder
    private var generalContent: some View {
        Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            .font(.system(size: 12))
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Automatically fix gaps and overlaps", isOn: $prefs.autoFixGapsOverlaps)
                .font(.system(size: 12))
            Text("When you edit or delete an entry, snap the day's entries together so there are no gaps or overlaps.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Endpoint-capture stays available via the `--capture-endpoints` launch
    // flag (EndpointCaptureController) — the settings card is intentionally
    // hidden so it isn't a user-facing option.

    @ViewBuilder
    private func diagnosticsContent(_ error: String) -> some View {
        Group {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Text("If HiBob's internal API changed, re-capture the routes (Docs/endpoints.md) and update BobAPI in Sources/Services/BobClient.swift.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Store the HiBob password + TOTP secret (in the Keychain) for autofilling the
/// SSO sign-in form. Kept in its own view so it can hold the editable fields.
private struct AutoSignInCard: View {
    @ObservedObject var state: BobState
    @ObservedObject var prefs: Prefs
    @State private var email = ""
    @State private var password = ""
    @State private var secret = ""
    @State private var editing = false

    private var hasSaved: Bool { Keychain.has(.password) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Fill my details on the sign-in screen", isOn: $prefs.autofillEnabled)
                .font(.system(size: 12))
            Toggle("Re-login automatically when the session expires", isOn: $prefs.autoReloginOnExpiry)
                .font(.system(size: 12))
                .disabled(!prefs.autofillEnabled)

            if editing || !hasSaved {
                editor
            } else {
                savedSummary
            }

            Text("Stored only in your macOS login Keychain and used only against the HiBob login form — never sent anywhere else. Signing in itself happens from the sign-in window (the “Sign in…” button above). If Okta changes their login page this may stop — sign in with a browser that day.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: load)
    }

    // MARK: Saved summary

    private var savedSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            summaryRow("envelope.fill", email.isEmpty ? "No email set" : email)
            summaryRow("key.fill", "Password ••••••••")
            if secret.isEmpty {
                summaryRow("lock.rotation", "No authenticator code")
            } else if let code = TOTP.code(secretBase32: secret) {
                summaryRow("lock.rotation", "Code \(code)", mono: true)
            } else {
                summaryRow("exclamationmark.triangle.fill", "Invalid TOTP secret", tint: .orange)
            }
            HStack(spacing: 8) {
                Label("Saved to Keychain", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 10)).foregroundStyle(.green)
                Spacer()
                Button("Clear", role: .destructive) { clearAll() }.controlSize(.small)
                Button("Edit") { editing = true }.controlSize(.small).buttonStyle(.borderedProminent)
            }
            .padding(.top, 2)
        }
        .disabled(!prefs.autofillEnabled)
    }

    private func summaryRow(_ symbol: String, _ text: String, mono: Bool = false, tint: Color = .secondary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint).frame(width: 16)
            Text(text)
                .font(.system(size: 12, design: mono ? .monospaced : .default))
                .foregroundStyle(text.hasPrefix("No ") || text.hasPrefix("Invalid") ? .secondary : .primary)
        }
    }

    // MARK: Editor

    private var editor: some View {
        Group {
            field("Email") {
                TextField("you@company.com", text: $email)
                    .textFieldStyle(.roundedBorder).textContentType(.username)
            }
            field("Password") {
                SecureField("HiBob / Okta password", text: $password).textFieldStyle(.roundedBorder)
            }
            field("TOTP secret") {
                VStack(alignment: .leading, spacing: 4) {
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
            HStack(spacing: 8) {
                Spacer()
                if hasSaved { Button("Cancel") { load(); editing = false }.controlSize(.small) }
                Button("Save") { save() }
                    .controlSize(.small).buttonStyle(.borderedProminent)
                    .disabled(email.isEmpty || password.isEmpty)
            }
        }
        .disabled(!prefs.autofillEnabled)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 12)).frame(width: 96, alignment: .leading).padding(.top, 4)
            content()
        }
    }

    // MARK: Load / save

    private func load() {
        email = UserDefaults.standard.string(forKey: "lastAccountEmail") ?? ""
        password = Keychain.get(.password) ?? ""
        secret = Keychain.get(.totpSecret) ?? ""
    }
    private func save() {
        UserDefaults.standard.set(email, forKey: "lastAccountEmail")
        Keychain.set(password, for: .password)
        // Accept a pasted otpauth:// URL, storing just the base32 secret.
        Keychain.set(TOTP.base32Secret(from: secret), for: .totpSecret)
        editing = false
    }
    private func clearAll() {
        email = ""; password = ""; secret = ""
        UserDefaults.standard.removeObject(forKey: "lastAccountEmail")
        Keychain.set(nil, for: .password); Keychain.set(nil, for: .totpSecret)
        editing = true
    }
}

/// Version + one-click update check against GitHub Releases.
private struct UpdatesCard: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current version \(updater.currentVersion)")
                    .font(.system(size: 12))
                Spacer()
                switch updater.phase {
                case .checking:
                    HStack(spacing: 6) { ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Checking…").font(.system(size: 11)).foregroundStyle(.secondary) }
                case .downloading, .installing:
                    HStack(spacing: 6) { ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text(updater.phase == .installing ? "Updating…" : "Downloading…")
                            .font(.system(size: 11)).foregroundStyle(.secondary) }
                default:
                    Button("Check for updates") { Task { await updater.checkNow() } }
                        .controlSize(.small)
                }
            }

            if let rel = updater.available {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                    Text("\(rel.version) is available").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Release notes") { updater.openReleasePage() }.controlSize(.small)
                    Button("Update now") { updater.install() }
                        .controlSize(.small).buttonStyle(.borderedProminent)
                }
            } else if case .upToDate = updater.phase {
                Label("You're up to date.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(.green)
            } else if case .failed(let msg) = updater.phase {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Updates download and install the latest build from GitHub, then relaunch Bob.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
