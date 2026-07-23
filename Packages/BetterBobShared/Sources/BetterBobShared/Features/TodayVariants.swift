import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import CoreMotion
#endif

/// Width of the hero's text column, and of the hero itself — reported via
/// preferences so a host can tell whether there's room to float Bob beside the
/// text (the threshold then tracks window size AND the actual copy length).
struct HeroTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
struct HeroWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
/// The water's *currently displayed* fill fraction (0…1) — eased during the
/// arrival sweep and level glides, not the raw target. A rider (Bob) reads this
/// so he tracks the visible waterline instead of jumping ahead of the wave.
struct HeroWaterFractionKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
    }

    public var doneBy: Date? { working && remaining > 0 ? Date().addingTimeInterval(remaining) : nil }
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
    // Measured live so Bob only floats beside the text when there's genuinely
    // room — the threshold then tracks both the window width and the copy
    // length, rather than a hard-coded guess.
    @State private var heroWidth: CGFloat = 0
    @State private var heroTextWidth: CGFloat = 0
    // The water's actual displayed fill (eased), so Bob rides the visible
    // waterline rather than jumping to the target ahead of the wave.
    @State private var heroWaterFraction: CGFloat = 0

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
        // Float Bob fully INSIDE the water (his right edge just inside the
        // waterline), toward its right edge — not straddling it. Leading text
        // pad is 20; 72 is BuoyBob's size; `inset` keeps him off the very edge.
        let bobSize: CGFloat = 72
        let inset: CGFloat = 16
        let gap: CGFloat = 10
        let textRight = 20 + heroTextWidth
        // Decide floater-vs-straddler from the TARGET fill (stable), so a
        // re-entry sweep never flips him to the top-left straddle mid-sweep.
        // Reveal + position use the DISPLAYED waterline, so he rides the wave in
        // and is hidden until it actually reaches him — never ahead of it.
        let targetRight = CGFloat(v.fraction) * heroWidth - inset
        let shownRight = heroWaterFraction * heroWidth - inset
        let isFloater = v.fraction >= 0.15 && heroWidth > 0
            && (targetRight - bobSize) >= (textRight + gap)
        let canFloat = isFloater && (shownRight - bobSize) >= (textRight + gap)
        let bobCenterX = max(bobSize / 2, shownRight - bobSize / 2)
        VStack(alignment: .leading, spacing: 16) {
                // Bob straddles the hero's top edge: the ring floats on the
                // waterline (the card's boundary), his head is out of the
                // water above it, his body inside.
                ZStack(alignment: .topLeading) {
                    LiquidHero(worked: v.worked, target: v.targetSecs, breakTotal: v.breakTotal,
                               greeting: greetingText(state), bottomInset: 12) {
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
                    // Once the waterline has moved far enough right to clear the
                    // text, Bob floats vertically centred on it and stirs ripples.
                    .waterRider(canFloat ? 0.5 : nil)
                    .overlay(alignment: .leading) {
                        if canFloat {
                            BuoyBob(sleeping: state.clockState == .clockedOut,
                                    onBreak: v.onBreak, size: bobSize, submerged: true)
                                .offset(x: bobCenterX - bobSize / 2)
                                .transition(.bobReplace)
                        }
                    }
                    // Measure the hero's own width for the waterline maths above.
                    .background(GeometryReader { p in
                        Color.clear.preference(key: HeroWidthKey.self, value: p.size.width)
                    })
                    // Content-sized: a fixed frame smaller than the content
                    // makes the hero spill past it top and bottom (SwiftUI
                    // doesn't clip), eating the gap to the next card.
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
                    // Swimming once it's ~15% deep but before there's room to
                    // float free: straddle the top edge, sitting a touch lower
                    // so he reads properly submerged. Wait for the width to be
                    // measured (heroWidth > 0) so he doesn't flash top-left for
                    // a frame before jumping to the centre on window reopen.
                    if v.fraction >= 0.15 && heroWidth > 0 && !isFloater {
                        BuoyBob(sleeping: state.clockState == .clockedOut,
                                onBreak: v.onBreak)
                            .padding(.top, 2)
                            .padding(.leading, 24)
                            .transition(.bobReplace)
                    } else if v.fraction < 0.15 && state.clockState != .clockedOut {
                        // Not enough water to swim: he hangs behind the card,
                        // paws on the lip, head peeking over at the water.
                        PeekingBob(size: 64, onBreak: v.onBreak)
                            .padding(.leading, 26)
                            .transition(.bobReplace)
                    }
                }
                .onPreferenceChange(HeroWidthKey.self) { heroWidth = $0 }
                .onPreferenceChange(HeroTextWidthKey.self) { heroTextWidth = $0 }
                .onPreferenceChange(HeroWaterFractionKey.self) { heroWaterFraction = $0 }
                .animation(Motion.standard, value: canFloat)
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
public struct LiquidHero<Top: View, Bottom: View>: View {
    let worked: TimeInterval
    let target: TimeInterval
    var breakTotal: TimeInterval = 0
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

    /// When set, the water is drawn in this color's hue instead of the system
    /// accent — orange/red for over-limit days, matching the month cells. Set
    /// via `.statusTint(_:)` so callers don't touch the init.
    var statusTint: Color?

    /// Normalized height (0…1) of a floating rider on the water (Bob), so the
    /// wave sheds ripples around him. Set via `.waterRider(_:)`; nil = none.
    var riderY: Double?

    /// The water's hue: the status tint when over a limit, else the accent.
    private var activeHue: Double { statusTint?.hueComponent ?? Color.accentHue }

    public init(worked: TimeInterval, target: TimeInterval, breakTotal: TimeInterval = 0,
         compact: Bool = false, greeting: String? = nil, cornerRadius: CGFloat = 16,
         customFraction: Double? = nil, customBig: String? = nil,
         customLine2: String? = nil, customLine3: String? = nil,
         bottomInset: CGFloat = 0,
         @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.worked = worked
        self.target = target
        self.breakTotal = breakTotal
        self.compact = compact
        self.greeting = greeting
        self.cornerRadius = cornerRadius
        self.customFraction = customFraction
        self.customBig = customBig
        self.customLine2 = customLine2
        self.customLine3 = customLine3
        self.bottomInset = bottomInset
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
    /// The interactive height-field surface, stirred by the cursor (macOS) or
    /// device tilt (iOS). A plain reference held in state: the physics step
    /// mutates it in place inside the frame clock, so it never re-triggers the
    /// view the way reassigning a value `@State` would.
    @State private var sim = WaterSim()
    /// Bumped on cursor activity so a finished day's still edge wakes back into
    /// the animated clock; throttled to avoid a re-render per pointer sample.
    @State private var lastInput: Date?
    #if os(iOS)
    @State private var motion = WaterMotionDriver()
    #endif

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
    /// `skew` rotates the deep→light axis so the depth shading leans WITH the
    /// surface on an iOS tilt (0 = the flat, horizontal wipe).
    private func waterGradient(skew: CGFloat = 0) -> LinearGradient {
        let h = activeHue
        let stops = dark
            ? [Color.hued(h, sat: 0.76, bri: 0.28), Color.hued(h, sat: 0.72, bri: 0.44),
               Color.hued(h, sat: 0.68, bri: 0.60)]
            : [Color.hued(h, sat: 0.32, bri: 0.80), Color.hued(h, sat: 0.30, bri: 0.86),
               Color.hued(h, sat: 0.28, bri: 0.91)]
        return LinearGradient(colors: stops,
                              startPoint: UnitPoint(x: 0, y: 0.5 - skew),
                              endPoint: UnitPoint(x: 1, y: 0.5 + skew))
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
                Text(customLine3 ?? subline)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(ink.opacity(0.66))
            }
            // Report the text column's real width so a host can decide whether
            // there's room to float Bob beside it (threshold tracks both the
            // window size and the actual copy length). Bubbles up the tree.
            .background(GeometryReader { p in
                Color.clear.preference(key: HeroTextWidthKey.self, value: p.size.width)
            })
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
                    // A finished day settles to a still edge to spare the CPU on
                    // Mac's retained windows — but only once the interactive
                    // surface is calm and the pointer has been idle. iOS keeps
                    // the clock running while the screen is up so device tilt
                    // always registers (it can't wake it via discrete events).
                    let cursorIdle = lastInput.map { Date().timeIntervalSince($0) > 0.4 } ?? true
                    #if os(iOS)
                    let maySettle = false
                    #else
                    // A floating rider keeps shedding ripples, so never settle to
                    // a still edge while Bob is on the water.
                    let maySettle = cursorIdle && sim.energy < 0.4 && riderY == nil
                    #endif
                    let settled = maySettle && fraction >= 1 && !animating
                        && (appearedAt.map { Date().timeIntervalSince($0) > 14 } ?? true)
                    // Low Power Mode: the phone (or Mac) is trying to save
                    // battery — hold a still surface rather than run the clock.
                    if Motion.reduce || settled || !windowVisible
                        || ProcessInfo.processInfo.isLowPowerModeEnabled {
                        water(level: fraction, amplitude: 0, phase: 0)
                            .preference(key: HeroWaterFractionKey.self, value: CGFloat(fraction))
                    } else {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                            // Clamped: the anchor sits slightly in the future
                            // so the sweep starts after the pane transition
                            // has finished, instead of stuttering through it.
                            let t = max(0, appearedAt.map { ctx.date.timeIntervalSince($0) } ?? 0)
                            let eased = 1 - pow(1 - min(1, t / 1.5), 3)
                            // The arrival slosh is bigger, faster and lopsided
                            // (second harmonic); all three fade slowly toward
                            // the small, slow, symmetric standing wave.
                            let decay = exp(-t / 3.0)
                            let sustain: CGFloat = fraction < 1 ? 5 : 0
                            let amp = sustain + (11 - sustain) * decay * (0.3 + 0.7 * eased)
                            let phase = seedPhase + 1.5 * t + (3.3 - 1.5) * 3.0 * (1 - decay)
                            let asymNow = 0.55 * exp(-t / 2.5)
                            let lvl = displayedFraction(at: ctx.date) * eased
                            // Step the interactive surface up to this frame, then
                            // read its displacement into the drawn waterline.
                            let rect = CGRect(origin: .zero, size: geo.size)
                            sim.level = CGFloat(lvl)
                            sim.riderY = riderY
                            sim.advance(to: ctx.date, height: geo.size.height) {
                                guard let c = sim.cursor else { return 0 }
                                return WaveField(level: lvl, amplitude: amp, phase: phase,
                                                 asym: asymNow, freq: seedFreq,
                                                 asymPhase: seedAsymPhase,
                                                 detail2: seedDetail2,
                                                 detail3: seedDetail3).x(c.y, in: rect)
                            }
                            // Lean the depth gradient with the surface: normalise
                            // the sim's tilt (points) by height so the shading
                            // rotates with the waterline on an iOS tilt.
                            let skew = max(-0.4, min(0.4, sim.tilt / max(1, geo.size.height)))
                            return water(level: lvl, amplitude: amp, phase: phase,
                                         asym: asymNow, disp: sim.snapshot, gradientSkew: skew)
                                .preference(key: HeroWaterFractionKey.self, value: CGFloat(lvl))
                        }
                    }
                }
                // Purely decorative — VoiceOver should read the hero's worked
                // time and percent, not narrate the animated fill.
                .accessibilityHidden(true)
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
        #if os(macOS)
        // Pointer stirs the surface at its own row. `.background` fills this same
        // frame, so `.local` here shares the shape's coordinate space — and the
        // whole card tracks, foreground text included.
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let p):
                sim.cursor = p
                // Throttle the state write: one wake unsticks a settled edge;
                // the running clock paints every frame after that.
                if lastInput.map({ Date().timeIntervalSince($0) > 0.3 }) ?? true {
                    lastInput = Date()
                }
            case .ended:
                sim.cursor = nil
            }
        }
        #endif
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
            if !visible { sim.rest() }   // drop the pointer; freeze the surface
            windowVisible = visible
        }
        #if os(iOS)
        .onAppear {
            // Reduce Motion / Low Power Mode keep the water static (see the draw
            // branch), so there's no point spinning Core Motion — skip it.
            guard !Motion.reduce, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
            // Device tilt drives the surface; feed tilt/shake straight into the
            // sim (no `@State`, so the frame clock — not a re-render — paints it).
            motion.start { tilt, shake in
                sim.tilt = tilt
                if shake > 0 { sim.splash(min(9, shake * 5)) }
            }
        }
        .onDisappear { motion.stop(); sim.rest() }
        #endif
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

    /// The fill plus its edge light: a tight, sharp gradient hugging the
    /// waterline (clipped by the wave itself) and a crisp rim line stroked
    /// exactly along the edge — a specular highlight, not a soft blur.
    /// Explicit ZStack: a bare view tuple inside TimelineView stacks
    /// vertically instead of overlapping.
    private func water(level: Double, amplitude: CGFloat, phase: Double,
                       asym: Double = 0, disp: [CGFloat] = [], gradientSkew: CGFloat = 0) -> some View {
        let field = WaveField(level: level, amplitude: amplitude, phase: phase, asym: asym,
                              freq: seedFreq, asymPhase: seedAsymPhase,
                              detail2: seedDetail2, detail3: seedDetail3, disp: disp)
        let shape = WaterShape(field: field)
        return ZStack(alignment: .topLeading) {
            shape.fill(waterGradient(skew: gradientSkew))
            if level > 0.02 {
                // Near-surface sheen: soft strokes of the real waterline,
                // blurred and clipped to the body so only the inner half shows.
                // The light therefore hugs the true edge and fades inward — a
                // straight gradient stayed pinned to the flat level while a
                // crest, a cursor reach or an iOS tilt pulled the surface off it.
                let line = WaterEdgeShape(field: field)
                line.stroke(glowColor.opacity(0.22),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                    .blur(radius: 8)
                    .clipShape(shape)
                line.stroke(glowColor.opacity(0.40),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .blur(radius: 2.5)
                    .clipShape(shape)
                // Crisp specular rim, exactly along the edge.
                line.stroke(glowColor.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
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
        if breakTotal > 0 { parts.append("\(Fmt.hm(breakTotal)) break") }
        return parts.joined(separator: " · ")
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

    /// Tell the water a rider (Bob) floats at normalized height `y` (0…1) so it
    /// sheds ripples around him. Pass nil for none. Chained like `statusTint`.
    public func waterRider(_ y: Double?) -> LiquidHero {
        var copy = self
        copy.riderY = y
        return copy
    }
}

extension LiquidHero where Top == EmptyView, Bottom == EmptyView {
    /// Slot-less hero — the popover's compact variant.
    public init(worked: TimeInterval, target: TimeInterval, breakTotal: TimeInterval = 0,
         compact: Bool = false, greeting: String? = nil, cornerRadius: CGFloat = 16,
         customFraction: Double? = nil, customBig: String? = nil,
         customLine2: String? = nil, customLine3: String? = nil,
         bottomInset: CGFloat = 0) {
        self.init(worked: worked, target: target, breakTotal: breakTotal,
                  compact: compact, greeting: greeting, cornerRadius: cornerRadius,
                  customFraction: customFraction, customBig: customBig,
                  customLine2: customLine2, customLine3: customLine3,
                  bottomInset: bottomInset,
                  top: { EmptyView() }, bottom: { EmptyView() })
    }
}

/// Bob in a lifebuoy: the ring wraps his waist — body behind the ring's
/// bottom arc, face in front of its top. Motion is Core-Animation driven
/// (repeat-forever sway and dip), so it is interpolated by the compositor
/// instead of sampled per frame; blinks run on a sparse async loop. Pauses
/// when the window isn't really visible.
public struct BuoyBob: View {
    public init(sleeping: Bool = false, onBreak: Bool = false, size: CGFloat = 72,
                submerged: Bool = false) {
        self.sleeping = sleeping
        self.onBreak = onBreak
        self.size = size
        self.submerged = submerged
    }
    var sleeping = false
    /// On a break he wears sunglasses.
    var onBreak = false
    var size: CGFloat = 72
    /// Floating fully inside the water: hide the legs/feet below the ring, so
    /// he reads as submerged to the waterline rather than dangling in mid-water.
    var submerged = false
    @State private var windowVisible = true
    @State private var swayAngle: Double = 0
    @State private var dipOffset: CGFloat = 0
    @State private var blink: CGFloat = 0
    // Fresh float character on every appearance, like the wave's seeds —
    // bounded so he never swings wider or dips deeper than before.
    @State private var swayAmp = Double.random(in: 2.0...3.2)
    @State private var swayDur = Double.random(in: 2.0...2.8)
    @State private var dipAmp = CGFloat.random(in: 0.024...0.035)
    @State private var dipDur = Double.random(in: 1.45...2.1)

    public var body: some View {
        content(blink: sleeping ? 1 : blink)
            .rotationEffect(.degrees(swayAngle))
            // Scaled to Bob's size — a fixed ±2.5pt was too much travel for
            // the popover's small swimmer.
            .offset(y: dipOffset)
            // Gated like every other clock: the z's 12fps TimelineView must
            // not keep ticking inside a retained-but-closed window.
            .overlay(alignment: .topTrailing) {
                if sleeping && windowVisible && !Motion.reduce { DriftingZs() }
            }
            .frame(width: size, height: size)
            .trackWindowVisibility { visible in
                windowVisible = visible
                applyFloat()
            }
            .onAppear { applyFloat() }
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

    private func applyFloat() {
        var t = Transaction()
        t.disablesAnimations = true
        if windowVisible && !Motion.reduce {
            // Jump to one extreme unanimated, then ping-pong to the other —
            // the animated value never rests at an extreme when paused,
            // which used to leave him frozen with a permanent left tilt.
            withTransaction(t) { swayAngle = -swayAmp; dipOffset = -size * dipAmp }
            withAnimation(.easeInOut(duration: swayDur).repeatForever(autoreverses: true)) {
                swayAngle = swayAmp
            }
            withAnimation(.easeInOut(duration: dipDur).repeatForever(autoreverses: true)) {
                dipOffset = size * dipAmp
            }
        } else {
            // A repeatForever animator is NOT cancelled by a disablesAnimations
            // write — it keeps ticking the attribute graph (and re-laying-out
            // the retained window) forever. Replacing it with a finite
            // animation is the only reliable way to stop it.
            withAnimation(.linear(duration: 0.01)) { swayAngle = 0; dipOffset = 0 }
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
            // sticking out below its bottom arc. When submerged, mask the feet
            // away at the ring's waterline so nothing dangles below it.
            BobMascot(blink: blink)
                .frame(width: size, height: size)
                .mask(alignment: .top) {
                    if submerged { Rectangle().frame(height: size * 0.78) }
                    else { Rectangle() }
                }
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

/// The waterline as a function: three sine components with incommensurate
/// wavelengths and speeds sum into an organic, never-quite-repeating edge
/// (a single sine reads as a rubber band). `asym` adds the lopsided slosh
/// harmonic during the arrival; amplitude 0 collapses to a straight line.
private struct WaveField {
    var level: Double       // 0…1 of the width
    var amplitude: CGFloat  // points
    var phase: Double
    var asym: Double = 0
    /// Seeded per appearance for variety.
    var freq: Double = 2.2
    var asymPhase: Double = 1.2
    var detail2 = 0.0
    var detail3 = 0.0
    /// Live per-column displacement from the interactive `WaterSim`, in points,
    /// added on top of the analytic waterline. Empty when the sim is idle.
    var disp: [CGFloat] = []

    func x(_ y: CGFloat, in rect: CGRect) -> CGFloat {
        let u = Double(y / rect.height)
        let theta = u * .pi * freq + phase
        var w = sin(theta)
        w += 0.55 * sin(u * .pi * freq * 1.83 + phase * 1.31 + detail2)
        w += 0.30 * sin(u * .pi * freq * 3.10 + phase * 0.57 + detail3)
        w *= 0.54  // renormalize the component sum to ~unit amplitude
        w += asym * sin(2 * theta + asymPhase)
        let edge = rect.width * min(1, level)
        return max(0, min(rect.width, edge + amplitude * CGFloat(w) + sampleDisp(u)))
    }

    /// Linearly interpolate the sim displacement at normalized height `u` (0…1).
    private func sampleDisp(_ u: Double) -> CGFloat {
        guard disp.count > 1 else { return 0 }
        let f = min(max(0, u), 1) * Double(disp.count - 1)
        let i = Int(f)
        if i >= disp.count - 1 { return disp[disp.count - 1] }
        let frac = CGFloat(f - Double(i))
        return disp[i] * (1 - frac) + disp[i + 1] * frac
    }
}

private struct WaterShape: Shape {
    var field: WaveField

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard field.level > 0.001, rect.height > 0 else { return p }
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: field.x(0, in: rect), y: 0))
        var y: CGFloat = 0
        while y < rect.height {
            y = min(y + 3, rect.height)
            p.addLine(to: CGPoint(x: field.x(y, in: rect), y: y))
        }
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

/// Just the waterline polyline, for stroking the crisp rim highlight.
private struct WaterEdgeShape: Shape {
    var field: WaveField

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard field.level > 0.001, rect.height > 0 else { return p }
        p.move(to: CGPoint(x: field.x(0, in: rect), y: 0))
        var y: CGFloat = 0
        while y < rect.height {
            y = min(y + 3, rect.height)
            p.addLine(to: CGPoint(x: field.x(y, in: rect), y: y))
        }
        return p
    }
}

/// A one-dimensional height field: a row of columns down the waterline, each
/// coupled to its neighbours by a damped wave equation. Poke one column and the
/// bump travels along the surface and reflects off the ends, the way a real
/// trough of water carries a ripple — none of which a closed-form curve can do.
///
/// The analytic `WaveField` still paints the calm ambient wave; this rides on
/// top as a live displacement, driven by the pointer (macOS) or device tilt
/// (iOS). It is a reference type mutated in place inside the 30fps frame clock,
/// so stepping it never triggers a SwiftUI re-render.
/// The platform-agnostic core of the water surface, as pure functions so the
/// physics can be exercised without a view or a clock (see Tests/main.swift).
/// A damped wave equation with reflective ends, plus a centre-pivoting tilt
/// lean whose ramp has zero mean — so tilt changes the surface ANGLE without
/// shifting its average position (the fill level).
enum WaterPhysics {
    static let c2: CGFloat = 1400   // propagation speed² — how fast ripples travel
    static let k: CGFloat = 30      // restoring pull toward the level surface
    static let damp: CGFloat = 2.6  // how quickly it all settles

    static func acceleration(disp: [CGFloat], vel: [CGFloat],
                             tilt: CGFloat, level: CGFloat,
                             c2: CGFloat = c2, k: CGFloat = k, damp: CGFloat = damp) -> [CGFloat] {
        let count = disp.count
        var accel = [CGFloat](repeating: 0, count: count)
        guard count > 1 else { return accel }
        for i in 0..<count {
            let l = disp[max(0, i - 1)]                 // reflective ends: a
            let r = disp[min(count - 1, i + 1)]         // ripple bounces back
            accel[i] = c2 * (l + r - 2 * disp[i]) - k * disp[i] - damp * vel[i]
        }
        if tilt != 0 {
            // Fade the lean out over the outer 15% of fill so it can't clip the
            // container wall (which would leak into an apparent progress change).
            let fade = min(1, min(level, 1 - level) / 0.15)
            for i in 0..<count {
                let u = CGFloat(i) / CGFloat(count - 1) // 0 top … 1 bottom
                accel[i] += k * tilt * fade * (u - 0.5) * 2
            }
        }
        return accel
    }

    /// Integrate the free surface (no pointer forcing) for `steps` fixed steps —
    /// the exact loop the sim runs, exposed for tests.
    static func advanceFreeSurface(disp: [CGFloat], vel: [CGFloat], dt: CGFloat, steps: Int,
                                   tilt: CGFloat = 0, level: CGFloat = 0.5)
        -> (disp: [CGFloat], vel: [CGFloat]) {
        var d = disp, v = vel
        for _ in 0..<steps {
            let a = acceleration(disp: d, vel: v, tilt: tilt, level: level)
            for i in 0..<d.count { v[i] += a[i] * dt; d[i] += v[i] * dt }
        }
        return (d, v)
    }
}

private final class WaterSim {
    let count: Int
    private var disp: [CGFloat]
    private var vel: [CGFloat]
    private var lastStep: Date?
    private var accumulator: Double = 0

    // Inputs, all in the hero's own coordinate space / gravity units.
    var cursor: CGPoint?            // macOS pointer; nil when it leaves
    private var lastCursor: CGPoint?
    private var cursorSpeed: CGFloat = 0
    /// Pointer presence last frame + its last row, so arrival and departure
    /// each shed a little ripple instead of the reach snapping in and out.
    private var pointerWasActive = false
    private var lastActiveU: Double?
    /// iOS device tilt as a surface *lean* in points (roll + pitch combined).
    /// Applied as a centre-pivoting ramp, so it changes the waterline's ANGLE
    /// only — never its average position, i.e. the fill level is untouched.
    var tilt: CGFloat = 0
    /// Current fill fraction (0…1). The lean fades out as the surface nears an
    /// edge, so a tilt can't clip against the container wall and leak into an
    /// apparent progress change — keeping the tilt strictly angular.
    var level: CGFloat = 0.5
    /// Normalized height (0…1) of a floating rider (Bob) sitting on the water,
    /// or nil when none. He bobs a shallow dimple that keeps shedding little
    /// ripples along the waterline — the cursor's wake, hands-free.
    var riderY: Double?
    private var riderPhase: Double = 0

    init(count: Int = 56) {
        self.count = count
        disp = Array(repeating: 0, count: count)
        vel = Array(repeating: 0, count: count)
    }

    /// Snapshot of the surface for the drawn `WaveField`.
    var snapshot: [CGFloat] { disp }

    /// How lively the surface is right now — used to decide when a finished
    /// day may settle back to a still edge.
    var energy: CGFloat {
        var e: CGFloat = 0
        for i in 0..<count { e += abs(disp[i]) + abs(vel[i]) * 0.1 }
        return e / CGFloat(count)
    }

    /// A shake: scatter velocity across the surface for a chaotic splash.
    func splash(_ strength: CGFloat) {
        for i in 0..<count { vel[i] += CGFloat.random(in: -strength...strength) }
    }

    /// A soft, localized velocity kick centred on a normalized-height row —
    /// used for the pointer's arrival/departure ripples.
    private func localImpulse(atNormalizedY u: Double, strength: CGFloat, sigma: Double) {
        let center = min(max(0, u), 1) * Double(count - 1)
        for i in 0..<count {
            let d = Double(i) - center
            vel[i] += strength * CGFloat(exp(-(d * d) / (2 * sigma * sigma)))
        }
    }

    /// Drop all input and freeze — called when the view is hidden so nothing
    /// stale lingers and no huge dt is integrated on the way back.
    func rest() {
        cursor = nil; lastCursor = nil; cursorSpeed = 0
        pointerWasActive = false; lastActiveU = nil
        tilt = 0
        riderY = nil; riderPhase = 0
        for i in 0..<count { disp[i] = 0; vel[i] = 0 }
        lastStep = nil; accumulator = 0
    }

    /// Integrate up to `date` in fixed sub-steps (stable regardless of frame
    /// rate). `baseXAtCursor` gives the analytic waterline x under the pointer,
    /// so reach/push are measured from the surface actually on screen.
    func advance(to date: Date, height: CGFloat, baseXAtCursor: () -> CGFloat) {
        guard let last = lastStep else { lastStep = date; lastCursor = cursor; return }
        var frameDt = date.timeIntervalSince(last)
        lastStep = date
        guard frameDt > 0 else { return }
        frameDt = min(frameDt, 0.05)   // clamp after a pause; never explode

        if let c = cursor, let lc = lastCursor {
            cursorSpeed = hypot(c.x - lc.x, c.y - lc.y) / CGFloat(frameDt)
        } else {
            cursorSpeed = 0
        }
        lastCursor = cursor

        // Arrival / departure ripples: the pointer entering pushes a small
        // swell at its row; leaving releases the reached peak into a wake,
        // rather than the reach appearing or vanishing instantly.
        let active = cursor != nil
        if let c = cursor { lastActiveU = Double(min(max(0, c.y / max(1, height)), 1)) }
        if active != pointerWasActive, let u = lastActiveU {
            localImpulse(atNormalizedY: u, strength: active ? 5 : 8, sigma: 3.5)
        }
        pointerWasActive = active

        let base = cursor != nil ? baseXAtCursor() : 0

        accumulator += frameDt
        let step = 1.0 / 120.0
        var guardN = 0
        while accumulator >= step && guardN < 10 {
            accumulator -= step
            physics(dt: CGFloat(step), height: height, cursorBaseX: base)
            guardN += 1
        }
    }

    private func physics(dt: CGFloat, height: CGFloat, cursorBaseX: CGFloat) {
        let c2 = WaterPhysics.c2, k = WaterPhysics.k, damp = WaterPhysics.damp

        // Wave equation + iOS tilt lean — the platform-agnostic core, pulled
        // out as a pure function so it can be unit-tested (see Tests/main.swift).
        var accel = WaterPhysics.acceleration(disp: disp, vel: vel,
                                              tilt: tilt, level: level,
                                              c2: c2, k: k, damp: damp)

        // macOS pointer: reach toward it in the air, push away from it in the
        // water — one rule, sign set by which side of the surface it is on. A
        // Gaussian around its row keeps the disturbance local; faster moves
        // pull harder; too far to reach and the pull fades to nothing.
        if let c = cursor {
            let u = Double(min(max(0, c.y / max(1, height)), 1))
            let center = u * Double(count - 1)
            let hot = 1 + min(1.4, cursorSpeed / 320)
            let reach: CGFloat = 26 * hot
            let push: CGFloat = 18 * hot
            let raw = c.x - cursorBaseX
            let target = max(-push, min(reach, raw))
            let overshoot = max(0, abs(raw) - reach)
            let falloff = CGFloat(exp(-Double(overshoot) / 40))
            let attract: CGFloat = 70
            let sigma = 3.0
            for i in 0..<count {
                let d = Double(i) - center
                let g = CGFloat(exp(-(d * d) / (2 * sigma * sigma)))
                accel[i] += g * attract * (target * falloff - disp[i])
            }
        }

        // Floating rider (Bob): each bob cycle sheds a distinct ripple at his
        // row that travels up and down the waterline — the same kind of wake
        // the cursor leaves, hands-free. A continuous push read too faint under
        // the standing wave, so this is a clear periodic pulse instead.
        if let u = riderY {
            riderPhase += Double(dt) * 4.4          // ~0.7 Hz bob
            if riderPhase >= 2 * .pi {
                riderPhase -= 2 * .pi
                localImpulse(atNormalizedY: u, strength: 10, sigma: 2.4)
            }
        }

        for i in 0..<count {
            vel[i] += accel[i] * dt
            disp[i] += vel[i] * dt
        }
    }
}

#if os(iOS)
/// Bridges Core Motion to the water: device tilt becomes a single surface-lean
/// value and sharp jerks become splashes. Updates arrive on the main queue and
/// are pushed straight into the sim, so nothing here touches SwiftUI state.
private final class WaterMotionDriver {
    private let manager = CMMotionManager()
    private var lastShakeMag: Double = 0
    /// A slowly-adapting "level" reference for each tilt axis. Whatever pose the
    /// phone is held in becomes flat within a couple of seconds, so the surface
    /// never sits permanently tilted; a held tilt eases back to level like real
    /// settling water. Nil until the first sample seeds it.
    private var neutralRoll: Double?
    private var neutralPitch: Double?

    func start(onUpdate: @escaping (_ tilt: CGFloat, _ shake: CGFloat) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let roll = m.gravity.x   // left-right tilt (0 held upright)
            let pitch = m.gravity.z  // up-down tilt (0 held vertical)
            if self.neutralRoll == nil { self.neutralRoll = roll; self.neutralPitch = pitch }
            // ~2.5s time constant at 30Hz.
            let adapt = 0.014
            self.neutralRoll! += (roll - self.neutralRoll!) * adapt
            self.neutralPitch! += (pitch - self.neutralPitch!) * adapt
            // Both axes lean the wave's angle; deviation from the adapted
            // neutral, so rest reads flat. Amplitude in points, clamped low so
            // even a big tilt stays a gentle lean.
            let lean = ((roll - self.neutralRoll!) + (pitch - self.neutralPitch!)) * 64
            let tilt = CGFloat(max(-34, min(34, lean)))

            let a = m.userAcceleration
            let mag = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            // Only the rising edge of a jerk splashes, so a shake makes a few
            // discrete splashes rather than a continuous churn.
            let shake: CGFloat = (mag > 0.28 && mag > self.lastShakeMag)
                ? CGFloat(mag - 0.28) : 0
            self.lastShakeMag = mag
            onUpdate(tilt, shake)
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
#endif
