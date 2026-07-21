import BetterBobShared
import SwiftUI

/// The month at a glance: stat tiles, the shared calendar heatmap, and the
/// balance trend — each in its own glass card. Day cells open the shared
/// day-detail editor in a sheet.
struct MonthScreen: View {
    @ObservedObject var state: BobState
    var onOpenToday: () -> Void = {}
    @State private var openDayKey: String?

    private var summary: CycleSummary? { state.cycleSummary }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if monthTargetSecs > 0 {
                    LiquidHero(worked: monthWorkedSecs, target: monthTargetSecs,
                               cornerRadius: 18)
                        .frame(height: 150)
                        .glassSurface()
                }
                statGrid
                CalendarHeatmap(state: state, onOpenToday: onOpenToday,
                                onOpenDay: { openDayKey = $0 })
                if summary?.days.isEmpty == false {
                    BalanceTrendCard(state: state)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .bobScreen(title: "Month")
        .toolbar {
            NavigationLink {
                ActivityScreen(state: state)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
        }
        .refreshable { await state.reconcile() }
        .task { await state.loadCycleData() }
        .sheet(isPresented: Binding(get: { openDayKey != nil },
                                    set: { if !$0 { openDayKey = nil } })) {
            if let key = openDayKey {
                DayDetailScreen(state: state, dateKey: key)
            }
        }
    }

    private var statGrid: some View {
        let balance = summary?.overUnderMinutes ?? 0
        let potential = summary?.potentialMinutes ?? 0
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                         spacing: 12) {
            StatTile(value: Fmt.hm(monthWorkedSecs),
                     caption: "Worked this cycle")
            StatTile(value: (balance >= 0 ? "+" : "−") + Fmt.hm(TimeInterval(abs(balance) * 60)),
                     caption: "Balance",
                     tint: balance >= 0 ? .primary : .bobOrange)
            if potential > 0 {
                StatTile(value: Fmt.hm(TimeInterval(potential * 60)),
                         caption: "Cycle target")
                StatTile(value: "\(summary?.days.count ?? 0)",
                         caption: "Days recorded")
            }
        }
    }

    // Mirrors the Mac CyclePane: HiBob's own totals are authoritative; the
    // per-day series drifts from them by rounding.
    private var monthWorkedSecs: TimeInterval {
        if let display = summary?.totalHoursDisplay {
            let mins = BobParsing.minutes(fromDisplay: display)
            if mins > 0 { return TimeInterval(mins * 60) }
        }
        return (summary?.days ?? []).reduce(0) { $0 + $1.worked * 3600 }
    }
    private var monthTargetSecs: TimeInterval {
        if let mins = summary?.potentialMinutes, mins > 0 { return TimeInterval(mins * 60) }
        return (summary?.days ?? []).reduce(0) { $0 + ($1.target ?? 0) * 3600 }
    }
}

/// Today's clock & edit history — pushed from the Month toolbar.
struct ActivityScreen: View {
    @ObservedObject var state: BobState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if state.activity.isEmpty {
                    GlassCard {
                        Text("No activity recorded today.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    }
                } else {
                    GlassGroupedSection(header: "Today") {
                        ForEach(Array(state.activity.enumerated()), id: \.offset) { i, event in
                            GlassRow(showDivider: i > 0) {
                                activityRow(event)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .bobScreen(title: "Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { await state.loadActivity() }
    }

    private func activityRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(event.kind))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.detail)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(Fmt.clock(event.timestamp))
                    if !event.actor.isEmpty {
                        Text("· \(event.actor)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func symbol(_ kind: ActivityEvent.Kind) -> String {
        switch kind {
        case .clockedIn: return "play.fill"
        case .clockedOut: return "stop.fill"
        case .addedBreak: return "cup.and.saucer.fill"
        case .edited: return "pencil"
        case .other: return "circle.dashed"
        }
    }
}
