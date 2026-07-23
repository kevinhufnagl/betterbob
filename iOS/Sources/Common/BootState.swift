import BetterBobShared
import Foundation

extension BobState {
    /// True while the app boots with a stored session and the first reconcile
    /// hasn't landed — the window where screens should show the loading Bob
    /// instead of flashing a signed-out or zeroed-out state. Both terms
    /// self-terminate: a reconcile flips `ready`, a session probe ends in
    /// `signedIn` or `lastError`.
    ///
    /// Keys off `connecting` (the launch probe actually running), NOT the
    /// persistent `usedSSO` preference: a stored SSO flag whose session never
    /// established would otherwise hold the loader on screen forever, masking
    /// the sign-in card with no way through. `connecting` always resolves.
    var bootingUp: Bool {
        !ready && lastError == nil && (signedIn || connecting)
    }
}
