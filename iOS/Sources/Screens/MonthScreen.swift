import BetterBobShared
import SwiftUI

/// The month at a glance: stat tiles, the shared calendar heatmap, and the
/// balance trend — each in its own glass card. Day cells open the shared
/// day-detail editor in a sheet.
struct MonthScreen: View {
    @ObservedObject var state: BobState
    var onOpenToday: () -> Void = {}

    private var summary: CycleSummary? { state.cycleSummary }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statGrid
                GlassCard {
                    CalendarHeatmap(state: state, onOpenToday: onOpenToday)
                }
                if summary?.days.isEmpty == false {
                    GlassCard {
                        BalanceTrendCard(state: state)
                    }
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
    }

    private var statGrid: some View {
        let workedMin = summary.map { $0.days.reduce(0) { $0 + Int($1.worked * 60) } } ?? 0
        let balance = summary?.overUnderMinutes ?? 0
        let potential = summary?.potentialMinutes ?? 0
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                         spacing: 12) {
            GlassCard(padding: 14) {
                StatTile(value: Fmt.hm(TimeInterval(workedMin * 60)),
                         caption: "Worked this cycle", symbol: "hammer.fill")
            }
            GlassCard(padding: 14) {
                StatTile(value: (balance >= 0 ? "+" : "−") + Fmt.hm(TimeInterval(abs(balance) * 60)),
                         caption: "Balance",
                         tint: balance >= 0 ? .primary : .bobOrange,
                         symbol: "scalemass.fill")
            }
            if potential > 0 {
                GlassCard(padding: 14) {
                    StatTile(value: Fmt.hm(TimeInterval(potential * 60)),
                             caption: "Cycle target", symbol: "target")
                }
                GlassCard(padding: 14) {
                    StatTile(value: "\(summary?.days.count ?? 0)",
                             caption: "Days recorded", symbol: "calendar")
                }
            }
        }
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
