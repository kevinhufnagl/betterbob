# BetterBob — agent notes

macOS menu-bar client for HiBob time tracking. Single-module SwiftUI app built
with plain `swiftc` — no Xcode project. Requires Apple Silicon + macOS 26
toolchain (`xcrun --show-sdk-version` → 26.x).

## Commands

```sh
./Scripts/build.sh          # build build/BetterBob.app
./Scripts/test.sh           # run the unit tests (Tests/main.swift, plain expect() harness)
./Scripts/release.sh 1.4    # cut a release — see below
```

## Releasing

1. Commit all feature work first — `release.sh` only commits the Info.plist
   version bump.
2. Run `./Scripts/release.sh <version>` (e.g. `1.4`, one minor up from the
   last `Release x.y` commit). It bumps `Resources/Info.plist`, clean-builds,
   zips the app, commits "Release <version>", tags `v<version>`, pushes, and
   publishes the GitHub release with the zip via `gh` — all in one go.
3. Nothing else to do: users get the update through the in-app updater, which
   watches GitHub Releases. **Never reinstall or relaunch the locally installed
   app** — the user updates via the updater.
4. Releases must be cut on a Mac holding the self-signed **"BetterBob
   Signing"** certificate (one-time: `./Scripts/make-signing-cert.sh`, run by
   the user — it needs their password). build.sh signs with it so Keychain +
   Location grants survive updates; without it, it falls back to ad-hoc and
   every update re-prompts users for those permissions.

## Gotchas

- **SourceKit diagnostics are noise.** The LSP can't see across files in this
  no-project setup, so it reports "Cannot find type X in scope" everywhere.
  The only real check is `./Scripts/build.sh` + `./Scripts/test.sh`.
- **Don't launch the built app to verify UI** — a second instance polls HiBob
  and the auto-break engine may write real attendance entries. Verify drawing
  code by compiling the file standalone with a small driver (works for
  self-contained files like `Sources/UI/BobMascot.swift`).
- **`Bob-TimeZoneOffset` header is required** on clockStatus calls or HiBob
  computes "now" in UTC (phantom clocked-in state, midnight bugs). Routes live
  in `Sources/Services/BobClient.swift`; if HiBob's private API changes,
  re-capture per `Docs/endpoints.md` (`--capture-endpoints` launch flag).
- **No emojis in UI copy** — BetterBob's text and Bob's captions stay plain.
- Attendance math is pure and unit-tested in `Services/AttendanceLogic` —
  put new time logic there (functions take entries + explicit `now`) and add
  `expect()` cases to `Tests/main.swift`.

## Layout

```
Sources/
  App/          @main + menu-bar status item
  Models/       core value types (entries, clock state, Fmt helpers)
  Services/     AttendanceLogic (pure math), BobClient (API), BobState
                (polling engine), BobParsing, Keychain, TOTP, Prefs, Updater, …
  Features/     Popover, Dashboard (today/month/time off), Onboarding, Settings
  Intents/      Siri / Shortcuts
  UI/           Bob the mascot (incl. menu-bar icon drawing) + shared components
Tests/          unit tests
Docs/           internal API capture guide + route table
```
