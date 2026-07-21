# iOS Native Restyle + Shared Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure code sharing into an SPM package (`Packages/BetterBobShared`, Colimate-style) and rebuild the iOS app's presentation as a native iOS 26 Liquid Glass app — keeping BetterBob's signature visuals (wave hero, Bob mascot, color system) and all shared engine logic.

**Architecture:** The package is a real SPM dependency for the iOS app + widget (`import BetterBobShared`); the Mac build keeps its single-module `swiftc` build, with the glob widened to `find Sources Packages …` so package sources compile straight into the Mac module (no imports in Mac code). iOS-only native screens live in `iOS/Sources/`, composed from shared components + new glass primitives.

**Tech Stack:** SwiftPM (tools 6.2, language mode 5), SwiftUI iOS 26 Liquid Glass (`.glassEffect`, `.buttonStyle(.glassProminent)`), XcodeGen, WidgetKit/ActivityKit.

## Global Constraints

- Mac build + tests stay green after every task: `./Scripts/build.sh && ./Scripts/test.sh`.
- iOS verification: `./Scripts/gen-ios.sh` then xcodebuild against the iOS simulator with `CODE_SIGNING_ALLOWED=NO`; destination matching is flaky — alternate between `generic/platform=iOS Simulator` and `platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1`. Never chain `grep || fallback` (grep matching error text reads as success).
- No emojis in UI copy. Never store TOTP seeds. `Bob-TimeZoneOffset` logic untouched. Never launch the local Mac app.
- Keep BetterBob's identity: wave hero (`LiquidHero`), Bob mascot family, teal accent, existing copy voice. Colimate is pattern reference only — no rust colors, no Colimate copy, no literal code lifts.
- Typography on iOS: Dynamic Type styles (`.body`, `.footnote`, `.title3`, `.caption`); `design: .rounded` only for chips/pills. No fixed 10–12pt desktop sizes in new iOS views.
- Glass recipe (single source of truth, defined once in Task 4): `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))` + 0.5pt `Color.white.opacity(0.08)` hairline stroke. Deployment target is iOS 26 — no availability fallbacks.
- Commit after every task on branch `ios-port`.

---

### Task 1: Create Packages/BetterBobShared and rewire the Mac build

**Files:**
- Create: `Packages/BetterBobShared/Package.swift`
- Move (git mv, preserving subfolders under `Packages/BetterBobShared/Sources/BetterBobShared/`): `Sources/Models/Models.swift`, `Sources/Models/WidgetSnapshot.swift`, `Sources/Services/{AttendanceLogic,BobParsing,BobClient,Keychain,Notifier,Prefs,BobState}.swift`, `Sources/Features/Settings/{SSOSignIn,SettingsPanel}.swift`, `Sources/Features/Onboarding/Onboarding.swift`, `Sources/Features/Dashboard/{DashboardView,DashboardSections,TodayVariants,EditableDayStrip,TimeOffPane}.swift`, `Sources/UI/{Motion,WindowVisibility,Components,PillControls,BobMascot}.swift`
- Stay in `Sources/` (mac-only): `App/`, `Intents/`, `Features/Popover/`, `Features/Dashboard/MainWindow.swift`, `Features/Settings/EndpointCapture.swift`, `Services/{WiFiMonitor,Updater,Uninstaller}.swift`
- Modify: `Scripts/build.sh` (glob), `Scripts/test.sh` (glob)

**Interfaces:**
- Produces: package skeleton whose sources still compile into the Mac module exactly as before. iOS is switched in Task 2.

- [ ] **Step 1:** `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BetterBobShared",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0")
    ],
    products: [
        .library(name: "BetterBobShared", targets: ["BetterBobShared"])
    ],
    targets: [
        .target(
            name: "BetterBobShared",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
```

- [ ] **Step 2:** `git mv` the files listed above into `Packages/BetterBobShared/Sources/BetterBobShared/<subfolder>/` keeping their Models/Services/Features/UI folder names.
- [ ] **Step 3:** In both `Scripts/build.sh` and `Scripts/test.sh`, change the source glob to include the package and exclude manifests/build dirs:

```bash
done < <(find Sources Packages -name '*.swift' -type f \
           -not -path '*/.build/*' -not -name 'Package.swift' -print0)
```

