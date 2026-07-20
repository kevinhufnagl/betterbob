// Unit tests — exercises the pure attendance math and HiBob JSON parsing
// the engine depends on. Run via Scripts/test.sh.
import Foundation

var failures = 0

func expect(_ condition: Bool, _ label: String) {
    if condition {
        print("  ok   \(label)")
    } else {
        print("  FAIL \(label)")
        failures += 1
    }
}

// A fixed day anchor; tests express times as hours from this midnight.
// 1_784_160_000 == 2026-07-16T00:00:00Z.
let day = Date(timeIntervalSince1970: 1_784_160_000)
func t(_ hours: Double) -> Date { day.addingTimeInterval(hours * 3600) }
let utc = TimeZone(identifier: "UTC")!

func work(_ from: Double, _ to: Double?) -> AttendanceEntry {
    AttendanceEntry(kind: .work, start: t(from), end: to.map(t))
}
func brk(_ from: Double, _ to: Double?) -> AttendanceEntry {
    AttendanceEntry(kind: .breakTime, start: t(from), end: to.map(t))
}

let sixH: TimeInterval = 6 * 3600
let halfH: TimeInterval = 30 * 60

func st(_ entries: [AttendanceEntry], now: Date) -> ClockState {
    AttendanceLogic.state(entries: entries, now: now)
}

// MARK: - ClockState

print("AttendanceLogic.state")

expect(st([], now: t(10)) == .clockedOut,
       "no entries → clocked out")

expect(st([work(9, nil)], now: t(10)) == .working(since: t(9)),
       "open work entry → working since clock-in")

expect(st([work(9, 12)], now: t(13)) == .clockedOut,
       "only closed entries → clocked out")

expect(st([work(9, 12), brk(12, nil)], now: t(12.2)) == .onBreak(since: t(12)),
       "open break (pause-style: work closed) → on break")

expect(st([work(9, nil), brk(12, nil)], now: t(12.2)) == .onBreak(since: t(12)),
       "open break (overlay-style: work still open) → break wins")

expect(st([work(9, nil), brk(12, 12.5)], now: t(14)) == .working(since: t(12.5)),
       "completed break resets the stretch → working since break end")

expect(st([work(9, 12), brk(12, 12.5), work(12.5, nil)], now: t(14)) == .working(since: t(12.5)),
       "pause-style resume → working since new work entry")

// A day of only closed entries reads as clocked out — even if HiBob's own
// nextClockAction is briefly confused (this was the real-world bug).
expect(st([work(9, 12), brk(12, 12.5), work(12.5, 14)], now: t(15)) == .clockedOut,
       "all entries closed → clocked out (open-entry is the source of truth)")

// MARK: - workedToday

print("AttendanceLogic.workedToday")

expect(AttendanceLogic.workedToday(entries: [work(9, 12)], now: t(13)) == 3 * 3600,
       "closed work entry → its duration")

expect(AttendanceLogic.workedToday(entries: [work(9, nil)], now: t(13)) == 4 * 3600,
       "open work entry counts up to now")

expect(AttendanceLogic.workedToday(entries: [work(9, nil), brk(12, 12.5)], now: t(13))
       == 3.5 * 3600,
       "overlay-style break subtracted from open work")

expect(AttendanceLogic.workedToday(
        entries: [work(9, 12), brk(12, 12.5), work(12.5, nil)], now: t(13))
       == 3.5 * 3600,
       "pause-style day sums the work pieces")

expect(AttendanceLogic.workedToday(entries: [work(9, nil), brk(12, nil)], now: t(12.5))
       == 3 * 3600,
       "open break stops the clock")

// MARK: - overDailyMax

print("AttendanceLogic.overDailyMax")

expect(!AttendanceLogic.overDailyMax(entries: [work(9, 19)], max: 10 * 3600, now: t(20)),
       "exactly at the max is not over it")

expect(AttendanceLogic.overDailyMax(entries: [work(9, nil)], max: 10 * 3600, now: t(19.5)),
       "open work entry counted to now crosses the max")

expect(!AttendanceLogic.overDailyMax(entries: [work(8, 19), brk(12, 13)], max: 10 * 3600, now: t(20)),
       "breaks don't count toward the daily max")

// MARK: - Auto-break actions

print("AttendanceLogic.action")

func act(_ entries: [AttendanceEntry], auto: Date? = nil, now: Date) -> AutoBreakAction? {
    AttendanceLogic.action(entries: entries, autoBreakStartedAt: auto,
                           threshold: sixH, breakLength: halfH, now: now)
}

expect(act([], now: t(10)) == nil, "clocked out → nothing")

expect(act([work(9, nil)], now: t(14)) == nil,
       "5h worked → nothing yet")

expect(act([work(9, nil)], now: t(15)) == .insertBreak(start: t(15), end: nil),
       "exactly 6h uninterrupted → open break at the 6h mark")

expect(act([work(9, nil)], now: t(15.3)) == .insertBreak(start: t(15), end: nil),
       "6h18m (woke inside the window) → break still open, placed at the 6h mark")

expect(act([work(9, nil)], now: t(16)) == .insertBreak(start: t(15), end: t(15.5)),
       "7h straight (window fully missed) → insert closed break at 6h..6h30m")

expect(act([work(9, nil), brk(12, 12.5)], now: t(18)) == nil,
       "manual break at noon resets the counter → 5.5h stretch, nothing")

expect(act([work(9, nil), brk(12, 12.5)], now: t(18.5)) == .insertBreak(start: t(18.5), end: nil),
       "6h after the manual break ended → auto-break fires again at the mark")

expect(act([work(9, 12)], now: t(16)) == nil,
       "clocked out before the mark (other device) → nothing")

expect(act([work(9, nil), brk(15, nil)], now: t(15.2)) == nil,
       "open manual break (no auto flag) → user owns it, leave alone")

expect(act([work(9, nil), brk(15, nil)], auto: t(15), now: t(15.2)) == nil,
       "auto-break running 12m → not done yet")

expect(act([work(9, nil), brk(15, nil)], auto: t(15), now: t(15.5)) == .endBreak(at: t(15.5)),
       "auto-break hit 30m → end it at its due end")

expect(act([work(9, nil), brk(15, nil)], auto: t(15), now: t(16.2)) == .endBreak(at: t(15.5)),
       "slept through the auto-break end → close it at the due end, not now")

