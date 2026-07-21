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
            let content = BobActivityAttributes.ContentState(
                isOnBreak: snapshot.state == .onBreak,
                stretchStart: snapshot.stretchStart ?? snapshot.updatedAt,
                workedBase: snapshot.workedBase,
                breakEnds: snapshot.breakEnds,
                showsTotal: Prefs.shared.liveActivityShowsTotal)
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