(test.sh keeps its additional `-not -path 'Sources/App/*'`.)
- [ ] **Step 4:** Verify Mac: `./Scripts/build.sh && ./Scripts/test.sh` — both green (pure file moves; one module as before).
- [ ] **Step 5:** Commit: `git commit -m "Move shared core into Packages/BetterBobShared (mac build globs it)"`

---

### Task 2: iOS consumes the package; publicize the shared surface

**Files:**
- Modify: `iOS/project.yml` (drop `../Sources` includes; add `packages:` + dependencies; app target keeps `- path: ../Sources/Intents/BobIntents.swift`)
- Modify: `Sources/Intents/BobIntents.swift` (conditional import)
- Modify: iOS-side files (`iOS/Sources/App/*.swift`, `iOS/Sources/Shared/*.swift`, `iOS/Sources/Widgets/*.swift`) — add `import BetterBobShared`
- Modify: package files — add `public` where the iOS module boundary requires it

**Interfaces:**
- Produces: iOS app + widget building against the package. Public API surface: whatever iOS-side code touches (`BobState`, `Prefs`, `AttendanceLogic`, `WidgetSnapshot`, `SSOSignInController`, `OnboardingController.completed`, mascot/hero/strip/heatmap/calendar views, color tokens, `Fmt`, `Notification.Name.presentOnboarding`, …).

- [ ] **Step 1:** `iOS/project.yml` — top level gains:

```yaml
packages:
  BetterBobShared:
    path: ../Packages/BetterBobShared
```

App target `sources:` becomes `Sources/App`, `Sources/Shared`, and `- path: ../Sources/Intents/BobIntents.swift`; `dependencies:` gains `- package: BetterBobShared`. Widget target `sources:` becomes `Sources/Widgets` + `Sources/Shared`; `dependencies:` gains `- package: BetterBobShared` (drop the direct `WidgetSnapshot.swift` path).
- [ ] **Step 2:** Top of `Sources/Intents/BobIntents.swift` (compiled into the Mac module directly AND into the iOS app target):

```swift
#if canImport(BetterBobShared)
import BetterBobShared
#endif
```

- [ ] **Step 3:** Add `import BetterBobShared` to every file under `iOS/Sources/`.
- [ ] **Step 4:** Build iOS; let the compiler drive the `public` pass. For each "X is inaccessible" error, mark the type/member `public` in the package (views: `public struct` + `public init(...)` + `public var body`; classes: `public` + `public` on the used members; `@Published` stay as declared with `public` access; enums/statics likewise). Iterate until green. Expect the bulk in: Models.swift, BobState, Prefs, AttendanceLogic, WidgetSnapshot, SSOSignIn, Components (colors + `AutoLoginInline`/`SignInFactorGroup`), BobMascot, TodayVariants (`LiquidHero`, `StatusPill`, swimmer Bobs, `TodayVals`), EditableDayStrip, DashboardSections (`CalendarHeatmap`, `BalanceTrendCard`, `ProgressRing`), TimeOffPane (`TimeOffCalendar`, `TimeOffBookingSheet`), DashboardView (`DashboardBG`, `Card`, `StatTile`, `PaneHeader`, `DayFmt`), Onboarding (`OnboardingController.completed`, `OnboardingView`), Prefs' `Notification.Name` extension.
- [ ] **Step 5:** Verify: iOS build green AND Mac build + tests green (`public` in a single-module build is harmless).
- [ ] **Step 6:** Commit: `"iOS: consume BetterBobShared as a real SPM package"`

---

### Task 3: App icon + asset catalog + accent color

**Files:**
- Create: `iOS/Colimate-style asset catalog` → `iOS/Resources/Assets.xcassets/` with `AppIcon.appiconset` (single 1024 `icon-1024.png` generated from `Scripts/generate_icon.swift`), `AppIcon.icon/` (copy of repo `Resources/AppIcon.icon` Icon Composer document), `AccentColor.colorset` (BetterBob teal)
- Modify: `iOS/project.yml`

