// Unit tests — exercises the pure attendance math and HiBob JSON parsing
// the engine depends on. Run via Scripts/test.sh.
import Foundation
import JavaScriptCore

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
    {"id":"timeOff","name":"Time off","data":[
      {"value":0},{"value":0},{"value":6.5,"valueDisplay":"6h 30m"}]},
    {"id":"overtime","name":"Over/undertime","data":[
      {"value":-1.05,"valueDisplay":"1h 03m"},{"value":1.17,"valueDisplay":"1h 10m"}]}
  ]},
  "summary":{"overUnderTime":{"sign":"-","hoursDisplay":"0h 26m"},
    "timeOffDisplay":"6h 30m",
    "potentialHours":{"payableTimePercentage":51},
    "payableHoursBreakdown":{"totalHoursDisplay":"87h 30m"}},
  "breakViolationCounter":2,"isSubmittable":true}
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
expect(summary?.isSubmittable == true, "isSubmittable flag surfaced (gates the Submit button)")
expect(summary?.days[2].timeOff == 6.5, "per-day time off decoded (a day off is not missing)")
expect(summary?.timeOffMinutes == 390, "cycle time-off total from timeOffDisplay")

expect(BobParsing.minutes(fromDisplay: "8h 05m") == 485, "Xh Ym → minutes")
expect(BobParsing.minutes(fromDisplay: "0h 00m") == 0, "zero display → 0")
expect(BobParsing.summary(fromSummaryJSON: data("{}")) == nil, "empty summary JSON → nil")

// Past cycles (the "Last month" tab): the timesheets list carries every
// visible sheet — the running cycle is id 0; a finished previous month keeps
// its real id and its submission status. Shape from a live 2026-08 capture.
let multiCycleJSON = data("""
{"employeeTimesheets":[
 {"id":0,"cycleStartDate":"2026-08-01","cycleEndDate":"2026-08-31",
  "timesheetState":{"timeSheetStatus":"Open","lockAt":1790373600000,"locked":false}},
 {"id":14068479,"cycleId":744445,"cycleStartDate":"2026-07-01","cycleEndDate":"2026-07-31",
  "timesheetState":{"timeSheetStatus":"WaitingForSubmission","lockAt":1787695200000,"locked":false}}]}
""")
let cycles = BobParsing.cycles(fromTimesheetsJSON: multiCycleJSON)
expect(cycles.count == 2, "both sheets decoded")
expect(cycles[0].id == 0 && cycles[0].status == "Open", "running sheet first, status Open")
expect(cycles[1].id == 14068479 && cycles[1].status == "WaitingForSubmission",
       "past sheet keeps its id + submission status")
expect(BobParsing.cycle(fromTimesheetsJSON: multiCycleJSON)?.id == 0,
       "current-cycle helper still returns the first sheet")
expect(BobParsing.lastClosedCycle(cycles, today: "2026-08-03")?.id == 14068479,
       "last closed cycle = the July sheet once August runs")
expect(BobParsing.lastClosedCycle(cycles, today: "2026-07-15") == nil,
       "no closed cycle while its month is still running")
expect(BobParsing.lastClosedCycle(BobParsing.cycles(fromTimesheetsJSON: timesheetsJSON),
                                  today: "2026-07-15") == nil,
       "single open sheet → no past cycle")
expect(BobParsing.cycles(fromTimesheetsJSON: data("{}")).isEmpty, "empty JSON → no cycles")
expect(cycles[1].awaitsSubmission, "WaitingForSubmission + unlocked → awaits submission")

// After the sheet is submitted it stays in the list, pending approval —
// shape from the live post-submit capture (2026-08-03).
let submittedJSON = data("""
{"employeeTimesheets":[
 {"id":14068479,"cycleStartDate":"2026-07-01","cycleEndDate":"2026-07-31",
  "timesheetState":{"timeSheetStatus":"Submitted","lockAt":1787695200000,"locked":false,
   "submittedBy":"3778865480379401034","submittedOn":"2026-08-03T11:44:33.391252"}}]}
""")
let submitted = BobParsing.cycles(fromTimesheetsJSON: submittedJSON).first
expect(submitted?.pendingApproval == true && submitted?.awaitsSubmission == false,
       "Submitted sheet → pending approval, no longer submittable")
expect(submitted?.submittedOn == "2026-08-03", "submittedOn trimmed to its day")

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

// MARK: - fillingGapBeforeClockIn (fill the hole a late clock-in leaves behind)

print("AttendanceLogic.fillingGapBeforeClockIn")

if let fixed = AttendanceLogic.fillingGapBeforeClockIn(
        entries: [work(9, 13.667), brk(13.667, 14.167), work(14.333, nil)]) {
    expect(fixed[1].end == t(14.333), "hole after a break → break stretches to the clock-in")
    expect(fixed[1].start == t(13.667), "break start untouched")
    expect(fixed[2].start == t(14.333) && fixed[2].end == nil, "open work entry untouched")
} else {
    expect(false, "10-minute hole after a break → fix")
}

