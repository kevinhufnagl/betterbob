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
        /// Today's target, for the strip's projected track.
        var target: TimeInterval = 0
        /// Next auto-break while working, if one is armed.
        var breakDue: Date?
        /// Projected clock-out. Fixed at update time, which stays correct
        /// between updates: while working, elapsed time and remaining work
        /// cancel out, and every state change pushes a fresh update.
        var doneBy: Date?
        /// Auto-break still owed today — the reason doneBy sits past the
        /// arithmetic remainder.
        var pendingBreak: TimeInterval = 0
        /// Today's timeline blocks for the day-strip miniature.
        var segments: [WidgetSnapshot.Segment] = []
    }
}