expect(act([work(9, nil), brk(15, 15.2), work(15.2, nil)], auto: t(15), now: t(15.5)) == nil,
       "user ended the auto-break early themselves → accept, nothing to do")

// MARK: - insertingBreak (retroactive repair → whole-day rewrite)

print("AttendanceLogic.insertingBreak")

// Straight 9→now open work stretch; splice a 15:00–15:30 break.
let splitOpen = AttendanceLogic.insertingBreak(
    into: [work(9, nil)], start: t(15), end: t(15.5))
expect(splitOpen?.count == 3, "open stretch → work/break/work")
expect(splitOpen?[0] == AttendanceEntry(kind: .work, start: t(9), end: t(15)),
       "leading work piece keeps original start, ends at break start")
expect(splitOpen?[1] == AttendanceEntry(kind: .breakTime, start: t(15), end: t(15.5)),
       "break in the middle")
expect(splitOpen?[2] == AttendanceEntry(kind: .work, start: t(15.5), end: nil),
       "trailing work piece stays open")

// Reason + id are carried onto the split pieces.
let withReason = AttendanceLogic.insertingBreak(
    into: [AttendanceEntry(kind: .work, start: t(9), end: t(17), id: "E1", reason: "In Office")],
    start: t(15), end: t(15.5))
expect(withReason?[0].id == "E1" && withReason?[0].reason == "In Office",
       "leading piece keeps id + reason")
expect(withReason?[2].id == nil && withReason?[2].reason == "In Office",
       "trailing piece is new (no id) but inherits the reason")

expect(AttendanceLogic.insertingBreak(into: [work(9, 12)], start: t(15), end: t(15.5)) == nil,
       "no work entry spans the window → nil (nothing safe to rewrite)")

// MARK: - nextEvent (precise timer scheduling / popover countdown)

print("AttendanceLogic.nextEvent")

func next(_ entries: [AttendanceEntry], auto: Date? = nil, now: Date) -> Date? {
    AttendanceLogic.nextEvent(entries: entries, autoBreakStartedAt: auto,
                              threshold: sixH, breakLength: halfH, now: now)
}

expect(next([], now: t(10)) == nil, "clocked out → no scheduled event")

expect(next([work(9, nil)], now: t(14)) == t(15),
       "working → auto-break due at stretch start + 6h")

expect(next([work(9, nil), brk(12, 12.5)], now: t(14)) == t(18.5),
       "after a manual break → due 6h after the break ended")

expect(next([work(9, nil), brk(15, nil)], auto: t(15), now: t(15.1)) == t(15.5),
       "on auto-break → break end due at start + 30m")

expect(next([work(9, nil), brk(15, nil)], now: t(15.1)) == nil,
       "on manual break → nothing scheduled (user ends it)")
// MARK: - BobParsing (real HiBob clockStatus / metadata shapes)

print("BobParsing")

func data(_ s: String) -> Data { Data(s.utf8) }

// Employee timezone the real API reports; entry times are local wall-clock.
let vienna = TimeZone(identifier: "Europe/Vienna")!
// 2026-07-16 in Vienna is CEST (UTC+2). Absolute time for a Vienna wall clock:
func vt(_ hour: Int, _ minute: Int) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = 7; c.day = 16; c.hour = hour; c.minute = minute
    var cal = Calendar(identifier: .gregorian); cal.timeZone = vienna
    return cal.date(from: c)!
}

// Trimmed but faithful clockStatus payload (as captured on-device).
let clockStatusJSON = data("""
{"start":"2026-07-16T16:15:15.276403","end":null,"comment":null,
 "nextClockAction":"switch","disabled":false,"errorMessage":null,
 "minutesWorkedToday":375,"breaksTotalMinutes":39,"secondsWorkedToday":22500,
 "entries":[
   {"id":80428078,"employeeId":"377","start":"2026-07-16T16:15","end":null,"reason":null,"entryType":"break","source":"punchClock"},
   {"id":80426654,"employeeId":"377","start":"2026-07-16T15:58","end":"2026-07-16T16:15","reason":null,"entryType":"work","source":"punchClock"},
   {"id":80392069,"employeeId":"377","start":"2026-07-16T09:22","end":"2026-07-16T15:20","reason":"In Office","isManuallyEdited":true,"entryType":"work","source":"employeeManuallyEdit"}
 ],
 "entryType":"break","currentLocalTime":"2026-07-16T16:16:14.7746"}
""")

guard let status = BobParsing.dayStatus(fromClockStatusJSON: clockStatusJSON, timeZone: vienna) else {
    expect(false, "clockStatus decodes to a DayStatus"); exit(1)
}
expect(status.minutesWorkedToday == 375 && status.breaksTotalMinutes == 39,
       "worked/break totals read straight from clockStatus")
expect(status.nextClockAction == "switch" && status.currentEntryType == "break",
       "nextClockAction and current entry type decoded")
expect(status.entries.count == 3, "all entries decoded")
// Entries are returned newest-first by HiBob; parser sorts chronologically.
expect(status.entries.first?.start == vt(9, 22)
       && status.entries.first?.kind == .work,
       "entries sorted chronologically, local wall-clock anchored to Vienna")
expect(status.entries.first?.id == "80392069" && status.entries.first?.reason == "In Office",
       "entry id (numeric) and reason name decoded")
expect(status.entries.last?.kind == .breakTime && status.entries.last?.end == nil,
       "open break entry: type break, end nil")

// When clockStatus reports us punched in (nextClockAction != "in") but returns
// the live entry with an end filled in, the latest matching entry is reopened.
let closedButWorkingJSON = data("""
{"nextClockAction":"out","entryType":"work","minutesWorkedToday":10,"breaksTotalMinutes":0,
 "entries":[
   {"id":"1","start":"2026-07-16T09:00","end":"2026-07-16T09:10","reason":null,"entryType":"work"}
 ]}
""")
let cbw = BobParsing.dayStatus(fromClockStatusJSON: closedButWorkingJSON, timeZone: vienna)
expect(cbw?.entries.last?.end == nil && cbw?.entries.last?.kind == .work,
       "in-progress work entry reopened when nextClockAction says we're clocked in")
expect(AttendanceLogic.state(entries: cbw?.entries ?? [], now: vt(9, 30)) == .working(since: vt(9, 0)),
       "reopened entry yields a working clock state")