if let fixed = AttendanceLogic.fillingGapBeforeClockIn(
        entries: [work(9, 14), work(15, nil)]) {
    expect(fixed.count == 3, "hole after work → a break is inserted")
    expect(fixed[1].kind == .breakTime && fixed[1].start == t(14) && fixed[1].end == t(15),
           "inserted break covers the hole exactly")
    expect(fixed[2].start == t(15) && fixed[2].end == nil, "open work entry untouched")
} else {
    expect(false, "1-hour hole after work → fix")
}

expect(AttendanceLogic.fillingGapBeforeClockIn(
        entries: [work(9, 12), brk(12, 12.5), work(12.5083, nil)]) == nil,
       "sub-minute hole → left alone")
expect(AttendanceLogic.fillingGapBeforeClockIn(
        entries: [work(9, 12), brk(12, 12.5), work(12.75, 16)]) == nil,
       "closed last entry → nothing to fix")
expect(AttendanceLogic.fillingGapBeforeClockIn(
        entries: [work(9, 12), brk(12, 12.5), brk(12.75, nil)]) == nil,
       "open break, not a clock-in → nothing to fix")
expect(AttendanceLogic.fillingGapBeforeClockIn(entries: [work(9, nil)]) == nil,
       "first clock-in of the day → nothing to fix")

// MARK: - Fmt.parseClock (hand-typed time text)

print("Fmt.parseClock")
expect(Fmt.parseClock("14:30")! == (14, 30), "HH:MM")
expect(Fmt.parseClock("1")! == (1, 0), "bare hour digit")
expect(Fmt.parseClock("01")! == (1, 0), "zero-padded hour")
expect(Fmt.parseClock("930")! == (9, 30), "three digits → H:MM")
expect(Fmt.parseClock("0930")! == (9, 30), "four digits → HH:MM")
expect(Fmt.parseClock("9:5")! == (9, 5), "single-digit minutes")
expect(Fmt.parseClock("14.30")! == (14, 30), "dot separator")
expect(Fmt.parseClock(" 8:15 ")! == (8, 15), "surrounding whitespace")
expect(Fmt.parseClock("2:20 pm")! == (14, 20), "pm shifts the hour")
expect(Fmt.parseClock("12am")! == (0, 0), "12am → midnight")
expect(Fmt.parseClock("12pm")! == (12, 0), "12pm → noon")
expect(Fmt.parseClock("24:00") == nil, "hour out of range → nil")
expect(Fmt.parseClock("12:60") == nil, "minutes out of range → nil")
expect(Fmt.parseClock("12:") == nil, "dangling separator → nil")
expect(Fmt.parseClock("abc") == nil, "letters → nil")
expect(Fmt.parseClock("") == nil, "empty → nil")
expect(Fmt.parseClock("12345") == nil, "too many digits → nil")

// MARK: - WidgetSnapshot

print("AttendanceLogic.widgetSnapshot")

let snapWorking = AttendanceLogic.widgetSnapshot(
    entries: [work(9, nil)], signedIn: true, target: sixH, breakEnds: nil,
    breakDue: t(15), now: t(11))
expect(snapWorking.state == .working, "working: state")
expect(snapWorking.stretchStart == t(9), "working: timer anchors at stretch start")
expect(abs(snapWorking.workedBase) < 1, "working: base excludes the open stretch")
expect(abs(snapWorking.workedTotal(now: t(11)) - 2 * 3600) < 1, "working: total = base + elapsed")
expect(snapWorking.breakDue == t(15), "working: carries the auto-break due time")
expect(snapWorking.doneBy(now: t(11)) == t(15), "working: done-by = now + remaining")

// The owed auto-break delays done-by only when it fires before the naive
// finish — a break due after you'd already be done can't push anything out.
var snapOwed = snapWorking
snapOwed.pendingBreak = 1800
snapOwed.breakDue = t(13)
expect(snapOwed.doneBy(now: t(11)) == t(15.5), "working: owed break firing first delays done-by")
snapOwed.breakDue = t(16)
expect(snapOwed.doneBy(now: t(11)) == t(15), "working: break due after the finish changes nothing")

// The strip's overtime rule: the scale pins to the moment the target was met.
let metSegs = [WidgetSnapshot.Segment(start: t(9), end: t(12), isBreak: false),
               WidgetSnapshot.Segment(start: t(12), end: t(12.5), isBreak: true),
               WidgetSnapshot.Segment(start: t(12.5), end: nil, isBreak: false)]
expect(WidgetSnapshot.targetMetAt(segments: metSegs, target: sixH, openEnd: t(17)) == t(15.5),
       "target met mid-open-stretch: 3h + 3h more lands at 15:30")
expect(WidgetSnapshot.targetMetAt(segments: metSegs, target: 9 * 3600, openEnd: t(17)) == nil,
       "target not yet met: nil")
expect(WidgetSnapshot.targetMetAt(segments: metSegs, target: 0, openEnd: t(17)) == nil,
       "no target: nil")

let snapBreak = AttendanceLogic.widgetSnapshot(
    entries: [work(9, 12), brk(12, nil)], signedIn: true, target: sixH,
    breakEnds: t(12.5), now: t(12.25))
