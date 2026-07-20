import SwiftUI
import AppKit

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
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state.clockState.tint).frame(width: 8, height: 8)
                .shadow(color: state.clockState.tint.opacity(0.6), radius: 3)
            Text(state.clockState.title).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(state.clockState.tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(state.clockState.tint.opacity(0.30), lineWidth: 0.7))
        .animation(Motion.standard, value: state.clockState)
    }
}

/// Clock in / out / break buttons + cooldown + auto-tag line.
struct TodayActions: View {
    @ObservedObject var state: BobState
    var vertical = true
    var now = Date()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 8))
                                  : AnyLayout(HStackLayout(spacing: 8))
            // Side-by-side buttons share one height: the info line would make
            // just one of them taller, so the whole row grows together.
            let rowTall: Bool = {
                switch state.projectedClockState {
                case .clockedOut: return autoTagTrailing != nil
                case .working: return autoBreakTrailing != nil
                case .onBreak: return endBreakTrailing != nil
                }
            }()
            let rowHeight: CGFloat? = vertical ? nil : (rowTall ? 40 : 34)
            // Buttons offer the state *after* everything queued, so you can line
            // up several punches; they fire a minute apart on their own.
            // The ZStack lets the outgoing row cross-fade over the incoming one
            // instead of stacking beside it mid-transition.
            ZStack {
                layout {
                    switch state.projectedClockState {
                    case .clockedOut:
                        btn("Clock in", "play.fill", .workAccent(scheme),
                            trailing: autoTagTrailing, height: rowHeight) { state.clockIn() }
                    case .working:
                        btn("Clock out", "stop.fill", .outAccent(scheme),
                            height: rowHeight) { state.clockOut() }
                        btn("Start break", "pause.circle.fill", .breakAccent(scheme),
                            trailing: autoBreakTrailing, height: rowHeight) { state.startManualBreak() }
                    case .onBreak:
                        btn("End break", "play.fill", .workAccent(scheme),
                            trailing: endBreakTrailing, height: rowHeight) { state.endBreak() }
                        btn("Clock out", "stop.fill", .outAccent(scheme),
                            height: rowHeight) { state.clockOut() }
                    }
                }
                .id(clockStateKey)
                .transition(.bobReplace)
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
    private func btn(_ label: String, _ sym: String, _ tint: Color,
                     trailing: String? = nil, height: CGFloat? = nil,
                     _ act: @escaping () -> Void) -> some View {
        ActionButton(label: label, sym: sym, tint: tint, trailing: trailing,
                     height: height, act: act)
    }

    /// "auto in 42m" inside the Start-break button — same as the popover.
    private var autoBreakTrailing: String? {
        guard case .working = state.clockState, let due = state.autoBreakDue else { return nil }
        return due <= now ? "auto now" : "auto in \(Fmt.hm(due.timeIntervalSince(now)))"
    }

    /// The reason the new entry gets tagged with automatically (Wi-Fi rule or
    /// default), shown under the Clock-in / End-break label.
    private var autoTagTrailing: String? {
        state.currentAutoReason
    }

    /// "back in 12m" inside the End-break button during an auto-break, plus
    /// the auto-tag when one applies: "back in 12m · as In Office".
    private var endBreakTrailing: String? {
        guard let ends = state.autoBreakEnds else { return autoTagTrailing }
        let back = ends <= now ? "back now" : "back in \(Fmt.hm(ends.timeIntervalSince(now)))"
        guard let tag = autoTagTrailing else { return back }
        return "\(back) · \(tag)"
    }
}

/// A clock-in/out/break pill with a hover state.
private struct ActionButton: View {
    let label: String
    let sym: String
    let tint: Color
    var trailing: String? = nil
    /// Explicit height so row-mates match; nil sizes to the content.
    var height: CGFloat? = nil
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            VStack(spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: sym).font(.system(size: 12, weight: .bold))
                    Text(label).font(.system(size: 13, weight: .semibold))
                }
                if let trailing {
                    // Second line so countdown + auto-tag get full width.
                    Text(trailing)
                        .font(.system(size: 9, weight: .medium)).opacity(0.7)
                }
            }
            .frame(maxWidth: .infinity).frame(height: height ?? (trailing == nil ? 34 : 40))
            .background(Capsule().fill(tint.opacity(hovering ? 0.22 : 0.16)))
            .overlay(Capsule().strokeBorder(tint.opacity(hovering ? 0.55 : 0.4), lineWidth: 0.8))
            .foregroundStyle(tint)
        }
        .buttonStyle(PressablePillStyle())
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .animation(Motion.quick, value: hovering)
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

private struct BobCenterKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

struct TodayTimeline: View {
    @ObservedObject var state: BobState
    @Environment(\.colorScheme) private var scheme
    @State private var cursor: CGPoint? = nil
    @State private var bobCenter: CGPoint = .zero

