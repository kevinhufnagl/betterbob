import BetterBobShared
import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

/// The lock-screen presence while clocked in: a branded navy card with Bob's
/// face wearing the clock state, the big live timer, today's timeline in
/// miniature, the projected clock-out, and a one-tap clock action. The
/// Dynamic Island mirrors the same pieces.
struct BobLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BobActivityAttributes.self) { context in
            LockScreenCard(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        BobFaceMark(color: .white,
                                    expression: context.state.isOnBreak ? .shades : .awake)
                            .frame(width: 22, height: 22)
                        Text(context.state.isOnBreak ? "On a break" : "Working")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BigTimer(state: context.state)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        TimelineStrip(state: context.state)
                            .frame(height: 12)
                        FooterLine(state: context.state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                BobFaceMark(color: context.state.isOnBreak ? .bobOrange : .bobTeal,
                            expression: context.state.isOnBreak ? .shades : .awake)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                BigTimer(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                BobFaceMark(color: context.state.isOnBreak ? .bobOrange : .bobTeal,
                            expression: context.state.isOnBreak ? .shades : .awake)
                    .frame(width: 18, height: 18)
            }
        }
    }
}

// MARK: - Lock screen

private struct LockScreenCard: View {
    let state: BobActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                BobFaceMark(color: .white, expression: state.isOnBreak ? .shades : .awake)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.isOnBreak ? "On a break" : "Working")
                        .font(.subheadline.weight(.semibold))
                    subtitle
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                // The timer Text is greedy — it claims all free width, and
                // without these two the digits sit at its leading edge,
                // stranded mid-card instead of on the right.
                .layoutPriority(1)
                Spacer(minLength: 8)
                BigTimer(state: state)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .multilineTextAlignment(.trailing)
            }
            TimelineStrip(state: state)
                .frame(height: 14)
            HStack(alignment: .center, spacing: 8) {
                FooterLine(state: state)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                if state.isOnBreak {
                    pill("End break", intent: PunchIntent(.endBreak))
                } else {
                    pill("Break", intent: PunchIntent(.startBreak))
                    pill("Clock out", intent: PunchIntent(.clockOut))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        // The app icon's navy, deepened so the white content carries.
        .activityBackgroundTint(Color.hued(0.598, sat: 0.80, bri: 0.30))
        .activitySystemActionForegroundColor(.white)
    }

    private func pill(_ label: String, intent: some AppIntent) -> some View {
        Button(intent: intent) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.white.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// One line of what's coming: the armed break while working, the return
    /// time on a break, the plain target when neither is known.
    private var subtitle: Text {
        if state.isOnBreak {
            if let ends = state.breakEnds { return Text("Back at \(ends, style: .time)") }
            return Text("Worked \(hm(state.workedBase)) so far")
        }
        if let due = state.breakDue { return Text("Break at \(due, style: .time)") }
        return Text("Target \(hm(state.target))")
    }
}

// MARK: - Shared pieces

/// The headline number. Working: a live count-up — the whole day (anchor
/// shifted back by the banked time) or just the open stretch, per setting.
/// On a break: the countdown to its end.
private struct BigTimer: View {
    let state: BobActivityAttributes.ContentState

    var body: some View {
        if state.isOnBreak, let ends = state.breakEnds {
            Text(timerInterval: Date()...ends, countsDown: true)
        } else if state.showsTotal {
            Text(timerInterval: state.stretchStart.addingTimeInterval(-state.workedBase)...Date.distantFuture,
                 countsDown: false)
        } else {
            Text(timerInterval: state.stretchStart...Date.distantFuture, countsDown: false)
        }
    }
}

/// The projection line: when today ends at the current pace, and why —
/// naming the owed break that pushes it out. On a break, the frozen total
/// (nothing accrues until the break ends) plus the projection.
private struct FooterLine: View {
    let state: BobActivityAttributes.ContentState

    var body: some View {
        if state.isOnBreak {
            if let done = state.doneBy {
                Text("Worked \(hm(state.workedBase)) · done by \(done, style: .time)")
            } else {
                Text("Worked \(hm(state.workedBase)) · target met")
            }
        } else if let done = state.doneBy {
            if state.pendingBreak > 0 {
                Text("Done by \(done, style: .time) · incl. \(hm(state.pendingBreak)) break")
            } else {
                Text("Done by \(done, style: .time)")
            }
        } else {
            Text("Target met · \(hm(state.target)) done")
        }
    }
}

/// The signature day-strip miniature, same drawing as the lock-screen
/// widget: the projected day as a faint capsule track, recorded blocks
/// inside it — work solid, breaks dimmed.
private struct TimelineStrip: View {
    let state: BobActivityAttributes.ContentState

    var body: some View {
        Canvas { ctx, size in
            let segments = state.segments
            guard let dayStart = segments.first?.start else { return }
            let now = Date()
            let open = segments.contains { $0.end == nil }
            let lastEnd = segments.compactMap(\.end).max() ?? now
            let recordedEnd = open ? max(now, lastEnd) : lastEnd

            let worked = state.isOnBreak
                ? state.workedBase
                : state.workedBase + max(0, now.timeIntervalSince(state.stretchStart))
            let remaining = max(0, state.target - worked) + state.pendingBreak
            let projectedEnd = recordedEnd.addingTimeInterval(remaining)
            let span = max(1, projectedEnd.timeIntervalSince(dayStart))

            let track = Path(roundedRect: CGRect(origin: .zero, size: size),
                             cornerRadius: size.height / 2)
            ctx.clip(to: track)
            ctx.fill(track, with: .color(.white.opacity(0.18)))

            for seg in segments {
                let x = seg.start.timeIntervalSince(dayStart) / span * size.width
                let end = seg.end ?? recordedEnd
                let w = max(1, end.timeIntervalSince(seg.start) / span * size.width)
                ctx.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)),
                         with: .color(.white.opacity(seg.isBreak ? 0.35 : 0.9)))
            }
        }
    }
}

private func hm(_ interval: TimeInterval) -> String {
    let m = Int(interval / 60)
    return String(format: "%d:%02d", m / 60, m % 60)
}
