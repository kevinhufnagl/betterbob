import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct SettingsPanel: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var state: BobState
    @ObservedObject var prefs: Prefs

    public init(state: BobState, prefs: Prefs) {
        self.state = state
        self.prefs = prefs
    }
    @State private var confirmingUninstall = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(title: "Settings",
                       subtitle: state.signedIn ? state.accountEmail : "Not signed in")

            SettingsGroup(title: "Account") { accountContent }
            SettingsGroup(title: "Automatic break") { autoBreakContent }
            SettingsGroup(title: "Daily limit") { dailyLimitContent }
            if state.signedIn {
                SettingsGroup(title: "Reasons") {
                    defaultReasonContent
                    #if os(macOS)
                    Divider().opacity(0.12)
                    wifiReasonContent
                    #endif
                }
            }
            SettingsGroup(title: "Notifications") { notificationsContent }
            #if os(macOS)
            SettingsGroup(title: "Menu bar") { menuBarContent }
            SettingsGroup(title: "Popover") { popoverContent }
            #endif
            SettingsGroup(title: "General") { generalContent }
            #if os(macOS)
            SettingsGroup(title: "Updates") { UpdatesCard() }
            SettingsGroup(title: "Uninstall") { uninstallContent }
            #endif
            if let err = state.lastError {
                SettingsGroup(title: "Diagnostics") { diagnosticsContent(err) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Account

    /// macOS opens the onboarding window; iOS asks the app root to show the
    /// onboarding cover instead.
    private func presentSignInSetup() {
        #if os(macOS)
        OnboardingController.shared.present()
        #else
        NotificationCenter.default.post(name: .presentOnboarding, object: nil)
        #endif
    }

    @ViewBuilder
    private var accountContent: some View {
        Group {
            if state.signedIn {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.primaryAccent(scheme))
                    Text("Signed in as \(state.accountEmail ?? "—")")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Sign-in setup…") { presentSignInSetup() }
                        .controlSize(.small)
                    Button("Sign out") { state.signOut() }
                        .controlSize(.small)
                }
            } else {
                Button {
                    presentSignInSetup()
                } label: {
                    Label("Sign in…", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .disabled(state.autoLoginInProgress)

                Text("Opens the sign-in window where you set up automatic sign-in — your password is stored in the Keychain, and at sign-in you type the one-time code or approve the Okta push. Edit or forget your saved sign-in there any time; a fully automatic option lives under Advanced there.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("The session lives in your login Keychain / cookie store and is used only against app.hibob.com — the same internal API the HiBob website itself uses with your own session. Nothing is sent anywhere else.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Auto-break

    @ViewBuilder
    private var autoBreakContent: some View {
        Group {
            Toggle("Insert a break automatically", isOn: $prefs.autoBreakEnabled)
                .font(.system(size: 12))
            Label("This is only to keep HiBob from flagging a missing break. Bob places it at the threshold — drag it to the time you actually took your break afterwards.",
                  systemImage: "info.circle")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    #if os(macOS)
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
                        Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.secondary)
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
                        Text("No rules yet.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }

                if !WiFiMonitor.shared.hasAccess {
                    Text("macOS needs Location access to read the Wi-Fi network name — “Add rule” prefills the current one and will ask for it. Your location is never used or stored.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(!prefs.wifiAutoReasonEnabled)

            Text("On a matching network, the open work entry gets that reason — overriding the default above. Only applied if you haven't set a reason yourself.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    #endif

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
            Toggle("Authenticator code needed to reconnect", isOn: $prefs.notifyAwaitingCode)
                .font(.system(size: 12))
        }
    }

    #if os(macOS)
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
    private var popoverContent: some View {
        Group {
            Toggle("Show worked-time header", isOn: $prefs.popoverShowHeader)
                .font(.system(size: 12))
            Toggle("Show warnings (missing break, daily max)", isOn: $prefs.popoverShowWarnings)
                .font(.system(size: 12))
            Toggle("Show today's entries", isOn: $prefs.popoverShowEntries)
                .font(.system(size: 12))
            Toggle("Show mini timeline (drag breaks and edges to edit)",
                   isOn: $prefs.popoverShowTimeline)
                .font(.system(size: 12))
        }
    }
    #endif

    @ViewBuilder
    private var generalContent: some View {
        #if os(macOS)
        Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            .font(.system(size: 12))
        #endif
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Automatically fix gaps and overlaps", isOn: $prefs.autoFixGapsOverlaps)
                .font(.system(size: 12))
            Text("When you edit or delete an entry, snap the day's entries together so there are no gaps or overlaps.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Uninstall

    #if os(macOS)
    @ViewBuilder
    private var uninstallContent: some View {
        Group {
            HStack {
                Text("Remove BetterBob from this Mac")
                    .font(.system(size: 12))
                Spacer()
                Button("Uninstall…", role: .destructive) { confirmingUninstall = true }
                    .controlSize(.small)
            }
            Text("Deletes your saved credentials, settings, and sign-in session, moves the app to the Trash, and quits. Your attendance records on HiBob are not touched.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Uninstall BetterBob?",
                            isPresented: $confirmingUninstall,
                            titleVisibility: .visible) {
            Button("Uninstall and quit", role: .destructive) { Uninstaller.run() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything BetterBob stores on this Mac is removed and the app moves to the Trash. Attendance data lives on HiBob and is not affected.")
        }
    }
    #endif

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
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if os(macOS)
/// Version + background-update status against GitHub Releases.
private struct UpdatesCard: View {
    @Environment(\.colorScheme) private var scheme
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
                        Text(updater.phase == .installing ? "Installing…" : "Downloading…")
                            .font(.system(size: 11)).foregroundStyle(.secondary) }
                default:
                    Button("Check for updates") { Task { await updater.checkNow() } }
                        .controlSize(.small)
                }
            }

            if let rel = updater.installed {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                    Text("\(rel.version) installed — applies on the next start")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Release notes") { updater.openReleasePage() }.controlSize(.small)
                    Button("Restart now") { updater.relaunch() }
                        .controlSize(.small).buttonStyle(.borderedProminent)
                }
            } else if case .upToDate = updater.phase {
                Label("You're up to date.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(Color.primaryAccent(scheme))
            } else if case .failed(let msg) = updater.phase {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Updates download and install automatically in the background, and take effect the next time Bob starts.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
