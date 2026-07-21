import SwiftUI
#if os(macOS)
import AppKit
#endif

// The Today layout and its shared helpers — TodayVals, the actions row and
// the interactive timeline strip.

struct TodayVals {
    var worked: TimeInterval = 0
    var targetSecs: TimeInterval = 8 * 3600
    var remaining: TimeInterval = 0
    var over = false
    var fraction: Double = 0
    var working = false
    var onBreak = false
    var started: Date?
    var breakTotal: TimeInterval = 0
    var autoBreakDue: Date?

    @MainActor
    init(_ state: BobState, now: Date) {
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

    var doneBy: Date? { working && remaining > 0 ? Date().addingTimeInterval(remaining) : nil }
}

@MainActor
private func greetingText(_ state: BobState) -> String {
    let name = state.profile?.name.split(separator: " ").first.map(String.init)
    let h = Calendar.current.component(.hour, from: Date())
    let part = h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    return name.map { "\(part), \($0)" } ?? part
}

// MARK: - Shared: status pill, actions, to-scale strip, agenda

struct StatusPill: View {
    @ObservedObject var state: BobState
    /// Match the water: the over-limit tint when past a limit, else the
    /// clock-state color (which already tracks the accent water).
    private var tint: Color { state.heroLimitTint ?? state.clockState.tint }
    var body: some View {
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
struct ActionDock: View {
    @ObservedObject var state: BobState
    var now = Date()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // The ZStack lets the outgoing pair cross-fade over the incoming one
        // instead of stacking beside it mid-transition.
        ZStack {
            HStack(spacing: 6) {
                switch state.projectedClockState {
                case .clockedOut:
                    DockButton(label: "Clock in", sym: "play.fill",
                               caption: autoTagTrailing, prominent: true) { state.clockIn() }
                case .working:
                    DockButton(label: "Start break", sym: "pause.fill",
                               caption: autoBreakTrailing, prominent: true) { state.startManualBreak() }
                    DockButton(label: "Clock out", sym: "stop.fill") { state.clockOut() }
                case .onBreak:
                    DockButton(label: "End break", sym: "play.fill",
                               caption: endBreakTrailing, prominent: true) { state.endBreak() }
                    DockButton(label: "Clock out", sym: "stop.fill") { state.clockOut() }
                }
            }
            .id(clockStateKey)
            .transition(.bobReplace)
        }
        .padding(5)
        .glassEffect(.regular, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.6))
        .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.14), radius: 12, y: 4)
        .animation(Motion.standard, value: state.projectedClockState)
    }

    /// Stable identity per clock state so the whole pair cross-fades.
    private var clockStateKey: String {
        switch state.projectedClockState {
        case .clockedOut: return "out"
        case .working: return "working"
        case .onBreak: return "break"
        }
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

/// One dock action. Prominent = solid accent capsule with a white label
/// (the next thing you'll do); quiet = glass capsule with a neutral label.
/// Fixed height so a captioned button and its plain neighbour stay level.
private struct DockButton: View {
    let label: String
    let sym: String
    var caption: String? = nil
    var prominent = false
    let act: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            VStack(spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: sym).font(.system(size: 12, weight: .bold))
                    Text(label).font(.system(size: 13, weight: .semibold))
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: 9, weight: .medium)).opacity(0.75)
                }
            }
            .foregroundStyle(prominent ? AnyShapeStyle(.white)
                                       : AnyShapeStyle(Color.primary.opacity(0.85)))
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(
                // Solid fill sits a notch deeper than controlAccent in dark
                // mode so the white label keeps its contrast.
                Capsule().fill(prominent
                    ? AnyShapeStyle(scheme == .dark
                        ? Color.systemAccentHued(sat: 0.72, bri: 0.78)
                        : Color.controlAccent(scheme))
                    : AnyShapeStyle(Color.primary.opacity(hovering ? 0.10 : 0.05))))
            .overlay {
                if prominent {
                    // Hover brightens the solid fill instead of re-tinting it.
                    Capsule().fill(Color.white.opacity(hovering ? 0.12 : 0))
                } else {
                    Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.7)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressablePillStyle())
        #if os(macOS)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        #endif
        .animation(Motion.quick, value: hovering)
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
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
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

struct TodayTimeline: View {
    @ObservedObject var state: BobState
    @Environment(\.colorScheme) private var scheme
    // The 1Hz clock only exists to tick the live worked-time counter. A closed
    // Window scene keeps its view tree (and this clock) alive in SwiftUI, so
    // gate it on real window visibility — otherwise it re-lays-out the whole
    // Today pane every second in the background, burning CPU for nobody.
    @State private var windowVisible = true

