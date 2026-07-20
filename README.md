# BetterBob

A native macOS menu-bar client for HiBob time tracking — clock in, clock
out, take breaks — with one smart behavior HiBob doesn't have: after **6
hours of uninterrupted work** it automatically starts a **30-minute break**
in HiBob and ends it on time. A single-module SwiftUI app compiled with
plain `swiftc`, no Xcode project. Bob, a cheerful beaver in a blue cap, is
your mascot throughout.

## How it works

- Talks to HiBob's **internal web API** (`app.hibob.com/api/...`) — the same
  calls the website makes — using your own session. No admin API keys needed.
  A `Bob-TimeZoneOffset` header is sent so the server computes "now" in your
  timezone (without it, HiBob answers in UTC and misreports your punch state).
- **HiBob is the source of truth.** Today's entries are re-fetched every
  minute, on wake, and after every action — clock in from your phone or take
  a break in the web UI and the app follows along.
- The **auto-break** fires only after a truly uninterrupted stretch: any
  break (from anywhere) resets the counter. A precise timer lands the break
  on the second; if your Mac was asleep at the mark, the break is inserted
  **retroactively** at the timestamps it should have had.
- Per-entry **Reason** (In Office / Work from home / … — all your tenant's
  options, fetched live) can be viewed and changed from the timeline.
- Optional **Wi-Fi rule**: on a chosen network (e.g. the office SSID) the open
  work entry is auto-tagged with a reason — but only if you haven't set one
  yourself. Reading the network name needs macOS Location access (asked once);
  your location is never used or stored.

## Signing in

A guided window (shown on first run, or via the **Sign in…** button in the
popover / Settings) offers two ways in:

- **Automatic** *(recommended)* — save your password + 6-digit authenticator
  code; Bob signs you in on his own after sleep, restart, or session expiry.
  Credentials live only in the macOS **Keychain**; the code accepts a bare
  base32 secret **or** a full `otpauth://` URL. Best for password + TOTP
  logins (not Okta Verify push).
- **Browser** — an embedded window opens `app.hibob.com/login`; you log in
  exactly as usual (Okta Verify push included) and the app captures the
  session. Quick, but you sign in again each time the session expires.

## Menu-bar popover

State icon (working / on break / clocked out, optional worked-time label),
prominent worked-today total, big clock in/out and break buttons, live
countdown to the auto-break, a "Saving…" hint while writes are in flight, and
today's timeline with reason pickers.

## Main window

- **Today** — a big worked total and a to-scale timeline. **Drag a break
  along the timeline** to move it: it keeps its length, the surrounding work
  resizes, and a marker + time pill preview where it lands before you drop.
- **This month** — a calendar heatmap (days with a break-policy issue show
  **orange**), running over/under, and a by-day list. Click any past day to
  edit its entries (timeline drag, time/reason edits, delete) or use the
  **wand** to insert the missing break(s).
- **Time off** — balances, upcoming leave, a request calendar, and existing
  requests.

## Settings

Sign in/out, auto-break threshold + length (default 6h/30m), master
auto-break switch, **auto-fix gaps & overlaps** on save, automatic sign-in
(credentials + auto-relogin), Wi-Fi reason rules, notifications, launch at
login, and the menu-bar label — plus a diagnostics card when something last
failed.

## Siri / Shortcuts

"Clock in", "Clock out", "Take a break" — from Spotlight, Shortcuts, and the
Action Button.

## The honest caveats

- The internal API is **unofficial** and can change without notice. All
  routes sit in one place (`BobAPI`) and the parser is deliberately tolerant;
  when something changes, re-capture per `Docs/endpoints.md`.
- Before first use, **verify the routes against your tenant** — see
  `Docs/endpoints.md`. This is the one manual setup step.
- The app automates *your own account* doing things you're allowed to do,
  but auto-inserted breaks are still attendance records — use it within your
  company's policy.

## Requirements

- macOS **26** (Tahoe) — uses macOS 26 SDK APIs (Liquid Glass)
- Xcode 17+ toolchain for building (`xcrun --show-sdk-version` → 26.x)

## Build & run

```sh
./Scripts/build.sh
open build/BetterBob.app
# or install:
cp -r build/BetterBob.app /Applications/
```

Unit tests (attendance math, auto-break decisions, JSON parsing, TOTP):

```sh
./Scripts/test.sh
```

## Project layout

```
Sources/
  App/                  BetterBob.swift (@main + AppDelegate + status item)
  Models/               AttendanceEntry, ClockState, AutoBreakAction, ReasonOption, …
  Services/             AttendanceLogic (pure decision math: auto-break,
                        gap/overlap normalise, break move), BobParsing
                        (tolerant JSON), BobClient (internal API), BobState
                        (polling engine), Keychain, TOTP, Prefs, WiFiMonitor, Notifier
  Features/Popover/     menu-bar popover
  Features/Dashboard/   main window: Today, month heatmap, day editor, time off,
                        the draggable timeline (EditableDayStrip)
  Features/Onboarding/  first-run / sign-in window
  Features/Settings/    settings + SSO sign-in + endpoint capture (dev)
  Intents/              Siri / Shortcuts App Intents
  UI/                   Bob mascot + shared Liquid Glass components
Tests/main.swift        unit tests (run via Scripts/test.sh)
Docs/endpoints.md       internal API capture guide + route table
Scripts/                build.sh, test.sh, generate_icon.swift
Resources/              Info.plist, AppIcon.icns (generated)
```

## License

MIT.
