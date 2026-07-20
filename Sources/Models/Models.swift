import Foundation

/// One attendance period from HiBob — either work or a break. `end == nil`
/// means the period is still open (currently clocked in / on break).
struct AttendanceEntry: Equatable {
    enum Kind: Equatable {
        case work
        case breakTime

        /// Simple, consistent glyph used everywhere for this entry type.
        var icon: String { self == .breakTime ? "pause.circle.fill" : "circle.fill" }
        var label: String { self == .breakTime ? "Break" : "Work" }
    }

    var kind: Kind
    var start: Date
    var end: Date?
    /// Server-side entry id — needed to edit this one entry (e.g. its reason).
    var id: String? = nil
    /// The entry's "Reason" (In Office, Work From Home, …), if the tenant uses them.
    var reason: String? = nil
}

/// A "when on this Wi-Fi network, use this reason" rule.
struct WiFiRule: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var ssid: String = ""
    var reasonName: String = ""
}

/// One choice from the tenant-defined "Reason" dropdown. `id` is HiBob's
/// `serverId` — required when writing a reason back (the write API takes the
/// id, though `clockStatus` reads reasons back by display name).
struct ReasonOption: Equatable, Hashable {
    var id: String? = nil
    var name: String
}

/// The full attendance picture for today, straight from
/// `GET /api/attendance/my/clockStatus`. HiBob hands us worked/break totals
/// and the next legal action directly, so we don't recompute what it already
/// tells us — the engine only adds the auto-break decision on top.
struct DayStatus: Equatable {
    var entries: [AttendanceEntry]
    var minutesWorkedToday: Int
    var breaksTotalMinutes: Int
    /// "in" (clocked out), "out" (working), or "switch" (toggle work/break).
    var nextClockAction: String
    /// Type of the currently open entry, if any ("work" / "break").
    var currentEntryType: String?
    /// HiBob has flagged the next action as unavailable (e.g. the day's
    /// entries are in an inconsistent state)…
    var disabled: Bool = false
    /// …with this human-readable reason, if any.
    var errorMessage: String? = nil
}

/// A single punch against `POST /api/attendance/my/punchClock`. The four
/// cases map to the exact request bodies the HiBob web app sends.
enum PunchAction: Equatable {
    case clockIn
    case clockOut
    case startBreak
    case endBreak

    /// `clockAction` field.
    var clockAction: String {
        switch self {
        case .clockIn: return "in"
        case .clockOut: return "out"
        case .startBreak, .endBreak: return "switch"
        }
    }
    /// `entryType` field — the type being switched *into*.
    var entryType: String {
        self == .startBreak ? "break" : "work"
    }
    /// `returnFromBreak` field — true only when ending a break.
    var returnFromBreak: Bool { self == .endBreak }

    var label: String {
        switch self {
        case .clockIn: return "Clock in"
        case .clockOut: return "Clock out"
        case .startBreak: return "Start break"
        case .endBreak: return "End break"
        }
    }
    var symbol: String {
        switch self {
        case .clockIn, .endBreak: return "play.fill"
        case .clockOut: return "stop.fill"
        case .startBreak: return "pause.circle.fill"
        }
    }

    /// The clock state you'd be in after this action — used to project the
    /// state after a queue of pending punches.
    func applied(to state: ClockState, at time: Date) -> ClockState {
        switch self {
        case .clockIn: return .working(since: time)
        case .clockOut: return .clockedOut
        case .startBreak: return .onBreak(since: time)
        case .endBreak: return .working(since: time)
        }
    }
}

/// A punch waiting in the action queue (HiBob requires ≥1 min between punches).
struct QueuedPunch: Identifiable, Equatable {
    let id = UUID()
    let action: PunchAction
    var fireAt: Date
}

/// The user's current punch state, derived from today's entries.
enum ClockState: Equatable {
    case clockedOut
    /// `since` is the start of the current *uninterrupted* work stretch —
    /// the later of the open work period's start and the last break's end.
    case working(since: Date)
    case onBreak(since: Date)
}

/// What the engine should do right now to enforce the auto-break rule. Breaks
/// are always placed at the exact moment they were due (the max mark), never at
/// "now" — so opening the app late still records the break at the right time.
enum AutoBreakAction: Equatable {
    /// Put a break starting at `start`. `end == nil` means it's still ongoing
    /// (opened the app mid-window); a date means the whole window already passed.
    case insertBreak(start: Date, end: Date?)
    /// Close the open auto-break at `at` (its due end) and resume work.
    case endBreak(at: Date)
}

