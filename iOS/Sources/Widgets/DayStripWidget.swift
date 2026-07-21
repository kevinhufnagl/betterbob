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

    /// Blocks laid out proportionally over the day span, like the app's
    /// editable strip — work solid, breaks dimmed, ends rounded.
    private func strip(_ snap: WidgetSnapshot) -> some View {
        Canvas { ctx, size in
            let segments = snap.segments
            guard let dayStart = segments.first?.start else { return }
            let open = segments.contains { $0.end == nil }
            let lastEnd = segments.compactMap(\.end).max() ?? snap.updatedAt
            let dayEnd = open ? max(snap.updatedAt, lastEnd) : lastEnd
            let span = max(1, dayEnd.timeIntervalSince(dayStart))
            let count = segments.count
            for (i, seg) in segments.enumerated() {
                let x = seg.start.timeIntervalSince(dayStart) / span * size.width
                let end = seg.end ?? dayEnd
                let w = max(2, end.timeIntervalSince(seg.start) / span * size.width - 1)
                let r: CGFloat = 4
                let rect = CGRect(x: x, y: 0, width: w, height: size.height)
                let path = Path(roundedRect: rect,
                                cornerRadii: RectangleCornerRadii(
                                    topLeading: i == 0 ? r : 1,
                                    bottomLeading: i == 0 ? r : 1,
                                    bottomTrailing: i == count - 1 ? r : 1,
                                    topTrailing: i == count - 1 ? r : 1))
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
            Text("Done · \(Duration.seconds(snap.workedBase).formatted(.time(pattern: .hourMinute)))")
        }
    }
}
