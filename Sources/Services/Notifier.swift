import Foundation
import UserNotifications

/// Local notifications for the moments that matter: the auto-break firing,
/// ending, repairs after sleep, and anything that failed.
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func autoBreakStarted(length: TimeInterval) {
        guard Prefs.shared.notifyAutoBreak else { return }
        post(title: "Break time",
             body: "6 hours of uninterrupted work — a \(Fmt.hm(length)) break just started in HiBob.")
    }

    static func autoBreakEnded() {
        guard Prefs.shared.notifyAutoBreak else { return }
        post(title: "Back to work",
             body: "Your auto-break is over — you're clocked back in.")
    }

    static func insertedPastBreak(start: Date, end: Date) {
        guard Prefs.shared.notifyAutoBreak else { return }
        post(title: "Break added retroactively",
             body: "The 6-hour mark passed while your Mac was asleep — a break was recorded from \(Fmt.clock(start)) to \(Fmt.clock(end)).")
    }

    static func targetReached(_ target: String) {
        guard Prefs.shared.notifyTargetReached else { return }
        post(title: "Target reached",
             body: "You've hit today's \(target) target — anything more is overtime.")
    }

    static func overDailyMax(_ max: String) {
        guard Prefs.shared.notifyOverMax else { return }
        post(title: "Over \(max) worked today",
             body: "You're past your daily maximum — consider clocking out.")
    }

    static func deadlineApproaching(days: Int) {
        guard Prefs.shared.notifyDeadline else { return }
        let when = days <= 0 ? "today" : "in \(days) day\(days == 1 ? "" : "s")"
        post(title: "Timesheet locks \(when)",
             body: "Submit your timesheet for approval before it locks.")
    }

    static func failure(_ message: String) {
        guard Prefs.shared.notifyFailures else { return }
        post(title: "BetterBob couldn't reach HiBob", body: message)
    }

    /// Notification identifier for "enter your code" — the tap handler opens
    /// the popover when it sees this.
    static let awaitingCodeID = "betterbob.awaitingCode"

    /// The HiBob session expired and automatic re-login is set up — nudge the
    /// user to reconnect. Tapping opens BetterBob and starts the sign-in so they
    /// can enter their authenticator code.
    static func awaitingCode() {
        guard Prefs.shared.notifyAwaitingCode else { return }
        post(title: "Sign back in to HiBob",
             body: "Your session expired — click to reconnect and enter your authenticator code.",
             identifier: awaitingCodeID)
    }

    /// Once per version — a new BetterBob build was installed in the background.
    static func updateInstalled(version: String) {
        guard UserDefaults.standard.string(forKey: "updateNotifiedVersion") != version else { return }
        UserDefaults.standard.set(version, forKey: "updateNotifiedVersion")
        post(title: "BetterBob \(version) installed",
             body: "The update applies the next time BetterBob starts.")
    }

    private static func post(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: identifier,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
