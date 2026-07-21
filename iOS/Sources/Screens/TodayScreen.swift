import BetterBobShared
import SwiftUI

/// A single sine wave filling from its crest to the bottom — the welcome
/// screen's calm water decoration.
private struct WelcomeWave: Shape {
    var phase: Double
    var height: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.height - height
        p.move(to: CGPoint(x: 0, y: mid))
        for x in stride(from: 0, through: rect.width, by: 3) {
            let y = mid + sin(x / rect.width * .pi * 2.4 + phase) * (height * 0.35)
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

/// Today, restaged for the phone: the wave hero with swimming Bob up top,
/// full-width glass clock actions, the touch-editable timeline, and today's
/// entries as native rows. All state flows through the shared engine.
struct TodayScreen: View {
    @ObservedObject var state: BobState
    @State private var editingEntry: EntryEdit?

    /// A fresh day: signed in, nothing punched yet, still clocked out. The
    /// empty water tank reads as "nothing here", so swap it for a welcome.
    private var isFreshDay: Bool {
        state.entries.isEmpty && state.clockState == .clockedOut
    }

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                // Signed-out and booting states never reach this screen —
                // RootView swaps the whole page for them.
                let vals = TodayVals(state, now: ctx.date)
                if isFreshDay {
                    freshDayWelcome(vals)
                        // Fill the viewport so the greeting centers on the
                        // whole page instead of floating above dead space.
                        .containerRelativeFrame(.vertical)
                } else {
                    VStack(spacing: 16) {
                        // The dock straddles the hero's bottom edge, like the
                        // Mac popover — the padding reserves its lower half.
                        hero(vals, now: ctx.date)
                            .padding(.bottom, 25)
                            .overlay(alignment: .bottom) {
                                ActionDock(state: state, now: ctx.date)
                            }
                        if let queued = state.queue.first {
                            Text("\(state.queue.count) queued · fires \(Fmt.clock(queued.fireAt))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if !state.entries.isEmpty {
                            timelineCard(now: ctx.date)
                        }
                        warnings
                        entriesSection
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .bobScreen(title: "Today")
        .refreshable { await state.reconcile() }
        .sheet(item: $editingEntry) { edit in
            EntryEditSheet(entry: edit.entry,
                           reasonOptions: state.reasonOptions,
                           onSave: { start, end in
                               state.updateEntryTimes(edit.entry, start: start, end: end)
                           },
                           onReason: { state.setReason(for: edit.entry, to: $0) },
                           onDelete: { state.deleteEntry(edit.entry) })
                .presentationDetents([.medium])
        }
    }

    // MARK: Fresh-day welcome

    private func freshDayWelcome(_ v: TodayVals) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            AnimatedBob().frame(width: 150, height: 150)
                .background(alignment: .center) { bubbles }
            Spacer().frame(height: 20)
            Text(greeting)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Ready when you are")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer().frame(height: 18)
            // Today's target as a quiet glass pill.
            Label("\(Fmt.hm(v.targetSecs)) today", systemImage: "target")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassSurface(cornerRadius: 22)
            Spacer(minLength: 28)
            ActionDock(state: state, now: Date())
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
        // A faint water motif along the bottom — the app's wave, at rest.
        .background(alignment: .bottom) { welcomeWaves }
    }

    /// Soft accent bubbles rising behind Bob — decorative, matches the palette.
    private var bubbles: some View {
        ZStack {
            ForEach(Array([(-70.0, 40.0, 14.0), (64.0, 8.0, 22.0), (-40.0, -60.0, 10.0),
                           (78.0, -44.0, 12.0), (30.0, 66.0, 8.0)].enumerated()), id: \.offset) { _, b in
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: b.2, height: b.2)
                    .offset(x: b.0, y: b.1)
            }
        }
        .frame(width: 220, height: 220)
        .blur(radius: 0.5)
    }

    /// Two layered waves in the accent hue, drifting like the LiquidHero's
    /// water — the same living motif, laid along the bottom of the page.
    private var welcomeWaves: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottom) {
                WelcomeWave(phase: t * 0.7, height: 42)
                    .fill(Color.accentColor.opacity(0.10))
                WelcomeWave(phase: -t * 1.1 + .pi, height: 30)
                    .fill(Color.accentColor.opacity(0.16))
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
        }
        .allowsHitTesting(false)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        if let first = state.profile?.name.split(separator: " ").first {
            return "\(part), \(first)"
        }
        return part
    }

    // MARK: Hero — the wave, untouched