// But a genuinely clocked-out day (nextClockAction == "in") is left closed.
let outJSON = data("""
{"nextClockAction":"in","minutesWorkedToday":480,"breaksTotalMinutes":30,
 "entries":[
   {"id":"1","start":"2026-07-16T09:00","end":"2026-07-16T17:00","reason":null,"entryType":"work"}
 ]}
""")
let outStatus = BobParsing.dayStatus(fromClockStatusJSON: outJSON, timeZone: vienna)
expect(outStatus?.entries.last?.end != nil,
       "clocked-out day keeps its last entry closed")

// Clocked out per HiBob (nextClockAction == "in") but the last entry came back
// dangling-open — close it at currentLocalTime so the app agrees with the web
// instead of showing a phantom ongoing period.
let clockedOutButOpenJSON = data("""
{"nextClockAction":"in","entryType":"work","minutesWorkedToday":480,"breaksTotalMinutes":0,
 "currentLocalTime":"2026-07-16T17:05:00",
 "entries":[
   {"id":"1","start":"2026-07-16T09:00","end":null,"reason":null,"entryType":"work"}
 ]}
""")
let cob = BobParsing.dayStatus(fromClockStatusJSON: clockedOutButOpenJSON, timeZone: vienna)
expect(cob?.entries.last?.end == vt(17, 5),
       "clocked-out day with a dangling-open entry gets closed at currentLocalTime")
expect(AttendanceLogic.state(entries: cob?.entries ?? [], now: vt(17, 30)) == .clockedOut,
       "closed dangling entry yields a clocked-out state, matching the web")
expect(status.entries[0].end == vt(15, 20),
       "closed work entry end parsed (no seconds, local)")

// AttendanceLogic still works on the parsed entries: the open break entry
// means we're on break since 16:15.
expect(AttendanceLogic.state(entries: status.entries, now: vt(16, 16))
       == .onBreak(since: vt(16, 15)),
       "parsed clockStatus feeds the engine: currently on break")

// disabled / errorMessage surfaced from clockStatus.
let disabledJSON = data("""
{"nextClockAction":"out","disabled":true,"errorMessage":"Clock out isn't available",
 "minutesWorkedToday":10,"breaksTotalMinutes":0,"entries":[]}
""")
let ds = BobParsing.dayStatus(fromClockStatusJSON: disabledJSON, timeZone: vienna)
expect(ds?.disabled == true && ds?.errorMessage == "Clock out isn't available",
       "disabled + errorMessage decoded from clockStatus")

expect(BobParsing.dayStatus(fromClockStatusJSON: data("{}"), timeZone: vienna) != nil,
       "empty-but-valid JSON → empty DayStatus, no crash")
expect(BobParsing.dayStatus(fromClockStatusJSON: data("not json"), timeZone: vienna) == nil,
       "garbage → nil")

// Reason options from metadata/lists → timeLogEntryReason.values[]
let listsJSON = data("""
{"workingLocations":{"type":"flat","values":[{"value":"Onsite","serverId":"onsite","archived":false}]},
 "timeLogEntryReason":{"type":"flat","editable":true,"values":[
   {"value":"In Office","serverId":"259891317","archived":false,"children":[]},
   {"value":"Work from home","serverId":"264961875","archived":false,"children":[]},
   {"value":"Smart Working","serverId":"259891316","archived":true,"children":[]}
 ]}}
""")
let reasons = BobParsing.reasonOptions(fromListsJSON: listsJSON)
expect(reasons.count == 2, "archived reasons dropped")
expect(reasons.map(\.name) == ["In Office", "Work from home"],
       "reason names decoded in order")
expect(reasons.first?.id == "259891317",
       "reason serverId decoded (this is what the write API needs)")
expect(BobParsing.reasonOptions(fromListsJSON: data("{\"other\":1}")).isEmpty,
       "no timeLogEntryReason → empty, no crash")

// Employee id from /api/user
expect(BobParsing.employeeID(fromUserJSON: data("{\"id\":\"1234567890\",\"email\":\"x\"}")) == "1234567890",
       "employee id (string) from /api/user")
expect(BobParsing.employeeID(fromUserJSON: data("{}")) == nil, "no id → nil")

// Local timestamp parser (no timezone in the string → employee tz).
expect(BobParsing.parseLocalTimestamp("2026-07-16T16:15", timeZone: vienna) == vt(16, 15),
       "HH:mm form (no seconds, no tz)")
expect(BobParsing.parseLocalTimestamp("2026-07-16T16:15:00", timeZone: vienna) == vt(16, 15),
       "with seconds")
expect(BobParsing.parseLocalTimestamp("2026-07-16T16:15:00.276403", timeZone: vienna) == vt(16, 15),
       "with microseconds")
expect(BobParsing.parseLocalTimestamp("nope", timeZone: vienna) == nil, "junk → nil")

// PunchAction request bodies match what the web app sends.
expect(PunchAction.clockOut.clockAction == "out" && !PunchAction.clockOut.returnFromBreak
       && PunchAction.clockOut.entryType == "work", "clock-out body")
expect(PunchAction.endBreak.clockAction == "switch" && PunchAction.endBreak.returnFromBreak
       && PunchAction.endBreak.entryType == "work", "end-break body")
expect(PunchAction.startBreak.clockAction == "switch" && !PunchAction.startBreak.returnFromBreak
       && PunchAction.startBreak.entryType == "break", "start-break body")
expect(PunchAction.clockIn.clockAction == "in" && PunchAction.clockIn.entryType == "work",
       "clock-in body")

// MARK: - Dashboard parsing (timesheets + summary)

print("BobParsing.dashboard")

let timesheetsJSON = data("""
{"employeeTimesheets":[{"id":0,"cycleStartDate":"2026-07-01","cycleEndDate":"2026-07-31",
 "timesheetState":{"timeSheetStatus":"Open","lockAt":1787695200000,"locked":false}}]}
""")
let cycle = BobParsing.cycle(fromTimesheetsJSON: timesheetsJSON)
expect(cycle?.id == 0 && cycle?.start == "2026-07-01" && cycle?.end == "2026-07-31",
       "cycle window decoded")
expect(cycle?.lockAt == Date(timeIntervalSince1970: 1787695200),
       "lockAt (ms) → deadline date")

