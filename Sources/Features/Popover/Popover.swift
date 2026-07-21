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
                .transition(.bobReplace)
            } else if state.signedIn {
                // 1s tick keeps worked-time and the countdown live.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 10) {
                        if prefs.popoverShowHeader { workedHeader(now: context.date) }
                        actionButtons(now: context.date)
                        if prefs.popoverShowWarnings {
                            if state.overMaxNonBreak { missingBreakWarning }
                            if !state.overMaxNonBreak, let short = state.breakGuidelineShortfall {
                                shortBreakWarning(short)
                            }
                            if state.overDailyMax { overDailyMaxWarning }
                        }
                        if prefs.popoverShowTimeline, !state.entries.isEmpty {
                            EditableDayStrip(entries: state.entries, now: context.date,
                                             height: 28) { updated in
                                state.saveDay(updated, on: Date())
                            }
                            .transition(.bobBanner)
                        }
                        if prefs.popoverShowEntries, !state.entries.isEmpty {
                            timeline
                                .transition(.bobBanner)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .animation(Motion.standard, value: state.entries)
                    .animation(Motion.standard, value: state.overMaxNonBreak)
                    .animation(Motion.standard, value: state.breakGuidelineShortfall)
                    .animation(Motion.standard, value: state.overDailyMax)
                    .animation(Motion.standard, value: state.queue)
                }
                .transition(.bobReplace)
            } else {
                signInPrompt
                    .transition(.bobReplace)
            }

            updateBanner
                .animation(Motion.standard, value: updater.phase)
                .animation(Motion.standard, value: updater.installed)
                .animation(Motion.standard, value: updater.dismissedVersion)

            Divider().opacity(0.3)
            footer
        }
        .frame(width: prefs.popoverWidth.points)
        .animation(Motion.standard, value: state.signedIn)
        .animation(Motion.standard, value: state.ready)
    }

    // MARK: - Update banner

    @ViewBuilder
    private var updateBanner: some View {
        switch updater.phase {
        case .downloading, .installing:
            banner(icon: "arrow.down.circle") {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text(updater.phase == .installing ? "Installing update…" : "Downloading update…")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
            }
        default:
            // "Later" hides this exact version's banner (Settings still shows it).
            if let rel = updater.installed, updater.dismissedVersion != rel.version {
                banner(icon: "sparkles") {
                    HStack(spacing: 8) {
                        Text("Updated to \(rel.version) — applies on next start")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Button("Later") { updater.dismiss(rel) }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                        Button("Restart") { updater.relaunch() }
                            .controlSize(.small).buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func banner<Content: View>(icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12))
                .foregroundStyle(Color.primaryAccent(scheme))
            content()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.primaryAccent(scheme).opacity(0.10))
        .transition(.bobBanner)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: BobIcon.menuBar(height: 22).tinted(.labelColor))
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
        // Compact layout puts both buttons on one row.
        let layout = prefs.popoverCompact ? AnyLayout(HStackLayout(spacing: 8))
                                          : AnyLayout(VStackLayout(spacing: 8))
        // Side-by-side buttons share one height: the info line would make
        // just one of them taller, so the whole row grows together.
        let rowTall: Bool = {
            switch state.projectedClockState {
            case .clockedOut: return autoTagTrailing != nil
            case .working: return autoBreakTrailing(now: now) != nil
            case .onBreak: return endBreakTrailing(now: now) != nil
            }
        }()
        let rowHeight: CGFloat? = prefs.popoverCompact ? (rowTall ? 40 : 34) : nil
        VStack(spacing: 8) {
            // Buttons reflect the state after everything queued; punches fire a
            // minute apart on their own (see the queue in the dashboard footer).
            // The ZStack lets the outgoing row cross-fade over the incoming one
            // instead of stacking below it mid-transition.
            ZStack {
                layout {
                    // All actions wear the primary accent — the icons carry
                    // the semantics.
                    switch state.projectedClockState {
                    case .clockedOut:
                        actionButton("Clock in", symbol: "play.fill", tint: .primaryAccent(scheme),
                                     trailing: autoTagTrailing, height: rowHeight) { state.clockIn() }
                    case .working:
                        actionButton("Clock out", symbol: "stop.fill", tint: .primaryAccent(scheme),
                                     height: rowHeight) { state.clockOut() }
                        actionButton("Start break", symbol: "pause.circle.fill", tint: .primaryAccent(scheme),
                                     trailing: autoBreakTrailing(now: now), height: rowHeight) {
                            state.startManualBreak()
                        }
                    case .onBreak:
                        actionButton("End break", symbol: "play.fill", tint: .primaryAccent(scheme),
                                     trailing: endBreakTrailing(now: now), height: rowHeight) { state.endBreak() }
                        actionButton("Clock out", symbol: "stop.fill", tint: .primaryAccent(scheme),
                                     height: rowHeight) { state.clockOut() }
                    }
                }
                .id(clockStateKey)
                .transition(.bobReplace)
            }
            if !state.queue.isEmpty {
                Text("\(state.queue.count) queued · fires \(Fmt.clock(state.queue[0].fireAt))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .transition(.bobBanner)
            }
        }
        .animation(Motion.standard, value: state.projectedClockState)
    }

    /// Stable identity per clock state so the whole button row cross-fades.
    private var clockStateKey: String {
        switch state.projectedClockState {
        case .clockedOut: return "out"
        case .working: return "working"
        case .onBreak: return "break"
        }
    }

    /// Full-width tinted capsule — matches the dashboard quick-action style.
    private func actionButton(_ label: String, symbol: String, tint: Color,
                              trailing: String? = nil, height: CGFloat? = nil,
                              action: @escaping () -> Void) -> some View {
        PopoverActionButton(label: label, symbol: symbol, tint: tint, trailing: trailing,
                            height: height, action: action)
    }

    /// "auto in 42m" shown under the Start-break label while working.
    private func autoBreakTrailing(now: Date) -> String? {
        guard case .working = state.clockState, let due = state.autoBreakDue else { return nil }
        return due <= now ? "auto now" : "auto in \(Fmt.hm(due.timeIntervalSince(now)))"
    }

    /// The reason the new entry gets tagged with automatically (Wi-Fi rule or
    /// default), shown under the Clock-in / End-break label.
    private var autoTagTrailing: String? {
        state.currentAutoReason
    }

    /// "back in 12m" shown under the End-break label during an auto-break,
    /// plus the auto-tag when one applies: "back in 12m · as In Office".
    private func endBreakTrailing(now: Date) -> String? {
        guard let ends = state.autoBreakEnds else { return autoTagTrailing }
        let back = ends <= now ? "back now" : "back in \(Fmt.hm(ends.timeIntervalSince(now)))"
        guard let tag = autoTagTrailing else { return back }
        return "\(back) · \(tag)"
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
            .foregroundStyle(Color.bobOrange)
            Button {
                state.addMissingBreak()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars").font(.system(size: 11, weight: .bold))
                    Text("Add \(Prefs.shared.breakMinutes)-min break")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.bobOrange)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(Capsule().fill(Color.bobOrange.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Color.bobOrange.opacity(0.4), lineWidth: 0.7))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(state.busy)
            .fastTooltip("Insert a break mid-shift — clock-in/out stay the same.")
        }
        .padding(9)
        .background(Color.bobOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.bobOrange.opacity(0.28), lineWidth: 0.7))
        .transition(.bobBanner)
    }

    /// Breaks logged but too short to count ("doesn't meet guidelines").
    private func shortBreakWarning(_ short: TimeInterval) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                Text("Breaks too short — \(Fmt.hm(short)) more needed")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Color.bobOrange)
            Button {
                state.fixBreakGuideline()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars").font(.system(size: 11, weight: .bold))
                    Text("Extend break to \(Prefs.shared.breakMinutes) min")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.bobOrange)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(Capsule().fill(Color.bobOrange.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Color.bobOrange.opacity(0.4), lineWidth: 0.7))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(state.busy)
            .fastTooltip("Only breaks of \(Prefs.shared.breakMinutes) min or more count toward the guideline.")
        }
        .padding(9)
        .background(Color.bobOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.bobOrange.opacity(0.28), lineWidth: 0.7))
        .transition(.bobBanner)
    }

    /// Red and actionless (you can't un-work hours) — a nudge to clock out.
    private var overDailyMaxWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.octagon.fill").font(.system(size: 10))
            Text("Over your \(Fmt.hm(Prefs.shared.maxDayLimit)) daily max — time to clock out")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(Color.bobRed)
        .padding(9)
        .background(Color.bobRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.bobRed.opacity(0.28), lineWidth: 0.7))
        .transition(.bobBanner)
    }

    // MARK: - Worked total (prominent, above the buttons)

    /// The same liquid hero as the dashboard, sized for the popover — with
    /// a smaller Bob straddling its top edge in his swim ring.
    private func workedHeader(now: Date) -> some View {
        let v = TodayVals(state, now: now)
        let dryAwake = v.fraction < 0.15 && state.clockState != .clockedOut
        return ZStack(alignment: .topLeading) {
            LiquidHero(worked: v.worked, target: v.targetSecs, breakTotal: v.breakTotal,
                       compact: true)
                .frame(height: 100)
                .padding(.top, dryAwake ? 26 : 18)
                .overlay(alignment: .bottomTrailing) {
                    // Clocked out on dry land: asleep bottom-right.
                    if v.fraction < 0.15, state.clockState == .clockedOut {
                        SleepingBob().frame(width: 62, height: 39)
                            .padding(.trailing, 12)
                            .padding(.bottom, 8)
                            .transition(.bobReplace)
                    }
                }
            // Swimming once the water is ~15% deep — otherwise (awake)
            // standing on the deck, watching the pool fill below.
            if v.fraction >= 0.15 {
                BuoyBob(sleeping: state.clockState == .clockedOut,
                        onBreak: v.onBreak, size: 44)
                    .padding(.leading, 14)
                    .transition(.bobReplace)
            } else if dryAwake {
                // Hanging behind the card, paws on the lip, head peeking over.
                PeekingBob(size: 46, onBreak: v.onBreak)
                    .padding(.leading, 16)
                    .transition(.bobReplace)
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
                .frame(minHeight: prefs.popoverCompact ? 24 : 30)
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
            AnimatedBob(sleeping: true).frame(width: 54, height: 54)
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
                .transition(.opacity)
            } else if let sync = state.lastSync {
                Text("Synced \(Fmt.clock(sync))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
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
        .animation(Motion.quick, value: state.busy || !state.deletingEntries.isEmpty)
    }
}

/// A clock-in/out/break pill for the popover, with a hover state (matching the
/// dashboard's — subtle brighten, no size change).
private struct PopoverActionButton: View {
    let label: String
    let symbol: String
    let tint: Color
    var trailing: String? = nil
    /// Explicit height so row-mates match; nil sizes to the content.
    var height: CGFloat? = nil
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                    Text(label).font(.system(size: 13, weight: .semibold))
                }
                if let trailing {
                    // Second line so countdown + auto-tag get full width.
                    Text(trailing)
                        .font(.system(size: 9, weight: .medium)).opacity(0.7)
                }
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: height ?? (trailing == nil ? 34 : 40))
            // Split roles: vivid control cut for the fill/border, deepened
            // legible tone for the label.
            .background(Capsule().fill(Color.controlAccent(scheme).opacity(hovering ? 0.26 : 0.18)))
            .overlay(Capsule().strokeBorder(Color.controlAccent(scheme).opacity(hovering ? 0.65 : 0.45),
                                            lineWidth: 0.8))
            .contentShape(Capsule())
        }
        .buttonStyle(PressablePillStyle())
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .animation(Motion.quick, value: hovering)
    }
}
