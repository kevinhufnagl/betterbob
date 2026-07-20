# BetterBob

A friendly macOS menu-bar app for HiBob time tracking — clock in, clock out,
and take breaks without ever opening the HiBob website. Its standout trick:
after a long stretch of uninterrupted work it quietly inserts a break for you
(you choose how long a stretch and how long a break), so you never blow past
your company's break rules. Bob, a cheerful beaver in a blue cap, keeps you
company in the menu bar.

## Install

BetterBob is Apple Silicon + macOS 26 (Tahoe).

1. Download the latest **`BetterBob-x.y.zip`** from the
   [**Releases**](https://github.com/kevinhufnagl/betterbob/releases/latest) page.
2. Unzip it and drag **BetterBob.app** into your **Applications** folder.
3. It's ad-hoc signed (not notarized), so the *first* launch needs a one-time
   Gatekeeper OK: **right-click BetterBob → Open → Open**. (Only the first time.)
4. Bob appears in your menu bar — click him and sign in to HiBob.

After that, updates are automatic: BetterBob checks GitHub Releases and offers a
one-click update when a new version is out.

## What it does

- **Clock in, out, and take breaks** right from the menu bar — no need to open
  HiBob.
- **Automatic breaks.** Work too long without a break and Bob adds one for you
  and ends it on time. You set how long a stretch triggers it and how long the
  break is. If your Mac was asleep when the break was due, Bob still logs it at
  the right time after the fact.
- **Always in sync.** HiBob stays the source of truth — clock in on your phone
  or edit something on the website and BetterBob keeps up within a minute.
- **Reasons on your entries** (In Office, Work from home, and whatever else your
  company uses) — set or change them in a click.
- **Office auto-tagging (optional).** On a Wi-Fi network you choose, work gets
  tagged with a reason like "In Office" automatically — unless you've set one
  yourself. It only reads the network name (macOS asks permission once); your
  location is never used or stored.

## Signing in

The first time — or any time you're signed out — Bob opens a sign-in window with
two choices:

- **Automatic** *(recommended)* — save your password and authenticator code once,
  and Bob signs you back in by himself after sleep, restarts, or when the session
  expires. Everything is stored only in your Mac's Keychain. Works when your login
  uses a password plus a 6-digit code (not for Okta Verify "approve on your
  phone" prompts).
- **Browser** — sign in through HiBob's normal login page (Okta push included).
  Quick, but you'll sign in again whenever the session expires.

## Around the app

**Menu bar** — your status at a glance: Bob wears a little play or pause badge
while the clock runs, and the text next to him is your choice — per status —
of worked time, the auto-break countdown, break time left, and more. Click him
for big clock in/out and break buttons and today's entries.

**Main window**
- **Today** — your worked total and a timeline of the day. Drag a break along
  the timeline to move it (the work around it adjusts), or grab the edge
  between two entries to lengthen or shorten them — you see where everything
  lands before you drop.
- **This month** — a calendar of your hours (days that need a break show up in
  orange, days over your daily max in red), how far over or under you are, and
  a day-by-day list. Click any past day to fix its entries, or tap the wand to
  drop in a missing break.
- **Time off** — balances, upcoming leave, and a calendar to request more.

**Settings** — sign in/out, the auto-break rule, the daily-hours limit (default
10h — over it, days flag red and Bob nudges you to clock out), automatic
sign-in, office Wi-Fi tagging, notifications, the popover's width, layout and
sections, launch at login, and more.

**Siri & Shortcuts** — "Clock in", "Clock out", "Take a break" from Spotlight,
Shortcuts, and the Action Button.

## Good to know

- BetterBob uses the same private HiBob web service the website itself uses, with
  your own login — no admin access or API keys. Because it's a private service,
  Bob can occasionally need a nudge if HiBob changes it (see the developer notes).
- Auto-inserted breaks are still real attendance records — use BetterBob within
  your company's time-tracking policy.

## For developers

A single-module SwiftUI app built with plain `swiftc` — no Xcode project.
Requires an Apple Silicon Mac on **macOS 26** (Tahoe) and the matching toolchain
(`xcrun --show-sdk-version` → 26.x).

```sh
./Scripts/build.sh          # build build/BetterBob.app
./Scripts/test.sh           # run the unit tests
./Scripts/release.sh 1.3    # bump, build, tag, push, publish a GitHub release
```

The attendance logic lives in `Services/AttendanceLogic` as pure, unit-tested
functions (auto-break decisions, gap/overlap fixing, moving a break). HiBob's
routes are all in one place (`BobClient`), the JSON parser is deliberately
tolerant, and one required header (`Bob-TimeZoneOffset`) makes the server report
your punch state in your own timezone instead of UTC. The private API is
unofficial and can change without notice — when it does, re-capture the routes
per `Docs/endpoints.md`.

```
Sources/
  App/          @main + menu-bar status item
  Models/       core value types (entries, clock state, …)
  Services/     AttendanceLogic (pure math), BobClient (API), BobState
                (polling engine), BobParsing, Keychain, TOTP, Prefs, Updater, …
  Features/     Popover, Dashboard (today/month/time off + draggable timeline),
                Onboarding (sign-in), Settings
  Intents/      Siri / Shortcuts
  UI/           Bob the mascot + shared components
Tests/          unit tests (Scripts/test.sh)
Docs/           internal API capture guide + route table
Scripts/        build.sh, test.sh, release.sh, generate_icon.swift
```

## License

MIT.