let summaryJSON = data("""
{"dailyBreakdown":{
  "categories":["2026-07-01","2026-07-02","2026-07-03"],
  "graphData":[
    {"id":"potentialHours","name":"Potential hours","target":[
      {"value":8,"valueDisplay":"8h 00m"},{"value":8,"valueDisplay":"8h 00m"},{"value":6.5,"valueDisplay":"6h 30m"}]},
    {"id":"hoursWorked","name":"Hours worked","data":[
      {"value":6.95,"valueDisplay":"6h 57m"},{"value":9.17,"valueDisplay":"9h 10m"},{"value":0,"valueDisplay":"0h 00m"}]},
    {"id":"overtime","name":"Over/undertime","data":[{"value":0}]}
  ]},
  "summary":{"overUnderTime":{"sign":"-","hoursDisplay":"0h 26m"},
    "potentialHours":{"payableTimePercentage":51},
    "payableHoursBreakdown":{"totalHoursDisplay":"87h 30m"}},
  "breakViolationCounter":2}
""")
let summary = BobParsing.summary(fromSummaryJSON: summaryJSON)
expect(summary?.days.count == 3, "three days decoded")
expect(summary?.days[0].worked == 6.95 && summary?.days[0].target == 8,
       "day 0 worked + target")
expect(summary?.days[2].target == 6.5 && summary?.days[2].worked == 0,
       "short-day target + zero worked")
expect(summary?.overUnderMinutes == -26, "over/undertime parsed as signed minutes (behind)")
expect(summary?.payableTimePercent == 51, "payable-time percent found in nested summary")
expect(summary?.totalHoursDisplay == "87h 30m", "total hours display found")
expect(summary?.breakViolations == 2, "break violation counter found")

expect(BobParsing.minutes(fromDisplay: "8h 05m") == 485, "Xh Ym → minutes")
expect(BobParsing.minutes(fromDisplay: "0h 00m") == 0, "zero display → 0")
expect(BobParsing.summary(fromSummaryJSON: data("{}")) == nil, "empty summary JSON → nil")

// Activity history
let historyJSON = data("""
{"date":"2026-07-16","events":[
 {"type":"clockedIn","actor":{"displayName":"Test User"},"timestamp":1784186523565,"details":{"clockIn":"09:22"}},
 {"type":"editedEntries","actor":{"displayName":"Test User"},"timestamp":1784208821926,"details":{"clockIn":"09:22","clockOut":"15:20","entryDuration":"5h 57m","reason":"In Office"}}
]}
""")
let activity = BobParsing.activity(fromHistoryJSON: historyJSON)
expect(activity.count == 2, "two history events decoded")
expect(activity.first?.kind == .edited, "newest-first: edit event on top")
expect(activity.first?.detail == "09:22 → 15:20 · 5h 57m · In Office",
       "edit detail assembled from clockIn/out/duration/reason")
expect(activity.last?.kind == .clockedIn && activity.last?.detail == "09:22",
       "clock-in event detail")
expect(BobParsing.activity(fromHistoryJSON: data("{}")).isEmpty, "no events → empty")

// MARK: - Time off

print("BobParsing.timeoff")

let balJSON = data("""
{"summary":[{"type":"Holiday","policyTypeDisplayName":"Holidays (days)","unit":"days",
 "cycleRange":"01/01/2026–31/12/2026","currentBalance":"45","totalAllowance":"25",
 "metrics":[{"value":"-6","title":"Days taken"}]}]}
""")
let bals = BobParsing.timeOffBalances(fromSummaryJSON: balJSON)
expect(bals.count == 1 && bals[0].displayName == "Holidays (days)", "balance decoded")
expect(bals[0].currentBalance == "45" && bals[0].totalAllowance == "25" && bals[0].daysTaken == "-6",
       "balance figures + days taken")

let polJSON = data("""
{"policies":[
 {"id":2201682,"type":"Holiday","displayName":"Holidays (days)","unit":"days","info":{"emoji":"🌴"}},
 {"id":2201696,"type":"Sick","displayName":"Sickness (days)","unit":"days","inactive":false},
 {"id":9,"type":"Old","displayName":"Old","inactive":true}]}
""")
let pols = BobParsing.timeOffPolicyTypes(fromConfigJSON: polJSON)
expect(pols.count == 2, "inactive policy filtered out")
expect(pols[0].id == "2201682" && pols[0].type == "Holiday" && pols[0].emoji == "🌴",
       "policy id/type/emoji decoded")

let calcJSON = data("""
{"amount":1,"submittable":true,"requestMessage":"You are requesting 1 day of Sunny Fridays",
 "forecastMessage":"…will be 0 days","validationMessages":{}}
""")
let calc = BobParsing.timeOffCalc(fromJSON: calcJSON)
expect(calc?.amount == 1 && calc?.submittable == true && calc?.validation == nil,
       "calc amount/submittable, no validation error")
expect(calc?.requestMessage.contains("Sunny Fridays") == true, "calc request message")

expect(BobParsing.timeOffRequests(fromInRangeJSON: data("{\"requests\":[],\"openRequests\":[]}")).isEmpty,
       "empty requests → none")
let reqJSON = data("""
{"requests":[{"id":123,"policyTypeDisplayName":"Holiday","startDate":"2026-08-01","endDate":"2026-08-05","status":"approved","amount":5}]}
""")
let reqs = BobParsing.timeOffRequests(fromInRangeJSON: reqJSON)
expect(reqs.count == 1 && reqs[0].id == "123" && reqs[0].status == "approved" && reqs[0].amount == "5",
       "request row decoded defensively")

// Month days (views/search grid) — reason serverId → name mapping.
let monthJSON = data("""
{"employees":[
  {"time_attendance_employee_timesheet":{"date":"Thu, 16/07/2026 (Today)","entries":[
    {"id":1,"start":"2026-07-16T09:00","end":"2026-07-16T12:00","entryType":"work","reason":"259891317"},
    {"id":2,"start":"2026-07-16T12:00","end":"2026-07-16T12:30","entryType":"break","reason":null}]}},
  {"time_attendance_employee_timesheet":{"date":"Fri, 17/07/2026","entries":[]}}
]}
""")
let reasonOpts = [ReasonOption(id: "259891317", name: "In Office")]
let mdays = BobParsing.monthDays(fromViewsSearchJSON: monthJSON, reasonOptions: reasonOpts, timeZone: vienna)
expect(mdays.count == 2, "two day rows decoded (incl. empty day via display date)")
expect(mdays[0].dateKey == "2026-07-16" && mdays[0].entries.count == 2,
       "day key from entry start; entries decoded")
