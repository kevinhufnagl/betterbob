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
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private func hm(_ interval: TimeInterval) -> String {
        let m = Int(interval / 60)
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    var body: some View {
        if let snap = entry.snapshot {
            switch family {
            case .accessoryCircular:
                Gauge(value: min(1, snap.workedTotal(now: entry.date) / max(snap.target, 1))) {
                    BobFaceMark()
                        .frame(width: 20, height: 20)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                // Tight three-liner — the lock screen slot clips anything
                // taller, and expanding frames spread the content apart.
                VStack(alignment: .leading, spacing: 0) {
                    Label(title(snap.state), systemImage: symbol(snap.state))
                        .font(.caption2.weight(.semibold))
                    timerText(snap)
                        .font(.headline.monospacedDigit())
                    Text("of \(hm(snap.target))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Label(title(snap.state), systemImage: symbol(snap.state))
                        .font(.caption.weight(.semibold))
                    timerText(snap)
                        .font(.title2.monospacedDigit().weight(.medium))
                    Text("of \(hm(snap.target)) today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            Label("Open BetterBob", systemImage: "clock")
                .font(.caption)
        }
    }

    @ViewBuilder private func timerText(_ snap: WidgetSnapshot) -> some View {
        if snap.state == .working, let start = snap.stretchStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
        } else {
            Text(hm(snap.workedTotal(now: entry.date)))
        }
    }

    private func title(_ s: WidgetSnapshot.State) -> String {
        switch s {
        case .working: return "Working"
        case .onBreak: return "On a break"
        case .clockedOut: return "Clocked out"
        case .signedOut: return "Signed out"
        }
    }
    private func symbol(_ s: WidgetSnapshot.State) -> String {
        switch s {
        case .working: return "play.fill"
        case .onBreak: return "pause.fill"
        case .clockedOut: return "clock"
        case .signedOut: return "lock.fill"
        }
    }
}
