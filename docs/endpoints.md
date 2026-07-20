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
                      .data[].valueDisplay    exact "0h 34m" (sum = the web
                                              UI's "running cycle balance")
cycleSummary.hoursWorkedDisplay               cycle worked total ("107h 59m")
cycleSummary.potentialHours.summaryDisplay    cycle potential ("176h 30m")
cycleSummary.potentialHours.payableTimePercentage
cycleSummary.overUnderTime.{sign,hoursDisplay}  balance incl. in-progress day
breakViolationCounter
```

Careful: `payableHoursBreakdown.totalHoursDisplay` is a *different* total
(regular+overtime payable) — don't use it for "worked".
