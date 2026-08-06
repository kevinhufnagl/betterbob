import SwiftUI
#if os(macOS)
import AppKit
#endif

// The Today layout and its shared helpers — TodayVals, the actions row and
// the interactive timeline strip.

public struct TodayVals {
    public var worked: TimeInterval = 0
    public var targetSecs: TimeInterval = 8 * 3600
    public var remaining: TimeInterval = 0
    public var over = false
    public var fraction: Double = 0
    public var working = false
    public var onBreak = false
    public var started: Date?
    public var breakTotal: TimeInterval = 0
    public var autoBreakDue: Date?

    @MainActor
    public init(_ state: BobState, now: Date) {
        worked = AttendanceLogic.workedToday(entries: state.entries, now: now)
        let targetHours = state.cycleSummary?.days.first { $0.date == DayFmt.today() }?.target ?? 8
        targetSecs = targetHours * 3600
        remaining = max(0, targetSecs - worked)
        over = targetSecs > 0 && worked >= targetSecs
        fraction = targetSecs > 0 ? worked / targetSecs : 0
        if case .working = state.clockState { working = true }
        if case .onBreak = state.clockState { onBreak = true }
        started = state.entries.map(\.start).min()
        breakTotal = state.entries.filter { $0.kind == .breakTime }
            .reduce(0) { $0 + (($1.end ?? now).timeIntervalSince($1.start)) }
        autoBreakDue = state.autoBreakDue
        pendingBreak = state.autoBreakDue != nil ? Prefs.shared.breakLength : 0
    }

    /// Length of the auto-break still owed today — it delays doneBy when it
    /// will fire before the target is reached.
    public var pendingBreak: TimeInterval = 0

    /// Naive finish plus the owed auto-break, but only when that break will
    /// actually fire first — the same rule as WidgetSnapshot.doneBy, so every
    /// surface promises the same time.
    public var doneBy: Date? {
        guard working, remaining > 0 else { return nil }
        var done = Date().addingTimeInterval(remaining)
        if pendingBreak > 0, let due = autoBreakDue, due < done {
            done = done.addingTimeInterval(pendingBreak)
        }
        return done
    }
}

// MARK: - Week left

/// The hero's week line: the day's "2h 30m left" one scale up. Nil until the
/// cycle summary lands (no target, nothing to be left of). A leading "~" marks
/// a week whose days ahead the sheet states no target for, so the figure leans
/// on your typical day for those.
@MainActor
public func weekHeroLine(_ state: BobState, now: Date) -> String? {
    let today = TodayVals(state, now: now)
    let week = AttendanceLogic.weekProgress(days: state.cycleSummary?.days ?? [],
                                           workedToday: today.worked,
                                           todayTarget: today.targetSecs,
                                           now: now,
                                           timeOffAhead: Set(state.timeOffByDay.keys),
                                           targetHistory: TargetHistory.load())
    guard week.hasTarget else { return nil }
    guard !week.met else {
        // Under a minute over is just done — no one wants "+0m over".
        return week.over >= 60 ? "\(Fmt.hm(week.over)) over this week"
                               : "week's hours in"
    }
    return "\(week.estimated ? "~" : "")\(Fmt.hm(week.remaining)) left this week"
}

@MainActor
private func greetingText(_ state: BobState) -> String {
    let name = state.profile?.name.split(separator: " ").first.map(String.init)
    let h = Calendar.current.component(.hour, from: Date())
    let part = h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    return name.map { "\(part), \($0)" } ?? part
}

// MARK: - Shared: status pill, actions, to-scale strip, agenda

public struct StatusPill: View {
    @ObservedObject var state: BobState

    public init(state: BobState) { self.state = state }
    /// Match the water: the over-limit tint when past a limit, else the
    /// clock-state color (which already tracks the accent water).
    private var tint: Color { state.heroLimitTint ?? state.clockState.tint }
    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 8, height: 8)
                .shadow(color: tint.opacity(0.6), radius: 3)
            Text(state.clockState.title).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        // Material backing so the pill stays legible over a full, saturated
        // hero — a bare translucent tint washed out against the water.
        .background {
            Capsule().fill(.regularMaterial)
            Capsule().fill(tint.opacity(0.16))
        }
        .overlay(Capsule().strokeBorder(tint.opacity(0.40), lineWidth: 0.8))
        .animation(Motion.standard, value: state.clockState)
        .animation(Motion.standard, value: state.heroLimitTint)
    }
}

/// Clock in / out / break buttons + cooldown + auto-tag line.
/// The clock actions as a floating glass dock: a liquid-glass capsule bar
/// meant to straddle the hero's bottom edge like a dock on the water. The
/// most likely next action is a solid accent capsule (with the countdown /
/// auto-tag as its caption); the alternative rides along as a quiet glass
/// one. Buttons offer the state *after* everything queued, so you can line
/// up several punches; they fire a minute apart on their own.
public struct ActionDock: View {
    @ObservedObject var state: BobState

    public init(state: BobState, now: Date) {
        self.state = state
        self.now = now
    }
    var now = Date()
    @Environment(\.colorScheme) private var scheme

    @Namespace private var glassNS

    /// Half the pills' height. Hosts that straddle the dock over an edge
    /// reserve exactly this much below the line, so the pills sit vertically
    /// centered on it — the old wrapper capsule's 25 no longer applies.
    public static var halfHeight: CGFloat {
        #if os(iOS)
        24
        #else
        20
        #endif
    }