expect(snapBreak.state == .onBreak, "break: state")
expect(snapBreak.stretchStart == nil, "break: no ticking timer")
expect(abs(snapBreak.workedBase - 3 * 3600) < 1, "break: base is worked-so-far")
expect(snapBreak.breakEnds == t(12.5), "break: carries the auto-break end")
expect(snapBreak.segments.count == 2, "break: carries today's timeline blocks")
expect(snapBreak.segments.last?.isBreak == true, "break: open block flagged as break")
expect(snapBreak.segments.last?.end == nil, "break: open block has no end")

let snapOut = AttendanceLogic.widgetSnapshot(
    entries: [work(9, 12)], signedIn: true, target: sixH, breakEnds: nil, now: t(14))
expect(snapOut.state == .clockedOut, "out: state")
expect(abs(snapOut.workedTotal(now: t(14)) - 3 * 3600) < 1, "out: total frozen")

let snapSignedOut = AttendanceLogic.widgetSnapshot(
    entries: [], signedIn: false, target: sixH, breakEnds: nil, now: t(10))
expect(snapSignedOut.state == .signedOut, "signed out: state")

print("AttendanceLogic.weekFractions")

// The test anchor (2026-07-16) is a Thursday; its ISO week runs Mon 13th – Sun 19th.
let weekDays = [
    DayHours(date: "2026-07-13", worked: 8, target: 8, overtime: nil),   // Monday, full
    DayHours(date: "2026-07-13", worked: 0, target: 8, overtime: nil),   // duplicate row, empty
    DayHours(date: "2026-07-14", worked: 10, target: 8, overtime: nil),  // Tuesday, over target
    DayHours(date: "2026-07-16", worked: 4, target: 8, overtime: nil),   // Thursday, half
    DayHours(date: "2026-07-12", worked: 8, target: 8, overtime: nil),   // Sunday before — other week
    DayHours(date: "2026-07-18", worked: 3, target: 8, overtime: nil),   // Saturday — not a bar
]
let fractions = AttendanceLogic.weekFractions(days: weekDays, today: t(10))
expect(fractions.count == 5, "week: five bars Mon-Fri")
expect(abs(fractions[0] - 1) < 0.01, "week: Monday full — duplicate empty row can't erase it")
expect(abs(fractions[1] - 1.25) < 0.01, "week: over-target day keeps its overshoot")
expect(abs(fractions[3] - 0.5) < 0.01, "week: Thursday half")
expect(fractions[2] == 0 && fractions[4] == 0, "week: unworked days empty")

print("AttendanceLogic.weekProgress")

// Same anchor: Thursday the 16th, so Mon–Wed are done and Friday is still ahead.
let progressDays = [
    DayHours(date: "2026-07-13", worked: 8, target: 8, overtime: nil),   // Monday
    DayHours(date: "2026-07-13", worked: 0, target: 8, overtime: nil),   // duplicate, empty
    DayHours(date: "2026-07-14", worked: 9, target: 8, overtime: nil),   // Tuesday
    DayHours(date: "2026-07-15", worked: 7, target: 8, overtime: nil),   // Wednesday
    DayHours(date: "2026-07-16", worked: 1, target: 8, overtime: nil),   // today, stale row
    DayHours(date: "2026-07-17", worked: 0, target: 8, overtime: nil),   // Friday, to come
    DayHours(date: "2026-07-18", worked: 0, target: nil, overtime: nil), // Saturday, no target
    DayHours(date: "2026-07-12", worked: 8, target: 8, overtime: nil),   // last week
]
let wp = AttendanceLogic.weekProgress(days: progressDays, workedToday: 4 * 3600,
                                      todayTarget: 8 * 3600, now: t(14))
expect(abs(wp.target - 40 * 3600) < 1, "week: target sums this week's days only")
expect(abs(wp.worked - 28 * 3600) < 1, "week: today's live total beats the sheet's stale row")
expect(abs(wp.remaining - 12 * 3600) < 1, "week: remaining is target minus worked")
expect(wp.daysToGo == 1, "week: one working day left after today")
expect(!wp.met && wp.hasTarget && !wp.partial, "week: short of target, whole week covered")

// On the Friday (t(38)), so the only days left are the weekend — nothing ahead
// to fill, and three ten-hour days have already banked the week.
let wpOver = AttendanceLogic.weekProgress(
    days: [DayHours(date: "2026-07-13", worked: 10, target: 8, overtime: nil),
           DayHours(date: "2026-07-14", worked: 10, target: 8, overtime: nil),
           DayHours(date: "2026-07-15", worked: 10, target: 8, overtime: nil)],
    workedToday: 2 * 3600, todayTarget: 4 * 3600, now: t(38))
expect(wpOver.met, "week: past the target reads as met")
expect(abs(wpOver.over - 4 * 3600) < 1, "week: overshoot named")
expect(wpOver.remaining == 0, "week: nothing left once met")
expect(abs(wpOver.fraction - 1) < 0.001, "week: bar caps at full")
expect(wpOver.daysToGo == 0, "week: the weekend isn't a day to go")

