# HiBob internal API — capture & verify

BetterBob talks to the same **internal web API** the HiBob single-page app
uses (`https://app.hibob.com/api/...`), authenticated with your own session
cookie — captured via the embedded browser sign-in (SSO/Okta) or a plain
email+password login where the tenant allows it. These routes are
**unofficial and undocumented** — the paths in
`Sources/Services/BobClient.swift` (`BobAPI`) are educated defaults and must
be verified against your tenant once.

## How to capture

1. Open Chrome/Safari DevTools → **Network** tab, filter **Fetch/XHR**.
2. Log in at `app.hibob.com` and open the **Attendance / Time & Attendance**
   page. Note every `api/...` request that fires on its own — one of them
   returns **today's entries**.
3. Click each button once and note the request it fires
   (method + URL + request body + response):
   - **Clock in**
   - **Clock out**
   - **Start break** / **End break**
   - Change an entry's **Reason** (In Office / Work From Home)
   - Add or edit a past entry (the "Quick Fix" flow) — this is the route
     used for retroactive break insertion
4. Also grab the request that returns the **Reason dropdown options**, and
   whichever early request contains your **employee id** (usually a
   `user`/`me`-style call).

Redact cookies/tokens before sharing captures anywhere. The interesting
parts are only: method, URL path, request JSON body, response JSON shape.

## Where each route lives in code

| Purpose            | `BobAPI` member    | Current default (verify!)                          |
| ------------------ | ------------------ | -------------------------------------------------- |
| Login              | `login`            | `POST api/login` `{email, password}`               |
| Current user / id  | `currentUser`      | `GET api/user`                                     |
| Today's entries    | `today(id)`        | `GET api/attendance/employees/{id}/today`          |
| Clock in           | `clockIn(id)`      | `POST api/attendance/employees/{id}/clock-in`      |
| Clock out          | `clockOut(id)`     | `POST api/attendance/employees/{id}/clock-out`     |
| Break start        | `breakStart(id)`   | `POST api/attendance/employees/{id}/break/start`   |
| Break end          | `breakEnd(id)`     | `POST api/attendance/employees/{id}/break/end`     |
| Insert past break  | `entries(id)`      | `POST api/attendance/employees/{id}/entries`       |
| Reason options     | `reasons`          | `GET api/attendance/reasons`                       |
| Set entry reason   | `entry(id, e)`     | `PUT api/attendance/employees/{id}/entries/{e}`    |

## Response parsing

`Sources/Services/BobParsing.swift` is deliberately tolerant — it accepts
several container keys (`entries`/`punches`/`items`/`records`), kind keys
(`type`/`entryType`/`kind`/`category`, anything containing "break" is a
break), time keys (`start`/`startTime`/`clockIn`/`in` + `end` variants), and
both ISO8601 and bare `HH:mm` timestamps. If your tenant's shape still isn't
covered, add a fixture to `Tests/main.swift` first, then extend the parser.

## Symptoms of a wrong route

- Settings → Diagnostics shows `HiBob returned HTTP 404 for …` — the path
  is wrong; replace it in `BobAPI`.
- "An auto-break action didn't stick" — the write endpoint returned 2xx but
  HiBob didn't record it; the body shape is probably wrong.
- Empty timeline while the web UI shows entries — the today-route is wrong
  or its response shape isn't covered by `BobParsing.entries`.

## Captured: timesheet summary shape (2026-07)

`GET api/attendance/employees/{id}/timesheets/{n}/summary` — the fields the
dashboard reads (verified against a live capture):