- [ ] **Step 1:** Generate the icon PNG: `swift Scripts/generate_icon.swift /tmp/bob-iconset` then take its 1024px PNG into `iOS/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` with a single-size `Contents.json` (`"platform": "ios", "size": "1024x1024"`).
- [ ] **Step 2:** Copy `Resources/AppIcon.icon` → `iOS/Resources/Assets.xcassets/AppIcon.icon` (Icon Composer layered icon; shares the AppIcon name).
- [ ] **Step 3:** `AccentColor.colorset/Contents.json` with BetterBob's teal (match `Color.bobTeal`'s values from Components.swift).
- [ ] **Step 4:** project.yml app target: add `- path: Resources/Assets.xcassets` to sources; settings gain `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` and `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor`.
- [ ] **Step 5:** Build, install to simulator, screenshot the home screen icon. Commit: `"iOS: Bob app icon, accent color, asset catalog"`

---

### Task 4: Glass design primitives

**Files:**
- Create: `iOS/Sources/Common/Glass.swift` (`GlassSurface`, `GlassCard`), `iOS/Sources/Common/GlassSection.swift` (`GlassGroupedSection`, `GlassRow`), `iOS/Sources/Common/Backdrop.swift` (BetterBob gradient backdrop + `.bobScreen()` modifier)

**Interfaces (consumed by Tasks 5–9):**
- `GlassCard(padding: CGFloat = 18) { content }` — glass card surface
- `GlassGroupedSection(header: String? = nil, footer: String? = nil) { rows }` + `GlassRow(showDivider: Bool = true) { content }` — inset-grouped-List look
- `View.bobScreen(title: String)` — backdrop + `.scrollContentBackground(.hidden)` + large `navigationTitle`; toolbars stay default so iOS 26 supplies scroll-aware glass.

- [ ] **Step 1:** Write the three files. Recipe fixed by Global Constraints; backdrop reuses the shared `DashboardBG`-style gradient in BetterBob's hues (subtle teal-tinted, scheme-adaptive), applied `.ignoresSafeArea()`.
- [ ] **Step 2:** Build iOS green. Commit: `"iOS: glass design primitives (card, grouped section, backdrop)"`

---

### Task 5: Native onboarding / sign-in screen

**Files:**
- Create: `iOS/Sources/Screens/OnboardingScreen.swift`
- Modify: `iOS/Sources/App/BetterBobApp.swift` (present it), `iOS/Sources/App/TodayTab.swift` → replaced in Task 6

