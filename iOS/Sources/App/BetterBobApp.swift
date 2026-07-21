import SwiftUI

@main
struct BetterBobApp: App {
    var body: some Scene {
        WindowGroup {
            // Touch a shared symbol so a broken include list fails the build.
            Text("BetterBob — worked \(Int(AttendanceLogic.workedToday(entries: [], now: Date())))s")
        }
    }
}