    private func hero(_ v: TodayVals, now: Date) -> some View {
        // Tall enough that the text block clears the dock straddling the
        // bottom edge; bottomInset reserves the covered strip inside the hero.
        LiquidHero(worked: v.worked, target: v.targetSecs, breakTotal: v.breakTotal,
                   compact: true, cornerRadius: 18, bottomInset: 30)
            .statusTint(state.heroLimitTint)
            .frame(height: 215)
            .overlay(alignment: .topLeading) {
                // Swimming once the water is ~15% deep, straddling the top
                // edge like the Mac popover.
                if v.fraction >= 0.15 {
                    BuoyBob(sleeping: state.clockState == .clockedOut,
                            onBreak: v.onBreak, size: 72)
                        .padding(.leading, 18)
                        .offset(y: 10)
                }
            }
            .overlay(alignment: .top) {
                // Too little water to swim, but still on the clock: he pokes
                // up over the section's top edge (middle — the corners hold
                // the status pill and worked-time text).
                if v.fraction < 0.15, state.clockState != .clockedOut {
                    PeekingBob(size: 92, onBreak: v.onBreak)
                        .offset(y: -51)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Dry and clocked out: asleep at the bottom of the section
                // (clear of the centered clock-in dock).
                if v.fraction < 0.15, state.clockState == .clockedOut {
                    SleepingBob()
                        .frame(width: 86, height: 54)
                        .padding(.trailing, 18)
                        .padding(.bottom, 8)
                }
            }
            .overlay(alignment: .topTrailing) {
                StatusPill(state: state)
                    .padding(12)
            }
            .glassSurface()
    }

    // MARK: Timeline strip (drag to edit — same math as the Mac)

    private func timelineCard(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TIMELINE")
                .font(.footnote.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            GlassCard(padding: 14) {
                EditableDayStrip(entries: state.entries, now: now, height: 48) { updated in
                    state.saveDay(updated, on: Date())
                }
            }
        }
    }

    // MARK: Warnings

    @ViewBuilder private var warnings: some View {
        if state.signedIn {
            // One wand at a time: an over-long stretch implies the shortfall
            // too, and adding the missing break resolves both.
            if state.hasOverLongStretch(state.entries) {
                breakWarning(
                    headline: "Over your \(Fmt.hm(Prefs.shared.threshold)) max without a break",
                    buttonTitle: "Add \(Prefs.shared.breakMinutes)-min break",
                    note: "Inserts a break mid-shift — clock-in and clock-out stay the same."
                ) { state.addMissingBreak() }
            } else if let shortfall = state.breakGuidelineShortfall {
                breakWarning(
                    headline: "Breaks too short — \(Fmt.hm(shortfall)) more needed",
                    buttonTitle: "Extend break to \(Prefs.shared.breakMinutes) min",
                    note: "Only breaks of \(Prefs.shared.breakMinutes) min or more count toward the guideline."
                ) { state.fixBreakGuideline() }
            }
            if state.overDailyMax {
                warningRow("Past the daily limit — only clocking out helps.",
                           symbol: "exclamationmark.octagon.fill", tint: .bobRed)
            }
        }
    }

    /// The Mac popover's break banner restaged: headline, tinted wand
    /// button, and the tooltip copy as a visible sub-line (touch can't hover).
    private func breakWarning(headline: String, buttonTitle: String, note: String,
                              action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(headline, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.bobOrange)
            Button(action: action) {
                Label(buttonTitle, systemImage: "wand.and.stars")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.bobOrange)
            .disabled(state.busy)
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 14, tint: .bobOrange)
    }

    private func warningRow(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassSurface(cornerRadius: 14, tint: tint)
    }

    // MARK: Entries

    @ViewBuilder private var entriesSection: some View {
        if state.signedIn, !state.entries.isEmpty {
            GlassGroupedSection(header: "Entries") {
                let sorted = state.entries.sorted { $0.start > $1.start }
                ForEach(Array(sorted.enumerated()), id: \.element.id) { i, entry in
                    GlassRow(showDivider: i > 0) {
                        entryRow(entry)
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: AttendanceEntry) -> some View {
        let tint = entry.kind == .breakTime ? Color.bobOrange : Color.accentColor
        let end = entry.end
        let duration = (end ?? Date()).timeIntervalSince(entry.start)
        return HStack(spacing: 12) {
            Capsule().fill(tint).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.clock(entry.start)) – \(end.map(Fmt.clock) ?? "now")")
                    .font(.body.monospacedDigit())
                Text("\(entry.kind == .breakTime ? "Break" : "Work") · \(Fmt.hm(duration))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let id = entry.id, state.deletingEntries.contains(id) {
                ProgressView().controlSize(.small)
            } else if entry.kind == .work {
                reasonMenu(entry)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editingEntry = EntryEdit(entry: entry) }
    }

    @ViewBuilder private func reasonMenu(_ entry: AttendanceEntry) -> some View {
        let hasReason = entry.reason?.isEmpty == false
        Menu {
            ForEach(state.reasonOptions, id: \.name) { opt in
                Button(opt.name) { state.setReason(for: entry, to: opt) }
            }
        } label: {
            Text(hasReason ? entry.reason! : "Add reason")
                .font(.footnote.weight(.medium))
                .foregroundStyle(hasReason ? Color.primary : Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.accentColor.opacity(hasReason ? 0.10 : 0.16)))
        }
    }
}