expect(mdays[0].entries[0].reason == "In Office",
       "reason serverId mapped to display name")
expect(mdays[1].dateKey == "2026-07-17" && mdays[1].entries.isEmpty,
       "empty day: key parsed from 'dd/MM/yyyy' display string")

// MARK: - dragged (edit an existing day by dragging a block)

print("AttendanceLogic.dragged")

// A contiguous day: work 9–12, break 12–13, work 13–17.
let dayCont = [work(9, 12), brk(12, 13), work(13, 17)]

// translate a block ripples it AND everything after by the same amount; the
// block before it stays put (a gap opens).
let dr1 = AttendanceLogic.dragged(dayCont, index: 1, mode: .translate, by: 3600, now: t(18))
expect(dr1[0].end == t(12) && dr1[1].start == t(13) && dr1[1].end == t(14)
       && dr1[2].start == t(14) && dr1[2].end == t(18),
       "translate ripples the block and the whole tail; earlier block untouched")

// translate the first block shifts the entire day.
let dr2 = AttendanceLogic.dragged(dayCont, index: 0, mode: .translate, by: 3600, now: t(18))
expect(dr2[0].start == t(10) && dr2[2].end == t(18), "translate index 0 ripples everything")

// A contiguous block can't be dragged left over the previous one.
let dr3 = AttendanceLogic.dragged(dayCont, index: 1, mode: .translate, by: -3600, now: t(18))
expect(dr3[1].start == t(12) && dr3[2].end == t(17), "translate clamped at the previous block")

// moveEnd resizes the end and ripples the tail (no compression).
let dr4 = AttendanceLogic.dragged(dayCont, index: 0, mode: .moveEnd, by: 3600, now: t(18))
expect(dr4[0].end == t(13) && dr4[1].start == t(13) && dr4[1].end == t(14) && dr4[2].end == t(18),
       "moveEnd grows the block and ripples the tail right")

// moveEnd can shrink too, pulling the tail left with it.
let dr5 = AttendanceLogic.dragged(dayCont, index: 0, mode: .moveEnd, by: -7200, now: t(18))
expect(dr5[0].end == t(10) && dr5[1].start == t(10) && dr5[2].end == t(15),
       "moveEnd shrinks the block and ripples the tail left")

// moveEnd is clamped so the block keeps at least minGap (5 min).
let dr6 = AttendanceLogic.dragged(dayCont, index: 0, mode: .moveEnd, by: -36000, now: t(18))
expect(dr6[0].end == t(9).addingTimeInterval(300)
       && dr6[0].end!.timeIntervalSince(dr6[0].start) == 300,
       "moveEnd clamped to keep the block >= minGap")

// An open last block has no end: any mode translates its start, staying open.
let dayOpen = [work(9, 12), brk(12, 13), work(13, nil)]
let dr7 = AttendanceLogic.dragged(dayOpen, index: 2, mode: .moveEnd, by: 1800, now: t(15))
expect(dr7[2].start == t(13.5) && dr7[2].end == nil && dr7[1].end == t(13),
       "open block translates its start and stays open; earlier blocks untouched")

// Results snap to the nearest snap step (5 min).
let dr8 = AttendanceLogic.dragged(dayCont, index: 0, mode: .moveEnd, by: 420, now: t(18))
expect(dr8[0].end == t(12).addingTimeInterval(300) && dr8[1].start == t(12).addingTimeInterval(300),
       "drag result snaps to the step and ripples the tail")

// moveStart resizes from the left: only the block's start moves — used for
// the day-start edge, so the clock-in shifts and nothing else does.
let dr10 = AttendanceLogic.dragged(dayCont, index: 0, mode: .moveStart, by: -3600, now: t(18))
expect(dr10[0].start == t(8) && dr10[0].end == t(12) && dr10[2].end == t(17),
       "moveStart moves the day's clock-in; everything else stays put")

// moveStart shrinking is clamped so the block keeps at least minGap.
let dr11 = AttendanceLogic.dragged(dayCont, index: 0, mode: .moveStart, by: 36000, now: t(18))
expect(dr11[0].start == t(12).addingTimeInterval(-300) && dr11[0].end == t(12),
       "moveStart clamped to keep the block >= minGap")

// An interior moveStart can't cross the previous block's end.
let dr12 = AttendanceLogic.dragged(dayCont, index: 2, mode: .moveStart, by: -7200, now: t(18))
expect(dr12[2].start == t(13) && dr12[1].end == t(13),
       "interior moveStart clamped at the previous block")

// moveStart on the open block clamps against now.
let dr13 = AttendanceLogic.dragged(dayOpen, index: 2, mode: .moveStart, by: 36000, now: t(15))
expect(dr13[2].start == t(15).addingTimeInterval(-300) && dr13[2].end == nil,
       "open block's moveStart clamped to now - minGap, stays open")

// A gap day: work 9–12, work 13–15. translate index 1 can slide left into the
// gap (up to the previous block) and ripples nothing after it (it's last).
let dayGap = [work(9, 12), work(13, 15)]
let dr9 = AttendanceLogic.dragged(dayGap, index: 1, mode: .translate, by: -7200, now: t(18))
expect(dr9[1].start == t(12) && dr9[1].end == t(14) && dr9[0].end == t(12),
       "translate slides left across a gap, clamped at the previous block")

// MARK: - boundaryMoved (drag the edge between two blocks)

print("AttendanceLogic.boundaryMoved")

let bm1 = AttendanceLogic.boundaryMoved(dayCont, after: 0, by: 1800, now: t(18))
expect(bm1[0].end == t(12.5) && bm1[1].start == t(12.5) && bm1[1].end == t(13)
       && bm1[2].start == t(13) && bm1[2].end == t(17),
       "boundary right: left block grows, right block shrinks, rest untouched")

let bm2 = AttendanceLogic.boundaryMoved(dayCont, after: 1, by: 36000, now: t(18))
expect(bm2[1].end == t(17).addingTimeInterval(-300) && bm2[2].start == t(17).addingTimeInterval(-300)
       && bm2[2].end == t(17),
       "clamped so the right block keeps >= minGap")