// A sheet that stops stating targets after today: weekdays ahead take the
// week's typical day, so "left this week" still means something. The weekend
// stays empty, and the whole thing is flagged as an estimate.
let wpTruncated = AttendanceLogic.weekProgress(
    days: [DayHours(date: "2026-07-13", worked: 8, target: 8, overtime: nil),
           DayHours(date: "2026-07-14", worked: 8, target: 8, overtime: nil),
           DayHours(date: "2026-07-15", worked: 8, target: 8, overtime: nil),
           DayHours(date: "2026-07-16", worked: 0, target: nil, overtime: nil),
           DayHours(date: "2026-07-17", worked: 0, target: nil, overtime: nil),
           DayHours(date: "2026-07-18", worked: 0, target: nil, overtime: nil)],
    workedToday: 2 * 3600, todayTarget: 8 * 3600, now: t(14))
expect(wpTruncated.estimated, "week: silent days ahead are flagged as estimated")
expect(abs(wpTruncated.target - 40 * 3600) < 1, "week: Friday filled with the typical day, Saturday not")
expect(wpTruncated.daysToGo == 1, "week: only the filled weekday is a day to go")

// A short Friday: the sheet states no target for the coming one, but earlier
// Fridays in the cycle do — the fill is that weekday's own 6.5h, not the
// week's 8h average, so a 38.5h week reads as 38.5h.
let wpShortFriday = AttendanceLogic.weekProgress(
    days: [DayHours(date: "2026-07-03", worked: 6.5, target: 6.5, overtime: nil), // earlier Friday
           DayHours(date: "2026-07-10", worked: 6.5, target: 6.5, overtime: nil), // earlier Friday
           DayHours(date: "2026-07-13", worked: 8, target: 8, overtime: nil),
           DayHours(date: "2026-07-14", worked: 8, target: 8, overtime: nil),
           DayHours(date: "2026-07-15", worked: 8, target: 8, overtime: nil),
           DayHours(date: "2026-07-16", worked: 0, target: 8, overtime: nil),
           DayHours(date: "2026-07-17", worked: 0, target: nil, overtime: nil)],   // Friday, silent
    workedToday: 4 * 3600, todayTarget: 8 * 3600, now: t(14))
expect(abs(wpShortFriday.target - 38.5 * 3600) < 1, "week: a silent Friday is filled from earlier Fridays")
expect(abs(wpShortFriday.remaining - 10.5 * 3600) < 1, "week: 28h in, 10h 30m to go")
expect(wpShortFriday.estimated, "week: still an estimate, even a well-informed one")

let wpDayOff = AttendanceLogic.weekProgress(
    days: [DayHours(date: "2026-07-13", worked: 8, target: 8, overtime: nil),
           DayHours(date: "2026-07-17", worked: 0, target: 0, overtime: nil)],
    workedToday: 4 * 3600, todayTarget: 8 * 3600, now: t(14))
expect(!wpDayOff.estimated, "week: a stated zero ahead is a booked day off, not a gap")
expect(wpDayOff.daysToGo == 0, "week: a day off isn't a day to go")
expect(abs(wpDayOff.target - 16 * 3600) < 1, "week: the day off adds nothing to the target")

let wpPartial = AttendanceLogic.weekProgress(
    days: [DayHours(date: "2026-07-16", worked: 0, target: 8, overtime: nil)],
    workedToday: 3 * 3600, todayTarget: 8 * 3600, now: t(14))
expect(wpPartial.partial, "week: earlier days missing from the sheet flag a cycle boundary")
expect(abs(wpPartial.worked - 3 * 3600) < 1, "week: a partial week counts what it has")

expect(!AttendanceLogic.weekProgress(days: [], workedToday: 0, todayTarget: 0,
                                     now: t(14)).hasTarget,
       "week: no target without cycle data")

print("AttendanceLogic.nextBackgroundRefresh")

expect(AttendanceLogic.nextBackgroundRefresh(now: t(10), breakDue: nil) == t(10).addingTimeInterval(15 * 60),
       "no break due: default cadence")
expect(AttendanceLogic.nextBackgroundRefresh(now: t(10), breakDue: t(10.1)) == t(10.1),
       "break due inside the window: wake exactly then")
expect(AttendanceLogic.nextBackgroundRefresh(now: t(10), breakDue: t(10).addingTimeInterval(10)) == t(10).addingTimeInterval(60),
       "break due immediately: never sooner than a minute out")
expect(AttendanceLogic.nextBackgroundRefresh(now: t(10), breakDue: t(12)) == t(10).addingTimeInterval(15 * 60),
       "break due far out: default cadence wins")

// MARK: - suggestedEnd (smart default when closing a forgotten open entry)

print("AttendanceLogic.suggestedEnd")

// A UTC calendar so time-of-day math matches the UTC test anchor regardless
// of the machine's zone.
var utcCal = Calendar(identifier: .gregorian); utcCal.timeZone = utc

// lastCheckoutSeconds: end of the day's latest closed work entry, as
// seconds-since-midnight.
expect(AttendanceLogic.lastCheckoutSeconds(entries: [work(9, 17)], calendar: utcCal) == 17 * 3600,
       "checkout secs: single closed day")
expect(AttendanceLogic.lastCheckoutSeconds(entries: [work(9, 12), brk(12, 12.5), work(12.5, 17.5)], calendar: utcCal) == 17.5 * 3600,
       "checkout secs: latest work end wins")
