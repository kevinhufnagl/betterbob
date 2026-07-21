import BetterBobShared
import ActivityKit
import Foundation

struct BobActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isOnBreak: Bool
        /// Timer anchor while working; break start while on a break.
        var stretchStart: Date
        var workedBase: TimeInterval
        var breakEnds: Date?
        /// Timer counts the whole day instead of the current stretch.
        var showsTotal: Bool = false
    }
}
