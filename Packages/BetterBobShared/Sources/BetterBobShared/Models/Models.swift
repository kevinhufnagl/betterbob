import Foundation

/// One attendance period from HiBob — either work or a break. `end == nil`
/// means the period is still open (currently clocked in / on break).
public struct AttendanceEntry: Equatable {
    public enum Kind: Equatable {
        case work
        case breakTime

        /// Simple, consistent glyph used everywhere for this entry type.
        var icon: String { self == .breakTime ? "pause.circle.fill" : "circle.fill" }
        var label: String { self == .breakTime ? "Break" : "Work" }
    }

    public var kind: Kind
    public var start: Date
    public var end: Date?
    /// Server-side entry id — needed to edit this one entry (e.g. its reason).
    public var id: String? = nil
    /// The entry's "Reason" (In Office, Work From Home, …), if the tenant uses them.
    public var reason: String? = nil
}

/// A "when on this Wi-Fi network, use this reason" rule.
public struct WiFiRule: Codable, Equatable, Identifiable, Hashable {
    public var id = UUID()
    public var ssid: String = ""
    public var reasonName: String = ""
}

/// One choice from the tenant-defined "Reason" dropdown. `id` is HiBob's
/// `serverId` — required when writing a reason back (the write API takes the
/// id, though `clockStatus` reads reasons back by display name).
public struct ReasonOption: Equatable, Hashable {
    public var id: String? = nil
    public var name: String
}

/// The full attendance picture for today, straight from
/// `GET /api/attendance/my/clockStatus`. HiBob hands us worked/break totals
/// and the next legal action directly, so we don't recompute what it already
/// tells us — the engine only adds the auto-break decision on top.
public struct DayStatus: Equatable {
    public var entries: [AttendanceEntry]
    public var minutesWorkedToday: Int
    public var breaksTotalMinutes: Int
    /// "in" (clocked out), "out" (working), or "switch" (toggle work/break).
    public var nextClockAction: String
    /// Type of the currently open entry, if any ("work" / "break").
    public var currentEntryType: String?
    /// HiBob has flagged the next action as unavailable (e.g. the day's
    /// entries are in an inconsistent state)…
    public var disabled: Bool = false
    /// …with this human-readable reason, if any.
    public var errorMessage: String? = nil
}

/// A single punch against `POST /api/attendance/my/punchClock`. The four
/// cases map to the exact request bodies the HiBob web app sends.
public enum PunchAction: Equatable {
    case clockIn
    case clockOut
    case startBreak
    case endBreak

    /// `clockAction` field.
    public var clockAction: String {
        switch self {
        case .clockIn: return "in"
        case .clockOut: return "out"
        case .startBreak, .endBreak: return "switch"
        }
    }
    /// `entryType` field — the type being switched *into*.
    public var entryType: String {
        self == .startBreak ? "break" : "work"
    }
    /// `returnFromBreak` field — true only when ending a break.
    public var returnFromBreak: Bool { self == .endBreak }

    public var label: String {
        switch self {
        case .clockIn: return "Clock in"
        case .clockOut: return "Clock out"
        case .startBreak: return "Start break"
        case .endBreak: return "End break"
        }
    }
    public var symbol: String {
        switch self {
        case .clockIn, .endBreak: return "play.fill"
        case .clockOut: return "stop.fill"
        case .startBreak: return "pause.circle.fill"
        }
    }

    /// The clock state you'd be in after this action — used to project the
    /// state after a queue of pending punches.
    public func applied(to state: ClockState, at time: Date) -> ClockState {
        switch self {
        case .clockIn: return .working(since: time)
        case .clockOut: return .clockedOut
        case .startBreak: return .onBreak(since: time)
        case .endBreak: return .working(since: time)
        }
    }
}

/// A punch waiting in the action queue (HiBob requires ≥1 min between punches).
public struct QueuedPunch: Identifiable, Equatable {
    public let id = UUID()
    public let action: PunchAction
    public var fireAt: Date
}

/// The user's current punch state, derived from today's entries.
public enum ClockState: Equatable {
    case clockedOut
    /// `since` is the start of the current *uninterrupted* work stretch —
    /// the later of the open work period's start and the last break's end.
    case working(since: Date)
    case onBreak(since: Date)
}

/// What the engine should do right now to enforce the auto-break rule. Breaks
/// are always placed at the exact moment they were due (the max mark), never at
/// "now" — so opening the app late still records the break at the right time.
public enum AutoBreakAction: Equatable {
    /// Put a break starting at `start`. `end == nil` means it's still ongoing
    /// (opened the app mid-window); a date means the whole window already passed.
    case insertBreak(start: Date, end: Date?)
    /// Close the open auto-break at `at` (its due end) and resume work.
    case endBreak(at: Date)
}

// MARK: - Dashboard (timesheet cycle) models

/// The current timesheet cycle window + its lock/submission deadline, from
/// `GET /api/attendance/employees/{id}/timesheets`.
public struct CycleInfo: Equatable {
    public var id: Int
    public var start: String   // "yyyy-MM-dd"
    public var end: String
    public var lockAt: Date?
}

/// One day's worked vs target hours (decimal hours), from the summary's
/// daily breakdown.
public struct DayHours: Equatable, Hashable {
    public var date: String    // "yyyy-MM-dd"
    public var worked: Double
    public var target: Double?
    /// HiBob's own signed over/undertime for the day, in hours — exact where
    /// worked−target drifts by rounding. Nil for unfinished days.
    public var overtime: Double?
}