expect(AttendanceLogic.lastCheckoutSeconds(entries: [work(9, nil)], calendar: utcCal) == nil,
       "checkout secs: open day → nil")
expect(AttendanceLogic.lastCheckoutSeconds(entries: [], calendar: utcCal) == nil,
       "checkout secs: empty day → nil")

// Usual check-out: median of three closed days (17, 17.5, 18) → 17.5, placed
// on the open entry's own day even though `now` is far past it.
let history3 = [[work(9, 17)], [work(9, 17.5)], [work(9, 18)]]
expect(AttendanceLogic.suggestedEnd(entryStart: t(9), history: history3, target: sixH,
                                    now: t(30), calendar: utcCal) == t(17.5),
       "usual check-out: median of recent days on the entry's day")

// Fewer than the minimum samples → fall through to target fill.
expect(AttendanceLogic.suggestedEnd(entryStart: t(9), history: [[work(9, 17)], [work(9, 18)]],
                                    target: sixH, now: t(30), calendar: utcCal) == t(15),
       "too little history → fill to target (9 + 6h)")

// Enough history but the usual check-out is before this entry's start →
// skip it and fill to target instead.
expect(AttendanceLogic.suggestedEnd(entryStart: t(19), history: history3, target: sixH,
                                    now: t(30), calendar: utcCal) == t(25),
       "usual check-out before start → fall through to target")

// No history and no target → current time-of-day on the entry's own day.
expect(AttendanceLogic.suggestedEnd(entryStart: t(9), history: [], target: nil,
                                    now: t(24 + 16), calendar: utcCal) == t(16),
       "no habit, no target → now's time-of-day on the entry's day")

// Nothing usable and now is before the start → clamp to the start.
expect(AttendanceLogic.suggestedEnd(entryStart: t(20), history: [], target: nil,
                                    now: t(24 + 8), calendar: utcCal) == t(20),
       "no habit/target and now-of-day before start → clamp to start")

// MARK: - Weekly rhythm (check-in / check-out by weekday)

print("AttendanceLogic.weekdayRhythm")

expect(AttendanceLogic.firstCheckinSeconds(entries: [work(9, 12), work(13, 17)], calendar: utcCal) == 9 * 3600,
       "checkin secs: earliest work start")
expect(AttendanceLogic.firstCheckinSeconds(entries: [], calendar: utcCal) == nil,
       "checkin secs: empty → nil")

// 2026-07-13 is a Monday, -14 Tuesday. Two Mondays average their in/out.
let facts = [
    DayFact(date: "2026-07-13", inSec: 9 * 3600, outSec: 17 * 3600),   // Mon
    DayFact(date: "2026-07-20", inSec: 10 * 3600, outSec: 18 * 3600),  // Mon
    DayFact(date: "2026-07-14", inSec: 8 * 3600, outSec: 16 * 3600),   // Tue
]
// Default (.current) calendar — matches DayFmt's own zone, so the weekday of
// a calendar date is read consistently regardless of the machine's timezone.
let rhythm = AttendanceLogic.weekdayRhythm(facts: facts)
expect(rhythm.count == 2, "rhythm: two weekdays present")
expect(rhythm[0].weekday == 0 && rhythm[0].count == 2, "rhythm: Monday first, two samples")
expect(rhythm[0].avgIn == 9.5 * 3600 && rhythm[0].avgOut == 17.5 * 3600, "rhythm: Monday averages")
expect(rhythm[1].weekday == 1 && rhythm[1].avgIn == 8 * 3600, "rhythm: Tuesday single sample")

// suggestedEnd from pre-extracted samples (the store-fed path).
expect(AttendanceLogic.suggestedEnd(entryStart: t(9), checkoutSamples: [17 * 3600, 17.5 * 3600, 18 * 3600],
                                    target: sixH, now: t(30), calendar: utcCal) == t(17.5),
       "suggestedEnd(samples): median check-out on the entry's day")
expect(AttendanceLogic.suggestedEnd(entryStart: t(9), checkoutSamples: [],
                                    target: sixH, now: t(30), calendar: utcCal) == t(15),
       "suggestedEnd(samples): no samples → fill to target")

// MARK: - DayHistory store (rolling, capped, upsert-by-date)

print("DayHistory")

let hDefaults = UserDefaults(suiteName: "test.dayhistory")!
hDefaults.removePersistentDomain(forName: "test.dayhistory")
DayHistory.merge([DayFact(date: "2026-07-13", inSec: 9 * 3600, outSec: 17 * 3600)], into: hDefaults)
DayHistory.merge([DayFact(date: "2026-07-13", inSec: 8 * 3600, outSec: 16 * 3600),   // refine same day
                  DayFact(date: "2026-07-14", inSec: 9 * 3600, outSec: 18 * 3600)], into: hDefaults)
let stored = DayHistory.load(hDefaults)
expect(stored.count == 2, "history: two distinct days")
expect(stored.first(where: { $0.date == "2026-07-13" })?.inSec == 8 * 3600,
       "history: same-date merge refines the record")
