import BetterBobShared
import Foundation

extension BobState {
    /// True while the app boots with a stored session and the first reconcile
    /// hasn't landed — the window where screens should show the loading Bob
    /// instead of flashing a signed-out or zeroed-out state. Both terms
    /// self-terminate: a reconcile flips `ready`, a session probe ends in
    /// `signedIn` or `lastError`. Stored credentials alone must NOT count —
    /// nothing probes for a signed-out user, so that state never resolves
    /// and the placeholder would trap the sign-in buttons forever.
    var bootingUp: Bool {
        !ready && lastError == nil && (signedIn || usedSSO)
    }
}