    public var body: some View {
        // One shared glass layer: each button is its own Liquid Glass capsule
        // and matched glassEffectIDs make state changes morph — one pill
        // splits into two on clock-in and merges back on clock-out, instead
        // of a cross-fade. No wrapper capsule; the pills ARE the dock.
        // The container's spacing is the merge radius: it must stay BELOW the
        // HStack gap or resting neighbours distort toward each other — shapes
        // should only flow together mid-morph, when they actually overlap.
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 10) {
                switch state.projectedClockState {
                case .clockedOut:
                    DockButton(label: "Clock in", sym: "play.fill",
                               caption: autoTagTrailing, prominent: true,
                               id: "primary", ns: glassNS) { state.clockIn() }
                case .working:
                    DockButton(label: "Start break", sym: "pause.fill",
                               caption: autoBreakTrailing, prominent: true,
                               id: "primary", ns: glassNS) { state.startManualBreak() }
                    DockButton(label: "Clock out", sym: "stop.fill",
                               id: "secondary", ns: glassNS) { state.clockOut() }
                case .onBreak:
                    DockButton(label: "End break", sym: "play.fill",
                               caption: endBreakTrailing, prominent: true,
                               id: "primary", ns: glassNS) { state.endBreak() }
                    DockButton(label: "Clock out", sym: "stop.fill",
                               id: "secondary", ns: glassNS) { state.clockOut() }
                }
            }
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.14), radius: 12, y: 4)
        .animation(Motion.standard, value: state.projectedClockState)
    }

    /// "auto in 42m" under the Start-break label while working.
    private var autoBreakTrailing: String? {
        guard case .working = state.clockState, let due = state.autoBreakDue else { return nil }
        return due <= now ? "auto now" : "auto in \(Fmt.hm(due.timeIntervalSince(now)))"
    }

    /// The reason the new entry gets tagged with automatically (Wi-Fi rule or
    /// default), shown under the Clock-in / End-break label.
    private var autoTagTrailing: String? {
        state.currentAutoReason
    }

    /// "back in 12m" under the End-break label during an auto-break, plus
    /// the auto-tag when one applies: "back in 12m · as In Office".
    private var endBreakTrailing: String? {
        guard let ends = state.autoBreakEnds else { return autoTagTrailing }
        let back = ends <= now ? "back now" : "back in \(Fmt.hm(ends.timeIntervalSince(now)))"
        guard let tag = autoTagTrailing else { return back }
        return "\(back) · \(tag)"
    }
}

/// One dock action: its own Liquid Glass capsule inside the dock's
/// GlassEffectContainer. Prominent gets a soft accent wash in the glass (the
/// next thing you'll do); quiet stays clear. The system supplies hover and
/// press response via interactive glass; matched ids morph across states.
/// Fixed height so a captioned button and its plain neighbour stay level.
private struct DockButton: View {
    let label: String
    let sym: String
    var caption: String? = nil
    var prominent = false
    let id: String
    let ns: Namespace.ID
    let act: () -> Void
    @Environment(\.colorScheme) private var scheme

    // Touch targets get a size up from the Mac's pointer-sized capsules.
    #if os(iOS)
    private let symSize: CGFloat = 14
    private let labelSize: CGFloat = 15
    private let captionSize: CGFloat = 11
    private let dockHeight: CGFloat = 48
    private let padH: CGFloat = 20
    #else
    private let symSize: CGFloat = 12
    private let labelSize: CGFloat = 13
    private let captionSize: CGFloat = 9
    private let dockHeight: CGFloat = 40
    private let padH: CGFloat = 16
    #endif

    var body: some View {
        Button(action: act) {
            VStack(spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: sym).font(.system(size: symSize, weight: .bold))
                    Text(label).font(.system(size: labelSize, weight: .semibold))
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: captionSize, weight: .medium)).opacity(0.75)
                }
            }
            .foregroundStyle(Color.primary.opacity(prominent ? 0.9 : 0.85))
            .padding(.horizontal, padH)
            .frame(height: dockHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(prominent ? .regular.tint(accentWash).interactive()
                               : .regular.interactive(), in: .capsule)
        .glassEffectID(id, in: ns)
        #if os(macOS)
        .onHover { h in
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        #endif
    }

    /// The welcome button's soft accent wash, shared by every prominent pill.
    private var accentWash: Color {
        (scheme == .dark
            ? Color.systemAccentHued(sat: 0.72, bri: 0.78)
            : Color.controlAccent(scheme)).opacity(0.3)
    }
}

/// Times under the day strip, one at each block boundary — the clock-in,
/// every work/break joint, and the day's end (or "now" while open). Real
/// times from the entries rather than an hour grid, positioned with the
/// same span math as the strip so each label sits exactly under its edge.
/// Labels that would collide are thinned left-to-right; the day's first
/// and last always survive.
struct BoundaryLabels: View {
    let entries: [AttendanceEntry]
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let sorted = entries.sorted { $0.start < $1.start }
            let start = sorted.map(\.start).min() ?? now
            let lastEnd = sorted.compactMap(\.end).max()
            let hasOpen = sorted.contains { $0.end == nil }
            let end = hasOpen ? max(now, lastEnd ?? now) : (lastEnd ?? now)
            let span = max(1, end.timeIntervalSince(start))
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                let all = marks(sorted, start: start, end: end, hasOpen: hasOpen,
                                span: span, w: w)
                ForEach(all, id: \.x) { m in
                    // The day's bookends carry a little more weight than the
                    // joints between blocks.
                    let edge = m.x == all.first?.x || m.x == all.last?.x
                    Text(m.text)
                        .font(.system(size: 9, weight: edge ? .semibold : .medium,
                                      design: .monospaced))
                        .foregroundStyle(edge ? AnyShapeStyle(.primary.opacity(0.7))
                                              : AnyShapeStyle(.secondary))
                        .position(x: min(max(m.x, 15), w - 15), y: 6)
                }
            }
        }
        .frame(height: 12)
    }

    private func marks(_ sorted: [AttendanceEntry], start: Date, end: Date, hasOpen: Bool,
                       span: TimeInterval, w: CGFloat) -> [(x: CGFloat, text: String)] {
        var times = Set(sorted.compactMap(\.end))
        times.insert(start)
        times.insert(end)
        let minGap: CGFloat = 42
        var kept: [(x: CGFloat, text: String)] = []
        for t in times.sorted() {
            let x = CGFloat(t.timeIntervalSince(start) / span) * w
            if let last = kept.last, x - last.x < minGap { continue }
            kept.append((x, t == end && hasOpen ? "now" : Fmt.clock(t)))
        }
        // The day's end always shows: drop earlier labels crowding it (never
        // the clock-in).
        let endX = w
        if let last = kept.last, last.x < endX {
            while kept.count > 1, endX - kept[kept.count - 1].x < minGap {
                kept.removeLast()
            }
            kept.append((endX, hasOpen ? "now" : Fmt.clock(end)))
        }
        return kept
    }
}