expect(stored.map(\.date) == ["2026-07-13", "2026-07-14"], "history: kept chronological")
hDefaults.removePersistentDomain(forName: "test.dayhistory")

// MARK: - Summary

print("")
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

// MARK: - The hero's water

print("WaveField")

let card = CGRect(x: 0, y: 0, width: 300, height: 150)
let still = WaveField(level: 0.5, amplitude: 0, phase: 0)
expect(still.polyline(in: card).allSatisfy { abs($0.x - 150) < 0.001 },
       "amplitude 0 → a dead straight waterline")
expect(still.polyline(in: card).first?.y == 0
        && still.polyline(in: card).last?.y == card.height,
       "the waterline spans the full height, both ends included")
let brimming = WaveField(level: 1, amplitude: 14, phase: 0.7)
expect(brimming.polyline(in: card).allSatisfy { $0.x <= 300.001 },
       "a brimming tank's wave can't push past the far wall")
let choppy = WaveField(level: 0.5, amplitude: 9, phase: 0.4,
                       freq: 2.2, asymPhase: 1.2, detail2: 1.1, detail3: 2.4)
// What a float feels is the wave itself: a crest is deeper water, so it carries
// the float toward the far wall.
expect(abs(choppy.ride(at: 0.3, height: 150).drift - choppy.wave(at: 0.3)) < 0.001,
       "a float's drift is the wave's own displacement")
expect(still.ride(at: 0.3, height: 150).slope == 0, "a still surface leans nothing")
// The light band under the waterline runs on its own wave — shallower, slower
// and out of step, so it never reads as a traced outline.
expect(choppy.parallel.amplitude < choppy.amplitude
        && choppy.parallel.freq < choppy.freq
        && choppy.parallel.phase != choppy.phase,
       "the edge light's wave parallels the surface without copying it")

// MARK: - Assisted sign-in page driver
//
// The driver is JavaScript evaluated inside the hidden web view, so it is
// tested the same way: run it against a stub DOM in JavaScriptCore and check
// which step it reports and which buttons it presses. Elements declare the
// CSS selectors they answer to rather than being matched for real — enough
// to pin the step classification, which is where the flow goes wrong.

print("SSO page driver")

/// One stub element: `sel` are the selector fragments it matches.
struct StubEl {
    var sel: [String]
    var text: String = ""
    var value: String = ""
}

/// Run `ticks` iterations of the driver over a stub page (the driver counts
/// ticks in page globals) and return the last step token plus every label it
/// clicked along the way.
func runDriver(_ els: [StubEl], body: String, host: String = "team-blue.okta.com",
               factor: SignInFactor, allowBack: Bool = true, probeTicks: Int = 4,
               picked: Bool = false, ticks: Int = 6) -> (step: String, clicks: [String], raw: String) {
    let ctx = JSContext()!
    ctx.exceptionHandler = { _, err in
        print("  JS exception: \(err?.toString() ?? "?")")
    }
    let elementsJSON = String(data: try! JSONEncoder().encode(
        els.map { ["sel": $0.sel.joined(separator: "\u{1}"), "text": $0.text, "value": $0.value] }
    ), encoding: .utf8)!
    ctx.evaluateScript("""
    var clicks = [];
    var location = { hostname: \(String(data: try! JSONEncoder().encode(host), encoding: .utf8)!),
                     pathname: '/signin' };
    function mkEl(spec) {
      var el = {
        sel: spec.sel.split('\\u0001'),
        textContent: spec.text, value: spec.value,
        disabled: false, offsetParent: {},
        click: function(){ clicks.push((this.textContent || this.value || '').trim()); },
        focus: function(){}, dispatchEvent: function(){ return true; },
        closest: function(){ return null; }, parentElement: null
      };
      return el;
    }
    var els = \(elementsJSON).map(mkEl);
    function matches(el, selector) {
      return selector.split(',').some(function(part){
        return el.sel.indexOf(part.trim()) >= 0;
      });
    }
    var document = {
      body: { innerText: \(String(data: try! JSONEncoder().encode(body), encoding: .utf8)!) },
      querySelector: function(s){
        var hit = els.filter(function(e){ return matches(e, s); });
        return hit.length ? hit[0] : null;
      },
      querySelectorAll: function(s){
        return els.filter(function(e){ return matches(e, s); });
      }
    };
    var window = { HTMLInputElement: { prototype: {} } };
    function Event(){}; function KeyboardEvent(){};
    \(picked ? "window.__bbFactorPicked = true;" : "")
    """)
    let script = SSOSignInController.autofillScript(
        email: "kevin@team.blue", password: "hunter2", otp: "",
        factor: factor, click: true, allowBack: allowBack, probeTicks: probeTicks)
    var raw = ""
    for _ in 0..<ticks {
        raw = ctx.evaluateScript(script)?.toString() ?? ""
    }
    let clicks = ctx.objectForKeyedSubscript("clicks").toArray() as? [String] ?? []
    return (raw.components(separatedBy: "||").first ?? "", clicks, raw)
}

