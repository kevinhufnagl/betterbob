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
            // Buttons offer the state *after* everything queued, so you can line
            // up several punches; they fire a minute apart on their own.
            layout {
                switch state.projectedClockState {
                case .clockedOut:
                    btn("Clock in", "play.fill", .workAccent(scheme),
                        trailing: autoTagTrailing) { state.clockIn() }
                case .working:
                    btn("Clock out", "stop.fill", .outAccent(scheme)) { state.clockOut() }
                    btn("Start break", "pause.circle.fill", .breakAccent(scheme),
                        trailing: autoBreakTrailing) { state.startManualBreak() }
                case .onBreak:
                    btn("End break", "play.fill", .workAccent(scheme),
                        trailing: endBreakTrailing) { state.endBreak() }
                    btn("Clock out", "stop.fill", .outAccent(scheme)) { state.clockOut() }
                }
            }
        }
    }
    private func btn(_ label: String, _ sym: String, _ tint: Color,
                     trailing: String? = nil,
                     _ act: @escaping () -> Void) -> some View {
        ActionButton(label: label, sym: sym, tint: tint, trailing: trailing, act: act)
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
            .frame(maxWidth: .infinity).frame(height: trailing == nil ? 34 : 40)
            .background(Capsule().fill(tint.opacity(hovering ? 0.22 : 0.16)))
            .overlay(Capsule().strokeBorder(tint.opacity(hovering ? 0.55 : 0.4), lineWidth: 0.8))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
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
                        .foregroundStyle(Color.accentColor).frame(width: 48, alignment: .leading)
                    ZStack { Rectangle().fill(Color.accentColor.opacity(0.4)).frame(width: 2)
                        Circle().stroke(Color.accentColor, lineWidth: 2).frame(width: 9, height: 9) }.frame(width: 12)
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
            let tint: Color = v.over ? .workAccent(scheme) : .accentColor
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    AnimatedBob(lookAt: lookAt).frame(width: 60, height: 60)
                        .background(GeometryReader { g in
                            let f = g.frame(in: .named("today"))
                            Color.clear.preference(key: BobCenterKey.self,
                                                   value: CGPoint(x: f.midX, y: f.midY))
                        })
                    Text(greetingText(state)).font(.system(size: 23, weight: .bold))
                    Spacer()
                    StatusPill(state: state)
                }

                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        // Prominent worked total.
                        HStack(alignment: .lastTextBaseline, spacing: 10) {
                            Text(Fmt.hm(v.worked)).font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(tint).contentTransition(.numericText())
                            Text("worked").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                            Spacer()
                            if state.busy || !state.deletingEntries.isEmpty {
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.small).scaleEffect(0.75)
                                    Text("Saving…").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                            Text("\(Int((v.fraction * 100).rounded()))%")
                                .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(tint)
                        }
                        .animation(.easeInOut(duration: 0.15), value: state.busy)

                        if state.entries.isEmpty {
                            Text("No entries yet today.").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 3) {
                                EditableDayStrip(entries: state.entries, now: ctx.date, height: 40) { updated in
                                    state.saveDay(updated, on: Date())
                                }
                                HStack {
                                    Text(state.entries.map(\.start).min().map(Fmt.clock) ?? "")
                                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(Fmt.clock(ctx.date) + " now")
                                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                                }
                            }
                        }

                        HStack(spacing: 18) {
                            legend(.workAccent(scheme), "Work")
                            legend(.breakAccent(scheme), "Break")
                            Spacer()
                            stat(Fmt.hm(v.breakTotal), "break", .breakAccent(scheme))
                            if v.over { stat(Fmt.hm(v.worked - v.targetSecs), "over", .workAccent(scheme)) }
                            else if v.remaining > 0 { stat(Fmt.hm(v.remaining), "left", .primary) }
                        }
                        Divider().opacity(0.15)
                        TodayActions(state: state, vertical: false, now: ctx.date)
                    }
                }

                if case .onBreak = state.clockState { breakBanner(ctx.date) }
                if state.overMaxNonBreak { missingBreakBanner }
                if state.overDailyMax { overDailyMaxBanner }

                EntriesTable(state: state)
            }
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
            Image(systemName: "wand.and.stars").font(.system(size: 16, weight: .semibold)).foregroundStyle(.orange)
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
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(Color.orange.opacity(0.45), lineWidth: 0.8))
                    .foregroundStyle(.orange)
            }.buttonStyle(.plain).disabled(state.busy)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.orange.opacity(0.30), lineWidth: 0.8))
    }

    /// Red and actionless — you can't un-work hours, so unlike the missing
    /// break there's no fix button.
    private var overDailyMaxBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 1) {
                Text("Over your \(Fmt.hm(Prefs.shared.maxDayLimit)) daily max")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(Fmt.hm(state.workedToday)) worked today — time to clock out.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.red.opacity(0.30), lineWidth: 0.8))
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label.uppercased()).kerning(0.4).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
        }
    }
    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 8)
            Text(t).font(.system(size: 10)).foregroundStyle(.secondary) }
    }
}