/// A tiny, durable record of one worked day's shape — first check-in and last
/// check-out as seconds since local midnight. Persisted across cycles (HiBob
/// only serves the current sheet) so the weekly-rhythm chart and the smart
/// end-time guess keep working after the month rolls over.
public struct DayFact: Codable, Equatable {
    public var date: String     // "yyyy-MM-dd"
    public var inSec: Int
    public var outSec: Int
    public init(date: String, inSec: Int, outSec: Int) {
        self.date = date; self.inSec = inSec; self.outSec = outSec
    }
}

/// One day's full attendance entries (from the monthly timesheet grid),
/// used for the by-day list and editing past days.
public struct DayEntries: Identifiable, Equatable {
    public var id: String { dateKey }
    public var date: Date
    public var dateKey: String     // "yyyy-MM-dd"
    public var entries: [AttendanceEntry]
}

/// Aggregated figures for the whole cycle, from
/// `GET .../timesheets/{id}/summary`.
public struct CycleSummary: Equatable {
    public var days: [DayHours]
    /// HiBob's own "potential hours" for the whole cycle, in minutes
    /// (0 = the payload didn't carry it). More authoritative than summing
    /// the per-day targets, which can drift by rounding.
    public var potentialMinutes: Int = 0
    /// Signed over/undertime for the cycle so far, in minutes (negative =
    /// behind) — HiBob's "running cycle balance".
    public var overUnderMinutes: Int
    /// Percent of the cycle's potential hours already worked.
    public var payableTimePercent: Int
    /// HiBob's own total-hours display string, e.g. "87h 30m".
    public var totalHoursDisplay: String
    /// Count of break-policy violations HiBob flagged this cycle.
    public var breakViolations: Int
}

/// One entry from the day's edit history (`.../timesheets/{date}/history`),
/// flattened into a human-readable feed item.
public struct ActivityEvent: Equatable {
    public enum Kind: Equatable {
        case clockedIn, clockedOut, addedBreak, edited, other
    }
    public var kind: Kind
    public var timestamp: Date
    public var detail: String       // e.g. "09:22 → 15:20 · 5h 57m · In Office"
    public var actor: String
}

// MARK: - Time off

/// A leave balance for one policy (e.g. Holidays: 45 of 25).
public struct TimeOffBalance: Equatable, Identifiable {
    public var id: String { type }
    public var type: String
    public var displayName: String
    public var unit: String            // "days" / "hours"
    public var currentBalance: String
    public var totalAllowance: String
    public var cycleRange: String
    public var daysTaken: String?
    /// Carryover into this cycle ("Prev. balance" metric), e.g. "+26".
    public var prevBalance: String?
    /// This cycle's grant ("Annual allowance" metric), e.g. "+25".
    public var annualAllowance: String?
}

/// A bookable leave type for the request picker.
public struct TimeOffPolicyType: Equatable, Identifiable, Hashable {
    public var id: String              // numeric policy id (string)
    var type: String            // internal code (e.g. "type292"); matches balances
    public var displayName: String
    public var unit: String
    public var emoji: String?
    /// The value the calculate/submit API expects in `policyType` — this is
    /// the display name, not the `type` code (verified against a live request).
    public var requestValue: String { displayName }
}

/// One existing time-off request.
public struct TimeOffRequest: Equatable, Identifiable {
    public var id: String
    public var typeName: String
    public var startDate: String
    public var endDate: String
    public var status: String
    public var amount: String
}

/// Result of the calculate-preview call before submitting a request.
public struct TimeOffCalc: Equatable {
    public var amount: Double
    public var submittable: Bool
    public var requestMessage: String
    public var forecast: String
    public var validation: String?
    /// HiBob's reason a request can't be submitted (e.g. max 1 day), if any.
    public var rejectReason: String?
    /// Fields HiBob needs that BetterBob can't supply (e.g. "attachments",
    /// "reasonCode") — such requests must be made in the HiBob web app.
    public var requiredFields: [String] = []
}

// MARK: - Formatting

public enum Fmt {
    /// "6h 12m" / "8h" / "42m" duration formatting for the popover — whole hours
    /// drop the "0m".
    public static func hm(_ interval: TimeInterval) -> String {
        let mins = max(0, Int(interval / 60))
        let h = mins / 60, m = mins % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    public static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// Parse hand-typed clock text into (hour, minute) — tolerant of the ways
    /// people actually type times: "9" → 9:00, "09" → 9:00, "930" / "0930" →
    /// 9:30, "9:5" → 9:05, "14.30" → 14:30, and a trailing am/pm. nil when it
    /// doesn't read as a time of day.
    public static func parseClock(_ s: String) -> (hour: Int, minute: Int)? {
        var text = s.trimmingCharacters(in: .whitespaces).lowercased()
        var pmShift = 0
        if text.hasSuffix("pm") || text.hasSuffix("am") {
            let isPM = text.hasSuffix("pm")
            text = String(text.dropLast(2)).trimmingCharacters(in: .whitespaces)
            pmShift = isPM ? 12 : -12   // applied only to 1–11 below
        }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: ".", omittingEmptySubsequences: false) }
        guard !parts.isEmpty, parts.count <= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else { return nil }
        var h: Int, m: Int
        if parts.count == 2 {
            guard parts[0].count <= 2, parts[1].count <= 2,
                  let hh = Int(parts[0]), let mm = Int(parts[1]) else { return nil }
            h = hh; m = mm
        } else {
            let digits = parts[0]
            switch digits.count {
            case 1, 2: h = Int(digits)!; m = 0
            case 3:    h = Int(digits.prefix(1))!; m = Int(digits.suffix(2))!
            case 4:    h = Int(digits.prefix(2))!; m = Int(digits.suffix(2))!
            default:   return nil
            }
        }
        if pmShift == 12, (1...11).contains(h) { h += 12 }        // 2pm → 14
        if pmShift == -12, h == 12 { h = 0 }                       // 12am → 0
        guard (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }
}
