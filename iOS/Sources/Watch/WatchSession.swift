import Foundation
import WatchConnectivity
import WidgetKit

/// The watch's whole data layer: the phone pushes a WidgetSnapshot through
/// the WCSession application context after every reconcile, and punches go
/// back as messages — sending one launches the iPhone app in the background,
/// which performs it through the same headless path as the Live Activity
/// pills and replies with the fresh snapshot.
final class WatchSession: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSession()

    @Published var snapshot: WidgetSnapshot?
    /// A punch is in flight — buttons show a spinner and won't double-fire.
    @Published var punching = false
    @Published var lastError: String?

    func start() {
        // The last snapshot, so a fresh launch shows the day immediately
        // instead of a blank screen while the phone is asked.
        snapshot = WatchStore.load()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Ask the phone for a fresh snapshot (also wakes its reconcile).
    func refresh() {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["refresh": true], replyHandler: { [weak self] reply in
            self?.apply(reply)
        }, errorHandler: { _ in })   // silent: the context push will catch up
    }

    /// Send a punch. The reply carries the post-punch snapshot; an error is
    /// surfaced, because a dead button on a watch is worse than an error line.
    func punch(_ action: String) {
        guard !punching else { return }
        punching = true
        lastError = nil
        guard WCSession.default.activationState == .activated else {
            punching = false
            lastError = "iPhone not reachable."
            return
        }
        WCSession.default.sendMessage(["punch": action], replyHandler: { [weak self] reply in
            DispatchQueue.main.async {
                self?.punching = false
                if let msg = reply["error"] as? String { self?.lastError = msg }
            }
            self?.apply(reply)
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.punching = false
                self?.lastError = error.localizedDescription
            }
        })
    }

    private func apply(_ payload: [String: Any]) {
        guard let data = payload["snapshot"] as? Data,
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        DispatchQueue.main.async {
            self.snapshot = snap
            // Into the watch-side app group, where the complications read it.
            WatchStore.save(data)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        apply(context)
    }
}
