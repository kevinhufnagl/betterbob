import Foundation

/// The internal web-API routes the HiBob single-page app calls, captured
/// from a live tenant (see Docs/endpoints.md). Unofficial, but verified
/// against a real HiBob account.
enum BobAPI {
    static let base = URL(string: "https://app.hibob.com")!

    static let currentUser = "api/user"
    /// Everything about today: entries, worked/break totals, next action.
    static let clockStatus = "api/attendance/my/clockStatus"
    /// Clock in/out and break start/end — one endpoint, four request bodies.
    static let punchClock = "api/attendance/my/punchClock"
    /// The tenant's metadata lists; reasons live under `timeLogEntryReason`.
    static let lists = "api/company/metadata/lists/?includeArchived=true"

    /// Timesheet cycles list (current cycle window + lock date).
    static func timesheets(_ employeeID: String) -> String {
        "api/attendance/employees/\(employeeID)/timesheets"
    }
    /// Per-cycle summary: daily worked/target breakdown + cycle totals.
    static func summary(_ employeeID: String, cycle: Int) -> String {
        "api/attendance/employees/\(employeeID)/timesheets/\(cycle)/summary"
    }
    /// Edit/clock history for one day (`yyyy-MM-dd`).
    static func history(_ employeeID: String, date: String) -> String {
        "api/attendance/employees/\(employeeID)/timesheets/\(date)/history"
    }
    /// The timesheet grid report — per-day entries for the whole cycle.
    static let viewsSearch = "api/company/views/search?idsOnly=false"

    // Time off
    static func timeOffBalances(_ id: String) -> String {
        "api/timeoff/employees/\(id)/balance/policies/summary-metrics"
    }
    static func timeOffPolicyConfig(_ id: String, from: String) -> String {
        "api/timeoff/employees/\(id)/timeoff/policy-request-configuration?from=\(from)"
    }
    static func timeOffRequestsInRange(_ id: String, from: String, to: String) -> String {
        "api/timeoff/employees/\(id)/requests/inRange?from=\(from)&to=\(to)"
    }
    static func timeOffCalculate(_ id: String) -> String {
        "api/timeoff/employees/\(id)/timeoff/requests/calculateTimeOff"
    }
    static func timeOffRequests(_ id: String) -> String {
        "api/timeoff/employees/\(id)/timeoff/requests"
    }
    static func timeOffCancel(_ id: String, request: String) -> String {
        "api/timeoff/employees/\(id)/requests/\(request)/cancels"
    }

    /// Edit a day's entries as a whole (used to set a reason, or to insert a
    /// retroactive break). `forDate` is `yyyy-MM-dd`.
    static func editEntries(_ employeeID: String, forDate: String) -> String {
        "api/attendance/employees/\(employeeID)/attendance/entries?forDate=\(forDate)"
    }
}

enum BobError: LocalizedError {
    case notSignedIn
    case sessionExpired
    case http(Int, path: String, message: String?)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in — open Settings and sign in to HiBob."
        case .sessionExpired:
            return "HiBob session expired — sign in again from Settings."
        case .http(let code, let path, let message):
            if let message { return "HiBob: \(message)" }
            return "HiBob returned HTTP \(code) for \(path)."
        case .badResponse(let what):
            return "HiBob response not understood (\(what)). The internal API may have changed — see Docs/endpoints.md."
        }
    }
}