    /// Where Bob's eyes should point, from the cursor relative to his face.
    private var lookAt: CGSize? {
        guard let c = cursor else { return nil }
        let dx = c.x - bobCenter.x, dy = c.y - bobCenter.y
        let d = max(1, hypot(dx, dy))
        let m = min(1, d / 140)
        return CGSize(width: dx / d * m, height: dy / d * m)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let v = TodayVals(state, now: ctx.date)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    AnimatedBob(lookAt: lookAt, sleeping: state.clockState == .clockedOut)
                        .frame(width: 60, height: 60)
                        .background(GeometryReader { g in
                            let f = g.frame(in: .named("today"))
                            Color.clear.preference(key: BobCenterKey.self,
                                                   value: CGPoint(x: f.midX, y: f.midY))
                        })
                    Text(greetingText(state)).font(.system(size: 23, weight: .bold))
                    Spacer()
                    StatusPill(state: state)
                }

                LiquidHero(worked: v.worked, target: v.targetSecs, breakTotal: v.breakTotal,
                           saving: state.busy || !state.deletingEntries.isEmpty)
                    .frame(height: 176)

                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        if state.entries.isEmpty {
                            Text("No entries yet today.").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 3) {
                                EditableDayStrip(entries: state.entries, now: ctx.date, height: 40) { updated in
                                    state.saveDay(updated, on: Date())
                                }
                                HStack {
                                    Text(state.entries.map(\.start).min().map(Fmt.clock) ?? "")
                                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                    Spacer()
                                    // "now" only while an entry is open — a
                                    // clocked-out day ends at its last entry.
                                    if state.entries.contains(where: { $0.end == nil }) {
                                        Text(Fmt.clock(ctx.date) + " now")
                                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                    } else {
                                        Text(state.entries.compactMap(\.end).max().map(Fmt.clock) ?? "")
                                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Divider().opacity(0.15)
                        TodayActions(state: state, vertical: false, now: ctx.date)
                    }
                }

                if case .onBreak = state.clockState { breakBanner(ctx.date).transition(.bobBanner) }
                if state.overMaxNonBreak { missingBreakBanner.transition(.bobBanner) }
                if state.overDailyMax { overDailyMaxBanner.transition(.bobBanner) }

                EntriesTable(state: state)
            }
            .animation(Motion.standard, value: state.clockState)
            .animation(Motion.standard, value: state.overMaxNonBreak)
            .animation(Motion.standard, value: state.overDailyMax)
            .animation(Motion.standard, value: state.entries)
            .coordinateSpace(name: "today")
            .background(MouseTracker { cursor = $0 })
            .onPreferenceChange(BobCenterKey.self) { bobCenter = $0 }
        }
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
                Label("Add break", systemImage: "wand.and.stars").font(.system(size: 12, weight: .semibold))
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
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            guard let window = (note.object as? NSWindow),
                  window.identifier?.rawValue.hasPrefix("main") == true else { return }
            DispatchQueue.main.async { HeroSweep.shared.generation += 1 }
        }
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
    var saving = false
    /// Smaller type and padding for the popover.
    var compact = false
    var cornerRadius: CGFloat = 16
    let top: Top
    let bottom: Bottom

    init(worked: TimeInterval, target: TimeInterval, breakTotal: TimeInterval = 0,
         saving: Bool = false, compact: Bool = false, cornerRadius: CGFloat = 16,
         @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.worked = worked
        self.target = target
        self.breakTotal = breakTotal
        self.saving = saving
        self.compact = compact
        self.cornerRadius = cornerRadius
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

    private var fraction: Double { target > 0 ? min(1, worked / target) : 0 }
    private var percent: Int { target > 0 ? Int((worked / target * 100).rounded()) : 0 }

    // The water starts cold blue and settles into the brand teal as the day
    // fills — a slow shift driven by the fraction. Dark mode is deep and
    // saturated; light mode the same hues as pastels with dark ink on top.
    private var dark: Bool { scheme == .dark }
    private func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ f: Double) -> Color {
        Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
    }
    private var waterGradient: LinearGradient {
        let stops: [((Double, Double, Double), (Double, Double, Double))] = dark
            ? [((0.075, 0.204, 0.420), (0.066, 0.245, 0.280)),
               ((0.098, 0.318, 0.620), (0.090, 0.410, 0.440)),
               ((0.157, 0.451, 0.800), (0.130, 0.570, 0.600))]
            : [((0.42, 0.58, 0.80), (0.38, 0.68, 0.71)),
               ((0.49, 0.65, 0.85), (0.45, 0.75, 0.77)),
               ((0.56, 0.72, 0.90), (0.52, 0.81, 0.83))]
        return LinearGradient(colors: stops.map { mix($0.0, $0.1, fraction) },
                              startPoint: .leading, endPoint: .trailing)
    }
    private var glowColor: Color {
        dark ? mix((0.45, 0.72, 1.0), (0.46, 0.83, 0.86), fraction)
             : mix((0.90, 0.96, 1.0), (0.86, 0.98, 0.98), fraction)
    }
    private var baseColor: Color {
        dark ? mix((0.043, 0.059, 0.090), (0.031, 0.078, 0.086), fraction)
             : mix((0.88, 0.91, 0.95), (0.86, 0.92, 0.93), fraction)
    }
    private var ink: Color { dark ? .white : Color(red: 0.06, green: 0.20, blue: 0.24) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            top.foregroundStyle(ink)
            Spacer(minLength: compact ? 4 : 8)
            VStack(alignment: .leading, spacing: 2) {
                // Worked time is the headline; the percentage sits under it.
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(Fmt.hm(worked))
                        .font(.system(size: compact ? 30 : 44, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(Motion.numeric, value: Fmt.hm(worked))
                        .foregroundStyle(ink)
                    if saving {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.small).scaleEffect(0.7).tint(ink)
                            Text("Saving…").font(.system(size: 10, weight: .medium))
                                .foregroundStyle(ink.opacity(0.8))
                        }
                        .transition(.opacity)
                    }
                }
                Text(target > 0 ? "\(percent)% of \(Fmt.hm(target))" : "worked today")
                    .font(.system(size: compact ? 11.5 : 13, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.92))
                    .contentTransition(.numericText())
                    .animation(Motion.numeric, value: percent)
                Text(subline)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(ink.opacity(0.66))
            }
            bottom
        }
        .padding(compact ? 12 : 20)
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
                    let settled = fraction >= 1
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
                            water(level: fraction * eased, amplitude: amp, phase: phase,
                                  asym: 0.55 * exp(-t / 2.5))
                        }
                    }
                }
            }
        }
        .animation(Motion.quick, value: saving)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if cornerRadius > 0 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08),
                                  lineWidth: 0.6)
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

    /// The fill plus its edge light. The light is a second fill of the same
    /// wave shape, brightening toward the waterline — clipped by the wave it
    /// hugs the sloshing edge exactly instead of reading as a blurred oval.
    /// Explicit ZStack: a bare two-view tuple inside TimelineView stacks
    /// vertically instead of overlapping.
    private func water(level: Double, amplitude: CGFloat, phase: Double,
                       asym: Double = 0) -> some View {
        let shape = WaterShape(level: level, amplitude: amplitude, phase: phase, asym: asym,
                               freq: seedFreq, asymPhase: seedAsymPhase)
        return ZStack(alignment: .topLeading) {
            shape.fill(waterGradient)
            if level > 0.02 {
                // Tight, eased ramp: barely-there until close to the edge,
                // building smoothly — a wide linear ramp read as a hard band.
                let edge = min(1, level)
                shape.fill(LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: glowColor.opacity(0), location: max(0, edge - 0.10)),
                        .init(color: glowColor.opacity(0.10), location: max(0.001, edge - 0.05)),
                        .init(color: glowColor.opacity(0.24), location: max(0.002, edge - 0.02)),
                        .init(color: glowColor.opacity(0.45), location: max(0.003, edge)),
                    ]),
                    startPoint: .leading, endPoint: .trailing))
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

