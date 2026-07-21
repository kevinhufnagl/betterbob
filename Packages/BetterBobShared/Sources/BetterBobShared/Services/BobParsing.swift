import Foundation

/// Decoding of HiBob's internal-API JSON, based on payloads captured from a
/// live tenant (see Docs/endpoints.md). The important source is
/// `GET /api/attendance/my/clockStatus`, whose entry times are **local
/// wall-clock with no timezone** — they're anchored using the employee's
/// timezone from `/api/user`.
public enum BobParsing {

    // MARK: - clockStatus

    public static func dayStatus(fromClockStatusJSON data: Data, timeZone: TimeZone) -> DayStatus? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var entries: [AttendanceEntry] = []
        for item in (root["entries"] as? [[String: Any]]) ?? [] {
            let typeString = (item["entryType"] as? String ?? "work").lowercased()
            let kind: AttendanceEntry.Kind = typeString.contains("break") ? .breakTime : .work
            guard let startRaw = item["start"] as? String,
                  let start = parseLocalTimestamp(startRaw, timeZone: timeZone)
            else { continue }
            let end = (item["end"] as? String).flatMap { parseLocalTimestamp($0, timeZone: timeZone) }
            entries.append(AttendanceEntry(
                kind: kind, start: start, end: end,
                id: stringValue(item["id"]),
                reason: item["reason"] as? String))
        }
        entries.sort { $0.start < $1.start }

        // `nextClockAction` is HiBob's authoritative punch state — it's exactly
        // what the web UI reflects — so we reconcile the entries to match it:
        //
        //  • Punched in ("out"/"switch") but nothing parsed as open → some
        //    responses return the in-progress entry with an `end` already filled
        //    in; reopen the latest entry of the current type.
        //  • Clocked out ("in") but an entry came back dangling-open → close it
        //    at currentLocalTime. This happens in the brief window right after a
        //    web clock-out, and without this the app shows a phantom ongoing
        //    period that can stick around until the next successful refresh.
        let nextAction = (root["nextClockAction"] as? String ?? "in").lowercased()
        if nextAction != "in", !entries.contains(where: { $0.end == nil }) {
            let wantBreak = (root["entryType"] as? String ?? "work").lowercased().contains("break")
            if let idx = entries.lastIndex(where: { ($0.kind == .breakTime) == wantBreak }) {
                entries[idx].end = nil
            }
        } else if nextAction == "in", entries.contains(where: { $0.end == nil }) {
            let closeAt = (root["currentLocalTime"] as? String)
                .flatMap { parseLocalTimestamp($0, timeZone: timeZone) }
            for idx in entries.indices where entries[idx].end == nil {
                entries[idx].end = max(entries[idx].start, closeAt ?? entries[idx].start)
            }
        }

