# BetterBob — Design

**Date:** 2026-07-16
**Status:** Approved

## Summary

BetterBob is a native macOS menu-bar app that clocks the user in and out of HiBob
time tracking, and automatically inserts a 30-minute break after 6 hours of
uninterrupted work. It follows the BetterVPN/Colimate architecture: a
single-module SwiftUI app compiled with plain `swiftc` (no Xcode project),
menu-bar popover UI with Liquid Glass styling, Keychain-backed secrets, and
App Intents for Siri/Shortcuts.

The user is a regular HiBob employee with no admin access, so the app uses
HiBob's **internal web API** (`app.hibob.com/api/...`) — the same calls the
web UI itself makes — authenticated with the user's own session. The official
API (`api.hibob.com/v1`) requires an admin-created service user and is out of
scope; if the company ever grants one, `BobClient` is the only layer that
would change.

## Requirements

1. Clock in and clock out from the menu bar.
2. Start and end breaks manually from the menu bar.
3. After **6 hours of uninterrupted work**, automatically start a break in
   HiBob, hold it for **30 minutes**, then automatically end it (back to work).
4. A manual break — taken via the app, the HiBob web UI, or the HiBob mobile
   app — resets the uninterrupted-work counter. Auto-break fires only on a
   truly unbroken 6-hour stretch.
5. If the Mac is asleep or off when the 6-hour mark passes, the break is
   inserted **retroactively** at the correct past timestamps on wake/launch,
   so the record in HiBob is identical to the real-time case.
6. Threshold (6h) and break length (30m) are configurable in Settings.
7. The user's tenant records breaks as an explicit entry type (the HiBob UI
   has a dedicated break action); the app uses that, not clock-out/in gaps.
8. Login is email + password (no SSO); credentials are stored in the Keychain
   and the app re-authenticates silently when the session expires.

## Non-goals

- No official-API / service-user integration.
- No timesheet editing beyond the break/clock actions above (no Quick Fix UI,
  no historical-day repair beyond the current uninterrupted stretch).
- No traffic blocking of any kind on failure — failures notify, never guess.
- No Windows/iOS versions.

## Architecture

```
Sources/
  App/BetterBob.swift          @main + AppDelegate + status item
  Models/                      AttendanceEntry, ClockState, DayTimeline, Settings
  Services/
    BobClient.swift            internal-API client: login, clockIn, clockOut,
                               breakStart, breakEnd, fetchToday
    SessionStore.swift         Keychain credentials + cookie storage, re-login
    AttendanceEngine.swift     state machine + timer math + reconciliation
    Prefs.swift                UserDefaults-backed settings
  Features/Popover/            menu-bar popover (primary surface)
  Features/Settings/           settings window
  Intents/                     App Intents: Clock In, Clock Out, Take a Break
  UI/                          shared Liquid Glass components
Tests/main.swift               engine + parsing unit tests (Scripts/test.sh)
Scripts/build.sh, test.sh      adapted from better-vpn
Docs/endpoints.md              captured internal API reference
```

### BobClient (HiBob integration)

- URLSession-based client for `https://app.hibob.com/api/...`.
- **Endpoint discovery is implementation step 1:** the exact paths are
  unofficial, so they are captured once from the browser DevTools network tab
  while performing each action manually, and recorded in `Docs/endpoints.md`.
  All paths live in one constants file; nothing else in the app knows them.
- Auth: `login(email, password)` → session cookie, persisted via
  `SessionStore`. On any 401/redirect-to-login response, one silent re-login
  is attempted before surfacing an error.
- **Contingency:** if programmatic login is blocked (captcha/MFA), pivot to an
  embedded `WKWebView` login window that captures the session cookie. Not
  built up front.
- `fetchToday()` returns the day's attendance entries and is the **source of
  truth** — polled every 60 seconds while clocked in, and on wake/launch/
  popover-open. Actions taken in HiBob's own web or mobile UI are absorbed,
  never fought.

### AttendanceEngine (the core)

A state machine — `clockedOut → working ⇄ onBreak` — whose inputs are
(a) the entries from `fetchToday()` and (b) an injected clock. All timer math
is pure functions over those inputs, unit-tested with a fake clock.

Rules:

- **Uninterrupted-work counter** = now − max(last clock-in, last break end),
  computed from server entries.
- At counter = 6h00m: POST break start, notify "Auto-break started".
- At 6h30m (i.e., 30m of break): POST break end, notify "Back to work".
- Any manual break (from anywhere) resets the counter; a manual break taken
  while the auto-break countdown is pending simply replaces it.
- If the user manually ends an auto-break early, the app accepts that (server
  is truth) and the counter restarts from the actual break end.
- **Retroactive repair** (wake/launch/reconnect): recompute from server
  entries. If a ≥6h unbroken stretch exists with no break, insert the break
  at [stretchStart + 6h00, stretchStart + 6h30] in the past. If "now" falls
  inside that window, start the break backdated and end it on schedule. If the
  user clocked out (via another device) before the 6h mark, do nothing.
- The engine only ever repairs the **current** work stretch of the current
  day — it never rewrites history further back.

### UI

- **Menu bar icon:** three visual states (clocked out / working / on break),
  optional elapsed-time label next to the icon.
- **Popover:** primary clock in/out button, break toggle, time worked today,
  live countdown to the auto-break ("break in 1h 12m"), link to Settings.
- **Settings window:** threshold and break-length steppers, launch at login,
  notification toggles, account section (email, re-login, sign out — sign out
  wipes Keychain and cookies).
- **Notifications:** auto-break started, auto-break ended, any failed HiBob
  write (with reason), re-login failure (action needed).

## Error handling

- **Session expiry:** silent Keychain re-login; notify only if that fails.
- **Network down at a scheduled action:** retry with exponential backoff; the
  retroactive-repair pass doubles as recovery since late inserts are backdated.
- **Internal API changed shape:** surfaced as a clear notification ("HiBob API
  response not understood") rather than silent misbehavior; paths and parsing
  are isolated in BobClient for easy re-capture.
- **Clock skew / DST:** all computation in absolute timestamps (`Date`),
  rendered in the local timezone only at the UI layer.

## Testing

- `Tests/main.swift` (run via `Scripts/test.sh`, same harness as BetterVPN):
  - Counter math: clock-in only, breaks resetting, multi-break days.
  - Auto-break triggering at exactly 6h; cancellation by manual break.
  - Retroactive repair: wake before/inside/after the missed window; stretch
    ended by an external clock-out.
  - BobClient response parsing against fixture JSON captured in
    `Docs/endpoints.md`.
- Live verification: build, log in with real credentials, verify one full
  clock-in → auto-break (with a temporarily lowered threshold) → clock-out
  cycle appears correctly in the HiBob web UI.

## Caveats (acknowledged)

- The internal API is unofficial and can change without notice; the app is
  built so only `BobClient` needs re-capture when it does.
- The app automates the user's own account performing actions they are
  entitled to perform, but auto-inserted breaks are still attendance records;
  the user accepts responsibility for using it within company policy.
