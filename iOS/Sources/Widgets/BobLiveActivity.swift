import BetterBobShared
import ActivityKit
import WidgetKit
import SwiftUI

struct BobLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BobActivityAttributes.self) { context in
            HStack {
                Label(context.state.isOnBreak ? "On a break" : "Working",
                      systemImage: context.state.isOnBreak ? "pause.fill" : "play.fill")
                    .font(.headline)
                Spacer()
                timer(context.state)
                    .font(.title3.monospacedDigit())
            }
            .padding()
            .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.isOnBreak ? "Break" : "Working",
                          systemImage: context.state.isOnBreak ? "pause.fill" : "play.fill")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context.state).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isOnBreak, let ends = context.state.breakEnds {
                        Text("Break ends \(ends, style: .time)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isOnBreak ? "pause.fill" : "play.fill")
            } compactTrailing: {
                timer(context.state).monospacedDigit().frame(maxWidth: 44)
            } minimal: {
                Image(systemName: context.state.isOnBreak ? "pause.fill" : "play.fill")
            }
        }
    }

    @ViewBuilder
    private func timer(_ state: BobActivityAttributes.ContentState) -> some View {
        if state.isOnBreak, let ends = state.breakEnds {
            Text(timerInterval: Date()...ends, countsDown: true)
        } else {
            Text(timerInterval: state.stretchStart...Date.distantFuture, countsDown: false)
        }
    }
}
