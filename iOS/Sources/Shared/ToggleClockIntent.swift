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

/// The Live Activity's actions, headless. LiveActivityIntent performs in the
/// APP's process (launched in the background if needed) without foregrounding
/// it — so the session cookies are right there and the punch can run
/// synchronously via `punchNow`, which returns only once the server call
/// landed and the fresh snapshot re-rendered the activity. Failure feedback
/// is the card itself: the optimistic flip rolls back to reality on the
/// reconcile — the iOS app posts no notifications, by design.
struct PunchIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Punch the Clock"
    static let description = IntentDescription("Performs a HiBob clock action without opening the app.")

    @Parameter(title: "Action") var action: PunchChoice

    init() {}
    init(_ action: PunchChoice) { self.action = action }

    @MainActor
    func perform() async throws -> some IntentResult {
        let state = BobState.shared
        guard state.signedIn else { return .result() }
        _ = await state.punchNow(action.punchAction)
        return .result()
    }
}

enum PunchChoice: String, AppEnum {
    case clockOut, startBreak, endBreak

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Clock Action")
    static let caseDisplayRepresentations: [PunchChoice: DisplayRepresentation] = [
        .clockOut: "Clock Out", .startBreak: "Start a Break", .endBreak: "End the Break",
    ]

    var punchAction: PunchAction {
        switch self {
        case .clockOut: return .clockOut
        case .startBreak: return .startBreak
        case .endBreak: return .endBreak
        }
    }
}
