import AppIntents
import BetterBobShared

/// The home-screen widget's button: clock in when out, clock out when
/// working, end the break when on one. `openAppWhenRun` routes the perform
/// into the app process — the widget process has no HiBob session, so a
/// silent punch from there would always fail.
struct ToggleClockIntent: AppIntent {
    static let title: LocalizedStringResource = "Clock In or Out"
    static let description = IntentDescription("Toggles the HiBob clock: in when out, out when working, ends a running break.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let state = BobState.shared
        guard state.signedIn else { return .result() }
        switch state.projectedClockState {
        case .clockedOut: state.clockIn()
        case .working:    state.clockOut()
        case .onBreak:    state.endBreak()
        }
        return .result()
    }
}

/// The Live Activity's second action while working. Same app-routed perform
/// as ToggleClockIntent, for the same reason: only the app has the session.
struct StartBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Break"
    static let description = IntentDescription("Starts a break on the HiBob clock while working.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let state = BobState.shared
        guard state.signedIn, case .working = state.projectedClockState else { return .result() }
        state.startManualBreak()
        return .result()
    }
}