/// The day's entries as a to-scale bar with solid work/break blocks (display
/// only — editing happens in the entries table below).
struct DayStrip: View {
    let entries: [AttendanceEntry]
    let now: Date
    var height: CGFloat = 20
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let sorted = entries.sorted { $0.start < $1.start }
            let start = sorted.map(\.start).min() ?? now
            let end = max(now, sorted.compactMap(\.end).max() ?? now)
            let span = max(1, end.timeIntervalSince(start))
            let w = geo.size.width
            let radius = height / 3
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.06))
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, e in
                    let accent = e.kind == .breakTime ? Color.breakAccent(scheme) : Color.workAccent(scheme)
                    let bx = CGFloat(e.start.timeIntervalSince(start) / span) * w
                    let bw = CGFloat((e.end ?? now).timeIntervalSince(e.start) / span) * w
                    Rectangle()
                        .fill(accent)
                        .frame(width: max(2, bw), height: height)
                        .overlay { blockLabel(e, width: bw) }
                        .offset(x: bx)
                        .opacity(e.end == nil ? 0.82 : 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .frame(height: height)
    }

    /// Each block's time range on a readable pill, shrinking to just the start
    /// (then nothing) as the block gets narrower.
    @ViewBuilder
    private func blockLabel(_ e: AttendanceEntry, width bw: CGFloat) -> some View {
        let text: String? = bw > 80 ? "\(Fmt.clock(e.start))–\(e.end.map(Fmt.clock) ?? "now")"
            : bw > 34 ? Fmt.clock(e.start) : nil
        if let text {
            Text(text)
                .font(.bobUI(9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(.regularMaterial))
                .fixedSize()
        }
    }
}

/// Vertical agenda rows of the day's entries.
struct AgendaList: View {
    @ObservedObject var state: BobState
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.entries.enumerated()), id: \.offset) { i, e in
                let tint = e.kind == .breakTime ? Color.breakAccent(scheme) : Color.workAccent(scheme)
                HStack(spacing: 12) {
                    Text(Fmt.clock(e.start)).font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(width: 48, alignment: .leading)
                    ZStack {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 2)
                        Circle().fill(tint).frame(width: 9, height: 9)
                    }.frame(width: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.kind.label + (e.reason.map { " · \($0)" } ?? ""))
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(Fmt.clock(e.start)) – \(e.end.map(Fmt.clock) ?? "now") · \(Fmt.hm((e.end ?? now).timeIntervalSince(e.start)))")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                if i < state.entries.count - 1 { Divider().opacity(0.12).padding(.leading, 60) }
            }
            if state.clockState != .clockedOut {
                HStack(spacing: 12) {
                    Text("now").font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.bobTeal).frame(width: 48, alignment: .leading)
                    ZStack { Rectangle().fill(Color.bobTeal.opacity(0.4)).frame(width: 2)
                        Circle().stroke(Color.bobTeal, lineWidth: 2).frame(width: 9, height: 9) }.frame(width: 12)
                    Text(state.clockState.title.lowercased() + "…").font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }.padding(.vertical, 8)
            }
        }
    }
}

func slimBar(_ fraction: Double, tint: Color, height: CGFloat = 8) -> some View {
    GeometryReader { geo in
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.08))
            Capsule().fill(tint).frame(width: geo.size.width * min(1, max(0.02, fraction)))
        }
    }
    .frame(height: height)
}

// MARK: - Today (to-scale timeline)

public struct TodayTimeline: View {
    @ObservedObject var state: BobState

    public init(state: BobState) { self.state = state }
    @Environment(\.colorScheme) private var scheme
    // The 1Hz clock only exists to tick the live worked-time counter. A closed
    // Window scene keeps its view tree (and this clock) alive in SwiftUI, so
    // gate it on real window visibility — otherwise it re-lays-out the whole
    // Today pane every second in the background, burning CPU for nobody.
    @State private var windowVisible = true
    /// The hero's live wave, so Bob rides the water it draws.
    @State private var wave = WaveModel()