Recipe (BetterBob identity, Colimate structure): full-screen `ZStack` over the backdrop; hero `AnimatedBob` (~140pt) with staged entrance; title block — "Hi, I'm Bob" `.largeTitle.bold()`, subtitle `.body` secondary, centered; then two paths:
- Primary card: "Sign in automatically" — email + password in `GlassRow`s (`.textContentType`, `.keyboardType`), full-width `.buttonStyle(.glassProminent)` `.controlSize(.large)` "Save & choose a method", then `SignInFactorGroup` once saved (mirror OnboardingView's logic — Keychain save via same `state.setupAutoLogin(email:password:)` path).
- Secondary: full-width `.buttonStyle(.glass)` "Sign in with a browser" → `state.startSSOSignIn()` (sheet appears via existing `signInSheet()`).
- While `state.autoLoginInProgress || awaitingOTP || pushPending`: show `AutoLoginInline(state:)` in a `GlassCard`.
- Footer `.footnote` secondary: same trust copy as the Mac onboarding (session only used against app.hibob.com).

- [ ] Steps: write screen → wire `fullScreenCover` → build → simulator screenshot → visually check typography/spacing → commit `"iOS: native onboarding with glass hero"`.

---

### Task 6: Today screen restyle

**Files:**
- Create: `iOS/Sources/Screens/TodayScreen.swift`
- Delete: `iOS/Sources/App/TodayTab.swift`
- Modify: `iOS/Sources/App/RootTabs.swift`

Layout: `.bobScreen(title: "Today")`; content `VStack(spacing: 16)`:
1. **Hero card**: `LiquidHero` (untouched wave + swimming Bob, via `TodayVals` fraction) inside a `GlassCard(padding: 0)` clipped to the card shape, height ~180; `StatusPill` + worked/target overlay text at Dynamic Type sizes.
2. **Action row**: clock in/out/break as `.glassProminent` (primary action per `projectedClockState`) + `.glass` (secondary), full-width in an `HStack`, driven by the same `state.clockIn()/clockOut()/startManualBreak()/endBreak()` queue.
3. **Timeline card**: `EditableDayStrip` (drag editing works with touch) + boundary times in a `GlassCard`.
4. **Entries**: `GlassGroupedSection(header: "Today")` of `GlassRow`s — kind icon, time range `.body`, reason menu (native `Menu` from `state.reasonOptions`), delete via `swipeActions`-like context menu.
5. **Warnings** (missing break / over max / queue pending) as tinted glass banners `.footnote`.
6. Signed-out state: compact version of the onboarding sign-in card.

- [ ] Steps: write → wire into RootTabs → build → screenshot → commit `"iOS: native Today screen — wave hero, glass actions, touch timeline"`.

---

### Task 7: Month screen restyle (+ Activity)

**Files:**
- Create: `iOS/Sources/Screens/MonthScreen.swift`, `iOS/Sources/Screens/ActivityScreen.swift`
- Modify: `iOS/Sources/App/RootTabs.swift`

Layout: `.bobScreen(title: "Month")`: 2-column `LazyVGrid` of stat tiles (worked, balance, overtime, days — from `state.cycleSummary`) as small `GlassCard`s; `CalendarHeatmap` in a `GlassCard`; `BalanceTrendCard` chart in a `GlassCard`; day list as `GlassRow`s opening the existing `DayDetailSheet` in `.sheet` (it already lost its fixed width on iOS). Activity: `GlassRow` list of `state.activity`, pushed from a toolbar clock icon. Ensure `state.setDashboardActive(true)` on appear so month data loads.

- [ ] Steps: write both → wire → build → screenshot → commit `"iOS: native Month and Activity screens"`.

---

### Task 8: Time Off screen restyle

**Files:**
- Create: `iOS/Sources/Screens/TimeOffScreen.swift`
- Modify: `iOS/Sources/App/RootTabs.swift`

Layout: `.bobScreen(title: "Time Off")`: balance cards (per policy type, `GlassCard` grid with `ProgressRing`); shared `TimeOffCalendar` in a `GlassCard` (tap/drag range select works on touch); requests as `GlassRow`s with cancel via confirmation dialog; booking flows through the existing `TimeOffBookingSheet` in `.sheet(...).presentationDetents([.medium, .large])`.

- [ ] Steps: write → wire → build → screenshot → commit `"iOS: native Time Off screen"`.

---

### Task 9: Settings screen restyle

**Files:**
- Create: `iOS/Sources/Screens/SettingsScreen.swift`
- Modify: `iOS/Sources/App/RootTabs.swift` (drop shared `SettingsPanel` usage on iOS)

`GlassGroupedSection`s mirroring the Mac panel's iOS-relevant groups, all rows native `Toggle`/`LabeledContent`/`Picker`/`Stepper` bound to the same `Prefs`/`BobState`:
- **Account** — signed-in row, "Sign-in setup" (posts `.presentOnboarding`), "Sign out" destructive.
- **Automatic break** — enable toggle; threshold + break length (native `Picker` of minute steps or `PillStepper` if it reads well; prefer native).
- **Daily limit** — max-day stepper with footer copy.
- **Reasons** — default reason `Picker` (footer: applied to untagged open entries).
- **Notifications** — the six toggles.
- **General** — auto-fix gaps toggle with footer.
- **Diagnostics** — last error row when present.
Footers carry the Mac panel's explanatory copy (trimmed for phone width).

- [ ] Steps: write → wire → build → screenshot → commit `"iOS: native Settings with glass grouped sections"`.

---

### Task 10: Final verification + docs

- [ ] Full sweep: `./Scripts/build.sh && ./Scripts/test.sh`; regenerate + build iOS app and widget; install to simulator; screenshot every tab + onboarding; check: no emojis, Dynamic Type sizes, wave hero intact, icon on home screen.
- [ ] Update `AGENTS.md` iOS section: package structure (`Packages/BetterBobShared`, public-API convention, mac glob), iOS screens layout (`iOS/Sources/Screens`, `Common`), icon/asset notes.
- [ ] Commit: `"iOS: document package + native screen structure"`.
