import SwiftUI
import WidgetKit

/// Watch-face complications, mirroring the iOS lock-screen widgets: Bob's
/// face ringed by target progress (circular + corner), the day-strip
/// timeline miniature (rectangular), and a one-line summary (inline). All
/// render the snapshot the watch app last mirrored into the app group.
@main
struct BetterBobWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BobFaceComplication()
        DayStripComplication()
        InlineComplication()
    }
}

// MARK: - Timeline plumbing

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WatchStore.load()))
    }

    /// One entry now, plus one at each moment the story changes on its own
    /// (break ends, break due, target met) so the face stays honest even if
    /// the app doesn't run again in between.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snap = WatchStore.load()
        let now = Date()
        var dates: [Date] = [now]
        for candidate in [snap?.breakEnds, snap?.breakDue, snap?.doneBy(now: now)] {
            if let d = candidate, d > now { dates.append(d.addingTimeInterval(1)) }
        }
        let entries = dates.sorted().map { SnapshotEntry(date: $0, snapshot: snap) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

// MARK: - Bob's face (circular + corner)

struct BobFaceComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchBobFace", provider: SnapshotProvider()) { entry in
            BobFaceComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Bob")
        .description("Bob wears the clock state; the ring is today's progress.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct BobFaceComplicationView: View {
    let entry: SnapshotEntry

    private var expression: WatchBobFace.Expression {
        switch entry.snapshot?.state {
        case .working: return .awake
        case .onBreak: return .shades
        default: return .asleep
        }
    }

    var body: some View {
        if let snap = entry.snapshot, snap.state != .signedOut {
            Gauge(value: min(1, snap.workedTotal(now: entry.date) / max(snap.target, 1))) {
                WatchBobFace(color: .primary, expression: expression)
                    .frame(width: 26, height: 26)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetLabel {
                Text("\(hm(snap.workedTotal(now: entry.date))) of \(hm(snap.target))")
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                WatchBobFace(color: .primary, expression: .asleep)
                    .frame(width: 32, height: 32)
            }
        }
    }
}

// MARK: - Day strip (rectangular)

struct DayStripComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchDayStrip", provider: SnapshotProvider()) { entry in
            DayStripComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Day strip")
        .description("Today's timeline in miniature, with the running total.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct DayStripComplicationView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snap = entry.snapshot, !snap.segments.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                strip(snap)
                    .frame(height: 14)
                bottomLine(snap)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("No entries yet today", systemImage: "clock")
                .font(.system(size: 11))
        }
    }

    /// Same drawing as the phone's lock-screen strip: the projected day as a
    /// faint capsule track, recorded blocks inside — work solid, breaks dim.
    private func strip(_ snap: WidgetSnapshot) -> some View {
        Canvas { ctx, size in
            let segments = snap.segments
            guard let dayStart = segments.first?.start else { return }
            let open = segments.contains { $0.end == nil }
            let lastEnd = segments.compactMap(\.end).max() ?? snap.updatedAt
            let recordedEnd = open ? max(snap.updatedAt, lastEnd) : lastEnd

            let remaining = max(0, snap.target - snap.workedTotal(now: snap.updatedAt))
                + (snap.pendingBreak ?? 0)
            let projectedEnd = recordedEnd.addingTimeInterval(remaining)
            let span = max(1, projectedEnd.timeIntervalSince(dayStart))

            let track = Path(roundedRect: CGRect(origin: .zero, size: size),
                             cornerRadius: size.height / 2)
            ctx.clip(to: track)
            ctx.fill(track, with: .color(.primary.opacity(0.18)))

            for seg in segments {
                let x = seg.start.timeIntervalSince(dayStart) / span * size.width
                let end = seg.end ?? recordedEnd
                let w = max(1, end.timeIntervalSince(seg.start) / span * size.width)
                ctx.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)),
                         with: .color(.primary.opacity(seg.isBreak ? 0.35 : 0.9)))
            }
        }
    }

    /// Ticking total while working (anchor shifted back by the banked time),
    /// plus percent — one concatenated Text so the greedy timer can't wrap.
    private func bottomLine(_ snap: WidgetSnapshot) -> some View {
        let pct = Int((snap.workedTotal(now: entry.date) / max(snap.target, 1) * 100).rounded())
        return Group {
            if snap.state == .working, let start = snap.stretchStart {
                (Text(timerInterval: start.addingTimeInterval(-snap.workedBase)...Date.distantFuture,
                      countsDown: false)
                    + Text(" · \(pct)%"))
                    .monospacedDigit()
            } else {
                Text("\(hm(snap.workedTotal(now: entry.date))) · \(pct)%")
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Inline

struct InlineComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchInline", provider: SnapshotProvider()) { entry in
            InlineComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Today at work")
        .description("Worked so far and when you'll be done, in one line.")
        .supportedFamilies([.accessoryInline])
    }
}

struct InlineComplicationView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snap = entry.snapshot, snap.state != .signedOut {
            switch snap.state {
            case .onBreak:
                if let ends = snap.breakEnds, ends > entry.date {
                    Text("Break · back \(ends, style: .time)")
                } else {
                    Text("On a break · \(hm(snap.workedTotal(now: entry.date)))")
                }
            default:
                if let done = snap.doneBy(now: entry.date) {
                    Text("\(hm(snap.workedTotal(now: entry.date))) · done \(done, style: .time)")
                } else {
                    Text("\(hm(snap.workedTotal(now: entry.date))) worked")
                }
            }
        } else {
            Text("BetterBob")
        }
    }
}

private func hm(_ interval: TimeInterval) -> String {
    let m = Int(interval / 60)
    return String(format: "%d:%02d", m / 60, m % 60)
}
