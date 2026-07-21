import BetterBobShared
import WidgetKit
import SwiftUI

// MARK: - Holiday pool

struct HolidayPoolWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HolidayPool", provider: SnapshotProvider()) { entry in
            HolidayPoolView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Holiday pool")
        .description("Days left in your vacation pool, draining as they get used.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct HolidayPoolView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var left: Double? { entry.snapshot?.holidayLeft }
    private var total: Double? { entry.snapshot?.holidayTotal }
    private var fraction: Double {
        guard let left, let total, total > 0 else { return 0 }
        return min(1, max(0, left / total))
    }
    private func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    var body: some View {
        if let left, let snap = entry.snapshot {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    WaveFill(fraction: fraction, color: .primary.opacity(0.35))
                        .clipShape(Circle())
                    Text(trimmed(left))
                        .font(.system(size: 16, weight: .bold).monospacedDigit())
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(snap.holidayName ?? "Time off")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Text("\(trimmed(left)) \(snap.holidayUnit ?? "days") left")
                        .font(.headline.monospacedDigit())
                    if let total {
                        Gauge(value: fraction) { EmptyView() }
                            .gaugeStyle(.accessoryLinearCapacity)
                        let _ = total
                    }
                }
            default:
                ZStack(alignment: .bottomLeading) {
                    WaveFill(fraction: fraction, color: .accentColor.opacity(0.45))
                        .ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trimmed(left))
                            .font(.title.bold().monospacedDigit())
                        Text(total.map { "of \(trimmed($0)) \(snap.holidayUnit ?? "days") left" }
                             ?? "\(snap.holidayUnit ?? "days") left")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Label("Open BetterBob", systemImage: "sun.max")
                .font(.caption)
        }
    }
}

// MARK: - Next time off

struct NextTimeOffWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextTimeOff", provider: SnapshotProvider()) { entry in
            NextTimeOffView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next time off")
        .description("Counting down to your next booked leave.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct NextTimeOffView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var daysAway: Int? {
        guard let start = entry.snapshot?.nextTimeOffStart else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: entry.date),
                                  to: cal.startOfDay(for: start)).day
    }

    var body: some View {
        if let snap = entry.snapshot, let start = snap.nextTimeOffStart, let days = daysAway {
            let when = days == 0 ? "today"
                     : days == 1 ? "tomorrow"
                     : "in \(days) days"
            if family == .accessoryInline {
                Text("\(snap.nextTimeOffName ?? "Time off") \(when)")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snap.nextTimeOffName ?? "Time off")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Text(when)
                        .font(.headline)
                    Text(start.formatted(.dateTime.weekday(.wide).day().month()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else if family == .accessoryInline {
            Text("No time off booked")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time off")
                    .font(.caption2.weight(.semibold))
                Text("Nothing booked")
                    .font(.headline)
                Text("Go book something sunny")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
