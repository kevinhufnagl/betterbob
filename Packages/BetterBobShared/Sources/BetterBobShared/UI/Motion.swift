import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Shared motion vocabulary — one place for the app's animation timing so the
// popover and dashboard move the same way. Every accessor collapses to nil
// (no animation) when the system's Reduce Motion setting is on, so passing
// these to .animation(_:value:) automatically honors accessibility.
enum Motion {
    static var reduce: Bool {
        #if os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        UIAccessibility.isReduceMotionEnabled
        #endif
    }

    /// Default for state-driven layout changes — clock state, banners, rows.
    static var standard: Animation? { reduce ? nil : .smooth(duration: 0.28) }
    /// Rolling numbers (worked time, percentages) — a touch slower so the
    /// numericText digits are readable mid-flight.
    static var numeric: Animation? { reduce ? nil : .smooth(duration: 0.4) }
    /// Hover / press feedback.
    static var quick: Animation? { reduce ? nil : .easeOut(duration: 0.13) }
    /// Pane/tab swaps — a small spring so sections settle rather than stop.
    static var lively: Animation? { reduce ? nil : .spring(response: 0.38, dampingFraction: 0.82) }
}

extension AnyTransition {
    /// Soft cross-dissolve with a hint of scale — content swapping in place.
    static let bobReplace = AnyTransition.opacity.combined(with: .scale(scale: 0.97))
    /// Banners and warning rows: grow in from the top edge, fade away.
    static let bobBanner = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
        removal: .opacity)
    /// Dashboard pane swap: new content rises in slightly, old content fades.
    static let bobSection = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 8)),
        removal: .opacity)
}

/// Style for the capsule action buttons: a subtle press-down scale so clicks
/// feel physical. Visual-only — behaves exactly like .plain otherwise.
struct PressablePillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Motion.reduce ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}
