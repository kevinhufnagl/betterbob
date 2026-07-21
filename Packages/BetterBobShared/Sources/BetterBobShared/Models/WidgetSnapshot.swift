import Foundation

/// The tiny cross-process snapshot the iOS widgets and Live Activity render
/// from — everything a separate process needs to show current state,
/// including a self-ticking timer anchor. Foundation-only so the Mac build
/// and tests compile it too.
struct WidgetSnapshot: Codable, Equatable {
    enum State: String, Codable {
        case working, onBreak, clockedOut, signedOut
    }

    var state: State
    /// Start of the current uninterrupted work stretch — the live timer's anchor.
    var stretchStart: Date?
    /// Worked seconds excluding the open stretch; the renderer adds the
    /// elapsed stretch on top while `state == .working`.
    var workedBase: TimeInterval
    var target: TimeInterval
    /// When the running auto-break ends, if one is running.
    var breakEnds: Date?
    var updatedAt: Date

    func workedTotal(now: Date) -> TimeInterval {
        guard state == .working, let start = stretchStart else { return workedBase }
        return workedBase + max(0, now.timeIntervalSince(start))
    }
}
