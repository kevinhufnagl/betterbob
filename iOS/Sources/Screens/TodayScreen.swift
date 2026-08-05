import BetterBobShared
import SwiftUI

/// Today, restaged for the phone: the wave hero with swimming Bob up top,
/// full-width glass clock actions, the touch-editable timeline, and today's
/// entries as native rows. All state flows through the shared engine.
///
/// Swiping horizontally pages through the cycle's days: the water tank stays
/// put — its level and numbers animate to the viewed day — while the content
/// below slides. Past days reuse the exact same layout through the per-day
/// engine calls; the clock dock, status pill and live warnings exist only on
/// today, where a clock actually runs.
struct TodayScreen: View {
    @ObservedObject var state: BobState
    @State private var editingEntry: EntryEdit?
    @State private var addingEntry = false
    /// The hero's live wave, so Bob rides the water it draws.
    @State private var wave = WaveModel()
    /// nil = live today; else the dateKey of the past day being viewed.
    @State private var viewedDayKey: String?
    /// Whether the last swipe went toward earlier days — drives which edge
    /// the below-hero content slides from.
    @State private var slideBack = false

    /// A fresh day: signed in, nothing punched yet, still clocked out. The
    /// empty water tank reads as "nothing here", so swap it for a welcome.
    private var isFreshDay: Bool {
        state.entries.isEmpty && state.clockState == .clockedOut
    }

    private var onBreakNow: Bool {
        if case .onBreak = state.clockState { return true }
        return false
    }

    // MARK: Day paging

    /// The cycle's days before today, oldest first — the swipe-back trail.
    private var pastKeys: [String] {
        let todayKey = DayFmt.today()
        return state.monthDays.map(\.dateKey).filter { $0 < todayKey }.sorted()
    }

    private var viewedDay: DayEntries? {
        viewedDayKey.flatMap { key in state.monthDays.first { $0.dateKey == key } }
    }

    private var screenTitle: String {
        guard let key = viewedDayKey, let date = DayFmt.date(key) else { return "Today" }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }

    /// Swipe left → toward today; swipe right → further back. Attached
    /// simultaneously so vertical scrolling keeps working; only decisively
    /// horizontal drags count.
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 25)
            .onEnded { v in
                let dx = v.translation.width
                guard abs(dx) > 60, abs(dx) > abs(v.translation.height) * 1.5 else { return }
                step(back: dx > 0)
            }
    }

    private func step(back: Bool) {
        let keys = pastKeys
        guard !keys.isEmpty else { return }
        slideBack = back
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            if back {
                if let current = viewedDayKey {
                    if let i = keys.firstIndex(of: current), i > 0 { viewedDayKey = keys[i - 1] }
                } else {
                    viewedDayKey = keys.last
                }
            } else if let current = viewedDayKey, let i = keys.firstIndex(of: current) {
                viewedDayKey = i + 1 < keys.count ? keys[i + 1] : nil
            }
        }
    }

    var body: some View {
        Group {
            // Signed-out and booting states never reach this screen — RootView
            // swaps the whole page for them.
            if viewedDayKey == nil, isFreshDay {
                // Full-bleed: expanding past the bottom safe area lets the
                // pool's water run under the glass tab bar to the screen's
                // physical bottom; the waterline and dock sit well above it.
                // The greeting IS the title here — hide the nav bar's.
                FreshDayWelcome(state: state)
                    .ignoresSafeArea(edges: .bottom)
                    .toolbarVisibility(.hidden, for: .navigationBar)
                    .simultaneousGesture(daySwipe)
            } else {
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        VStack(spacing: 16) {
                            // The one persistent water tank: values switch per
                            // day and the level sloshes to them — it never
                            // slides away with the content below.
                            heroSection(now: ctx.date)
                            dayContent(now: ctx.date)
                                .id(viewedDayKey ?? "today")
                                .transition(.asymmetric(
                                    insertion: .move(edge: slideBack ? .leading : .trailing)
                                        .combined(with: .opacity),
                                    removal: .move(edge: slideBack ? .trailing : .leading)
                                        .combined(with: .opacity)))
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.85),
                                   value: viewedDayKey)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
                .refreshable { await state.reconcile() }
                .simultaneousGesture(daySwipe)
            }
        }
        .bobScreen(title: screenTitle)
        // Past days come from the cycle grid, loaded on demand like the
        // Month pane does.
        .task { await state.loadCycleData() }
        // Add a past/forgotten entry by hand. Hidden on a fresh day, whose
        // nav bar is hidden anyway — swiping back or the Month tab covers it.
        .toolbar {
            if viewedDayKey != nil || !isFreshDay {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addingEntry = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add entry")
                }
            }
        }
        .sheet(item: $editingEntry) { edit in
            if let day = viewedDay {
                EntryEditSheet(entry: edit.entry,
                               reasonOptions: state.reasonOptions,
                               isLast: day.entries.max(by: { $0.start < $1.start })?.id == edit.entry.id,
                               suggestedEnd: state.suggestedEndForOpenEntry(edit.entry),
                               onSave: { start, end in
                                   state.updateEntryTimes(edit.entry, in: day.entries,
                                                          on: day.date, start: start, end: end)
                               },
                               onReason: { state.setReason(for: edit.entry, in: day.entries,
                                                           on: day.date, to: $0) },
                               onDelete: { state.deleteEntry(edit.entry, in: day.entries,
                                                             on: day.date) })
                    .presentationDetents([.medium])
            } else {
                EntryEditSheet(entry: edit.entry,
                               reasonOptions: state.reasonOptions,
                               isLast: isLastEntry(edit.entry),
                               suggestedEnd: state.suggestedEndForOpenEntry(edit.entry),
                               onSave: { start, end in
                                   state.updateEntryTimes(edit.entry, start: start, end: end)
                               },
                               onReason: { state.setReason(for: edit.entry, to: $0) },
                               onDelete: { state.deleteEntry(edit.entry) })
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $addingEntry) {
            if let day = viewedDay {
                let cal = Calendar.current
                let s = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day.date) ?? day.date
                let e = cal.date(bySettingHour: 17, minute: 0, second: 0, of: day.date) ?? day.date
                NewEntrySheet(reasonOptions: state.reasonOptions,
                              defaultStart: s, defaultEnd: e) { kind, start, end, reason in
                    state.addEntry(kind: kind, start: start, end: end,
                                   reason: reason?.name, in: day.entries, on: day.date)
                }
                .presentationDetents([.medium])
            } else {
                let (s, e) = defaultNewEntryTimes()
                NewEntrySheet(reasonOptions: state.reasonOptions,
                              defaultStart: s, defaultEnd: e) { kind, start, end, reason in
                    state.addEntry(kind: kind, start: start, end: end, reason: reason?.name)
                }
                .presentationDetents([.medium])
            }
        }
    }

    /// The day's chronologically last entry — the only one that can be
    /// reopened by clearing its end.
    private func isLastEntry(_ entry: AttendanceEntry) -> Bool {
        state.entries.max(by: { $0.start < $1.start })?.id == entry.id
    }

    /// A one-hour slot ending at the most recent entry's start (so a new entry
    /// slots in before what's logged), else the hour up to now — both rounded
    /// to 5 minutes.
    private func defaultNewEntryTimes() -> (Date, Date) {
        let anchor = state.entries.map(\.start).min() ?? Date()
        func round5(_ d: Date) -> Date {
            let t = (d.timeIntervalSinceReferenceDate / 300).rounded() * 300
            return Date(timeIntervalSinceReferenceDate: t)
        }
        let end = round5(anchor)
        return (end.addingTimeInterval(-3600), end)
    }

    // MARK: Hero — one tank for every day

    /// The viewed day's numbers, from the live engine for today and from the
    /// cycle grid for a past day (its target from the same summary sheet
    /// TodayVals reads).
    private struct DayVals {
        var worked: TimeInterval = 0
        var target: TimeInterval = 0
        var breakTotal: TimeInterval = 0
        var doneBy: Date?
        var fraction: Double { target > 0 ? worked / target : 0 }
    }

    private func vals(now: Date) -> DayVals {
        if let day = viewedDay {
            let dayEnd = day.entries.compactMap(\.end).max() ?? day.date
            let worked = AttendanceLogic.workedToday(entries: day.entries, now: dayEnd)
            let breaks = day.entries.filter { $0.kind == .breakTime }
                .reduce(0.0) { $0 + (($1.end ?? dayEnd).timeIntervalSince($1.start)) }
            let target = (state.cycleSummary?.days.first { $0.date == day.dateKey }?.target ?? 8) * 3600
            return DayVals(worked: worked, target: target, breakTotal: breaks, doneBy: nil)
        }
        let v = TodayVals(state, now: now)
        return DayVals(worked: v.worked, target: v.targetSecs,
                       breakTotal: v.breakTotal, doneBy: v.doneBy)
    }

    private func heroSection(now: Date) -> some View {
        let viewingToday = viewedDay == nil
        let v = vals(now: now)
        // The dock straddles the hero's bottom edge on today only; past days
        // have no clock to drive, so the tank keeps its full height plain.
        return hero(v, now: now, viewingToday: viewingToday)
            .padding(.bottom, viewingToday ? ActionDock.halfHeight : 0)
            .overlay(alignment: .bottom) {
                if viewingToday { ActionDock(state: state, now: now) }
            }
    }

    private func hero(_ v: DayVals, now: Date, viewingToday: Bool) -> some View {
        // Tall enough that the text block clears the dock straddling the
        // bottom edge; bottomInset reserves the covered strip inside the hero.
        LiquidHero(worked: v.worked, target: v.target, breakTotal: v.breakTotal,
                   doneBy: v.doneBy, compact: true, cornerRadius: 18,
                   bottomInset: viewingToday ? 30 : 0, wave: wave)
            .statusTint(viewingToday ? state.heroLimitTint : nil)
            .weekLine(viewingToday ? weekHeroLine(state, now: now) : nil)
            .frame(height: 215)
            .overlay(alignment: .topLeading) {
                // Swimming once the water is ~15% deep, straddling the top
                // edge like the Mac popover, riding the hero's own wave. On a
                // past day he's asleep on it — that day is over.
                if v.fraction >= 0.15 {
                    BuoyBob(sleeping: !viewingToday || state.clockState == .clockedOut,
                            onBreak: viewingToday && onBreakNow, size: 72)
                        .waveFloat(on: wave, at: CGPoint(x: 18, y: 10))
                }
            }
            .overlay(alignment: .top) {
                // Too little water to swim, but still on the clock: he pokes
                // up over the section's top edge (middle — the corners hold
                // the status pill and worked-time text).
                if viewingToday, v.fraction < 0.15, state.clockState != .clockedOut {
                    PeekingBob(size: 92, onBreak: onBreakNow)
                        .offset(y: -51)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Dry and clocked out (or an empty past day): asleep at the
                // bottom of the section.
                if v.fraction < 0.15, !viewingToday || state.clockState == .clockedOut {
                    SleepingBob()
                        .frame(width: 86, height: 54)
                        .padding(.trailing, 18)
                        .padding(.bottom, 8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if viewingToday {
                    StatusPill(state: state)
                        .padding(12)
                }
            }
            .glassSurface()
    }

    // MARK: Below the hero — slides between days

    @ViewBuilder
    private func dayContent(now: Date) -> some View {
        if let day = viewedDay {
            if day.entries.isEmpty {
                GlassCard {
                    Text("No entries recorded for this day.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
            } else {
                timelineCard(entries: day.entries, now: now, on: day.date)
                pastFixes(day)
                entriesSection(day.entries, day: day)
            }
        } else {
            if let queued = state.queue.first {
                Text("\(state.queue.count) queued · fires \(Fmt.clock(queued.fireAt))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !state.entries.isEmpty {
                timelineCard(entries: state.entries, now: now, on: Date())
            }
            warnings
            entriesSection(state.entries, day: nil)
        }
    }

    // MARK: Timeline strip (drag to edit — same math as the Mac)

    private func timelineCard(entries: [AttendanceEntry], now: Date, on date: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TIMELINE")
                .font(.footnote.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            GlassCard(padding: 14) {
                EditableDayStrip(entries: entries, now: now, height: 48) { updated in
                    state.saveDay(updated, on: date)
                }
            }
        }
    }

    // MARK: Warnings (today) and fixes (past days)

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

    @ViewBuilder private func pastFixes(_ day: DayEntries) -> some View {
        if let shortfall = state.breakShortfall(day.entries) {
            Button {
                state.fixBreakGuideline(in: day.entries, on: day.date)
            } label: {
                Label("Fix break — \(Fmt.hm(shortfall)) short of the guideline",
                      systemImage: "wand.and.rays")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
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

    @ViewBuilder private func entriesSection(_ entries: [AttendanceEntry], day: DayEntries?) -> some View {
        if state.signedIn, !entries.isEmpty {
            GlassGroupedSection(header: "Entries") {
                // Chronological, newest at the bottom — same reading order as
                // the Mac. Row identity is the sorted position, NOT entry.id:
                // optimistic entries haven't got a server id yet, and several
                // nil ids collapse into one identity, which is how rows used
                // to land out of order.
                let sorted = entries.sorted { $0.start < $1.start }
                ForEach(Array(sorted.enumerated()), id: \.offset) { i, entry in
                    GlassRow(showDivider: i > 0) {
                        entryRow(entry, day: day)
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: AttendanceEntry, day: DayEntries?) -> some View {
        let tint = entry.kind == .breakTime ? Color.bobOrange : Color.accentColor
        let end = entry.end
        let openEnd = day.map { d in d.entries.compactMap(\.end).max() ?? d.date } ?? Date()
        let duration = (end ?? openEnd).timeIntervalSince(entry.start)
        return HStack(spacing: 12) {
            Capsule().fill(tint).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.clock(entry.start)) – \(end.map(Fmt.clock) ?? (day == nil ? "now" : "open"))")
                    .font(.body.monospacedDigit())
                Text("\(entry.kind == .breakTime ? "Break" : "Work") · \(Fmt.hm(duration))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let id = entry.id, state.deletingEntries.contains(id) {
                ProgressView().controlSize(.small)
            } else if entry.kind == .work {
                reasonMenu(entry, day: day)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editingEntry = EntryEdit(entry: entry) }
    }

    @ViewBuilder private func reasonMenu(_ entry: AttendanceEntry, day: DayEntries?) -> some View {
        let hasReason = entry.reason?.isEmpty == false
        Menu {
            ForEach(state.reasonOptions, id: \.name) { opt in
                Button(opt.name) {
                    if let day {
                        state.setReason(for: entry, in: day.entries, on: day.date, to: opt)
                    } else {
                        state.setReason(for: entry, to: opt)
                    }
                }
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