    public var body: some View {
        Group {
            if windowVisible {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    content(now: ctx.date)
                }
            } else {
                content(now: Date())
            }
        }
        .trackWindowVisibility { windowVisible = $0 }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let ctxDate = now
        let v = TodayVals(state, now: ctxDate)
        VStack(alignment: .leading, spacing: 16) {
                // Bob straddles the hero's top edge: the ring floats on the
                // waterline (the card's boundary), his head is out of the
                // water above it, his body inside.
                ZStack(alignment: .topLeading) {
                    LiquidHero(worked: v.worked, target: v.targetSecs, breakTotal: v.breakTotal,
                               doneBy: v.doneBy, greeting: greetingText(state), bottomInset: 12,
                               wave: wave) {
                        HStack {
                            Spacer()
                            StatusPill(state: state)
                        }
                    } bottom: {
                        EmptyView()
                    }
                    // Water turns orange/red on the same limits as the month
                    // cells (red past the daily max, orange for an over-long run
                    // or break shortfall).
                    .statusTint(state.heroLimitTint)
                    .weekLine(weekHeroLine(state, now: ctxDate))
                    // Content-sized: a fixed frame smaller than the content
                    // makes the hero spill past it top and bottom (SwiftUI
                    // doesn't clip), eating the gap to the next card.
                    // Swimming once it's ~15% deep, straddling the top edge —
                    // sitting a touch lower so he reads properly submerged, and
                    // riding the hero's own wave. An overlay, not a layout
                    // sibling, so the float reads the card's geometry.
                    .overlay(alignment: .topLeading) {
                        if v.fraction >= 0.15 {
                            // Flush with the section top — no dead air above his
                            // head; the ring stays just as submerged (center 8pt
                            // below the hero's edge).
                            BuoyBob(sleeping: state.clockState == .clockedOut,
                                    onBreak: v.onBreak)
                                .waveFloat(on: wave, at: CGPoint(x: 24, y: -34))
                                .transition(.bobReplace)
                        }
                    }
                    .padding(.top, 36)
                    .overlay(alignment: .bottomTrailing) {
                        // Clocked out on dry land: asleep bottom-right.
                        if v.fraction < 0.15, state.clockState == .clockedOut {
                            SleepingBob().frame(width: 86, height: 54)
                                .padding(.trailing, 18)
                                .padding(.bottom, 12)
                                .transition(.bobReplace)
                        }
                    }
                    if v.fraction < 0.15, state.clockState != .clockedOut {
                        // Not enough water to swim: he hangs behind the card,
                        // paws on the lip, head peeking over at the water.
                        PeekingBob(size: 64, onBreak: v.onBreak)
                            .padding(.leading, 26)
                            .transition(.bobReplace)
                    }
                }
                // The action dock floats half over the water, half over the
                // page — the bottom padding reserves room for the lower half
                // so it never overlaps the next card.
                .padding(.bottom, ActionDock.halfHeight)
                .overlay(alignment: .bottom) {
                    ActionDock(state: state, now: ctxDate)
                }

                // The day strip floats naked on the page — no card box — with
                // the entry boundary times underneath. (An empty day shows
                // nothing here; the entries card carries the empty message.)
                if !state.entries.isEmpty {
                    VStack(spacing: 5) {
                        EditableDayStrip(entries: state.entries, now: ctxDate, height: 40) { updated in
                            state.saveDay(updated, on: Date())
                        }
                        BoundaryLabels(entries: state.entries, now: ctxDate)
                    }
                    .padding(.horizontal, 2)
                }

                // A forgotten clock-out on a past day is a real data problem —
                // surface it here on Today, not only in the month tab.
                if let fc = state.forgottenClockOut { unclosedBanner(fc).transition(.bobBanner) }
                if case .onBreak = state.clockState { breakBanner(ctxDate).transition(.bobBanner) }
                if state.overMaxNonBreak { missingBreakBanner.transition(.bobBanner) }
                if !state.overMaxNonBreak, let short = state.breakGuidelineShortfall {
                    shortBreakBanner(short).transition(.bobBanner)
                }
                if state.overDailyMax { overDailyMaxBanner.transition(.bobBanner) }

                EntriesTable(state: state)
            }
        .animation(Motion.standard, value: state.clockState)
        .animation(Motion.standard, value: state.overMaxNonBreak)
        .animation(Motion.standard, value: state.breakGuidelineShortfall)
        .animation(Motion.standard, value: state.overDailyMax)
        .animation(Motion.standard, value: state.entries)
        .animation(Motion.standard, value: state.unclosedDays)
    }

    /// Forgot-to-clock-out CTA on Today: closes the open entry at the smart
    /// check-out guess on one click (matches the popover banner + month fix).
    private func unclosedBanner(_ fc: (date: Date, dateKey: String, suggestedEnd: Date)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.bobMagenta)
            VStack(alignment: .leading, spacing: 1) {
                Text("Forgot to clock out \(fc.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                    .font(.system(size: 12, weight: .semibold))
                Text("That entry is still open — close it at your usual check-out. You can fine-tune the time after.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { state.closeForgottenClockOut() } label: {
                Label("Close at \(Fmt.clock(fc.suggestedEnd))", systemImage: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(Color.bobMagenta.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(Color.bobMagenta.opacity(0.45), lineWidth: 0.8))
                    .foregroundStyle(Color.bobMagenta)
            }.buttonStyle(.plain).disabled(state.busy)
        }
        .padding(14)
        .background(Color.bobMagenta.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.bobMagenta.opacity(0.30), lineWidth: 0.8))
    }

    /// Shown while on a break — makes clear whether Bob will clock you back in.
    @ViewBuilder
    private func breakBanner(_ now: Date) -> some View {
        let tint = Color.breakAccent(scheme)
        HStack(spacing: 12) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                if let ends = state.autoBreakEnds {
                    Text("On an automatic break").font(.system(size: 13, weight: .semibold))
                    let mins = ends <= now ? "any moment" : "in \(Fmt.hm(ends.timeIntervalSince(now)))"
                    Text("Bob clocks you back in at \(Fmt.clock(ends)) — \(mins).")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("On a break").font(.system(size: 13, weight: .semibold))
                    Text("This one won't resume by itself — end it whenever you're ready.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(tint.opacity(0.30), lineWidth: 0.8))
    }

    private var missingBreakBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.bobOrange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Over your \(Fmt.hm(Prefs.shared.threshold)) max without a break")
                    .font(.system(size: 12, weight: .semibold))
                Text("Insert a \(Prefs.shared.breakMinutes)-min break mid-shift — clock-in/out stay the same.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { state.addMissingBreak() } label: {
                Label("Add \(Prefs.shared.breakMinutes)-min break", systemImage: "wand.and.stars").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(Color.bobOrange.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(Color.bobOrange.opacity(0.45), lineWidth: 0.8))
                    .foregroundStyle(Color.bobOrange)
            }.buttonStyle(.plain).disabled(state.busy)
        }
        .padding(14)
        .background(Color.bobOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.bobOrange.opacity(0.30), lineWidth: 0.8))
    }

    /// HiBob would flag this day as "Break not taken or doesn't meet
    /// guidelines": breaks exist but are too short to count.
    private func shortBreakBanner(_ short: TimeInterval) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.bobOrange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Breaks too short — \(Fmt.hm(short)) more needed")
                    .font(.system(size: 12, weight: .semibold))
                Text("Only breaks of \(Prefs.shared.breakMinutes) min or more count toward the guideline. Extend a break — clock-in/out stay the same.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { state.fixBreakGuideline() } label: {
                Label("Extend break", systemImage: "wand.and.stars").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(Color.bobOrange.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(Color.bobOrange.opacity(0.45), lineWidth: 0.8))
                    .foregroundStyle(Color.bobOrange)
            }.buttonStyle(.plain).disabled(state.busy)
        }
        .padding(14)
        .background(Color.bobOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.bobOrange.opacity(0.30), lineWidth: 0.8))
    }

    /// Red and actionless — you can't un-work hours, so unlike the missing
    /// break there's no fix button.
    private var overDailyMaxBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.bobRed)
            VStack(alignment: .leading, spacing: 1) {
                Text("Over your \(Fmt.hm(Prefs.shared.maxDayLimit)) daily max")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(Fmt.hm(state.workedToday)) worked today — time to clock out.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.bobRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.bobRed.opacity(0.30), lineWidth: 0.8))
    }

}

/// Gate for the dashboard hero's sweep-in: it plays once per "window
/// session". Closing the main window bumps the generation, so reopening it
/// (from the popover or an app relaunch) replays the sweep — but tab
/// switches, focus changes and un-occlusion render the settled water
/// immediately.
@MainActor
final class HeroSweep {
    static let shared = HeroSweep()
    private var generation = 0
    private var played = -1
    private var observer: NSObjectProtocol?

    private init() {
        #if os(macOS)
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            guard let window = (note.object as? NSWindow),
                  window.identifier?.rawValue.hasPrefix("main") == true else { return }
            DispatchQueue.main.async { HeroSweep.shared.generation += 1 }
        }
        #endif
    }

    /// True the first time a hero asks in the current window session.
    func shouldPlay() -> Bool {
        guard played != generation else { return false }
        played = generation
        return true
    }

    /// The popover's hero sweeps just once per app run — the very first time
    /// it's seen; every later popover open renders the settled water.
    private var popoverPlayed = false
    func shouldPlayPopover() -> Bool {
        guard !popoverPlayed else { return false }
        popoverPlayed = true
        return true
    }
}