let bm3 = AttendanceLogic.boundaryMoved(dayCont, after: 0, by: -36000, now: t(18))
expect(bm3[0].end == t(9).addingTimeInterval(300) && bm3[1].start == t(9).addingTimeInterval(300),
       "clamped so the left block keeps >= minGap")

let bm4 = AttendanceLogic.boundaryMoved(dayCont, after: 2, by: 3600, now: t(18))
expect(bm4[2].end == t(18) && bm4[1] == dayCont[1],
       "last boundary just moves the clock-out")

let bm5 = AttendanceLogic.boundaryMoved(dayOpen, after: 1, by: 3600, now: t(15))
expect(bm5[1].end == t(14) && bm5[2].start == t(14) && bm5[2].end == nil,
       "boundary before the open block moves it and keeps it open")

let bm6 = AttendanceLogic.boundaryMoved(dayCont, after: 0, by: 420, now: t(18))
expect(bm6[0].end == t(12).addingTimeInterval(300),
       "boundary snaps to the 5-min grid")

// MARK: - TOTP (RFC 6238 SHA-1 vectors, 6-digit)

print("TOTP")
let totpSecret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"   // base32 of "12345678901234567890"
func totpAt(_ unix: Double) -> String? {
    TOTP.code(secretBase32: totpSecret, at: Date(timeIntervalSince1970: unix))
}
expect(totpAt(59) == "287082", "RFC 6238 vector @ T=59")
expect(totpAt(1111111109) == "081804", "RFC 6238 vector @ T=1111111109")
expect(totpAt(1234567890) == "005924", "RFC 6238 vector @ T=1234567890")
expect(TOTP.code(secretBase32: "not base32 !!!") == nil, "invalid base32 → nil")
expect(TOTP.base32Decode(totpSecret).flatMap { String(data: $0, encoding: .utf8) } == "12345678901234567890",
       "base32 decodes to the ASCII secret")
expect(TOTP.code(secretBase32: "jbsw y3dp ehpk 3pxp") != nil, "spaces in the secret are tolerated")
// otpauth:// URL → the secret is extracted (and a code computes from it).
expect(TOTP.base32Secret(from: "otpauth://totp/Okta:me@co.com?secret=\(totpSecret)&issuer=Okta&period=30") == totpSecret,
       "otpauth:// URL → base32 secret extracted")
expect(TOTP.base32Secret(from: "  \(totpSecret)  ") == totpSecret, "bare secret is just trimmed")
expect(TOTP.code(secretBase32: "otpauth://totp/x?secret=\(totpSecret)", at: Date(timeIntervalSince1970: 59)) == "287082",
       "code computes straight from an otpauth:// URL")

// MARK: - overLongStretch (wand: any uninterrupted run past the max)

print("AttendanceLogic.overLongStretch")
expect(AttendanceLogic.overLongStretch(entries: [work(9, 16)], threshold: sixH, now: t(17))?.start == t(9),
       "single 7h work run is flagged")
expect(AttendanceLogic.overLongStretch(entries: [work(9, 12), brk(12, 12.5), work(12.5, 15)],
                                       threshold: sixH, now: t(16)) == nil,
       "two short runs split by a break: no violation")
expect(AttendanceLogic.overLongStretch(entries: [work(9, 12), brk(12, 12.5), work(12.5, 20)],
                                       threshold: sixH, now: t(21))?.start == t(12.5),
       "the over-long run after a break is still flagged")
expect(AttendanceLogic.overLongStretch(entries: [work(9, nil)], threshold: sixH, now: t(16))?.end == t(16),
       "an open run is measured to now")

// MARK: - insertingAllBreaks (wand: fix a whole over-long day at once)

print("AttendanceLogic.insertingAllBreaks")

// 13h uninterrupted (9→22) needs TWO breaks to bring every run under 6h.
let thirteen = AttendanceLogic.insertingAllBreaks(
    into: [work(9, 22)], threshold: sixH, breakLength: halfH, now: t(22))
expect(thirteen?.filter { $0.kind == .breakTime }.count == 2,
       "13h block → two breaks inserted")
// First break sits at the edge of the first max window (9h + 6h = 15:00).
expect(thirteen?.contains(AttendanceEntry(kind: .breakTime, start: t(15), end: t(15.5))) == true,
       "first break at the edge of the max (15:00–15:30), not the middle")
// After the first break work resumes 15:30; its own 6h edge is 21:30.
expect(thirteen?.contains(AttendanceEntry(kind: .breakTime, start: t(21.5), end: t(22))) == true,
       "second break at the next max edge (21:30–22:00)")
// No run in the rebuilt day exceeds the max anymore.
expect(AttendanceLogic.overLongStretch(entries: thirteen ?? [], threshold: sixH, now: t(22)) == nil,
       "rebuilt 13h day has no over-long run left")

// A 7h day needs exactly one break, placed at the edge.
let seven = AttendanceLogic.insertingAllBreaks(
    into: [work(9, 16)], threshold: sixH, breakLength: halfH, now: t(16))
expect(seven?.filter { $0.kind == .breakTime }.count == 1
       && seven?.contains(AttendanceEntry(kind: .breakTime, start: t(15), end: t(15.5))) == true,
       "7h block → one break at the 6h edge")

// A compliant day is left untouched.
expect(AttendanceLogic.insertingAllBreaks(
    into: [work(9, 12), brk(12, 12.5), work(12.5, 15)],
    threshold: sixH, breakLength: halfH, now: t(16)) == nil,
    "day already within the max → nil (nothing to fix)")

// MARK: - closingBreak (retroactive auto-break end)

print("AttendanceLogic.closingBreak")

// Open auto-break at 15:00; close it at its due end 15:30 and resume work.
let closed = AttendanceLogic.closingBreak(
    into: [work(9, 15), brk(15, nil)], at: t(15.5), reason: "In Office")
expect(closed?.count == 3, "closing an open break appends a resumed work entry")
expect(closed?[1] == AttendanceEntry(kind: .breakTime, start: t(15), end: t(15.5)),
       "the open break is closed at its due end")
expect(closed?[2] == AttendanceEntry(kind: .work, start: t(15.5), end: nil, id: nil, reason: "In Office"),
       "work resumes at the break end, open, inheriting the reason")
expect(AttendanceLogic.closingBreak(into: [work(9, nil)], at: t(15.5), reason: nil) == nil,
       "no open break → nil")