// Okta's push-wait screen: no fields, and the copy says the push went out.
// It reaches this screen without the driver ever clicking a chooser row when
// push is the account's only enrolled method.
let pushWait = runDriver([
    StubEl(sel: ["button", "[role=button]"], text: "Resend push notification"),
    StubEl(sel: ["a", "button", "[role=button]"], text: "Verify with something else"),
    StubEl(sel: ["a", "button", "[role=button]"], text: "Back to sign in"),
], body: "Push notification sent. Open Okta Verify on your iPhone and tap Yes, it's me.",
   factor: .oktaVerifyPush)
expect(pushWait.step == "push",
       "a push-sent screen reads as 'push' even without a chooser click")
expect(!pushWait.clicks.contains("Back to sign in"),
       "the driver never clicks Back to sign in while a push is out")
expect(pushWait.clicks.isEmpty,
       "the driver presses nothing at all on the push-wait screen")

// The chooser must keep classifying as 'select' even once a factor has been
// picked once — newer Okta widgets show a second method screen, and calling
// that 'push' would strand the flow with nothing left to click it forward.
let chooser = runDriver([
    StubEl(sel: ["a", "button", "[role=button]"], text: "Get a push notification"),
    StubEl(sel: ["a", "button", "[role=button]"], text: "Enter a code"),
], body: "Verify it's you with a security method. Select from the following options.",
   factor: .oktaVerifyPush, picked: true)
expect(chooser.step == "select", "the method chooser stays 'select' after an earlier pick")
expect(chooser.clicks.contains("Get a push notification"),
       "the chooser's push row gets picked")

// Okta bouncing back to the chooser is the stuck case: a verification that
// never completed — the Okta Verify app on this Mac popping a fingerprint
// prompt the hidden web view can't finish — returns to the very page the row
// was picked from, in the SAME document. The per-choice guard still holds that
// row's signature, so nothing clicks it forward and the flow dies there. The
// guard has to expire.
let bouncedRows = [
    StubEl(sel: ["a", "button", "[role=button]"], text: "Select Okta Verify push"),
    StubEl(sel: ["a", "button", "[role=button]"], text: "Select Google Authenticator"),
]
let bouncedBody = "Verify it's you with a security method. Select from the following options."
expect(runDriver(bouncedRows, body: bouncedBody, factor: .oktaVerifyPush, ticks: 4)
        .clicks.count == 1,
       "a freshly picked row isn't picked again while the click is still landing")
expect(runDriver(bouncedRows, body: bouncedBody, factor: .oktaVerifyPush, ticks: 20)
        .clicks.count == 2,
       "a chooser still sitting there ~20s later gets its row picked again")
// While it sits, the driver says it's waiting on the authenticator rather than
// still choosing one — a FastPass prompt has no page of its own to show.
expect(runDriver(bouncedRows, body: bouncedBody, factor: .oktaVerifyPush, ticks: 4)
        .raw.contains("waiting"),
       "a picked row that's still on screen reports waiting, not choosing")
expect(!runDriver(bouncedRows, body: bouncedBody, factor: .oktaVerifyPush, ticks: 1)
        .raw.contains("waiting"),
       "the tick that does the picking doesn't claim to be waiting yet")
expect(runDriver(bouncedRows, body: bouncedBody, factor: .oktaVerifyPush, ticks: 60)
        .clicks.count == 3,
       "re-picks are capped — a chooser that never advances can't spray pushes")
// Never re-pick while the page itself says a push is already out, though:
// that's how the flow used to send a second one and kill the first.
expect(runDriver(bouncedRows,
                 body: bouncedBody + " Push notification sent. Open Okta Verify.",
                 factor: .oktaVerifyPush, ticks: 20).clicks.count == 1,
       "a chooser page that also says a push went out is left alone")

// Okta Identity Engine's first chooser lists authenticators by NAME — only a
// second screen names push vs code — so a push run has to be willing to click a
// row that says nothing about pushes. This is the page the first sign-in on a
// Mac with Okta Verify installed dies on.
let nameOnlyRows = [
    StubEl(sel: ["a", "button", "[role=button]"], text: "Back to login"),
    StubEl(sel: ["a", "button", "[role=button]"], text: "Okta Verify"),
    StubEl(sel: ["a", "button", "[role=button]"], text: "Google Authenticator"),
    StubEl(sel: ["a", "button", "[role=button]"], text: "Security Key or Biometric"),
]
let nameOnlyBody = "Verify it's you with a security method. Select from the following options."
let byName = runDriver(nameOnlyRows, body: nameOnlyBody, factor: .oktaVerifyPush, ticks: 3)
expect(byName.clicks == ["Okta Verify"],
       "a push run picks the bare 'Okta Verify' row on a name-only chooser")
expect(byName.raw.contains("rows:") && byName.raw.contains("Google Authenticator"),
       "the chooser reports the rows Okta offered, so a dead end can name them")
// Reported among the offered rows (it is, after all, what Okta listed) but
// never clickable — biometric rows can't be driven from a hidden web view.
expect(runDriver([
    StubEl(sel: ["a", "button", "[role=button]"], text: "Security Key or Biometric"),
], body: nameOnlyBody, factor: .oktaVerifyPush, ticks: 20).clicks.isEmpty,
       "a security-key row is never clicked")