/// Outsiders-style liquid progress hero: the water level is today's fraction
/// of target, with a sloshing waterline. Optional `top`/`bottom` slots render
/// on the water — the dashboard puts its greeting row and the timeline-plus-
/// buttons glass panel there. `cornerRadius: 0` makes it a full-bleed section.
/// The hero's edge light, as a ramp: thin overlapping bars stepping into the
/// water, their opacity falling off smoothly. Four wide layers left ridges you
/// could count; bars narrower than their spacing blend into one gradient that
/// follows the waterline. (File scope: `LiquidHero` is generic, and generic
/// types can't hold static stored properties.)
private let waterEdgeLight: [(inset: CGFloat, opacity: Double)] = (0..<14).map { step in
    let depth = Double(step) * 2
    return (inset: CGFloat(-1 - depth), opacity: 0.115 * exp(-pow(depth / 11, 1.7)))
}
private let waterEdgeLightWidth: CGFloat = 4.5

public struct LiquidHero<Top: View, Bottom: View>: View {
    let worked: TimeInterval
    let target: TimeInterval
    var breakTotal: TimeInterval = 0
    /// Projected finish (break-aware, from TodayVals) — joins the subline
    /// while working so the hero answers "when am I done" everywhere the
    /// Live Activity does.
    var doneBy: Date?
    /// Smaller type and padding for the popover.
    var compact = false
    /// Shown above the numbers, like the phone page's greeting line.
    var greeting: String?
    var cornerRadius: CGFloat = 16
    /// Display overrides: the time-off pool reuses the water with its own
    /// numbers (days instead of hours) and its own fill level.
    var customFraction: Double?
    var customBig: String?
    var customLine2: String?
    var customLine3: String?
    let top: Top
    let bottom: Bottom

    /// Extra bottom padding for the content — room for an ActionDock that
    /// straddles the hero's bottom edge, so no text runs under it.
    var bottomInset: CGFloat = 0

    /// Publishes the wave being drawn so a swimmer can ride it. Pass the same
    /// model to `.waveFloat(…)`; heroes nobody floats on leave it nil.
    var wave: WaveModel?

    /// When set, the water is drawn in this color's hue instead of the system
    /// accent — orange/red for over-limit days, matching the month cells. Set
    /// via `.statusTint(_:)` so callers don't touch the init.
    var statusTint: Color?

    /// Where the week stands, appended to the day's own subline after a dot.
    /// Set via `.weekLine(_:)`; nil leaves the subline alone. See
    /// `weekHeroLine(_:now:)`.
    var weekLine: String?

    /// The water's hue: the status tint when over a limit, else the accent.
    private var activeHue: Double { statusTint?.hueComponent ?? Color.accentHue }

    public init(worked: TimeInterval, target: TimeInterval, breakTotal: TimeInterval = 0,
         doneBy: Date? = nil,
         compact: Bool = false, greeting: String? = nil, cornerRadius: CGFloat = 16,
         customFraction: Double? = nil, customBig: String? = nil,
         customLine2: String? = nil, customLine3: String? = nil,
         bottomInset: CGFloat = 0, wave: WaveModel? = nil,
         @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.worked = worked
        self.target = target
        self.breakTotal = breakTotal
        self.doneBy = doneBy
        self.compact = compact
        self.greeting = greeting
        self.cornerRadius = cornerRadius
        self.customFraction = customFraction
        self.customBig = customBig
        self.customLine2 = customLine2
        self.customLine3 = customLine3
        self.bottomInset = bottomInset
        self.wave = wave
        self.top = top()
        self.bottom = bottom()
    }

    @Environment(\.colorScheme) private var scheme
    /// Anchor for the sweep-in and the decaying wave.
    @State private var appearedAt: Date?
    /// The 30fps wave clock only runs while the window can actually be seen —
    /// SwiftUI retains closed windows, and an unpaused clock burns CPU forever.
    @State private var windowVisible = true
    // Fresh wave character on every appearance, so no two sloshes look alike.
    @State private var seedPhase = Double.random(in: 0..<(2 * .pi))
    @State private var seedFreq = Double.random(in: 1.9...2.6)
    @State private var seedAsymPhase = Double.random(in: 0..<(2 * .pi))
    @State private var seedDetail2 = Double.random(in: 0..<(2 * .pi))
    @State private var seedDetail3 = Double.random(in: 0..<(2 * .pi))
    /// Eases the waterline toward a changed fraction (an entry edit moves the
    /// level by a lot at once) instead of snapping. Nil while tracking live.
    @State private var levelAnim: (from: Double, to: Double, start: Date)?

    private var fraction: Double {
        customFraction ?? (target > 0 ? min(1, worked / target) : 0)
    }
    private var percent: Int { target > 0 ? Int((worked / target * 100).rounded()) : 0 }

    /// The level to draw: mid-animation it eases from→to; otherwise the live
    /// fraction (also after an animation finishes, so second-by-second creep
    /// never drifts behind).
    private func displayedFraction(at date: Date) -> Double {
        guard let anim = levelAnim else { return fraction }
        let p = date.timeIntervalSince(anim.start) / 0.9
        guard p < 1 else { return fraction }
        let eased = 1 - pow(1 - max(0, p), 3)
        return anim.from + (anim.to - anim.from) * eased
    }