        return DayStatus(
            entries: entries,
            minutesWorkedToday: intValue(root["minutesWorkedToday"]) ?? 0,
            breaksTotalMinutes: intValue(root["breaksTotalMinutes"]) ?? 0,
            nextClockAction: root["nextClockAction"] as? String ?? "in",
            currentEntryType: root["entryType"] as? String,
            disabled: root["disabled"] as? Bool ?? false,
            errorMessage: root["errorMessage"] as? String)
    }

    // MARK: - Reason options (metadata/lists → timeLogEntryReason)

    public static func reasonOptions(fromListsJSON data: Data) -> [ReasonOption] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["timeLogEntryReason"] as? [String: Any],
              let values = list["values"] as? [[String: Any]]
        else { return [] }
        return values.compactMap { v in
            guard let name = v["value"] as? String,
                  (v["archived"] as? Bool) != true
            else { return nil }
            return ReasonOption(id: stringValue(v["serverId"]), name: name)
        }
    }

    // MARK: - Timesheet cycle (dashboard)

    /// The current (first) timesheet cycle from the timesheets list.
    public static func cycle(fromTimesheetsJSON data: Data) -> CycleInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sheets = root["employeeTimesheets"] as? [[String: Any]],
              let first = sheets.first,
              let id = intValue(first["id"]),
              let start = first["cycleStartDate"] as? String,
              let end = first["cycleEndDate"] as? String
        else { return nil }
        let lockMs = (first["timesheetState"] as? [String: Any])
            .flatMap { intValue($0["lockAt"]) }
        return CycleInfo(id: id, start: start, end: end,
                         lockAt: lockMs.map { Date(timeIntervalSince1970: Double($0) / 1000) })
    }

    /// Per-day worked/target plus cycle totals from the summary endpoint.
    public static func summary(fromSummaryJSON data: Data) -> CycleSummary? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let breakdown = root["dailyBreakdown"] as? [String: Any],
              let categories = breakdown["categories"] as? [String],
              let graph = breakdown["graphData"] as? [[String: Any]]
        else { return nil }

        func series(_ id: String, _ key: String) -> [Double?] {
            guard let s = graph.first(where: { $0["id"] as? String == id }),
                  let points = s[key] as? [Any] else { return [] }
            return points.map { ($0 as? [String: Any]).flatMap { doubleValue($0["value"]) } }
        }
        let worked = series("hoursWorked", "data")
        let target = series("potentialHours", "target")

        // The per-day over/undertime series — exact daily values for the
        // balance trend (worked−target re-derivation drifts by rounding).
        let overtimes = series("overtime", "data")

        var days: [DayHours] = []
        for (i, date) in categories.enumerated() {
            days.append(DayHours(date: date,
                                 worked: i < worked.count ? (worked[i] ?? 0) : 0,
                                 target: i < target.count ? target[i] : nil,
                                 overtime: i < overtimes.count ? overtimes[i] : nil))
        }

        // Cycle totals live in a nested summary object; find by key anywhere.
        let overUnder = findDict(root, key: "overUnderTime")
        let sign = (overUnder?["sign"] as? String) == "-" ? -1 : 1
        let overUnderMin = sign * minutes(fromDisplay: overUnder?["hoursDisplay"] as? String ?? "0h 0m")

        // HiBob's whole-cycle "potential hours" total — the same number its
        // own web UI shows, preferred over summing per-day targets (which
        // drift by per-day rounding). Tolerant about the value's shape.
        // Captured shape: cycleSummary.potentialHours.summaryDisplay.
        let potentialMin: Int = {
            if let d = findDict(root, key: "potentialHours"),
               let disp = (d["summaryDisplay"] ?? d["hoursDisplay"] ?? d["display"]) as? String {
                return minutes(fromDisplay: disp)
            }
            if let disp = findString(root, key: "potentialHoursDisplay") {
                return minutes(fromDisplay: disp)
            }
            return 0
        }()

        return CycleSummary(
            days: days,
            potentialMinutes: potentialMin,
            overUnderMinutes: overUnderMin,
            payableTimePercent: findInt(root, key: "payableTimePercentage") ?? 0,
            // "hoursWorkedDisplay" is the cycle's worked total; the older
            // "totalHoursDisplay" probe hit the payable-hours breakdown.
            totalHoursDisplay: findString(root, key: "hoursWorkedDisplay")
                ?? findString(root, key: "totalHoursDisplay") ?? "—",
            breakViolations: findInt(root, key: "breakViolationCounter") ?? 0)
    }

    /// Parse HiBob "Xh Ym" duration displays into minutes.
    public static func minutes(fromDisplay s: String) -> Int {
        var h = 0, m = 0
        for token in s.split(separator: " ") {
            if token.hasSuffix("h") { h = Int(token.dropLast()) ?? 0 }
            if token.hasSuffix("m") { m = Int(token.dropLast()) ?? 0 }
        }
        return h * 60 + m
    }

    // MARK: - Month day entries (views/search timesheet grid)

    /// Per-day entries for the whole cycle. Reason is a serverId here, mapped
    /// back to its display name via the reason options.
    public static func monthDays(fromViewsSearchJSON data: Data,
                          reasonOptions: [ReasonOption],
                          timeZone: TimeZone) -> [DayEntries] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["employees"] as? [[String: Any]] else { return [] }
        var idToName: [String: String] = [:]
        for r in reasonOptions { if let id = r.id { idToName[id] = r.name } }

        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian); df.timeZone = timeZone
        df.dateFormat = "yyyy-MM-dd"

        var out: [DayEntries] = []
        for row in rows {
            guard let ts = row["time_attendance_employee_timesheet"] as? [String: Any] else { continue }
            // Skip week-group header rows ("Week 13/07/2026 - 19/07/2026"): they
            // carry no entries and their first date is the week's Monday, which
            // would collide with — and shadow — the real Monday row.
            let display = ((ts["date"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            if display.lowercased().hasPrefix("week") { continue }
            let rawEntries = (ts["entries"] as? [[String: Any]]) ?? []
            var entries: [AttendanceEntry] = []
            for item in rawEntries {
                let typeString = (item["entryType"] as? String ?? "work").lowercased()
                guard let startRaw = item["start"] as? String,
                      let start = parseLocalTimestamp(startRaw, timeZone: timeZone) else { continue }
                let end = (item["end"] as? String).flatMap { parseLocalTimestamp($0, timeZone: timeZone) }
                let reasonID = stringValue(item["reason"])
                entries.append(AttendanceEntry(
                    kind: typeString.contains("break") ? .breakTime : .work,
                    start: start, end: end,
                    id: stringValue(item["id"]),
                    reason: reasonID.flatMap { idToName[$0] }))
            }
            // Day key from the first entry's date, else the display "dd/MM/yyyy".
            let key: String?
            if let first = entries.first {
                key = df.string(from: first.start)
            } else {
                key = dayKey(fromDisplay: ts["date"] as? String, formatter: df, timeZone: timeZone)
            }
            guard let dateKey = key, let date = df.date(from: dateKey) else { continue }
            out.append(DayEntries(date: date, dateKey: dateKey, entries: entries.sorted { $0.start < $1.start }))
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Extract "dd/MM/yyyy" from a display string like "Thu, 16/07/2026 (Today)".
    private static func dayKey(fromDisplay s: String?, formatter df: DateFormatter, timeZone: TimeZone) -> String? {
        guard let s, let m = s.range(of: #"\d{2}/\d{2}/\d{4}"#, options: .regularExpression) else { return nil }
        let parts = s[m].split(separator: "/")
        guard parts.count == 3 else { return nil }
        return "\(parts[2])-\(parts[1])-\(parts[0])"
    }

    // MARK: - Activity history

    public static func activity(fromHistoryJSON data: Data) -> [ActivityEvent] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }
        return events.compactMap { ev in
            guard let type = ev["type"] as? String,
                  let ms = intValue(ev["timestamp"]) else { return nil }
            let kind: ActivityEvent.Kind
            switch type {
            case "clockedIn": kind = .clockedIn
            case "clockedOut": kind = .clockedOut
            case "addedBreak": kind = .addedBreak
            case "editedEntries", "editedWorkEntry", "editedBreak": kind = .edited
            default: kind = .other
            }
            let d = ev["details"] as? [String: Any] ?? [:]
            var parts: [String] = []
            if let ci = d["clockIn"] as? String { parts.append(ci) }
            if let co = d["clockOut"] as? String { parts.append("→ \(co)") }
            if let dur = d["entryDuration"] as? String { parts.append("· \(dur)") }
            if let reason = d["reason"] as? String { parts.append("· \(reason)") }
            let actor = (ev["actor"] as? [String: Any])?["displayName"] as? String ?? ""
            return ActivityEvent(kind: kind,
                                 timestamp: Date(timeIntervalSince1970: Double(ms) / 1000),
                                 detail: parts.joined(separator: " "),
                                 actor: actor)
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Time off

    public static func timeOffBalances(fromSummaryJSON data: Data) -> [TimeOffBalance] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = root["summary"] as? [[String: Any]] else { return [] }
        return summary.compactMap { s in
            guard let type = s["type"] as? String else { return nil }
            let metrics = s["metrics"] as? [[String: Any]] ?? []
            func metric(_ title: String) -> String? {
                metrics.first { ($0["title"] as? String) == title }?["value"] as? String
            }
            return TimeOffBalance(
                type: type,
                displayName: s["policyTypeDisplayName"] as? String ?? type,
                unit: s["unit"] as? String ?? "days",
                currentBalance: stringValue(s["currentBalance"]) ?? "—",
                totalAllowance: stringValue(s["totalAllowance"]) ?? "—",
                cycleRange: s["cycleRange"] as? String ?? "",
                daysTaken: metric("Days taken"),
                prevBalance: metric("Prev. balance"),
                annualAllowance: metric("Annual allowance"))
        }
    }

    public static func timeOffPolicyTypes(fromConfigJSON data: Data) -> [TimeOffPolicyType] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let policies = root["policies"] as? [[String: Any]] else { return [] }
        return policies.compactMap { p in
            guard let type = p["type"] as? String, (p["inactive"] as? Bool) != true else { return nil }
            return TimeOffPolicyType(
                id: stringValue(p["id"]) ?? type,
                type: type,
                displayName: p["displayName"] as? String ?? type,
                unit: p["unit"] as? String ?? "days",
                emoji: (p["info"] as? [String: Any])?["emoji"] as? String)
        }
    }

    public static func timeOffRequests(fromInRangeJSON data: Data) -> [TimeOffRequest] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let lists = ["requests", "openRequests"].compactMap { root[$0] as? [[String: Any]] }
        return lists.flatMap { $0 }.compactMap { r in
            guard let id = stringValue(r["id"]) else { return nil }
            return TimeOffRequest(
                id: id,
                typeName: (r["policyTypeDisplayName"] as? String) ?? (r["policyType"] as? String)
                    ?? (r["type"] as? String) ?? "Time off",
                startDate: r["startDate"] as? String ?? "",
                endDate: r["endDate"] as? String ?? "",
                status: (r["status"] as? String) ?? (r["requestStatus"] as? String) ?? "pending",
                amount: stringValue(r["amount"]) ?? stringValue(r["totalDuration"]) ?? "")
        }
    }

    public static func timeOffCalc(fromJSON data: Data) -> TimeOffCalc? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // validationMessages: {"level":"ERROR","messages":[{"reason":"…"}]}
        var validation: String?
        if let vm = root["validationMessages"] as? [String: Any] {
            if let msgs = vm["messages"] as? [[String: Any]] {
                validation = msgs.compactMap { $0["reason"] as? String }.joined(separator: " ")
                if validation?.isEmpty == true { validation = nil }
            }
        }
        return TimeOffCalc(
            amount: doubleValue(root["amount"]) ?? 0,
            submittable: root["submittable"] as? Bool ?? false,
            requestMessage: root["requestMessage"] as? String ?? "",
            forecast: root["forecastMessage"] as? String ?? root["forecastedRemainingBalance"] as? String ?? "",
            validation: validation,
            rejectReason: root["rejectReason"] as? String,
            requiredFields: (root["additionalRequiredFields"] as? [String]) ?? [])
    }

    // MARK: - Employee id (/api/user)

    public static func employeeID(fromUserJSON data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return stringValue(root["id"])
    }

    // MARK: - Timestamps

    /// Parse a HiBob local wall-clock timestamp — `YYYY-MM-DDTHH:mm`, with
    /// optional `:ss` and optional fractional seconds, and no timezone —
    /// interpreting it in `timeZone`.
    public static func parseLocalTimestamp(_ raw: String, timeZone: TimeZone) -> Date? {
        let trimmed = raw.split(separator: ".").first.map(String.init) ?? raw
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let dateAndTime = trimmed.split(separator: "T")
        guard dateAndTime.count == 2 else { return nil }
        let dateParts = dateAndTime[0].split(separator: "-").compactMap { Int($0) }
        let timeParts = dateAndTime[1].split(separator: ":").compactMap { Int($0) }
        guard dateParts.count == 3, timeParts.count >= 2 else { return nil }

        var c = DateComponents()
        c.year = dateParts[0]; c.month = dateParts[1]; c.day = dateParts[2]
        c.hour = timeParts[0]; c.minute = timeParts[1]
        c.second = timeParts.count >= 3 ? timeParts[2] : 0
        return calendar.date(from: c)
    }

    // MARK: - Helpers

    private static func stringValue(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    /// Depth-first search for the first value under `key` anywhere in the
    /// tree — the summary nests its totals a few objects deep and the exact
    /// path isn't guaranteed stable.
    private static func findValue(_ any: Any, key: String) -> Any? {
        if let dict = any as? [String: Any] {
            if let v = dict[key] { return v }
            for v in dict.values {
                if let found = findValue(v, key: key) { return found }
            }
        } else if let arr = any as? [Any] {
            for v in arr {
                if let found = findValue(v, key: key) { return found }
            }
        }
        return nil
    }
    private static func findDict(_ any: Any, key: String) -> [String: Any]? {
        findValue(any, key: key) as? [String: Any]
    }
    private static func findInt(_ any: Any, key: String) -> Int? {
        intValue(findValue(any, key: key))
    }
    private static func findString(_ any: Any, key: String) -> String? {
        findValue(any, key: key) as? String
    }
    private static func findDouble(_ any: Any, key: String) -> Double? {
        doubleValue(findValue(any, key: key))
    }
}
