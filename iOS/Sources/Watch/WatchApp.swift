import SwiftUI

@main
struct BetterBobWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WatchSession.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchHome(session: WatchSession.shared)
        }
        .onChange(of: scenePhase) { _, phase in
            // Raising the wrist is the moment the numbers must be fresh —
            // ask the phone for a new snapshot on every foreground.
            if phase == .active { WatchSession.shared.refresh() }
        }
    }
}
