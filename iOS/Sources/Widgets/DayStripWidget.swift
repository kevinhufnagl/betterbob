import BetterBobShared
import WidgetKit
import SwiftUI

/// The signature timeline as a lock-screen miniature: today's work and break
/// blocks drawn to scale (work solid, breaks dimmed), a live line beneath.
/// You read the day's shape — late start, long break, marathon stretch —
/// instead of just a number.
struct DayStripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DayStrip", provider: SnapshotProvider()) { entry in
            DayStripWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Day strip")
        .description("Today's timeline in miniature, with the running total.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct DayStripWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snap = entry.snapshot, !snap.segments.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                strip(snap)
                    .frame(height: 16)
                bottomLine(snap)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("No entries yet today", systemImage: "clock")
                .font(.caption2)
        }
    }

    /// The expected day as a faint track, filling with blocks as it happens —
    /// work solid, breaks dimmed. The track's length is the projected
    /// clock-out (recorded time plus what's still owed toward the target), so
    /// a fresh morning shows mostly empty and fills as you go.
    private func strip(_ snap: WidgetSnapshot) -> some View {
        Canvas { ctx, size in
            let segments = snap.segments
            guard let dayStart = segments.first?.start else { return }
            let open = segments.contains { $0.end == nil }
            let lastEnd = segments.compactMap(\.end).max() ?? snap.updatedAt
            let recordedEnd = open ? max(snap.updatedAt, lastEnd) : lastEnd

            let dayOver = snap.state == .clockedOut || snap.state == .signedOut
            // Project from the snapshot's own timestamp, NOT the render time:
            // widgets re-render hours after the last data push, and measuring
            // "worked so far" at render time would assume non-stop work since
            // then — collapsing the remaining track to nothing.
            let asOf = snap.updatedAt
            let remaining = max(0, snap.target - snap.workedTotal(now: asOf))
            let projectedEnd = dayOver ? recordedEnd
                                       : max(recordedEnd, asOf.addingTimeInterval(remaining))
            let span = max(1, projectedEnd.timeIntervalSince(dayStart))
            let r: CGFloat = 4

            // The whole expected day as a faint track.
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size),
                          cornerRadius: r),
                     with: .color(.primary.opacity(0.18)))

            for (i, seg) in segments.enumerated() {
                let x = seg.start.timeIntervalSince(dayStart) / span * size.width
                let end = seg.end ?? recordedEnd
                let w = max(2, end.timeIntervalSince(seg.start) / span * size.width - 1)
                // Round only edges that coincide with the track's ends.
                let atTrackEnd = dayOver && i == segments.count - 1
                let rect = CGRect(x: x, y: 0, width: w, height: size.height)
                let path = Path(roundedRect: rect,
                                cornerRadii: RectangleCornerRadii(
                                    topLeading: i == 0 ? r : 1,
                                    bottomLeading: i == 0 ? r : 1,
                                    bottomTrailing: atTrackEnd ? r : 1,
                                    topTrailing: atTrackEnd ? r : 1))
                ctx.fill(path, with: .color(.primary.opacity(seg.isBreak ? 0.35 : 0.9)))
            }
        }
    }

    @ViewBuilder private func bottomLine(_ snap: WidgetSnapshot) -> some View {
        switch snap.state {
        case .working:
            if let start = snap.stretchStart {
                HStack(spacing: 4) {
                    Text("Working")
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                }
            } else {
                Text("Working")
            }
        case .onBreak:
            if let ends = snap.breakEnds, ends > entry.date {
                HStack(spacing: 4) {
                    Text("Break")
                    Text(timerInterval: entry.date...ends, countsDown: true)
                        .monospacedDigit()
                }
            } else {
                Text("On a break")
            }
        case .clockedOut, .signedOut:
            Text("Clocked out · \(Duration.seconds(snap.workedBase).formatted(.time(pattern: .hourMinute)))")
        }
    }
}