extension LiquidHero where Top == EmptyView, Bottom == EmptyView {
    /// Slot-less hero — the popover's compact variant.
    init(worked: TimeInterval, target: TimeInterval, breakTotal: TimeInterval = 0,
         saving: Bool = false, compact: Bool = false, cornerRadius: CGFloat = 16) {
        self.init(worked: worked, target: target, breakTotal: breakTotal, saving: saving,
                  compact: compact, cornerRadius: cornerRadius,
                  top: { EmptyView() }, bottom: { EmptyView() })
    }
}

/// Left-anchored fill whose trailing edge is a sine wave — amplitude 0 makes
/// it a straight vertical line. `asym` blends in a second harmonic so the
/// slosh leans to one side instead of being a clean symmetric sine.
private struct WaterShape: Shape {
    var level: Double       // 0…1 of the width
    var amplitude: CGFloat  // points
    var phase: Double
    var asym: Double = 0
    /// Wavelength and harmonic offset — seeded per appearance for variety.
    var freq: Double = 2.2
    var asymPhase: Double = 1.2

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard level > 0.001, rect.height > 0 else { return p }
        let edge = rect.width * min(1, level)
        func waveX(_ y: CGFloat) -> CGFloat {
            let theta = Double(y / rect.height) * .pi * freq + phase
            let wave = sin(theta) + asym * sin(2 * theta + asymPhase)
            return min(rect.width, edge + amplitude * CGFloat(wave))
        }
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: waveX(0), y: 0))
        var y: CGFloat = 0
        while y < rect.height {
            y = min(y + 4, rect.height)
            p.addLine(to: CGPoint(x: waveX(y), y: y))
        }
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}
