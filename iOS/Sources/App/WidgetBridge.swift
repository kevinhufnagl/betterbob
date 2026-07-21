import BetterBobShared
import Combine
import Foundation

/// Mirrors engine state into the App Group after every poll so the widgets
/// (and later the Live Activity) always render the latest reconcile.
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()
    private var cancellables: Set<AnyCancellable> = []

    func start() {
        let state = BobState.shared
        state.$lastSync
            .combineLatest(state.$clockState, state.$signedIn)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.push() }
            .store(in: &cancellables)
    }

    func push() {
        let state = BobState.shared
        // The day's real target (from the cycle summary, like the app hero) —
        // NOT Prefs.threshold, which is the auto-break threshold.
        let target = TodayVals(state, now: Date()).targetSecs
        let snapshot = AttendanceLogic.widgetSnapshot(
            entries: state.entries, signedIn: state.signedIn,
            target: target, breakEnds: state.autoBreakEnds,
            breakDue: state.autoBreakDue,
            now: Date())
        SharedStore.save(snapshot)
        LiveActivityController.shared.sync(snapshot)
    }
}