// MARK: - Dashboard (timesheet cycle) models

/// The current timesheet cycle window + its lock/submission deadline, from
/// `GET /api/attendance/employees/{id}/timesheets`.
struct CycleInfo: Equatable {
    var id: Int
    var start: String   // "yyyy-MM-dd"
    var end: String
    var lockAt: Date?
}

/// One day's worked vs target hours (decimal hours), from the summary's
/// daily breakdown.
struct DayHours: Equatable, Hashable {
    var date: String    // "yyyy-MM-dd"
    var worked: Double
    var target: Double?
    /// HiBob's own signed over/undertime for the day, in hours — exact where
    /// worked−target drifts by rounding. Nil for unfinished days.
    var overtime: Double?
}

/// One day's full attendance entries (from the monthly timesheet grid),
/// used for the by-day list and editing past days.
struct DayEntries: Identifiable, Equatable {
    var id: String { dateKey }
    var date: Date
    var dateKey: String     // "yyyy-MM-dd"
    var entries: [AttendanceEntry]
}

/// Aggregated figures for the whole cycle, from
/// `GET .../timesheets/{id}/summary`.
struct CycleSummary: Equatable {
    var days: [DayHours]
    /// HiBob's own "potential hours" for the whole cycle, in minutes
    /// (0 = the payload didn't carry it). More authoritative than summing
    /// the per-day targets, which can drift by rounding.
    var potentialMinutes: Int = 0
    /// Signed over/undertime for the cycle so far, in minutes (negative =
    /// behind) — HiBob's "running cycle balance".
    var overUnderMinutes: Int
    /// Percent of the cycle's potential hours already worked.
    var payableTimePercent: Int
    /// HiBob's own total-hours display string, e.g. "87h 30m".
    var totalHoursDisplay: String
    /// Count of break-policy violations HiBob flagged this cycle.
    var breakViolations: Int
}

/// One entry from the day's edit history (`.../timesheets/{date}/history`),
/// flattened into a human-readable feed item.
struct ActivityEvent: Equatable {
    enum Kind: Equatable {
        case clockedIn, clockedOut, addedBreak, edited, other
    }
    var kind: Kind
    var timestamp: Date
    var detail: String       // e.g. "09:22 → 15:20 · 5h 57m · In Office"
    var actor: String
}

// MARK: - Time off

/// A leave balance for one policy (e.g. Holidays: 45 of 25).
struct TimeOffBalance: Equatable, Identifiable {
    var id: String { type }
    var type: String
    var displayName: String
    var unit: String            // "days" / "hours"
    var currentBalance: String
    var totalAllowance: String
    var cycleRange: String
    var daysTaken: String?
    /// Carryover into this cycle ("Prev. balance" metric), e.g. "+26".
    var prevBalance: String?
    /// This cycle's grant ("Annual allowance" metric), e.g. "+25".
    var annualAllowance: String?
}

/// A bookable leave type for the request picker.
struct TimeOffPolicyType: Equatable, Identifiable, Hashable {
    var id: String              // numeric policy id (string)
    var type: String            // internal code (e.g. "type292"); matches balances
    var displayName: String
    var unit: String
    var emoji: String?
    /// The value the calculate/submit API expects in `policyType` — this is
    /// the display name, not the `type` code (verified against a live request).
    var requestValue: String { displayName }
}

/// One existing time-off request.
struct TimeOffRequest: Equatable, Identifiable {
    var id: String
    var typeName: String
    var startDate: String
    var endDate: String
    var status: String
    var amount: String
}

/// Result of the calculate-preview call before submitting a request.
struct TimeOffCalc: Equatable {
    var amount: Double
    var submittable: Bool
    var requestMessage: String
    var forecast: String
    var validation: String?
    /// HiBob's reason a request can't be submitted (e.g. max 1 day), if any.
    var rejectReason: String?
    /// Fields HiBob needs that BetterBob can't supply (e.g. "attachments",
    /// "reasonCode") — such requests must be made in the HiBob web app.
    var requiredFields: [String] = []
}

// MARK: - Formatting

enum Fmt {
    /// "6h 12m" / "8h" / "42m" duration formatting for the popover — whole hours
    /// drop the "0m".
    static func hm(_ interval: TimeInterval) -> String {
        let mins = max(0, Int(interval / 60))
        let h = mins / 60, m = mins % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}