    // The water wears the Mac's accent color — the same hue the system
    // gives buttons and sidebar selections — using the original teal's
    // saturation/brightness recipe: deep and saturated in dark mode,
    // pastel with dark ink in light mode.
    private var dark: Bool { scheme == .dark }
    private var waterGradient: LinearGradient {
        let h = activeHue
        let stops = dark
            ? [Color.hued(h, sat: 0.76, bri: 0.28), Color.hued(h, sat: 0.72, bri: 0.44),
               Color.hued(h, sat: 0.68, bri: 0.60)]
            : [Color.hued(h, sat: 0.32, bri: 0.80), Color.hued(h, sat: 0.30, bri: 0.86),
               Color.hued(h, sat: 0.28, bri: 0.91)]
        return LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
    }
    private var glowColor: Color {
        dark ? Color.hued(activeHue, sat: 0.45, bri: 0.88) : Color.hued(activeHue, sat: 0.14, bri: 0.99)
    }
    private var baseColor: Color {
        dark ? Color.hued(activeHue, sat: 0.55, bri: 0.09) : Color.hued(activeHue, sat: 0.08, bri: 0.92)
    }
    private var ink: Color { dark ? .white : Color(red: 0.06, green: 0.20, blue: 0.24) }

    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            top.foregroundStyle(ink)
            Spacer(minLength: compact ? 4 : 8)
            VStack(alignment: .leading, spacing: 2) {
                if let greeting, !compact {
                    Text(greeting)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.75))
                        .padding(.bottom, 2)
                }
                // Worked time is the headline; the percentage sits under it.
                Text(customBig ?? Fmt.hm(worked))
                    .font(.system(size: compact ? 30 : 44, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(Motion.numeric, value: customBig ?? Fmt.hm(worked))
                    .foregroundStyle(ink)
                Text(customLine2 ?? (target > 0 ? "\(percent)% of \(Fmt.hm(target))" : "worked today"))
                    .font(.system(size: compact ? 11.5 : 13, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.92))
                    .contentTransition(.numericText())
                    .animation(Motion.numeric, value: customLine2 ?? "\(percent)")
                // The day's line, with the week riding along on the end of it
                // after a dot — quieter than the day, same row.
                sublineText
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(ink.opacity(0.66))
                    .contentTransition(.numericText())
                    .animation(Motion.numeric, value: (customLine3 ?? subline) + (weekLine ?? ""))
            }
            bottom
        }
        .padding(compact ? 12 : 20)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Water sized by the content — a greedy GeometryReader sibling
            // would fight a slot-driven height.
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    baseColor
                    // A finished day settles into a still, straight edge; an
                    // unfinished one keeps a small standing wave going after
                    // the arrival slosh dies down.
                    let animating = levelAnim.map { Date().timeIntervalSince($0.start) < 0.9 } ?? false
                    let settled = fraction >= 1 && !animating
                        && (appearedAt.map { Date().timeIntervalSince($0) > 14 } ?? true)
                    if Motion.reduce || settled || !windowVisible {
                        water(in: geo.size, field: field(level: fraction, at: Date(),
                                                         sweep: 1, still: true))
                    } else {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                            // Clamped: the anchor sits slightly in the future
                            // so the sweep starts after the pane transition
                            // has finished, instead of stuttering through it.
                            let t = max(0, appearedAt.map { ctx.date.timeIntervalSince($0) } ?? 0)
                            let eased = 1 - pow(1 - min(1, t / 1.5), 3)
                            water(in: geo.size,
                                  field: field(level: displayedFraction(at: ctx.date) * eased,
                                               at: ctx.date, sweep: eased))
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if cornerRadius > 0 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08),
                                  lineWidth: 0.6)
            }
        }
        .onChange(of: fraction) { old, new in
            guard !Motion.reduce else { return }
            let now = Date()
            if let anim = levelAnim, now.timeIntervalSince(anim.start) < 0.9 {
                // Mid-glide: redirect only if the destination itself moved,
                // continuing from the currently displayed position.
                guard abs(new - anim.to) > 0.005 else { return }
                levelAnim = (from: displayedFraction(at: now), to: new, start: now)
            } else {
                // No glide (or a finished one, whose displayed value tracks
                // the live fraction again — comparing against `new` there
                // would always read as zero delta and skip the ease).
                // Deadband: the per-second tick creeps invisibly on its own —
                // only real jumps (entry edits, break changes) get the ease.
                guard abs(new - old) > 0.005 else { return }
                levelAnim = (from: old, to: new, start: now)
            }
        }
        .trackWindowVisibility { visible in
            // Regaining visibility resumes the standing wave where it was;
            // the sweep only replays for a fresh window session (reopened
            // after a close).
            if visible && !windowVisible && !compact && HeroSweep.shared.shouldPlay() {
                appearedAt = Date().addingTimeInterval(0.4)
            }
            windowVisible = visible
        }
        .onAppear {
            if compact {
                appearedAt = HeroSweep.shared.shouldPlayPopover()
                    ? Date()
                    : Date().addingTimeInterval(-60)
            } else if HeroSweep.shared.shouldPlay() {
                appearedAt = Date().addingTimeInterval(0.4)
            } else {
                // Same window session (tab switch back, refocus): render the
                // settled water immediately, standing wave already going.
                // An anchor safely in the past — but not distantPast, which
                // would feed astronomically large phases into sin().
                appearedAt = Date().addingTimeInterval(-60)
            }
        }
    }

    /// The wave to draw at `date`: the arrival slosh is bigger, faster and
    /// lopsided (second harmonic); all three fade slowly toward the small, slow,
    /// symmetric standing wave. `still` flattens it outright, for Reduce Motion
    /// and for a day that has settled.
    private func field(level: Double, at date: Date, sweep: Double,
                       still: Bool = false) -> WaveField {
        let t = max(0, appearedAt.map { date.timeIntervalSince($0) } ?? 0)
        let decay = exp(-t / 3.0)
        let sustain: Double = fraction < 1 ? 5 : 0
        return WaveField(
            level: level,
            amplitude: still ? 0 : sustain + (11 - sustain) * decay * (0.3 + 0.7 * sweep),
            phase: seedPhase + 1.5 * t + (3.3 - 1.5) * 3.0 * (1 - decay),
            asym: still ? 0 : 0.55 * exp(-t / 2.5),
            freq: seedFreq, asymPhase: seedAsymPhase,
            detail2: seedDetail2, detail3: seedDetail3)
    }

    /// The fill plus its edge light: a soft band of light gathered under the
    /// waterline, and a crisp rim line stroked exactly along the edge — a
    /// specular highlight, not a soft blur.
    /// Explicit ZStack: a bare view tuple inside TimelineView stacks
    /// vertically instead of overlapping.
    private func water(in size: CGSize, field: WaveField) -> some View {
        // Hand the swimmer the wave we're about to draw. A plain box write, no
        // publishing — it invalidates nothing, and the float re-reads it on its
        // own per-frame clock.
        wave?.record(field, in: size)
        let shape = WaterShape(field: field)
        return ZStack(alignment: .topLeading) {
            shape.fill(waterGradient)
            if field.level > 0.02 {
                // Light gathered under the waterline. It follows the wave — a
                // straight gradient band read as a ruled line against a curved
                // edge — but on its own slower, shallower wave, the way light in
                // water never quite traces the surface.
                let band = WaterEdgeShape(field: field.parallel)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(waterEdgeLight.enumerated()), id: \.offset) { _, layer in
                        band
                            .stroke(glowColor.opacity(layer.opacity),
                                    style: StrokeStyle(lineWidth: waterEdgeLightWidth,
                                                       lineCap: .round))
                            .offset(x: layer.inset)
                    }
                }
                // One blur over the stack, not one per bar: it only has to take
                // the edge off bars that already overlap.
                .blur(radius: 2)
                .mask(shape)
                WaterEdgeShape(field: field)
                    .stroke(glowColor.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// The day's subline plus the week's tail, as one run of text. The tail is
    /// styled a shade fainter than the rest so the row still reads day-first.
    private var sublineText: Text {
        let day = customLine3 ?? subline
        guard let weekLine else { return Text(day) }
        var line = AttributedString(day)
        var tail = AttributedString(" · \(weekLine)")
        tail.foregroundColor = ink.opacity(0.5)
        line.append(tail)
        return Text(line)
    }

    private var subline: String {
        var parts: [String] = []
        if target > 0 {
            let over = worked - target
            // The percent line above already names the target.
            parts.append(over >= 0 ? "+\(Fmt.hm(over)) over" : "\(Fmt.hm(-over)) left")
        } else {
            parts.append("No target today")
        }
        if let doneBy { parts.append("done by \(Fmt.clock(doneBy))") }
        if breakTotal > 0 { parts.append("\(Fmt.hm(breakTotal)) break") }
        return parts.joined(separator: " · ")
    }
}

/// Floats a swimmer on the hero's water. Everything he does comes from the wave
/// the hero just drew (via `WaveModel`): the ripple under him carries him along
/// with it, lifts him as it swells, and rocks him with its slope — so he moves
/// with the water instead of on an idle animation of his own.
///
/// Apply it *inside* an `.overlay` on the hero, so the geometry it reads is the
/// card's own — a greedy reader as a layout sibling would fight the hero's
/// content sizing.
public struct WaveFloat: ViewModifier {
    /// The hero's wave, recorded per frame. Nil until it has drawn once.
    var wave: WaveModel?
    /// Where he floats, from the card's top-leading corner. Negative y straddles
    /// the top edge, which is where he sits on the waterline.
    var at: CGPoint

    /// The wave clock stops with the window — SwiftUI keeps closed windows
    /// alive, and an unpaused display link burns CPU forever.
    @State private var windowVisible = true

    public func body(content: Content) -> some View {
        Group {
            if Motion.reduce || !windowVisible {
                // Held where the wave last left him: read once, no clock.
                ride(content, on: wave?.ride(at: at.y))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                    ride(content, on: wave?.ride(at: at.y))
                }
            }
        }
        .trackWindowVisibility { windowVisible = $0 }
    }

    private func ride(_ content: Content,
                      on sample: (drift: Double, slope: Double)?) -> some View {
        // A crest is deeper water: it pushes him toward the far wall and lifts
        // him as it passes. He leans with the surface too, but the waterline is
        // far steeper per point than a float should tilt — a fraction of it,
        // capped.
        let drift = sample?.drift ?? 0
        let lean = min(0.09, max(-0.09, -(sample?.slope ?? 0) * 0.30))
        return content
            .rotationEffect(.radians(lean))
            .offset(x: at.x + CGFloat(drift * 0.5), y: at.y - CGFloat(drift * 0.35))
    }
}