    var body: some View {
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
                    // Swimming once it's ~15% deep, straddling the top edge —
                    // sitting a touch lower so he reads properly submerged.
                    if v.fraction >= 0.15 {
                        // Flush with the section top — no dead air above his
                        // head; the ring stays just as submerged (center 8pt
                        // below the hero's edge).
                        BuoyBob(sleeping: state.clockState == .clockedOut,
                                onBreak: v.onBreak)
                            .padding(.top, 2)
                            .padding(.leading, 24)
                            .transition(.bobReplace)
                    } else if state.clockState != .clockedOut {
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
                .padding(.bottom, 25)
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
struct LiquidHero<Top: View, Bottom: View>: View {
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

    /// The water's hue: the status tint when over a limit, else the accent.
    private var activeHue: Double { statusTint?.hueComponent ?? Color.accentHue }

    init(worked: TimeInterval, target: TimeInterval, breakTotal: TimeInterval = 0,
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

    var body: some View {
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
                        water(level: fraction, amplitude: 0, phase: 0)
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
                            let sustain: CGFloat = fraction < 1 ? 3.5 : 0
                            let amp = sustain + (11 - sustain) * decay * (0.3 + 0.7 * eased)
                            let phase = seedPhase + 1.5 * t + (3.3 - 1.5) * 3.0 * (1 - decay)
                            water(level: displayedFraction(at: ctx.date) * eased,
                                  amplitude: amp, phase: phase,
                                  asym: 0.55 * exp(-t / 2.5))
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

    /// The fill plus its edge light: a tight, sharp gradient hugging the
    /// waterline (clipped by the wave itself) and a crisp rim line stroked
    /// exactly along the edge — a specular highlight, not a soft blur.
    /// Explicit ZStack: a bare view tuple inside TimelineView stacks
    /// vertically instead of overlapping.
    private func water(level: Double, amplitude: CGFloat, phase: Double,
                       asym: Double = 0) -> some View {
        let field = WaveField(level: level, amplitude: amplitude, phase: phase, asym: asym,
                              freq: seedFreq, asymPhase: seedAsymPhase,
                              detail2: seedDetail2, detail3: seedDetail3)
        let shape = WaterShape(field: field)
        return ZStack(alignment: .topLeading) {
            shape.fill(waterGradient)
            if level > 0.02 {
                let edge = min(1, level)
                shape.fill(LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: glowColor.opacity(0), location: max(0, edge - 0.05)),
                        .init(color: glowColor.opacity(0.14), location: max(0.001, edge - 0.014)),
                        .init(color: glowColor.opacity(0.50), location: max(0.002, edge)),
                    ]),
                    startPoint: .leading, endPoint: .trailing))
                WaterEdgeShape(field: field)
                    .stroke(glowColor.opacity(0.9),
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
    func statusTint(_ tint: Color?) -> LiquidHero {
        var copy = self
        copy.statusTint = tint
        return copy
    }
}

extension LiquidHero where Top == EmptyView, Bottom == EmptyView {
    /// Slot-less hero — the popover's compact variant.
    init(worked: TimeInterval, target: TimeInterval, breakTotal: TimeInterval = 0,
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
struct BuoyBob: View {
    var sleeping = false
    /// On a break he wears sunglasses.
    var onBreak = false
    var size: CGFloat = 72
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

    var body: some View {
        content(blink: sleeping ? 1 : blink)
            .rotationEffect(.degrees(swayAngle))
            // Scaled to Bob's size — a fixed ±2.5pt was too much travel for
            // the popover's small swimmer.
            .offset(y: dipOffset)
            .overlay(alignment: .topTrailing) { if sleeping { DriftingZs() } }
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
            withTransaction(t) { swayAngle = 0; dipOffset = 0 }
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
struct PeekingBob: View {
    var size: CGFloat = 64
    /// On a break: sunglasses on, drink standing on the lip beside him.
    var onBreak = false

    var body: some View {
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
        Ellipse()
            .fill(Color(red: 0.64, green: 0.44, blue: 0.28))
            .overlay(Ellipse().strokeBorder(
                Color(red: 0.42, green: 0.27, blue: 0.16).opacity(0.55), lineWidth: 1.2))
            .frame(width: size * 0.19, height: size * 0.13)
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

    func x(_ y: CGFloat, in rect: CGRect) -> CGFloat {
        let u = Double(y / rect.height)
        let theta = u * .pi * freq + phase
        var w = sin(theta)
        w += 0.55 * sin(u * .pi * freq * 1.83 + phase * 1.31 + detail2)
        w += 0.30 * sin(u * .pi * freq * 3.10 + phase * 0.57 + detail3)
        w *= 0.54  // renormalize the component sum to ~unit amplitude
        w += asym * sin(2 * theta + asymPhase)
        let edge = rect.width * min(1, level)
        return min(rect.width, edge + amplitude * CGFloat(w))
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
