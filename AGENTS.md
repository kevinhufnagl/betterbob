# BetterBob — agent notes

macOS menu-bar client for HiBob time tracking, plus an iOS companion app
sharing the `Packages/BetterBobShared` core. The Mac app is a single-module SwiftUI app
built with plain `swiftc` — no Xcode project. Requires Apple Silicon +
macOS 26 toolchain (`xcrun --show-sdk-version` → 26.x).

## Commands

```sh
./Scripts/build.sh          # build build/BetterBob.app (macOS)
./Scripts/test.sh           # run the unit tests (Tests/main.swift, plain expect() harness)
./Scripts/gen-ios.sh        # regenerate iOS/BetterBob-iOS.xcodeproj (brew install xcodegen)
./Scripts/release.sh 1.4    # cut a macOS release — see below
```

## Shared package + iOS app

Cross-platform code lives in **`Packages/BetterBobShared`** (engine: BobState,
Prefs, BobClient, AttendanceLogic, models, SSO controller — plus the shared
UI: wave hero, Bob mascot family, color system, day strip, heatmap,
calendars). It is consumed two ways:

- The **Mac build** globs the package's `.swift` files straight into its
  single `swiftc` module (`find Sources Packages …` in build.sh/test.sh) —
  Mac code uses shared types with **no import**.
- The **iOS app + widget** link it as a real SwiftPM dependency and
  `import BetterBobShared`. Anything iOS touches must be `public` (views also
  need an explicit `public init` and `public var body`).

Mac-only code stays in `Sources/` (menu-bar app, Popover, MainWindow,
WiFiMonitor, Updater, Uninstaller). `Sources/Intents/BobIntents.swift`
compiles into BOTH app targets and uses `#if canImport(BetterBobShared)`.

The iOS app (`iOS/`, XcodeGen — regenerate via `./Scripts/gen-ios.sh`) is a
native iOS 26 Liquid Glass app:

- `iOS/Sources/Common/` — glass primitives (`GlassCard`/`GlassSurface`,
  `GlassGroupedSection`/`GlassRow`, `.bobScreen()` backdrop). One recipe:
  `.glassEffect(.regular, in: rr18)` + 0.5pt white 8% hairline.
- `iOS/Sources/Screens/` — native screens (Onboarding, Today, Month,
  Activity, Time Off, Settings) composing shared components with Dynamic
  Type styles — never the Mac's fixed 10–12pt fonts.
- `iOS/Sources/App` — shell, lifecycle, BGAppRefreshTask, widget bridge;
  `iOS/Sources/Widgets` — widget extension + Live Activity;
  `iOS/Resources/Assets.xcassets` — Bob app icon + navy AccentColor (the
  icon's background; the brand color is pinned, hue 0.598).
- Build/run on a device from Xcode (personal team, automatic signing):
  `./Scripts/gen-ios.sh && open iOS/BetterBob-iOS.xcodeproj`.
- Verification builds go against the iOS simulator with
  `CODE_SIGNING_ALLOWED=NO`; xcodebuild's destination matching is flaky here —
  if `generic/platform=iOS Simulator` errors, retry with a concrete
  `platform=iOS Simulator,name=iPhone 17 Pro,OS=…` destination (or vice versa).
- Sign-in on iOS: manual/browser mode presents a visible sheet
  (`SSOSignInController.sheetWebView` + `SignInSheet.swift`); assisted mode
  runs invisibly like the Mac — the WKWebView is parked full-size at the
  back of the key window, behind all app content, so WebKit keeps driving
  Okta while only the inline OTP card shows.
- Background auto-break is best-effort (`BGAppRefreshTask` chained around
  auto-break due times) plus catch-up on foreground; widgets and the Live
  Activity read a `WidgetSnapshot` from the App Group
  (`group.k3n.betterbob`).

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

- **Closed windows keep animating.** SwiftUI retains a closed Window scene's
  view tree with its display links armed, and per-view `trackWindowVisibility`
  gates are leaky (backing views get duplicated during scene setup; the
  survivor can end up detached and never hear `willClose`). MainWindow
  therefore swaps its whole shell for `Color.clear` when the root tracker
  reports the window invisible — keep that pattern, don't rely on gating
  individual clocks. Also: a `repeatForever` animation is not cancelled by a
  `disablesAnimations` write; replace it with a finite animation
  (`withAnimation(.linear(duration: 0.01))`) to stop it.
- **SourceKit diagnostics are noise.** The LSP can't see across files in this
  no-project setup, so it reports "Cannot find type X in scope" everywhere.
  The only real check is `./Scripts/build.sh` + `./Scripts/test.sh`.
- **Don't launch the built app to verify UI** — a second instance polls HiBob
  and the auto-break engine may write real attendance entries. Verify drawing
  code by compiling the file standalone with a small driver (works for
  self-contained files like the package's `UI/BobMascot.swift`).
- **`Bob-TimeZoneOffset` header is required** on clockStatus calls or HiBob
  computes "now" in UTC (phantom clocked-in state, midnight bugs). Routes live
  in the package's `Services/BobClient.swift`; if HiBob's private API changes,
  re-capture per `Docs/endpoints.md` (`--capture-endpoints` launch flag).
- **No emojis in UI copy** — BetterBob's text and Bob's captions stay plain.
- Attendance math is pure and unit-tested in the package's
  `Services/AttendanceLogic.swift` — put new time logic there (functions take
  entries + explicit `now`) and add `expect()` cases to `Tests/main.swift`.

## Layout

```
Sources/                          Mac-only
  App/                            @main + menu-bar status item
  Features/                       Popover, Dashboard (MainWindow + panes), Settings glue
  Services/                       Updater, Uninstaller, WiFiMonitor
  Intents/                        Siri / Shortcuts (compiles into both app targets)
Packages/BetterBobShared/Sources/BetterBobShared/
  Models/                         core value types (entries, clock state, Fmt helpers)
  Services/                       AttendanceLogic (pure math), BobClient (API),
                                  BobState (polling engine), BobParsing, Keychain,
                                  TOTP, Prefs, Notifier, …
  Features/                       shared UI: heroes + glass dock (TodayVariants),
                                  FreshDayWelcome, dashboard sections, day strip,
                                  time off, Settings panel, Onboarding, SSO sign-in
  UI/                             Bob mascot family (incl. menu-bar icon), colors,
                                  motion, window-visibility tracker
iOS/                              XcodeGen app + widgets (see above)
Tests/                            unit tests
Docs/                             internal API capture guide + route table
```