extension View {
    /// See `WaveFloat`.
    public func waveFloat(on wave: WaveModel?, at: CGPoint) -> some View {
        modifier(WaveFloat(wave: wave, at: at))
    }
}

extension LiquidHero {
    /// Draw the water in `tint`'s hue (orange/red for over-limit days). Pass nil
    /// to keep the accent. Chained so callers don't thread it through the init.
    public func statusTint(_ tint: Color?) -> LiquidHero {
        var copy = self
        copy.statusTint = tint
        return copy
    }

    /// Add the week's "12h 30m left this week" to the end of the day's own
    /// line. Pass nil (the default) for heroes that aren't about today.
    public func weekLine(_ text: String?) -> LiquidHero {
        var copy = self
        copy.weekLine = text
        return copy
    }
}

extension LiquidHero where Top == EmptyView, Bottom == EmptyView {
    /// Slot-less hero — the popover's compact variant.
    public init(worked: TimeInterval, target: TimeInterval, breakTotal: TimeInterval = 0,
         doneBy: Date? = nil,
         compact: Bool = false, greeting: String? = nil, cornerRadius: CGFloat = 16,
         customFraction: Double? = nil, customBig: String? = nil,
         customLine2: String? = nil, customLine3: String? = nil,
         bottomInset: CGFloat = 0, wave: WaveModel? = nil) {
        self.init(worked: worked, target: target, breakTotal: breakTotal,
                  doneBy: doneBy,
                  compact: compact, greeting: greeting, cornerRadius: cornerRadius,
                  customFraction: customFraction, customBig: customBig,
                  customLine2: customLine2, customLine3: customLine3,
                  bottomInset: bottomInset, wave: wave,
                  top: { EmptyView() }, bottom: { EmptyView() })
    }
}

/// Bob in a lifebuoy: the ring wraps his waist — body behind the ring's
/// bottom arc, face in front of its top. He has no float animation of his own:
/// `.waveFloat(…)` rides him on the wave the hero is actually drawing, so he
/// moves with the water under him. Blinks run on a sparse async loop, paused
/// when the window isn't really visible.
public struct BuoyBob: View {
    public init(sleeping: Bool = false, onBreak: Bool = false, size: CGFloat = 72) {
        self.sleeping = sleeping
        self.onBreak = onBreak
        self.size = size
    }
    var sleeping = false
    /// On a break he wears sunglasses.
    var onBreak = false
    var size: CGFloat = 72
    @State private var windowVisible = true
    @State private var blink: CGFloat = 0

