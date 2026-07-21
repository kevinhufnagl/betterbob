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
        let snapshot = AttendanceLogic.widgetSnapshot(
            entries: state.entries, signedIn: state.signedIn,
            target: Prefs.shared.threshold, breakEnds: state.autoBreakEnds,
            now: Date())
        SharedStore.save(snapshot)
        // LiveActivityController.shared.sync(snapshot)  ← wired in Task 11
    }
}