```
dailyBreakdown.categories                     ["yyyy-MM-dd", …]
dailyBreakdown.graphData[]                    series, matched by "id":
  id=hoursWorked      .data[].value           worked hours per day
  id=potentialHours   .target[].value         target hours per day
  id=overtime         .data[].value           signed over/under per day
                      .data[].valueDisplay    exact, SIGNED: "-1h 03m"
  id=timeOff          .data[].value           booked time off per day, hours
cycleSummary.timeOffDisplay                   cycle time-off total ("6h 30m")

`cycleSummary.overUnderTime` is the figure the web timesheet header shows —
if it looks a minute off from an open browser tab, the tab is stale (an entry
edit moves it), not the parsing.
cycleSummary.hoursWorkedDisplay               cycle worked total ("107h 59m")
cycleSummary.potentialHours.summaryDisplay    cycle potential ("176h 30m")
cycleSummary.potentialHours.payableTimePercentage
cycleSummary.overUnderTime.{sign,hoursDisplay}  balance incl. in-progress day
breakViolationCounter
```

Careful: `payableHoursBreakdown.totalHoursDisplay` is a *different* total
(regular+overtime payable) — don't use it for "worked".

## Captured: summary series semantics (2026-08-06, live grab)

Verified against the running August sheet (`/timesheets/0/summary`) and the
approved July sheet (`/timesheets/14068479/summary`):

- **Every per-day series stops at today.** For days after today, `worked`,
  `target`, `timeOff`, and `overtime` are all **null** — not zero. The sheet
  states nothing about the future, including future booked time off; the only
  source for upcoming holidays is the time-off requests route.
- **A booked time-off day keeps its stated target.** 2026-07-24 (a full-day
  holiday): `worked 0`, `target 6.5`, `timeOff 6.5`, `overtime 0h 00m` —
  HiBob credits the time off, the day is NOT a zero-target day and NOT a
  deficit. `totals` for that day is 6.5 (worked + timeOff = payable).
- **Stated weekday targets** (this tenant, July): Mon–Thu 8h, **Fri 6.5h**,
  Sat/Sun explicit 0. A cycle's first occurrence of a weekday has no
  precedent inside the cycle — cross-cycle history is required to fill it.
- `graphData` also carries `id=nonWorkingEvents` (0 throughout July; likely
  public holidays) and `id=totals` (worked + timeOff per day).

## Captured: past cycles ("Last month" tab, 2026-08)

`GET api/attendance/employees/{id}/timesheets` returns **every sheet HiBob
still exposes**, not just the running cycle:

```
employeeTimesheets[]
  id                              0 for the RUNNING cycle; a finished previous
                                  month keeps its real sheet id (e.g. 14068479)
  cycleStartDate / cycleEndDate   "yyyy-MM-dd"
  timesheetState.timeSheetStatus  "Open" | "WaitingForSubmission" | …
  timesheetState.locked           bool
  timesheetState.lockAt           epoch ms
```

Everything else reuses the existing routes with the past sheet's id:

- `GET …/timesheets/{pastId}/summary` — same shape as the current cycle,
  plus a root-level `isSubmittable` bool (gates the Submit action).
- `POST api/company/views/search` with `"timesheetId": {pastId}` — the same
  grid report returns the past month's per-day rows (weekly `isSummary: true`
  rows interleaved; day rows carry `dateKey`).
- `POST …/attendance/entries?forDate=…` — verified to work retroactively on
  a past-cycle day (same body as an active day).
- `POST …/timesheets/{id}/details` `{"fields":["policyDetails"]}` — policy
  config only (cycle type, break rules, overtime settings); not the grid.

## Captured: timesheet submit (2026-08-03, live one-shot)

`PUT api/attendance/employees/{id}/sheets/{sheetId}/submit` — careful, the
segment is **`sheets`**, not `timesheets`. Empty body. Response:

```
{"isAutoApproved":false,
 "timesheetState":{"timeSheetStatus":"Submitted","lockAt":…,"locked":false,
                   "submittedBy":"…","submittedOn":"2026-08-03T11:44:33.391252"}}
```

After submitting, the sheet **stays** in the timesheets list with status
"Submitted" (pending manager approval; the policy's `approvalType` was
"manager"). Status lifecycle observed so far:
`Open` → `WaitingForSubmission` → `Submitted`. There is no un-submit.