    public var body: some View {
        content(blink: sleeping ? 1 : blink)
            // Gated like every other clock: the z's 12fps TimelineView must
            // not keep ticking inside a retained-but-closed window.
            .overlay(alignment: .topTrailing) {
                if sleeping && windowVisible && !Motion.reduce { DriftingZs() }
            }
            .frame(width: size, height: size)
            .trackWindowVisibility { windowVisible = $0 }
            .task(id: windowVisible && !sleeping && !Motion.reduce) {
                guard windowVisible, !sleeping, !Motion.reduce else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 3_200_000_000...5_800_000_000))
                    if Task.isCancelled { break }
                    withAnimation(.easeIn(duration: 0.08)) { blink = 1 }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    withAnimation(.easeOut(duration: 0.12)) { blink = 0 }
                }
            }
    }

    private func content(blink: CGFloat) -> some View {
        // Even quarters: dash length = perimeter / 8, so the white segments
        // tile the ellipse exactly — no visible seam where the path closes.
        // Tight and chunky around his waist, in the Mac's accent hue.
        let a = size * 0.40, b = size * 0.21
        let perimeter = Double.pi * (3 * (a + b) - ((3 * a + b) * (a + 3 * b)).squareRoot())
        let dash = perimeter / 8
        return ZStack {
            // Whole Bob behind — his body sits inside the ring, feet
            // sticking out below its bottom arc.
            BobMascot(blink: blink)
                .frame(width: size, height: size)
            // Lit from above, shaded below — an inflatable, not a sticker.
            Ellipse()
                .stroke(LinearGradient(colors: [Color.systemAccentHued(sat: 0.68, bri: 0.82),
                                                Color.systemAccentHued(sat: 0.86, bri: 0.50)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: size * 0.26)
                .frame(width: size * 0.80, height: size * 0.42)
                .offset(y: size * 0.08)
            Ellipse()
                .stroke(LinearGradient(colors: [.white, Color(white: 0.80)],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: size * 0.26, dash: [dash, dash]))
                .frame(width: size * 0.80, height: size * 0.42)
                .offset(y: size * 0.08)
                .opacity(0.92)
            // Glossy rim along the tube's upper edge.
            Ellipse()
                .stroke(Color.white.opacity(0.35), lineWidth: size * 0.035)
                .frame(width: size * 0.80, height: size * 0.42)
                .offset(y: size * 0.035)
            // Head and face again in front of the ring's top arc; the mask's
            // straight edge hides inside the ring band.
            BobMascot(blink: blink)
                .frame(width: size, height: size)
                .mask(alignment: .top) { Rectangle().frame(height: size * 0.56) }
            // Paws gripping the ring's top tube, one either side, resting on
            // the band below his chin — tilted with the tube's slope.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse()
                    .fill(Color(red: 0.64, green: 0.44, blue: 0.28))
                    .overlay(Ellipse().strokeBorder(
                        Color(red: 0.42, green: 0.27, blue: 0.16),
                        lineWidth: max(1, size * 0.015)))
                    .frame(width: size * 0.19, height: size * 0.13)
                    .rotationEffect(.degrees(14 * side))
                    .offset(x: size * 0.27 * side, y: size * 0.07)
            }
            if onBreak {
                BobShades(size: size)
                // Standing on the ring's tube beside his ear, leaning
                // slightly outward with it.
                TropicalDrink(size: size)
                    .rotationEffect(.degrees(8))
                    .offset(x: size * 0.40, y: -size * 0.02)
            }
        }
    }
}

/// Break-time sunglasses: two dark lenses over the eyes plus a bridge,
/// sized/positioned relative to the Bob they sit on (his frame's center).
struct BobShades: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                RoundedRectangle(cornerRadius: size * 0.045, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.10, blue: 0.13))
                    .overlay(alignment: .topLeading) {
                        Capsule().fill(.white.opacity(0.35))
                            .frame(width: size * 0.055, height: size * 0.018)
                            .rotationEffect(.degrees(-30))
                            .offset(x: size * 0.03, y: size * 0.03)
                    }
                    .frame(width: size * 0.17, height: size * 0.125)
                    .offset(x: size * 0.11 * side, y: -size * 0.15)
            }
            RoundedRectangle(cornerRadius: size * 0.01)
                .fill(Color(red: 0.09, green: 0.10, blue: 0.13))
                .frame(width: size * 0.07, height: size * 0.025)
                .offset(y: -size * 0.17)
        }
    }
}

/// A break-time drink: juice glass with a straw, scaled off its Bob.
struct TropicalDrink: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Capsule().fill(Color(red: 0.95, green: 0.44, blue: 0.30))
                .frame(width: size * 0.035, height: size * 0.20)
                .rotationEffect(.degrees(22))
                .offset(x: size * 0.055, y: -size * 0.14)
            RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.72, blue: 0.35),
                                              Color(red: 0.98, green: 0.52, blue: 0.24)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.17, height: size * 0.24)
                .overlay(RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: size * 0.015))
                .offset(y: size * 0.05)
        }
        .frame(width: size * 0.26, height: size * 0.34)
    }
}

/// Bob hanging behind the hero's top edge: paws gripping the lip, head
/// peeking over, eyes on the water filling below — waiting for enough
/// depth to swim. The mask cutoff sits exactly on the card's edge, so his
/// body reads as hidden behind it.
public struct PeekingBob: View {
    var size: CGFloat = 64
    /// On a break: sunglasses on, drink standing on the lip beside him.
    var onBreak = false

    public init(size: CGFloat = 64, onBreak: Bool = false) {
        self.size = size
        self.onBreak = onBreak
    }

    public var body: some View {
        ZStack(alignment: .top) {
            AnimatedBob(lookAt: .zero)
                .frame(width: size, height: size)
                .overlay { if onBreak { BobShades(size: size) } }
                .mask(alignment: .top) { Rectangle().frame(height: size * 0.56) }
            HStack(spacing: size * 0.40) {
                paw
                paw
            }
            .offset(y: size * 0.50)
            if onBreak {
                TropicalDrink(size: size)
                    .offset(x: size * 0.46, y: size * 0.23)
            }
        }
        .frame(width: size, height: size * 0.64, alignment: .top)
    }

    private var paw: some View {
        // Solid fur fill + solid darker rim — no partial-opacity stroke, which
        // read as see-through paws against the bright water.
        Ellipse()
            .fill(Color(red: 0.64, green: 0.44, blue: 0.28))
            .overlay(Ellipse().strokeBorder(
                Color(red: 0.42, green: 0.27, blue: 0.16), lineWidth: 1.2))
            .frame(width: size * 0.19, height: size * 0.13)
            .compositingGroup()
    }
}

/// Three z's drifting up-right on staggered phases — a tiny 12fps clock.
struct DriftingZs: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottomLeading) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t / 2.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Text("z")
                        .font(.system(size: 7 + CGFloat(i) * 3, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .opacity(sin(phase * .pi) * 0.9)
                        .offset(x: CGFloat(i) * 6 + phase * 4, y: -CGFloat(i) * 6 - phase * 5)
                }
            }
            .offset(x: 8, y: 0)
        }
    }
}

/// The submerged body of water. The waterline itself lives with the rest of the
/// wave maths in `WaterWave.swift`, so the swimmer floating on it and the unit
/// tests read the same surface the hero draws.
private struct WaterShape: Shape {
    var field: WaveField

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let line = field.polyline(in: rect)
        guard field.level > 0.001, let first = line.first else { return p }
        p.move(to: .zero)
        p.addLine(to: first)
        for pt in line.dropFirst() { p.addLine(to: pt) }
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

/// Just the waterline polyline, for stroking the crisp rim highlight and the
/// soft band of light that follows it into the water.
private struct WaterEdgeShape: Shape {
    var field: WaveField

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let line = field.polyline(in: rect)
        guard field.level > 0.001, let first = line.first else { return p }
        p.move(to: first)
        for pt in line.dropFirst() { p.addLine(to: pt) }
        return p
    }
}