// MARK: - normalized (auto-fix gaps + overlaps on save)

print("AttendanceLogic.normalized")

func w(_ from: Double, _ to: Double?, _ id: String) -> AttendanceEntry {
    AttendanceEntry(kind: .work, start: t(from), end: to.map(t), id: id)
}
func b(_ from: Double, _ to: Double?, _ id: String) -> AttendanceEntry {
    AttendanceEntry(kind: .breakTime, start: t(from), end: to.map(t), id: id)
}

// Gap (8–10 work, 10:30–12 break), break just edited → work end snaps to the
// break's start (the anchor wins).
let gapB = AttendanceLogic.normalized([w(8, 10, "W"), b(10.5, 12, "B")], anchor: "B")
expect(gapB.count == 2 && gapB[0].end == t(10.5) && gapB[1].start == t(10.5) && gapB[1].end == t(12),
       "gap, break edited → work end snaps up to break start")

// Same gap, work just edited → break start snaps back to work's end.
let gapW = AttendanceLogic.normalized([w(8, 10, "W"), b(10.5, 12, "B")], anchor: "W")
expect(gapW[0].end == t(10) && gapW[1].start == t(10) && gapW[1].end == t(12),
       "gap, work edited → break start snaps back to work end")

// Overlap (8–11 work, 10–12 break), break edited → work end pulled back.
let ov = AttendanceLogic.normalized([w(8, 11, "W"), b(10, 12, "B")], anchor: "B")
expect(ov[0].end == t(10) && ov[1].start == t(10),
       "overlap, break edited → work end pulled back to break start")

// No anchor (e.g. after a delete leaves a gap): later entry snaps back to the
// earlier one's end; earlier entry and the clock-out are preserved.
let del = AttendanceLogic.normalized([work(8, 10), work(11, 12)])
expect(del.count == 2 && del[0].end == t(10) && del[1].start == t(10) && del[1].end == t(12),
       "no anchor: gap closed by pulling the later entry back")

// Anchor fully covers a neighbour → the swallowed entry is dropped.
let sw = AttendanceLogic.normalized([w(8, 12, "W"), b(9, 10, "B")], anchor: "W")
expect(sw.count == 1 && sw[0].id == "W", "anchor swallows a covered entry → dropped")

// Open final entry stays open; the entry before snaps to its start.
let openTail = AttendanceLogic.normalized([w(8, 10, "W"), w(10.5, nil, "W2")], anchor: "W2")
expect(openTail.count == 2 && openTail[0].end == t(10.5) && openTail[1].end == nil,
       "open final entry: previous snaps to its start, tail stays open")

// Already contiguous → unchanged.
let tidy = [work(8, 10), brk(10, 10.5), work(10.5, 12)]
expect(AttendanceLogic.normalized(tidy) == tidy, "already contiguous → unchanged")

// MARK: - moved (drag a block to a new time, keep duration, stay contiguous)

print("AttendanceLogic.moved")

let dayWBW = [w(8, 12, "W1"), b(12, 12.5, "B"), w(12.5, 17, "W2")]

// Drag the break earlier to 10:00 → work before shrinks, work after grows,
// the break keeps its 30-min length and everything stays contiguous.
let movedEarly = AttendanceLogic.moved(dayWBW, id: "B", toStart: t(10))
expect(movedEarly == [w(8, 10, "W1"), b(10, 10.5, "B"),
                      AttendanceEntry(kind: .work, start: t(10.5), end: t(17))],
       "drag break earlier → surrounding work resizes, break keeps its length")

// Drag it later to 15:00 — crosses the original work/break boundary, so the
// work block is re-split at the new spot.
let movedLate = AttendanceLogic.moved(dayWBW, id: "B", toStart: t(15))
expect(movedLate == [w(8, 15, "W1"), b(15, 15.5, "B"),
                     AttendanceEntry(kind: .work, start: t(15.5), end: t(17))],
       "drag break later → same, other direction")

// Total worked time is unchanged by a reposition.
func workOf(_ es: [AttendanceEntry]) -> TimeInterval {
    es.filter { $0.kind == .work }.reduce(0) { $0 + ($1.end ?? $1.start).timeIntervalSince($1.start) }
}
expect(workOf(movedEarly) == workOf(dayWBW), "reposition preserves total worked time")

// Unknown id → just normalised, no move.
expect(AttendanceLogic.moved(dayWBW, id: "nope", toStart: t(10)) == AttendanceLogic.normalized(dayWBW),
       "unknown id → unchanged (normalised)")

// MARK: - Updater.isNewer (version comparison for auto-update)

print("Updater.isNewer")
expect(Updater.isNewer("v1.1", than: "1.0"), "1.1 > 1.0")
expect(Updater.isNewer("1.0.1", than: "1.0"), "1.0.1 > 1.0")
expect(Updater.isNewer("2.0", than: "1.9"), "2.0 > 1.9")
expect(Updater.isNewer("v1.10", than: "v1.9"), "1.10 > 1.9 (numeric, not lexical)")
expect(!Updater.isNewer("1.0", than: "1.0"), "equal → not newer")
expect(!Updater.isNewer("1.0", than: "1.0.1"), "1.0 < 1.0.1")
expect(!Updater.isNewer("1.9", than: "2.0"), "older → not newer")

// MARK: - Clocked-out gaps interrupt the work stretch

print("AttendanceLogic gaps")

expect(AttendanceLogic.stretchStart(entries: [work(9, 11), work(23, nil)]) == t(23),
       "clock-out gap resets the stretch start")

expect(st([work(9, 11), work(23, nil)], now: t(23.5)) == .working(since: t(23)),
       "working since re-clock-in after a gap")

expect(AttendanceLogic.overLongStretch(entries: [work(9, 11), work(23, nil)],
                                       threshold: sixH, now: t(23.5)) == nil,
       "out at 11, back at 23 → no over-long stretch")

expect(AttendanceLogic.overLongStretch(entries: [work(9, 11), work(11.1, nil)],
                                       threshold: sixH, now: t(17.5)) != nil,
       "a 6-min blip doesn't reset the counter")

expect(AttendanceLogic.insertingAllBreaks(into: [work(9, 11), work(23, nil)],
                                          threshold: sixH, breakLength: halfH,
                                          now: t(23.5)) == nil,
       "wand has nothing to fix on a gap day")

