import SwiftUI
import AppKit

/// Menu-bar popover: clock in, clock out, break — one flick away.
struct PopoverRootView: View {
    @ObservedObject var state: BobState
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var updater = Updater.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var scheme

    private func kindColor(_ kind: AttendanceEntry.Kind) -> Color {
        kind == .breakTime ? .breakAccent(scheme) : .workAccent(scheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)

            if state.signedIn && !state.ready {
                BobPlaceholder(title: "Getting your day ready…", lines: BobLines.loading, size: 64) {
                    ProgressView().controlSize(.small)
                }
            } else if state.signedIn {
                // 1s tick keeps worked-time and the countdown live.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 10) {
                        workedHeader(now: context.date)
                        actionButtons(now: context.date)
                        if state.overMaxNonBreak { missingBreakWarning }
                        if state.overDailyMax { overDailyMaxWarning }
                        if !state.entries.isEmpty {
                            timeline
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            } else {
                signInPrompt
            }

            updateBanner

            Divider().opacity(0.3)
            footer
        }
        .frame(width: 400)
    }

    // MARK: - Update banner

    @ViewBuilder
    private var updateBanner: some View {
        switch updater.phase {
        case .downloading, .installing:
            banner(icon: "arrow.down.circle") {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text(updater.phase == .installing ? "Updating — Bob will restart…" : "Downloading update…")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
            }
        default:
            if let rel = updater.available {
                banner(icon: "sparkles") {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Update available · \(rel.version)")
                                .font(.system(size: 11, weight: .semibold))
                            if case .failed = updater.phase {
                                Text("Update failed — try the release page")
                                    .font(.system(size: 9)).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Button("Later") { updater.dismissForNow() }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                        Button("Update") { updater.install() }
                            .controlSize(.small).buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func banner<Content: View>(icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Color.accentColor)
            content()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.10))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: BobIcon.menuBar(height: 22).tinted(.systemGreen))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("BetterBob").font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.signedIn {
                Button {
                    openAppWindow("main")
                } label: {
                    Image(systemName: "macwindow")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .fastTooltip("Open BetterBob")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func openAppWindow(_ id: String) {
        NotificationCenter.default.post(name: .closePopover, object: nil)
        NSApp.setActivationPolicy(.regular)
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var subtitle: String {
        guard state.signedIn else { return "Not signed in" }
        if let err = state.lastError { return err }
        switch state.clockState {
        case .clockedOut: return "Clocked out"
        case .working:
            // Day's first clock-in, not the current uninterrupted stretch.
            if let first = state.entries.map(\.start).min() {
                return "Working since \(Fmt.clock(first))"
            }
            return "Working"
        case .onBreak(let since): return "On break since \(Fmt.clock(since))"
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionButtons(now: Date) -> some View {
        VStack(spacing: 8) {
            // Buttons reflect the state after everything queued; punches fire a
            // minute apart on their own (see the queue in the dashboard footer).
            switch state.projectedClockState {
            case .clockedOut:
                let label = state.currentAutoReason.map { "Clock in · \($0)" } ?? "Clock in"
                actionButton(label, symbol: "play.fill", tint: .workAccent(scheme)) { state.clockIn() }
            case .working:
                actionButton("Clock out", symbol: "stop.fill", tint: .outAccent(scheme)) { state.clockOut() }
                actionButton("Start break", symbol: "pause.circle.fill", tint: .breakAccent(scheme),
                             trailing: autoBreakTrailing(now: now)) {
                    state.startManualBreak()
                }
            case .onBreak:
                actionButton("End break", symbol: "play.fill", tint: .workAccent(scheme),
                             trailing: backToWorkTrailing(now: now)) { state.endBreak() }
                actionButton("Clock out", symbol: "stop.fill", tint: .outAccent(scheme)) { state.clockOut() }
            }
            if !state.queue.isEmpty {
                Text("\(state.queue.count) queued · fires \(Fmt.clock(state.queue[0].fireAt))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .animation(.smooth(duration: 0.2), value: state.projectedClockState)
    }

    /// Full-width tinted capsule — matches the dashboard quick-action style.
    private func actionButton(_ label: String, symbol: String, tint: Color,
                              trailing: String? = nil,
                              action: @escaping () -> Void) -> some View {
        PopoverActionButton(label: label, symbol: symbol, tint: tint, trailing: trailing, action: action)
    }

    /// "auto in 42m" shown inside the Start-break button while working.
    private func autoBreakTrailing(now: Date) -> String? {
        guard case .working = state.clockState, let due = state.autoBreakDue else { return nil }
        return due <= now ? "auto now" : "auto in \(Fmt.hm(due.timeIntervalSince(now)))"
    }

    /// "back in 12m" shown inside the End-break button during an auto-break.
    private func backToWorkTrailing(now: Date) -> String? {
        guard let ends = state.autoBreakEnds else { return nil }
        return ends <= now ? "back now" : "back in \(Fmt.hm(ends.timeIntervalSince(now)))"
    }

    // MARK: - Over-max-non-break warning + wand

    private var missingBreakWarning: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                Text("Over your \(Fmt.hm(Prefs.shared.threshold)) max without a break")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.orange)
            Button {
                state.addMissingBreak()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars").font(.system(size: 11, weight: .bold))
                    Text("Add \(Prefs.shared.breakMinutes)-min break")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(Capsule().fill(Color.orange.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.7))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(state.busy)
            .fastTooltip("Insert a break mid-shift — clock-in/out stay the same.")
        }
        .padding(9)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.orange.opacity(0.28), lineWidth: 0.7))
    }

    /// Red and actionless (you can't un-work hours) — a nudge to clock out.
    private var overDailyMaxWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.octagon.fill").font(.system(size: 10))
            Text("Over your \(Fmt.hm(Prefs.shared.maxDayLimit)) daily max — time to clock out")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(.red)
        .padding(9)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.red.opacity(0.28), lineWidth: 0.7))
    }

    // MARK: - Worked total (prominent, above the buttons)

    /// Big worked figure in the same style as the dashboard's headline number,
    /// with the day's progress toward target on the right.
    private func workedHeader(now: Date) -> some View {
        let v = TodayVals(state, now: now)
        let tint: Color = v.over ? .workAccent(scheme) : .accentColor
        return HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(Fmt.hm(v.worked))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(tint).contentTransition(.numericText())
            Text("worked").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if v.targetSecs > 0 {
                Text("\(Int((v.fraction * 100).rounded()))%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
        }
    }

    // MARK: - Today's timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TODAY")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
                .padding(.bottom, 2)
            ForEach(Array(state.entries.enumerated()), id: \.offset) { index, entry in
                if index > 0 {
                    Divider().opacity(0.25)
                }
                HStack(spacing: 8) {
                    Image(systemName: entry.kind.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(kindColor(entry.kind))
                        .frame(width: 14)
                    Text(entry.kind.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                    if entry.kind == .work {
                        reasonMenu(for: entry)
                    }
                    Spacer()
                    Text("\(Fmt.clock(entry.start)) – \(entry.end.map(Fmt.clock) ?? "now") (\(Fmt.hm((entry.end ?? Date()).timeIntervalSince(entry.start))))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.85))
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
                .contextMenu {
                    if entry.id != nil {
                        Button(role: .destructive) {
                            state.deleteEntry(entry)
                        } label: {
                            Label("Delete entry", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(10)
        .insetCard()
    }

    /// Per-entry "Reason" picker (In Office, Work From Home, …) — shown
    /// when the tenant has reasons and the entry has a server id to edit.
    @ViewBuilder
    private func reasonMenu(for entry: AttendanceEntry) -> some View {
        if !state.reasonOptions.isEmpty, entry.id != nil {
            Menu {
                ForEach(state.reasonOptions, id: \.self) { option in
                    Button {
                        state.setReason(for: entry, to: option)
                    } label: {
                        if option.name == entry.reason {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(option.name)
                        }
                    }
                }
            } label: {
                let hasReason = !(entry.reason ?? "").isEmpty
                let accent = Color.reasonAccent(scheme)
                HStack(spacing: 3) {
                    Text(hasReason ? entry.reason! : "Set reason")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                        .opacity(0.7)
                }
                .foregroundStyle(hasReason ? accent : Color.secondary)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(hasReason ? accent.opacity(0.20) : Color.primary.opacity(0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder((hasReason ? accent : Color.primary).opacity(0.30), lineWidth: 0.8)
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
        } else if let reason = entry.reason {
            Text(reason)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
        }
    }

    // MARK: - Signed out / footer

    private var signInPrompt: some View {
        VStack(spacing: 8) {
            AnimatedBob().frame(width: 54, height: 54)
            Text("Bob's off the clock")
                .font(.system(size: 12, weight: .semibold))
            Text("Sign in to HiBob to get going")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if state.autoLoginInProgress {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Signing you in…").font(.system(size: 11, weight: .medium))
                    }
                    if !state.autoLoginStatus.isEmpty {
                        Text(state.autoLoginStatus).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: state.autoLoginStatus)
            } else {
                // One button — the sign-in window is where you pick automatic
                // vs browser (and set up automatic sign-in). Change it later in
                // Settings.
                Button {
                    NotificationCenter.default.post(name: .closePopover, object: nil)
                    OnboardingController.shared.present()
                } label: {
                    Label("Sign in…", systemImage: "arrow.right.circle.fill")
                }
                .controlSize(.small).buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
    }

    private var footer: some View {
        HStack {
            if state.busy || !state.deletingEntries.isEmpty {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("Saving…").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else if let sync = state.lastSync {
                Text("Synced \(Fmt.clock(sync))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// A clock-in/out/break pill for the popover, with a hover state (matching the
/// dashboard's — subtle brighten, no size change).
private struct PopoverActionButton: View {
    let label: String
    let symbol: String
    let tint: Color
    var trailing: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                Text(label).font(.system(size: 13, weight: .semibold))
                if let trailing {
                    Text("· \(trailing)")
                        .font(.system(size: 11, weight: .medium)).opacity(0.7)
                }
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Capsule().fill(tint.opacity(hovering ? 0.22 : 0.16)))
            .overlay(Capsule().strokeBorder(tint.opacity(hovering ? 0.55 : 0.4), lineWidth: 0.8))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
