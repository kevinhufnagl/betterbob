import BetterBobShared
import Foundation

extension BobState {
    /// True while the app boots with a stored session and the first reconcile
    /// hasn't landed — the window where screens should show the loading Bob
    /// instead of flashing a signed-out or zeroed-out state. Resolves either
    /// way: success flips `ready`, a failed probe sets `lastError`.
    var bootingUp: Bool {
        !ready && lastError == nil && (signedIn || usedSSO || canAutoSignIn)
    }
}
