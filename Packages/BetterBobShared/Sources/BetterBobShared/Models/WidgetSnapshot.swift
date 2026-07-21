import Foundation

/// The tiny cross-process snapshot the iOS widgets and Live Activity render
/// from — everything a separate process needs to show current state,
/// including a self-ticking timer anchor. Foundation-only so the Mac build
/// and tests compile it too.
public struct WidgetSnapshot: Codable, Equatable {
    public enum State: String, Codable {
        case working, onBreak, clockedOut, signedOut
    }

    /// One block of today's timeline — enough for a widget to draw the
    /// day-strip miniature without knowing the full entry model.
    public struct Segment: Codable, Equatable {
        public var start: Date
        public var end: Date?
        public var isBreak: Bool

        public init(start: Date, end: Date?, isBreak: Bool) {
            self.start = start
            self.end = end
            self.isBreak = isBreak
        }
    }

    public var state: State
    /// Start of the current uninterrupted work stretch — the live timer's anchor.
    public var stretchStart: Date?
    /// Worked seconds excluding the open stretch; the renderer adds the
    /// elapsed stretch on top while `state == .working`.
    public var workedBase: TimeInterval
    public var target: TimeInterval
    /// When the running auto-break ends, if one is running.
    public var breakEnds: Date?
    /// When the next auto-break is due while working, if one is armed.
    public var breakDue: Date?
    /// Today's timeline blocks, in order (open block has `end == nil`).
    public var segments: [Segment] = []
    public var updatedAt: Date

    // Extras the app fills in from engine state it alone knows. All optional
    // so a snapshot written by an older build still decodes.
    /// Length of the auto-break still owed today (nil/0 = none pending) —
    /// projections must add it to the remaining work.
    public var pendingBreak: TimeInterval?
    public var cycleWorkedMinutes: Int?
    public var cyclePotentialMinutes: Int?
    public var cycleBalanceMinutes: Int?
    public var holidayLeft: Double?
    public var holidayTotal: Double?
    public var holidayUnit: String?
    public var holidayName: String?
    public var nextTimeOffName: String?
    public var nextTimeOffStart: Date?
    /// Mon…Fri of the current week as worked/target fractions (0 for days
    /// not yet worked).
    public var weekFractions: [Double]?

    public init(state: State, stretchStart: Date?, workedBase: TimeInterval,
                target: TimeInterval, breakEnds: Date?, breakDue: Date? = nil,
                segments: [Segment] = [], updatedAt: Date) {
        self.state = state
        self.stretchStart = stretchStart
        self.workedBase = workedBase
        self.target = target
        self.breakEnds = breakEnds
        self.breakDue = breakDue
        self.segments = segments
        self.updatedAt = updatedAt
    }

    public func workedTotal(now: Date) -> TimeInterval {
        guard state == .working, let start = stretchStart else { return workedBase }
        return workedBase + max(0, now.timeIntervalSince(start))
    }

    /// When the target will be reached at the current pace — only meaningful
    /// while working and still short of the target. Includes the pending
    /// auto-break: a break still owed pushes the real clock-out later.
    public func doneBy(now: Date) -> Date? {
        guard state == .working else { return nil }
        let remaining = target - workedTotal(now: now)
        guard remaining > 0 else { return nil }
        return now.addingTimeInterval(remaining + (pendingBreak ?? 0))
    }
}
