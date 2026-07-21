import BetterBobShared
import SwiftUI

/// Settings, restaged for the phone: glass grouped sections with native
/// controls bound straight to the shared Prefs/BobState — the same knobs the
/// Mac panel drives, minus mac-only groups (menu bar, popover, updates).
struct SettingsScreen: View {
    @ObservedObject var state: BobState
    @ObservedObject var prefs: Prefs

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                accountSection
                autoBreakSection
                dailyLimitSection
                if state.signedIn { reasonsSection }
                notificationsSection
                generalSection
                diagnosticsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .bobScreen(title: "Settings")
    }

    // MARK: Account

    private var accountSection: some View {
        GlassGroupedSection(
            header: "Account",
            footer: "The session lives in the Keychain and cookie store and is used only against app.hibob.com — the same internal API the HiBob website itself uses."
        ) {
            if state.signedIn {
                GlassRow(showDivider: false) {
                    LabeledContent("Signed in as") {
                        Text(state.accountEmail ?? "—")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                GlassRow {
                    Button("Sign-in setup") {
                        NotificationCenter.default.post(name: .presentOnboarding, object: nil)
                    }
                }
                GlassRow {
                    Button("Sign out", role: .destructive) { state.signOut() }
                }
            } else {
                GlassRow(showDivider: false) {
                    Button {
                        NotificationCenter.default.post(name: .presentOnboarding, object: nil)
                    } label: {
                        Label("Sign in…", systemImage: "arrow.right.circle.fill")
                    }
                    .disabled(state.autoLoginInProgress)
                }
            }
        }
    }

    // MARK: Automatic break

    private var autoBreakSection: some View {
        GlassGroupedSection(
            header: "Automatic break",
            footer: "Keeps HiBob from flagging a missing break. Bob places it at the threshold — drag it to the time you actually took your break afterwards. If the app was asleep at the mark, the break is inserted retroactively at the right time."
        ) {
            GlassRow(showDivider: false) {
                Toggle("Insert a break automatically", isOn: $prefs.autoBreakEnabled)
            }
            GlassRow {
                minutePicker("After uninterrupted work of", value: $prefs.thresholdMinutes,
                             range: stride(from: 60, through: 600, by: 15))
                    .disabled(!prefs.autoBreakEnabled)
            }
            GlassRow {
                minutePicker("Break length", value: $prefs.breakMinutes,
                             range: stride(from: 5, through: 120, by: 5))
                    .disabled(!prefs.autoBreakEnabled)
            }
        }
    }

    private var dailyLimitSection: some View {
        GlassGroupedSection(
            header: "Daily limit",
            footer: "Days over the limit show up red on Today and the month calendar, and Bob notifies you the moment you cross it while clocked in."
        ) {
            GlassRow(showDivider: false) {
                minutePicker("Warn when a day tops", value: $prefs.maxDayMinutes,
                             range: stride(from: 360, through: 960, by: 30))
            }
        }
    }

    private func minutePicker(_ label: String, value: Binding<Int>,
                              range: StrideThrough<Int>) -> some View {
        Picker(label, selection: value) {
            ForEach(Array(range), id: \.self) { minutes in
                Text(Fmt.hm(TimeInterval(minutes * 60))).tag(minutes)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: Reasons

    private var reasonsSection: some View {
        GlassGroupedSection(
            header: "Reasons",
            footer: "Applied to an untagged open work entry automatically."
        ) {
            GlassRow(showDivider: false) {
                Picker("Always tag work as", selection: $prefs.defaultReasonName) {
                    Text("Off").tag("")
                    ForEach(state.reasonOptions, id: \.name) { opt in
                        Text(opt.name).tag(opt.name)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        GlassGroupedSection(header: "Notify me when…") {
            GlassRow(showDivider: false) {
                Toggle("Auto-break started / ended", isOn: $prefs.notifyAutoBreak)
            }
            GlassRow { Toggle("Daily target reached", isOn: $prefs.notifyTargetReached) }
            GlassRow { Toggle("Worked past the daily max", isOn: $prefs.notifyOverMax) }
            GlassRow { Toggle("Timesheet deadline approaching", isOn: $prefs.notifyDeadline) }
            GlassRow { Toggle("Something failed", isOn: $prefs.notifyFailures) }
            GlassRow { Toggle("Authenticator code needed", isOn: $prefs.notifyAwaitingCode) }
        }
    }

    // MARK: General

    private var generalSection: some View {
        GlassGroupedSection(
            header: "General",
            footer: "When you edit or delete an entry, snap the day's entries together so there are no gaps or overlaps."
        ) {
            GlassRow(showDivider: false) {
                Toggle("Automatically fix gaps and overlaps", isOn: $prefs.autoFixGapsOverlaps)
            }
        }
    }

    // MARK: Diagnostics

    @ViewBuilder private var diagnosticsSection: some View {
        if let err = state.lastError {
            GlassGroupedSection(header: "Diagnostics") {
                GlassRow(showDivider: false) {
                    Label {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}