expect(runDriver(nameOnlyRows, body: nameOnlyBody, factor: .googleAuthenticator, ticks: 3)
        .clicks == ["Google Authenticator"],
       "a Google Authenticator run picks its own row from the same chooser")
expect(runDriver(nameOnlyRows, body: nameOnlyBody, factor: .oktaVerifyCode, ticks: 3)
        .clicks == ["Okta Verify"],
       "an Okta Verify code run goes through the same row, then the method screen")
// The method screen: no authenticator name on the rows, just the two ways.
let methodRows = [
    StubEl(sel: ["a", "button", "[role=button]"], text: "Get a push notification"),
    StubEl(sel: ["a", "button", "[role=button]"], text: "Enter a code"),
]
expect(runDriver(methodRows, body: nameOnlyBody, factor: .oktaVerifyCode, ticks: 3)
        .clicks == ["Enter a code"],
       "the code run takes 'Enter a code' on the method screen")
expect(runDriver(methodRows, body: nameOnlyBody, factor: .oktaVerifyPush, ticks: 3)
        .clicks == ["Get a push notification"],
       "the push run takes the push row on the method screen")
// A chooser with no row for the requested factor must click nothing at all —
// picking a method the user didn't ask for would strand them worse — and must
// say so, which is what raises the banner instead of a line of fine print.
let noRowForPush = runDriver([
    StubEl(sel: ["a", "button", "[role=button]"], text: "Google Authenticator"),
], body: nameOnlyBody, factor: .oktaVerifyPush, ticks: 20)
expect(noRowForPush.clicks.isEmpty,
       "a chooser without an Okta Verify row is left untouched on a push run")
expect(noRowForPush.raw.contains("nopick"),
       "and reports that the requested method had no row")
expect(!byName.raw.contains("nopick"),
       "a chooser that does have the row reports no such thing")

// Okta's hand-off after a successful verification: fieldless, its copy still
// mentions the authenticator, but the only button is a "Yes"-ish one. It reads
// as 'select' — and must NOT be reported as a chooser, or the status line calls
// a successful sign-in "Choosing your authenticator" and the banner fires on it.
let handoff = runDriver([
    StubEl(sel: ["button", "[role=button]"], text: "Yes, keep me signed in"),
], body: "Verify it's you. Your authenticator confirmed the sign-in. One moment…",
   factor: .oktaVerifyPush, ticks: 8)
expect(handoff.raw.contains("norows") && !handoff.raw.contains("nopick"),
       "a page with no method rows is reported as no chooser, not a failed pick")
expect(!handoff.raw.contains("rows:"),
       "and it offers no method rows to name")

// A chooser that merely MENTIONS Okta's device flow is still a chooser. Naming
// FastPass as a step token instead of a marker stranded exactly this page: the
// row branch never ran, so nothing was ever clicked.
let fastPassChooser = runDriver([
    StubEl(sel: ["a", "button", "[role=button]"], text: "Use a push notification"),
    StubEl(sel: ["a", "button", "[role=button]"], text: "Google Authenticator"),
], body: "Verify it's you with a security method. Okta FastPass. Select from the following options.",
   factor: .googleAuthenticator, ticks: 3)
expect(fastPassChooser.step == "select",
       "a chooser naming FastPass still classifies as the chooser")
expect(fastPassChooser.clicks == ["Google Authenticator"],
       "and its Google row still gets picked")

// The FastPass probe — fieldless, naming Okta's own device flow. Without Okta
// Verify installed nothing can ever resolve it, so it's escaped via its own
// Back link (which some tenants label "Back to login").
let fastPass = runDriver([
    StubEl(sel: ["a", "button", "[role=button]"], text: "Back to login"),
], body: "Signing in with Okta FastPass", factor: .oktaVerifyPush)
expect(fastPass.step == "loading" && fastPass.raw.contains("fastpass"),
       "the probe stays a 'loading' step, with FastPass reported as a marker")
expect(fastPass.clicks.contains("Back to login"),
       "the driver escapes the FastPass probe once it stalls")
expect(runDriver([
    StubEl(sel: ["a", "button", "[role=button]"], text: "Back to login"),
], body: "Signing in with Okta FastPass", factor: .oktaVerifyPush,
   allowBack: false).clicks.isEmpty,
       "past the identifier stage the Back link is left alone")
// With Okta Verify installed the probe is live — it raises a Touch ID prompt —
// so the escape waits it out instead of cancelling the approval in progress.
expect(runDriver([
    StubEl(sel: ["a", "button", "[role=button]"], text: "Back to login"),
], body: "Signing in with Okta FastPass", factor: .oktaVerifyPush,
   probeTicks: 28, ticks: 20).clicks.isEmpty,
       "a live FastPass probe isn't clicked away while Okta Verify is prompting")
expect(runDriver([
    StubEl(sel: ["a", "button", "[role=button]"], text: "Back to login"),
], body: "Signing in with Okta FastPass", factor: .oktaVerifyPush,
   probeTicks: 28, ticks: 30).clicks == ["Back to login"],
       "…but a probe that never resolves is still escaped, once")

if failures == 0 {
    print("All tests passed.")
} else {
    print("\(failures) test(s) FAILED.")
    exit(1)
}
