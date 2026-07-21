import BetterBobShared
import WidgetKit
import SwiftUI

@main
struct BetterBobWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        BobLiveActivity()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: SharedStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: SharedStore.load())
        completion(Timeline(entries: [entry],
                            policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your clock state and time worked today.")
        .supportedFamilies([.systemSmall, .accessoryRectangular,
                            .accessoryCircular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private func hm(_ interval: TimeInterval) -> String {
        let m = Int(interval / 60)
        return String(format: "%d:%02d", m / 60, m % 60)
    }
    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
    private func fraction(_ snap: WidgetSnapshot) -> Double {
        min(1, snap.workedTotal(now: entry.date) / max(snap.target, 1))
    }

    var body: some View {
        if let snap = entry.snapshot {
            switch family {
            case .accessoryCircular: circular(snap)
            case .accessoryRectangular: rectangular(snap)
            case .accessoryInline: inline(snap)
            default: small(snap)
            }
        } else {
            Label("Open BetterBob", systemImage: "clock")
                .font(.caption)
        }
    }

    // MARK: Circular — filling while working, draining on break, calm when done

    @ViewBuilder private func circular(_ snap: WidgetSnapshot) -> some View {
        switch snap.state {
        case .working:
            Gauge(value: fraction(snap)) {
                BobFaceMark().frame(width: 20, height: 20)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .onBreak:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "pause.fill").font(.caption2)
                    if let ends = snap.breakEnds, ends > entry.date {
                        Text(timerInterval: entry.date...ends, countsDown: true)
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                    } else {
                        Text("Break").font(.caption2)
                    }
                }
            }
        case .clockedOut, .signedOut:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    BobFaceMark().frame(width: 16, height: 16)
                    Text(snap.state == .signedOut ? "—" : hm(snap.workedBase))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
            }
        }
    }

    // MARK: Rectangular — status, big timer, progress bar / context line

    @ViewBuilder private func rectangular(_ snap: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            switch snap.state {
            case .working:
                Text(statusLine(snap))
                    .font(.caption2.weight(.semibold))
                if let start = snap.stretchStart {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(.headline.monospacedDigit())
                }
                Gauge(value: fraction(snap)) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            case .onBreak:
                Text("On a break")
                    .font(.caption2.weight(.semibold))
                if let ends = snap.breakEnds, ends > entry.date {
                    Text(timerInterval: entry.date...ends, countsDown: true)
                        .font(.headline.monospacedDigit())
                    Text("back at \(clock(ends))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(hm(snap.workedBase))
                        .font(.headline.monospacedDigit())
                    Text("worked so far")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .clockedOut, .signedOut:
                Text(snap.state == .signedOut ? "Signed out" : "Clocked out")
                    .font(.caption2.weight(.semibold))
                Text(hm(snap.workedBase))
                    .font(.headline.monospacedDigit())
                Text("of \(hm(snap.target))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Working", enriched with the next fixed point when one is known —
    /// absolute times so a stale snapshot never shows a wrong countdown.
    private func statusLine(_ snap: WidgetSnapshot) -> String {
        if let due = snap.breakDue, due > entry.date {
            return "Working · break \(clock(due))"
        }
        if let done = snap.doneBy(now: entry.date) {
            return "Working · done \(clock(done))"
        }
        return "Working"
    }

    // MARK: Inline — one line above the clock

    @ViewBuilder private func inline(_ snap: WidgetSnapshot) -> some View {
        switch snap.state {
        case .working:
            if let start = snap.stretchStart {
                Text("Working ") + Text(timerInterval: start...Date.distantFuture, countsDown: false)
            } else {
                Text("Working")
            }
        case .onBreak:
            if let ends = snap.breakEnds, ends > entry.date {
                Text("Break ends \(clock(ends))")
            } else {
                Text("On a break")
            }
        case .clockedOut:
            Text("Clocked out · \(hm(snap.workedBase))")
        case .signedOut:
            Text("BetterBob · signed out")
        }
    }

    // MARK: Home screen small — glance plus a real button

    @ViewBuilder private func small(_ snap: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(smallTitle(snap), systemImage: smallSymbol(snap))
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            if snap.state == .working, let start = snap.stretchStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.title2.monospacedDigit().weight(.medium))
            } else if snap.state == .onBreak, let ends = snap.breakEnds, ends > entry.date {
                Text(timerInterval: entry.date...ends, countsDown: true)
                    .font(.title2.monospacedDigit().weight(.medium))
            } else {
                Text(hm(snap.workedTotal(now: entry.date)))
                    .font(.title2.monospacedDigit().weight(.medium))
            }
            Gauge(value: fraction(snap)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(.accentColor)
            Spacer(minLength: 0)
            if snap.state != .signedOut {
                Button(intent: ToggleClockIntent()) {
                    Text(buttonTitle(snap))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func smallTitle(_ snap: WidgetSnapshot) -> String {
        switch snap.state {
        case .working: return "Working"
        case .onBreak: return "On a break"
        case .clockedOut: return "Clocked out"
        case .signedOut: return "Signed out"
        }
    }
    private func smallSymbol(_ snap: WidgetSnapshot) -> String {
        switch snap.state {
        case .working: return "play.fill"
        case .onBreak: return "pause.fill"
        case .clockedOut: return "clock"
        case .signedOut: return "lock.fill"
        }
    }
    private func buttonTitle(_ snap: WidgetSnapshot) -> String {
        switch snap.state {
        case .working: return "Clock out"
        case .onBreak: return "End break"
        default: return "Clock in"
        }
    }
}
