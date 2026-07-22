---
name: mac-liquid-glass
description: Use when building or styling any UI for the BetterBob macOS app — popover, dashboard/main window, settings, onboarding, menu bar — especially anything described as glassy, floating, translucent, frosted, card, panel, pill, capsule, dock, or button. Also use when picking colors, animations, hover states, or window/popover plumbing for the Mac app.
---

# Mac Native UI + Liquid Glass (BetterBob)

The Mac app targets macOS 26 and uses the **real Liquid Glass APIs**
(`glassEffect`, `GlassEffectContainer`, `glassEffectID`) — never fake glass
with materials or solid fills. Shared UI lives in
`Packages/BetterBobShared/Sources/BetterBobShared/{UI,Features}/` and compiles
into the Mac module directly (no `import BetterBobShared` in Mac code).

## Which surface treatment? (decision table)

| You are building | Use | Source of truth |
|---|---|---|
| A page/panel filling a window | `.pagePanelChrome()` — `glassEffect(.regular, in: .rect(cornerRadius: 16))` + 0.5pt `Color.white.opacity(0.05)` hairline | `UI/Components.swift:14` |
| Floating action buttons / a dock of pills | `GlassEffectContainer` + per-button interactive glass capsules (recipe below) | `Features/TodayVariants.swift` (`ActionDock`/`DockButton`) |
| A small badge/pill sitting ON saturated color (the water hero) | `.regularMaterial` backing capsule + tint fill + tinted `strokeBorder` — bare glass/tint washes out there | `StatusPill`, `TodayVariants.swift:66` |
| Content nested inside a glass panel | `.insetCard()` (`Color.primary.opacity(0.04)` fill + 0.06 hairline) | `UI/Components.swift:57` |
| A settings section | `SettingsGroup { … }` → solid `settingsCard()` on `.controlBackgroundColor` (System-Settings look, deliberately NOT glass) | `UI/Components.swift:69` |
| Tinted warning/info banner | tint `.opacity(0.08)` fill in rounded rect + `.opacity(0.28)` strokeBorder + `.transition(.bobBanner)` | `Popover.swift` warnings |
| Window-wide backdrop | `DashboardBG()` gradient behind panes; full-window effects via `.containerBackground(for: .window)` | `DashboardView.swift:23`, `MainWindow.swift:93` |

Glass needs a backdrop to refract — panes place `DashboardBG()` behind
content; never stack glass on plain window background.

## The canonical glass dock (copy this shape)

From `ActionDock` — floating pill buttons that straddle an edge:

```swift
@Namespace private var glassNS

GlassEffectContainer(spacing: 4) {   // spacing = merge radius; MUST stay
    HStack(spacing: 10) {            // BELOW the HStack gap or resting pills
                                     // distort toward each other
        Button(action: primary) { /* label */ }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(accentWash).interactive(), in: .capsule)
            .glassEffectID("primary", in: glassNS)   // matched ids morph
        Button(action: secondary) { /* label */ }    // across state changes
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("secondary", in: glassNS)
    }
}
.shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.14), radius: 12, y: 4)
```

Rules baked into that shape:

- **No wrapper capsule** — the pills ARE the dock. One shadow on the container.
- **Prominent = tinted glass, never a solid fill.** The wash is
  `accent.opacity(0.3)` inside the glass; foreground stays `Color.primary`
  (~0.9), never `.white` on a filled capsule.
- `.interactive()` supplies hover/press response — don't hand-roll highlight
  states on glass.
- Straddling an edge: host reserves `ActionDock.halfHeight` bottom padding and
  places the dock with `.overlay(alignment: .bottom)` (see `Popover.swift`
  `workedHeader` and `MainWindow`).
- Mac buttons get `.onHover { NSCursor.pointingHand.set() … }`.
- Sizes are the Mac tier: symbol 12, label 13, caption 9, height 40, padH 16
  (iOS sizes in the same file are bigger — don't copy those).

## Native conventions (Mac)

- **Shell**: `NSStatusItem` + `NSPopover` (`.transient`), not `MenuBarExtra`.
  Popover content is built on show (`NSHostingController` with
  `sizingOptions = [.preferredContentSize]`) and torn down in
  `popoverDidClose` so no clocks run while closed. Dashboard is a
  `Window("BetterBob", id: "main")` scene; opening it flips activation policy
  to `.regular` + `openWindow(id:)`, closing falls back to `.accessory`
  (`Sources/App/BetterBob.swift`).
- **Controls**: hand-rolled capsules over native chrome — `Color.primary
  .opacity(0.06–0.07)` fill + `0.10–0.15` hairline `strokeBorder`, and
  `PillDateField`/`PillStepper` instead of native steppers/pickers
  (`UI/PillControls.swift`). `.borderedProminent` only for a real primary
  form action (e.g. OTP "Sign in"). Menus: `.menuStyle(.button)` +
  `.menuIndicator(.hidden)` inside a styled capsule label.
- **Type**: fixed 9–13pt `.system(size:weight:)`; times/counters are
  `design: .monospaced` (or `.monospacedDigit()`) with
  `.contentTransition(.numericText())`; section captions 10–11pt semibold
  uppercase with `.kerning(0.5)`.
- **Color**: never stock `.green/.orange/.blue`. Everything derives from the
  system accent via `Color.systemAccentHued(sat:bri:)` /
  `primaryAccent(scheme)` / `controlAccent(scheme)` (scheme-aware pairs), plus
  fixed `bobTeal/bobOrange/bobRed/bobViolet` where the scheme can't be read
  (`UI/Components.swift:131`). Clock states already have a vocabulary:
  `ClockState.tint/.symbol/.title`.
- **Motion**: only `Motion.standard/numeric/quick/lively` (auto-nil under
  Reduce Motion) and transitions `.bobReplace/.bobBanner/.bobSection`;
  press feedback via `PressablePillStyle` (`UI/Motion.swift`).
- **Animation clocks**: 1s `TimelineView(.periodic…)` drives live time; any
  view owning a clock must be gated by `trackWindowVisibility` — MainWindow
  swaps its whole shell to `Color.clear` when hidden. Never `repeatForever`.

## Common mistakes

| Mistake | Fix |
|---|---|
| `.ultraThinMaterial` / `NSVisualEffectView` for a "glassy" control | Real `.glassEffect(…)`. Materials are only a legibility backing over saturated color (StatusPill, DayStrip labels) |
| Primary button = solid accent capsule + white text | Tinted interactive glass (`.regular.tint(accent.opacity(0.3)).interactive()`), `Color.primary` foreground |
| Wrapping dock pills in an outer capsule/panel | Pills are the dock; shadow on the `GlassEffectContainer` |
| `GlassEffectContainer(spacing:)` ≥ stack spacing | Keep container spacing below the gap — shapes should merge only mid-morph |
| Cross-fading between button sets on state change | Same `glassEffectID` namespace ids so one pill splits/merges |
| Glass panel without its hairline | Add 0.5pt `Color.white.opacity(0.05–0.10)` `strokeBorder` on the same shape |
| Skipping the backdrop | Glass over the bare window reads flat — put `DashboardBG()` (or the hero) behind it |
| Making settings glassy | Settings intentionally use solid `settingsCard()` |
