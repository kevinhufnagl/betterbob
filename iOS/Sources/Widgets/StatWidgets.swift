import BetterBobShared
import WidgetKit
import SwiftUI

// MARK: - Shared drawing

/// A static water fill with a wavy top edge — the app's signature hero,
/// frozen for widget rendering (widgets can't animate shapes).
struct WaveFill: View {
    var fraction: Double
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let level = size.height * (1 - max(0, min(1, fraction)))
            var p = Path()
            p.move(to: CGPoint(x: 0, y: level))
            for x in stride(from: CGFloat(0), through: size.width, by: 2) {
                let y = level + sin(x / size.width * .pi * 3.2) * min(4, size.height * 0.04)
                p.addLine(to: CGPoint(x: x, y: y))
            }
            p.addLine(to: CGPoint(x: size.width, y: size.height))
            p.addLine(to: CGPoint(x: 0, y: size.height))
            p.closeSubpath()
            ctx.fill(p, with: .color(color))
        }
    }
}

/// Five capsule bars, one per workday Mon–Fri, filled against the day's
/// target; today is drawn solid, the rest dimmed.
struct WeekBars: View {
    var fractions: [Double]
    var date: Date

    var body: some View {
        let todayIndex = (Calendar(identifier: .iso8601).component(.weekday, from: date) + 5) % 7
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        Capsule().fill(.primary.opacity(0.18))
                        Capsule().fill(.primary.opacity(i == todayIndex ? 0.9 : 0.55))
                            .frame(height: max(3, geo.size.height * (i < fractions.count ? fractions[i] : 0)))
                    }
                }
            }
        }
    }
}

private func hm(_ minutes: Int) -> String {
    String(format: "%d:%02d", minutes / 60, abs(minutes) % 60)
}

// MARK: - Month progress

struct MonthProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MonthProgress", provider: SnapshotProvider()) { entry in
            MonthProgressView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Month progress")
        .description("Hours worked against the cycle's target.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct MonthProgressView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var worked: Int? { entry.snapshot?.cycleWorkedMinutes }
    private var potential: Int? { entry.snapshot?.cyclePotentialMinutes }
    private var fraction: Double {
        guard let worked, let potential, potential > 0 else { return 0 }
        return min(1, Double(worked) / Double(potential))
    }

    var body: some View {
        if let worked, let potential, potential > 0 {
            switch family {
            case .accessoryCircular:
                Gauge(value: fraction) {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("This cycle")
                        .font(.caption2.weight(.semibold))
                    Text("\(hm(worked)) of \(hm(potential))")
                        .font(.headline.monospacedDigit())
                    Gauge(value: fraction) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                }
            default:
                ZStack(alignment: .bottomLeading) {
                    WaveFill(fraction: fraction, color: .accentColor.opacity(0.45))
                        .ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.title.bold().monospacedDigit())
                        Text("\(hm(worked)) of \(hm(potential)) this cycle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Label("Open BetterBob", systemImage: "calendar")
                .font(.caption)
        }
    }
}

// MARK: - Cycle balance

struct CycleBalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CycleBalance", provider: SnapshotProvider()) { entry in
            CycleBalanceView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Balance")
        .description("Your running over/under for the cycle, with the week at a glance.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct CycleBalanceView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let balance = entry.snapshot?.cycleBalanceMinutes {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Balance")
                        .font(.caption2.weight(.semibold))
                    Text((balance >= 0 ? "+" : "−") + hm(abs(balance)))
                        .font(.headline.monospacedDigit())
                }
                if let fractions = entry.snapshot?.weekFractions {
                    WeekBars(fractions: fractions, date: entry.date)
                        .frame(width: 56)
                }
            }
        } else {
            Label("Open BetterBob", systemImage: "scalemass")
                .font(.caption)
        }
    }
}

// MARK: - Week strip

struct WeekStripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekStrip", provider: SnapshotProvider()) { entry in
            WeekStripView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Week")
        .description("Monday to Friday against each day's target.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct WeekStripView: View {
    let entry: SnapshotEntry

    private let labels = ["M", "T", "W", "T", "F"]

    var body: some View {
        if let fractions = entry.snapshot?.weekFractions {
            VStack(spacing: 2) {
                WeekBars(fractions: fractions, date: entry.date)
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { i in
                        Text(labels[i])
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        } else {
            Label("Open BetterBob", systemImage: "calendar")
                .font(.caption)
        }
    }
}

// MARK: - Done by

struct DoneByWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoneBy", provider: SnapshotProvider()) { entry in
            DoneByView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Done by")
        .description("When you'll hit today's target at the current pace, pending break included.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct DoneByView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var doneBy: Date? {
        guard let snap = entry.snapshot else { return nil }
        return snap.doneBy(now: snap.updatedAt)
    }

    var body: some View {
        if family == .accessoryInline {
            if let doneBy {
                Text("Done by \(doneBy.formatted(date: .omitted, time: .shortened))")
            } else if let snap = entry.snapshot, snap.state == .clockedOut {
                Text("Clocked out")
            } else {
                Text("BetterBob")
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    if let doneBy {
                        Text("done")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(doneBy.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .minimumScaleFactor(0.7)
                    } else {
                        BobFaceMark(expression: .asleep)
                            .frame(width: 26, height: 26)
                    }
                }
            }
        }
    }
}