// MARK: - Break guideline (breaks logged but too short)

print("AttendanceLogic.breakShortfall")

expect(AttendanceLogic.breakShortfall(entries: [work(9, 12), brk(12, 12.5), work(12.5, 16.5)],
                                      threshold: sixH, required: halfH, now: t(17)) == nil,
       "30-min break on a 7h day → compliant")

expect(AttendanceLogic.breakShortfall(entries: [work(9, 12), brk(12, 12.2), work(12.2, 16.5)],
                                      threshold: sixH, required: halfH, now: t(17)) == halfH,
       "12-min break doesn't qualify → full 30 min missing")

expect(AttendanceLogic.breakShortfall(entries: [work(9, 12), work(12.6, 16)],
                                      threshold: sixH, required: halfH, now: t(17)) == nil,
       "a 36-min clocked-out gap counts like a break")

expect(AttendanceLogic.breakShortfall(entries: [work(9, 14)],
                                      threshold: sixH, required: halfH, now: t(14)) == nil,
       "under the threshold → no requirement yet")

expect(AttendanceLogic.breakShortfall(
        entries: [work(9, 12), brk(12, 12.25), work(12.25, 15), brk(15, 15.25), work(15.25, 17.5)],
        threshold: sixH, required: halfH, now: t(18)) == halfH,
       "two 15-min breaks don't satisfy a 30-min single-break minimum")

expect(AttendanceLogic.breakShortfall(entries: [work(9, 12), work(12.34, 18)],
                                      threshold: sixH, required: halfH, now: t(18)) == halfH,
       "a 20-min gap interrupts the stretch but doesn't meet the guideline")

let shortDay = [work(9, 12), brk(12, 12.2), work(12.2, 16.5)]
if let fixed = AttendanceLogic.meetingBreakGuideline(entries: shortDay, threshold: sixH,
                                                     required: halfH, now: t(17)) {
    expect(AttendanceLogic.breakShortfall(entries: fixed, threshold: sixH,
                                          required: halfH, now: t(17)) == nil,
           "guideline fix makes the day compliant")
    expect(fixed.first?.start == t(9) && fixed.compactMap(\.end).max() == t(16.5),
           "guideline fix keeps clock-in and clock-out")
} else {
    expect(false, "guideline fix produces a result for a short-break day")
}

expect(AttendanceLogic.meetingBreakGuideline(entries: [work(9, 12), brk(12, 12.5), work(12.5, 16.5)],
                                             threshold: sixH, required: halfH, now: t(17)) == nil,
       "compliant day → nothing to fix")

// MARK: - StatsHTTP (phone stats page routing + JSON)

print("StatsHTTP.requestLine")
expect(StatsHTTP.requestLine("GET /abc HTTP/1.1\r\nHost: x\r\n\r\n")! == ("GET", "/abc"),
       "plain GET → method + path")
expect(StatsHTTP.requestLine("GET /abc?x=1&y=2 HTTP/1.1\r\n\r\n")! == ("GET", "/abc"),
       "query string stripped")
expect(StatsHTTP.requestLine("POST /t/action/clockIn HTTP/1.1\r\n\r\n")! == ("POST", "/t/action/clockIn"),
       "POST parsed")
expect(StatsHTTP.requestLine("GARBAGE") == nil, "garbage → nil")
expect(StatsHTTP.requestLine("GET /abc") == nil, "missing HTTP version → nil")

print("StatsHTTP.route")
expect(StatsHTTP.route(method: "GET", path: "/tok3n", token: "tok3n") == .page,
       "token path → page")
expect(StatsHTTP.route(method: "GET", path: "/tok3n/", token: "tok3n") == .page,
       "trailing slash → page")
expect(StatsHTTP.route(method: "GET", path: "/tok3n/stats.json", token: "tok3n") == .json,
       "stats.json → json")
expect(StatsHTTP.route(method: "GET", path: "/wrong", token: "tok3n") == .notFound,
       "wrong token → notFound")
expect(StatsHTTP.route(method: "GET", path: "/", token: "tok3n") == .notFound,
       "root → notFound")
expect(StatsHTTP.route(method: "GET", path: "/tok3n", token: "") == .notFound,
       "empty token → everything notFound")
expect(StatsHTTP.route(method: "POST", path: "/tok3n/action/clockIn", token: "tok3n") == .action("clockIn"),
       "POST action → action(clockIn)")
expect(StatsHTTP.route(method: "GET", path: "/tok3n/action/clockIn", token: "tok3n") == .notFound,
       "GET on action route → notFound (POST-only)")
expect(StatsHTTP.route(method: "POST", path: "/tok3n/action/", token: "tok3n") == .notFound,
       "empty action name → notFound")
expect(StatsHTTP.route(method: "POST", path: "/tok3n", token: "tok3n") == .notFound,
       "POST on page route → notFound")

print("StatsHTTP.json")
let snap = StatsSnapshot(
    name: "Kevin \"K\" \\ line\nbreak", state: "working", projected: "break",
    actionsEnabled: true, workedSeconds: 3600, asOf: 1_784_160_000,
    targetSeconds: 28_800, breakSeconds: 1800, breakEndsAt: nil,
    entries: [.init(kind: "work", start: 1_784_160_000, end: 1_784_163_600),
              .init(kind: "break", start: 1_784_163_600, end: nil)])
let parsed = (try? JSONSerialization.jsonObject(with: Data(StatsHTTP.json(snap).utf8))) as? [String: Any]
expect(parsed != nil, "escaped snapshot parses as valid JSON")
expect(parsed?["name"] as? String == "Kevin \"K\" \\ line\nbreak", "name round-trips through escaping")
expect(parsed?["worked"] as? Int == 3600, "worked carried over")
expect(parsed?["projected"] as? String == "break", "projected state carried over")
expect(parsed?["actions"] as? Bool == true, "actions flag carried over")
expect(parsed?["breakEndsAt"] is NSNull, "nil breakEndsAt → null")
let jsonEntries = parsed?["entries"] as? [[String: Any]]
expect(jsonEntries?.count == 2, "both entries encoded")
expect(jsonEntries?[1]["end"] is NSNull, "open entry end → null")

// MARK: - Summary

print("")
if failures == 0 {
    print("All tests passed.")
} else {
    print("\(failures) test(s) FAILED.")
    exit(1)
}
