import BetterBobShared
import ActivityKit
import Foundation

/// Owns the one Live Activity mirroring the clock state: started on clock-in,
/// updated on every snapshot push, ended on clock-out or sign-out. Updates are
/// local-only (no push token), so they land whenever the app runs — the
/// timer text itself ticks on its own in between.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private var activity: Activity<BobActivityAttributes>?

    func sync(_ snapshot: WidgetSnapshot) {
        guard Prefs.shared.liveActivityEnabled else {
            end()
            return
        }
        switch snapshot.state {
        case .working, .onBreak:
            // Projected clock-out. Working: the snapshot's own projection.
            // On a break: no stretch is open, so workedBase is the whole
            // day — remaining work starts once the break ends.
            let doneBy: Date?
            if snapshot.state == .working {
                doneBy = snapshot.doneBy(now: Date())
            } else {
                let remaining = snapshot.target - snapshot.workedBase
                doneBy = remaining > 0
                    ? (snapshot.breakEnds ?? Date()).addingTimeInterval(remaining)
                    : nil
            }
            let content = BobActivityAttributes.ContentState(
                isOnBreak: snapshot.state == .onBreak,
                stretchStart: snapshot.stretchStart ?? snapshot.updatedAt,
                workedBase: snapshot.workedBase,
                breakEnds: snapshot.breakEnds,
                showsTotal: Prefs.shared.liveActivityShowsTotal,
                target: snapshot.target,
                breakDue: snapshot.breakDue,
                doneBy: doneBy,
                pendingBreak: snapshot.pendingBreak ?? 0,
                segments: snapshot.segments)
            if let activity {
                Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
            } else {
                activity = try? Activity.request(
                    attributes: BobActivityAttributes(),
                    content: ActivityContent(state: content, staleDate: nil))
            }
        case .clockedOut, .signedOut:
            end()
        }
    }

    private func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