/// URLSession client for HiBob's internal web API, authenticated with the
/// session cookies captured by the SSO sign-in. There is no programmatic
/// re-login (the tenant uses Okta), so an expired session surfaces as
/// `.sessionExpired` and the user re-signs-in through the browser.
final class BobClient {
    private let session: URLSession
    /// The employee's IANA timezone from /api/user (entry times are local).
    private(set) var timeZone: TimeZone = .current
    private var timeZoneName: String = TimeZone.current.identifier

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        cfg.timeoutIntervalForRequest = 20
        // Never serve a cached response — clockStatus is highly dynamic and a
        // stale hit would show us clocked out while HiBob says we're clocked in.
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        session = URLSession(configuration: cfg)
    }

    // MARK: - Identity

    struct User {
        var id: String
        var email: String?
        var name: String
        var role: String
        var site: String
    }

    /// Confirms the session is live and captures employee id + timezone + the
    /// profile fields shown in the dashboard header.
    func currentUser() async throws -> User {
        let data = try await get(BobAPI.currentUser)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = BobParsing.employeeID(fromUserJSON: data) else {
            throw BobError.badResponse("no employee id in /api/user")
        }
        if let tz = root["timezone"] as? String, let zone = TimeZone(identifier: tz) {
            timeZone = zone
            timeZoneName = tz
        }
        return User(id: id,
                    email: root["email"] as? String,
                    name: root["displayName"] as? String ?? "",
                    role: root["jobRoleDisplayName"] as? String ?? "",
                    site: root["site"] as? String ?? "")
    }

    // MARK: - Reads

    func fetchDayStatus() async throws -> DayStatus {
        let data = try await get(BobAPI.clockStatus)
        guard let status = BobParsing.dayStatus(fromClockStatusJSON: data, timeZone: timeZone) else {
            throw BobError.badResponse("clockStatus")
        }
        return status
    }

    func fetchReasonOptions() async throws -> [ReasonOption] {
        let data = try await get(BobAPI.lists)
        return BobParsing.reasonOptions(fromListsJSON: data)
    }

    /// Load the current cycle and its per-day summary for the dashboard.
    func fetchCycleSummary(employeeID: String) async throws -> (CycleInfo, CycleSummary)? {
        let tsData = try await get(BobAPI.timesheets(employeeID))
        guard let cycle = BobParsing.cycle(fromTimesheetsJSON: tsData) else { return nil }
        let sumData = try await get(BobAPI.summary(employeeID, cycle: cycle.id))
        guard let summary = BobParsing.summary(fromSummaryJSON: sumData) else { return nil }
        return (cycle, summary)
    }

    // MARK: - Time off

    func fetchTimeOffBalances(employeeID: String) async throws -> [TimeOffBalance] {
        BobParsing.timeOffBalances(fromSummaryJSON: try await get(BobAPI.timeOffBalances(employeeID)))
    }

    func fetchTimeOffPolicyTypes(employeeID: String) async throws -> [TimeOffPolicyType] {
        let from = dayString(Date())
        return BobParsing.timeOffPolicyTypes(
            fromConfigJSON: try await get(BobAPI.timeOffPolicyConfig(employeeID, from: from)))
    }

    func fetchTimeOffRequests(employeeID: String) async throws -> [TimeOffRequest] {
        let cal = Calendar.current
        let from = dayString(cal.date(byAdding: .month, value: -6, to: Date()) ?? Date())
        let to = dayString(cal.date(byAdding: .year, value: 1, to: Date()) ?? Date())
        return BobParsing.timeOffRequests(
            fromInRangeJSON: try await get(BobAPI.timeOffRequestsInRange(employeeID, from: from, to: to)))
    }

    /// Preview a request (day count, forecast, validity) before submitting.
    func calculateTimeOff(employeeID: String, body: [String: Any]) async throws -> TimeOffCalc? {
        BobParsing.timeOffCalc(fromJSON:
            try await post(BobAPI.timeOffCalculate(employeeID), json: body))
    }

    func submitTimeOff(employeeID: String, body: [String: Any]) async throws {
        _ = try await post(BobAPI.timeOffRequests(employeeID), json: body)
    }

    func cancelTimeOff(employeeID: String, request: String) async throws {
        _ = try await post(BobAPI.timeOffCancel(employeeID, request: request), json: [:])
    }

    private func dayString(_ date: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian); df.timeZone = timeZone
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    /// Every day's entries for the cycle (the monthly timesheet grid).
    func fetchMonthDays(employeeID: String, cycleId: Int,
                        reasonOptions: [ReasonOption]) async throws -> [DayEntries] {
        let body: [String: Any] = [
            "instructions": [["values": ["Active"], "operator": "text_equals",
                              "fieldPath": "/internal/status"]],
            "sortBy": "/root/displayName",
            "fields": ["/time_attendance_employee_timesheet/date",
                       "/time_attendance_employee_timesheet/entries",
                       "/time_attendance_employee_timesheet/hoursWorked"],
            "employeeId": employeeID,
            "timesheetId": cycleId,
            "type": "time_attendance_employee_timesheet",
        ]
        let data = try await post(BobAPI.viewsSearch, json: body)
        return BobParsing.monthDays(fromViewsSearchJSON: data,
                                    reasonOptions: reasonOptions, timeZone: timeZone)
    }

    /// Today's clock/edit history for the activity feed.
    func fetchActivity(employeeID: String, date: Date) async throws -> [ActivityEvent] {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian); df.timeZone = timeZone
        df.dateFormat = "yyyy-MM-dd"
        let data = try await get(BobAPI.history(employeeID, date: df.string(from: date)))
        return BobParsing.activity(fromHistoryJSON: data)
    }

    // MARK: - Actions

    func punch(_ action: PunchAction, employeeID: String) async throws {
        _ = try await post(BobAPI.punchClock, json: [
            "timeZone": timeZoneName,
            "clockAction": action.clockAction,
            "entryType": action.entryType,
            "employeeId": employeeID,
            "returnFromBreak": action.returnFromBreak,
        ])
    }

    /// Replace today's entry list — the write path for changing a reason or
    /// inserting a retroactive break. `entries` must be the *full* day.
    func writeEntries(_ entries: [[String: Any]], employeeID: String, forDate: Date) async throws {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.timeZone = timeZone
        df.dateFormat = "yyyy-MM-dd"
        _ = try await post(BobAPI.editEntries(employeeID, forDate: df.string(from: forDate)),
                           jsonArray: entries)
    }

    // MARK: - HTTP plumbing

    private func get(_ path: String) async throws -> Data {
        try await send("GET", path, body: nil)
    }

    private func post(_ path: String, json: [String: Any]) async throws -> Data {
        try await send("POST", path, body: try? JSONSerialization.data(withJSONObject: json))
    }

    private func post(_ path: String, jsonArray: [[String: Any]]) async throws -> Data {
        try await send("POST", path, body: try? JSONSerialization.data(withJSONObject: jsonArray))
    }

    private func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
        // Plain string join, not appendingPathComponent — several paths carry
        // a query string (?includeArchived, ?forDate) whose "?" that method
        // would percent-encode into the path and break the request.
        guard let url = URL(string: BobAPI.base.absoluteString + "/" + path) else {
            throw BobError.badResponse("bad URL for \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        // HiBob computes currentLocalTime / nextClockAction using this header —
        // the web app sends it. Without it the server falls back to UTC, so its
        // idea of "now" is off by the tz offset and it can report the wrong
        // punch state (e.g. clocked out reads as still working). Matches JS
        // getTimezoneOffset(): minutes to add to local to reach UTC (UTC+2 → -120).
        let offsetMinutes = -timeZone.secondsFromGMT(for: Date()) / 60
        request.setValue("\(offsetMinutes)", forHTTPHeaderField: "Bob-TimeZoneOffset")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BobError.badResponse("not HTTP")
        }

        // Expired Okta session: 401/403, or the login page's HTML served
        // where JSON was expected.
        let looksLikeHTML = data.first == UInt8(ascii: "<")
        if http.statusCode == 401 || http.statusCode == 403
            || (http.statusCode == 200 && looksLikeHTML) {
            throw BobError.sessionExpired
        }

        guard (200..<300).contains(http.statusCode) else {
            throw BobError.http(http.statusCode, path: path, message: errorMessage(from: data))
        }
        return data
    }

    /// HiBob returns `{"key":"...","error":"human message"}` on refusals
    /// (e.g. "requires at least 1 minute between clock actions").
    private func errorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root["error"] as? String ?? root["message"] as? String
    }
}
