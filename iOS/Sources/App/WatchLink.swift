import BetterBobShared
import Foundation
import WatchConnectivity

/// The phone's half of the watch bridge: pushes every widget snapshot into
/// the WCSession application context, and performs the punches the watch
/// sends back — through the same awaited `punchNow` path as the Live
/// Activity pills, for the same reason: a watch message can launch this app
/// in the background, and the process sleeps the moment the reply is sent.
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Called by WidgetBridge on every snapshot save. Application context
    /// keeps only the latest value and delivers it when the watch wakes —
    /// exactly the semantics a status mirror wants.
    func push(_ snapshot: WidgetSnapshot) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired,
              session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? session.updateApplicationContext(["snapshot": data])
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            var errorText: String?
            if let raw = message["punch"] as? String {
                if let action = Self.action(raw) {
                    let ok = await BobState.shared.punchNow(action)
                    if !ok {
                        errorText = BobState.shared.lastError ?? "Couldn't reach HiBob."
                    }
                } else {
                    errorText = "Unknown action."
                }
            } else if message["refresh"] != nil {
                await BobState.shared.reconcile()
            }
            // Write the snapshot synchronously (reconcile's own push is
            // debounced and would race the reply), then answer with it.
            WidgetBridge.shared.push()
            var reply: [String: Any] = [:]
            if let snap = SharedStore.load(), let data = try? JSONEncoder().encode(snap) {
                reply["snapshot"] = data
            }
            if let errorText { reply["error"] = errorText }
            replyHandler(reply)
        }
    }

    private static func action(_ raw: String) -> PunchAction? {
        switch raw {
        case "clockIn": return .clockIn
        case "clockOut": return .clockOut
        case "startBreak": return .startBreak
        case "endBreak": return .endBreak
        default: return nil
        }
    }
}
