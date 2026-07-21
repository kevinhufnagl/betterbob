import AppKit
import ServiceManagement
import UserNotifications
import WebKit

/// Removes every trace BetterBob leaves on this Mac — Keychain credentials,
/// settings, the embedded browser session, the login item, per-app caches —
/// then moves the app bundle to the Trash and quits. Attendance data lives on
/// HiBob and is untouched; only local state is deleted.
enum Uninstaller {
    static func run() {
        Keychain.wipeAll()
        try? SMAppService.mainApp.unregister()
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        HTTPCookieStorage.shared.cookies?.forEach(HTTPCookieStorage.shared.deleteCookie)
        resetPermissionGrants()

        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }

        // The web-view store clears asynchronously; trashing and quitting wait
        // for its completion handler so termination can't cut the wipe short.
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            removeLeftoverContainers()
            try? FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
            NSApp.terminate(nil)
        }
    }

    /// Best-effort reset of the TCC grants (Location, used for Wi-Fi tagging)
    /// so a reinstall starts from a clean slate. Failure is fine — grants on a
    /// trashed app are inert.
    private static func resetPermissionGrants() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "All", id]
        try? p.run()
        p.waitUntilExit()
    }

    /// The per-bundle-id folders macOS keeps outside the app bundle. The
    /// website-data removal above already emptied their contents; this clears
    /// the empty shells (and whatever a future macOS leaves behind).
    private static func removeLeftoverContainers() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let lib = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
        for path in ["WebKit/\(id)",
                     "HTTPStorages/\(id)",
                     "Caches/\(id)",
                     "Saved Application State/\(id).savedState"] {
            try? FileManager.default.removeItem(at: lib.appendingPathComponent(path))
        }
    }
}
