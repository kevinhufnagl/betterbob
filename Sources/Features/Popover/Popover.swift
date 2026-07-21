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
            } else if state.signedIn && state.entries.isEmpty && state.clockState == .clockedOut {
                // A fresh day: the welcome, same as the dashboard and iOS.
                FreshDayWelcome(state: state, compact: true)
                    .frame(height: 300)
                    .transition(.bobReplace)
            } else if state.signedIn {
                // 1s tick keeps worked-time and the countdown live.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 10) {
                        if prefs.popoverShowHeader {
                            // Dock straddles the hero's bottom edge, same as
                            // the dashboard; the padding reserves its lower half.
                            workedHeader(now: context.date)
                                .padding(.bottom, 25)
                                .overlay(alignment: .bottom) {
                                    ActionDock(state: state, now: context.date)
                                }
                        } else {
                            ActionDock(state: state, now: context.date)
                        }
                        if !state.queue.isEmpty {
                            Text("\(state.queue.count) queued · fires \(Fmt.clock(state.queue[0].fireAt))")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                                .transition(.bobBanner)
                        }
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
        .frame(width: 460)
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
                       compact: true, bottomInset: 20)
                .statusTint(state.heroLimitTint)
                .frame(height: 112)
                .padding(.top, dryAwake ? 28 : 21)
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
                    // A hair higher so his float's low point clears the text.
                    .offset(y: -2)
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
            // Newest entry on top, matching the dashboard's Today list.
            ForEach(Array(state.entries.reversed().enumerated()), id: \.offset) { index, entry in
                if index > 0 {
                    Divider().opacity(0.25)
                }
                HStack(spacing: 8) {
                    // The tinted label carries the work/break color cue.
                    Text(entry.kind.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(kindColor(entry.kind))
                    if entry.kind == .work {
                        reasonMenu(for: entry)
                    }
                    Spacer()
                    Text("\(Fmt.clock(entry.start)) – \(entry.end.map(Fmt.clock) ?? "now") (\(Fmt.hm((entry.end ?? Date()).timeIntervalSince(entry.start))))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.85))
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 24)
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
            // Hidden while the code field is up — the card carries its own copy.
            if !state.autoLoginInProgress {
                Text("Sign in to HiBob to get going")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if state.autoLoginInProgress {
                AutoLoginInline(state: state, fillWidth: true)
            } else if state.canAutoSignIn {
                // Credentials on file: one click per second-factor method — the
                // code field (or push wait) appears in place. Or open the window
                // for browser / other options.
                VStack(spacing: 8) {
                    SignInFactorGroup(state: state)
                    Button("More options") {
                        NotificationCenter.default.post(name: .closePopover, object: nil)
                        OnboardingController.shared.present()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                // No stored credentials: the window is where you set up automatic
                // or browser sign-in.
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

