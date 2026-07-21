import AppIntents
import Foundation
// On iOS this file compiles into the app target next to the BetterBobShared
// package; on macOS it is globbed into the single app module, where no such
// module exists.
#if canImport(BetterBobShared)
import BetterBobShared
#endif

/// "Hey Siri, clock in" — punch actions from Siri, Spotlight, Shortcuts,
/// and the Action Button.
struct ClockInIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock In"
    static var description = IntentDescription("Clocks you in to HiBob.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard BobState.shared.signedIn else {
            return .result(dialog: "Sign in to HiBob first — open BetterBob's settings.")
        }
        if case .clockedOut = BobState.shared.clockState {
            BobState.shared.clockIn()
            return .result(dialog: "Clocking in.")
        }
        return .result(dialog: "You're already clocked in.")
    }
}

struct ClockOutIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock Out"
    static var description = IntentDescription("Clocks you out of HiBob.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard BobState.shared.signedIn else {
            return .result(dialog: "Sign in to HiBob first — open BetterBob's settings.")
        }
        if case .clockedOut = BobState.shared.clockState {
            return .result(dialog: "You're not clocked in.")
        }
        BobState.shared.clockOut()
        return .result(dialog: "Clocking out.")
    }
}

struct TakeBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Take a Break"
    static var description = IntentDescription("Starts a break in HiBob.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard BobState.shared.signedIn else {
            return .result(dialog: "Sign in to HiBob first — open BetterBob's settings.")
        }
        switch BobState.shared.clockState {
        case .working:
            BobState.shared.startManualBreak()
            return .result(dialog: "Starting your break.")
        case .onBreak:
            return .result(dialog: "You're already on a break.")
        case .clockedOut:
            return .result(dialog: "You're not clocked in.")
        }
    }
}

struct BobShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClockInIntent(),
            phrases: [
                "Clock in with \(.applicationName)",
                "Start work in \(.applicationName)",
            ],
            shortTitle: "Clock in",
            systemImageName: "clock.fill"
        )
        AppShortcut(
            intent: ClockOutIntent(),
            phrases: [
                "Clock out with \(.applicationName)",
                "Stop work in \(.applicationName)",
            ],
            shortTitle: "Clock out",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: TakeBreakIntent(),
            phrases: [
                "Take a break with \(.applicationName)",
            ],
            shortTitle: "Take a break",
            systemImageName: "cup.and.saucer.fill"
        )
    }
}
