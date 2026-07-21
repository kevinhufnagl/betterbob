import BetterBobShared
import BackgroundTasks
import Foundation

/// Best-effort background polling: iOS decides when refreshes actually run,
/// so breaks may be written late — reconcile()'s catch-up path then inserts
/// them retroactively at the time they were due, matching the Mac.
enum BackgroundRefresh {
    static let taskID = "k3n.betterbob.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            handle(task as! BGAppRefreshTask)
        }
    }

    @MainActor
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = AttendanceLogic.nextBackgroundRefresh(
            now: Date(), breakDue: BobState.shared.autoBreakDue)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let work = Task { @MainActor in
            await BobState.shared.reconcile()
            schedule()                       // chain the next wake
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
