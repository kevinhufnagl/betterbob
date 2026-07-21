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

            // Measure "worked so far" at the snapshot's own timestamp (a
            // render hours later must not assume non-stop work since), and
            // append the remaining work directly after the LAST RECORDED
            // entry — anchoring it at the push time would insert a phantom
            // empty gap when the snapshot lands long after a clock-out.
            let remaining = max(0, snap.target - snap.workedTotal(now: snap.updatedAt))
            let projectedEnd = recordedEnd.addingTimeInterval(remaining)
            let span = max(1, projectedEnd.timeIntervalSince(dayStart))
            let r = size.height / 2

            // The whole expected day as a faint capsule track.
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size),
                          cornerRadius: r),
                     with: .color(.primary.opacity(0.18)))

            // Each block a capsule of its own — work solid, breaks dimmed.
            for seg in segments {
                let x = seg.start.timeIntervalSince(dayStart) / span * size.width
                let end = seg.end ?? recordedEnd
                let w = max(size.height / 2, end.timeIntervalSince(seg.start) / span * size.width - 1.5)
                let rect = CGRect(x: x, y: 0, width: w, height: size.height)
                let path = Path(roundedRect: rect, cornerRadius: min(w, size.height) / 2)
                ctx.fill(path, with: .color(.primary.opacity(seg.isBreak ? 0.35 : 0.9)))
            }
        }
    }

    /// Worked total (live-ticking while working) and percent of target.
    private func bottomLine(_ snap: WidgetSnapshot) -> some View {
        let asOf = snap.updatedAt
        let pct = Int((snap.workedTotal(now: asOf) / max(snap.target, 1) * 100).rounded())
        return HStack(spacing: 4) {
            if snap.state == .working, let start = snap.stretchStart {
                // Anchor shifted back by the banked time so the ticking
                // value reads the whole day's total.
                Text(timerInterval: start.addingTimeInterval(-snap.workedBase)...Date.distantFuture,
                     countsDown: false)
                    .monospacedDigit()
            } else {
                Text(hm(snap.workedTotal(now: asOf)))
                    .monospacedDigit()
            }
            Text("worked · \(pct)%")
        }
    }

    private func hm(_ interval: TimeInterval) -> String {
        let m = Int(interval / 60)
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}
