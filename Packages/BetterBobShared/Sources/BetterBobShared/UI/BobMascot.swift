import SwiftUI
#if os(macOS)
import AppKit
#endif

// Bob — the BetterBob mascot, a (cute) beaver. Beavers are the original
// clock-watchers: industrious, always building on schedule. Drawn as vector
// art so he's crisp at any size, adapts to light/dark, animates in-app, and
// renders down to a template menu-bar image and the app icon.

/// Bob's palette. `mono` collapses everything to a single ink colour for the
/// template menu-bar glyph.
public struct BobPalette {
    public init() {}
    var furLight = Color(red: 0.64, green: 0.44, blue: 0.28)
    var fur      = Color(red: 0.55, green: 0.36, blue: 0.22)
    var furDark  = Color(red: 0.42, green: 0.27, blue: 0.16)
    var muzzle   = Color(red: 0.92, green: 0.82, blue: 0.68)
    var teeth    = Color(red: 0.99, green: 0.98, blue: 0.93)
    var nose     = Color(red: 0.28, green: 0.18, blue: 0.13)
    var pupil    = Color(red: 0.16, green: 0.10, blue: 0.07)
    var blush    = Color(red: 0.93, green: 0.55, blue: 0.48)
    var outline  = Color(red: 0.30, green: 0.19, blue: 0.11)
    // Bob's cap wears the Mac's accent, like the rest of the brand.
    var capBlue  = Color.systemAccentHued(sat: 0.83, bri: 0.58)
    var capDark  = Color.systemAccentHued(sat: 0.85, bri: 0.39)
}

/// A single frame of Bob's face. `blink` 0→1 closes the eyes; `tail` -1→1 wags
/// the paddle tail; `look` shifts the pupils horizontally.
struct BobMascot: View {
    var blink: CGFloat = 0
    var tail: CGFloat = 0
    var look: CGSize = .zero      // -1…1 each axis; where the pupils point
    var palette = BobPalette()

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                arms(s)
                bodyShape(s)
                feet(s)
                ears(s)
                head(s)
                cap(s)
                cheeks(s)
                eyes(s)
                muzzle(s)
            }
            .frame(width: s, height: s)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: pieces (unit coordinates × s, y down)

    private func arms(_ s: CGFloat) -> some View {
        ForEach([0.24, 0.76], id: \.self) { ux in
            Ellipse().fill(palette.fur)
                .frame(width: s * 0.13, height: s * 0.18)
                .position(x: s * ux, y: s * 0.69)
        }
    }

    private func bodyShape(_ s: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.20, style: .continuous)
                .fill(LinearGradient(colors: [palette.furLight, palette.fur],
                                     startPoint: .top, endPoint: .bottom))
            Ellipse().fill(palette.muzzle.opacity(0.8))
                .frame(width: s * 0.28, height: s * 0.30)
                .offset(y: s * 0.04)
        }
        .frame(width: s * 0.48, height: s * 0.44)
        .position(x: s * 0.5, y: s * 0.73)
    }

    private func feet(_ s: CGFloat) -> some View {
        ForEach([0.40, 0.60], id: \.self) { ux in
            Ellipse().fill(palette.furDark)
                .frame(width: s * 0.16, height: s * 0.10)
                .position(x: s * ux, y: s * 0.93)
        }
    }

    private func head(_ s: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(
                LinearGradient(colors: [palette.furLight, palette.fur],
                               startPoint: .top, endPoint: .bottom))
            Ellipse().strokeBorder(palette.outline.opacity(0.25), lineWidth: s * 0.012)
        }
        .frame(width: s * 0.58, height: s * 0.54)
        .position(x: s * 0.5, y: s * 0.37)
    }

    private func ears(_ s: CGFloat) -> some View {
        ForEach([0.21, 0.79], id: \.self) { ux in
            ZStack {
                Circle().fill(palette.fur)
                Circle().fill(palette.furDark).frame(width: s * 0.085, height: s * 0.085)
            }
            .frame(width: s * 0.18, height: s * 0.18)
            .position(x: s * ux, y: s * 0.23)
        }
    }

    private func cap(_ s: CGFloat) -> some View {
        ZStack {
            // Visor — a wide, thin brim over the brow.
            RoundedRectangle(cornerRadius: s * 0.05, style: .continuous).fill(palette.capDark)
                .frame(width: s * 0.72, height: s * 0.12)
                .position(x: s * 0.5, y: s * 0.30)
            // Crown — a rounded dome: fully round on top, flat where it meets
            // the visor (an ellipse pinches in at the bottom and reads as an egg).
            UnevenRoundedRectangle(topLeadingRadius: s * 0.30, bottomLeadingRadius: s * 0.06,
                                   bottomTrailingRadius: s * 0.06, topTrailingRadius: s * 0.30,
                                   style: .continuous)
                .fill(LinearGradient(colors: [palette.capBlue, palette.capBlue.opacity(0.88)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.60, height: s * 0.34)
                .position(x: s * 0.5, y: s * 0.185)
            // Button on top.
            Circle().fill(palette.capDark)
                .frame(width: s * 0.045, height: s * 0.045)
                .position(x: s * 0.5, y: s * 0.02)
            // Wordmark.
            Text("bob")
                .font(.system(size: s * 0.15, weight: .heavy))
                .foregroundStyle(.white)
                .position(x: s * 0.5, y: s * 0.17)
        }
    }

    private func cheeks(_ s: CGFloat) -> some View {
        ForEach([0.32, 0.68], id: \.self) { ux in
            Ellipse().fill(palette.blush.opacity(0.45))
                .frame(width: s * 0.13, height: s * 0.085)
                .position(x: s * ux, y: s * 0.46)
                .blur(radius: s * 0.006)
        }
    }

    private func eyes(_ s: CGFloat) -> some View {
        ForEach([0.39, 0.61], id: \.self) { ux in
            ZStack(alignment: .top) {
                Circle().fill(.white)
                    .overlay(Circle().strokeBorder(palette.outline.opacity(0.18), lineWidth: s * 0.006))
                Circle().fill(palette.pupil)
                    .frame(width: s * 0.075, height: s * 0.075)
                    .offset(x: look.width * s * 0.032, y: s * 0.03 + look.height * s * 0.03)
                Circle().fill(.white.opacity(0.9))
                    .frame(width: s * 0.024, height: s * 0.024)
                    .offset(x: look.width * s * 0.032 - s * 0.018, y: s * 0.012 + look.height * s * 0.03)
                // Eyelid closes from the top for the blink.
                palette.furLight
                    .frame(height: s * 0.15 * blink)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(width: s * 0.15, height: s * 0.15)
            .clipShape(Circle())
            .position(x: s * ux, y: s * 0.35)
        }
    }

    private func muzzle(_ s: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(palette.muzzle)
                .frame(width: s * 0.40, height: s * 0.30)
            // nose
            RoundedRectangle(cornerRadius: s * 0.03, style: .continuous)
                .fill(palette.nose)
                .frame(width: s * 0.12, height: s * 0.08)
                .offset(y: -s * 0.055)
            // two big front teeth
            HStack(spacing: s * 0.008) {
                tooth(s); tooth(s)
            }
            .offset(y: s * 0.06)
        }
        .position(x: s * 0.5, y: s * 0.48)
    }

    private func tooth(_ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: s * 0.012, style: .continuous)
            .fill(palette.teeth)
            .overlay(RoundedRectangle(cornerRadius: s * 0.012, style: .continuous)
                .strokeBorder(palette.outline.opacity(0.18), lineWidth: s * 0.005))
            .frame(width: s * 0.062, height: s * 0.12)
    }

}

/// Idle-animated Bob for the app — gentle breathing, an occasional blink, and
/// a lazy tail wag, all derived deterministically from the clock (no timers).
/// `sleeping` closes his eyes, slows the breathing, and floats z's — used
/// wherever the clock is off (same look as the phone page).
public struct AnimatedBob: View {
    /// When set, Bob's eyes point here (−1…1 each axis) instead of idly wandering.
    var lookAt: CGSize? = nil
    var sleeping = false
    var palette = BobPalette()

    public init(lookAt: CGSize? = nil, sleeping: Bool = false, palette: BobPalette = BobPalette()) {
        self.lookAt = lookAt
        self.sleeping = sleeping
        self.palette = palette
    }
    // Only animate while the window is really visible — a retained-but-
    // hidden view (closed popover or closed-yet-retained window) must not
    // keep the 24fps clock running. Gated on the window tracker alone:
    // onAppear/onDisappear misfire during pane transitions.
    @State private var windowVisible = true

    public var body: some View {
        Group {
            if windowVisible {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    if sleeping {
                        // Deep, slow breaths; eyes shut; the cursor can't wake him.
                        BobMascot(blink: 1, look: .zero, palette: palette)
                            .scaleEffect(1 + 0.035 * sin(t * 0.9), anchor: .bottom)
                            .overlay(alignment: .topTrailing) { zzz(t) }
                    } else {
                        let breathe = 1 + 0.02 * sin(t * 1.6)
                        let tail = CGFloat(sin(t * 1.8)) * 0.6
                        // A quick blink in the first ~0.16s of every 4.2s cycle.
                        let cycle = t.truncatingRemainder(dividingBy: 4.2)
                        let blink = cycle < 0.16 ? CGFloat(sin(cycle / 0.16 * .pi)) : 0
                        let idle = CGSize(width: sin(t * 0.7) * 0.5, height: sin(t * 0.9) * 0.18)
                        BobMascot(blink: blink, tail: tail, look: lookAt ?? idle, palette: palette)
                            .scaleEffect(breathe, anchor: .bottom)
                            .animation(.easeOut(duration: 0.18), value: lookAt)
                    }
                }
            } else {
                BobMascot(blink: sleeping ? 1 : 0, look: sleeping ? .zero : (lookAt ?? .zero),
                          palette: palette)
            }
        }
        .trackWindowVisibility { windowVisible = $0 }
    }

    /// Three z's drifting up-right on staggered phases of one shared cycle.
    private func zzz(_ t: Double) -> some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(0..<3, id: \.self) { i in
                let phase = (t / 2.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: 8 + CGFloat(i) * 3, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(sin(phase * .pi) * 0.9)
                    .offset(x: CGFloat(i) * 7 + phase * 4,
                            y: -CGFloat(i) * 7 - phase * 6)
            }
        }
        .offset(x: 8, y: 2)
    }
}

/// Bob asleep on his side, in profile: lying flat with his tail out the
/// back, cap still on, one closed eye — perfectly still except his chest
/// slowly rising and falling. Draw in a 1.6:1 frame.
struct SleepingBob: View {
    var palette = BobPalette()
    @State private var windowVisible = true

    var body: some View {
        Group {
            if windowVisible && !Motion.reduce {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    content(breathe: 1 + 0.05 * (0.5 + 0.5 * sin(t * 0.75)))
                        .overlay(alignment: .topTrailing) { DriftingZs().offset(x: 0, y: 4) }
                }
            } else {
                content(breathe: 1)
            }
        }
        .trackWindowVisibility { windowVisible = $0 }
    }

    private func content(breathe: Double) -> some View {
        GeometryReader { g in
            let s = min(g.size.width / 1.6, g.size.height)
            let w = s * 1.6
            ZStack {
                // Paddle tail, flat on the ground behind him.
                Ellipse().fill(palette.furDark)
                    .frame(width: w * 0.24, height: s * 0.14)
                    .rotationEffect(.degrees(-10))
                    .position(x: w * 0.10, y: s * 0.86)
                // Body and belly breathe together, anchored at the ground so
                // only the chest rises.
                ZStack {
                    Ellipse().fill(LinearGradient(colors: [palette.furLight, palette.fur],
                                                  startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.54, height: s * 0.54)
                    Ellipse().fill(palette.muzzle.opacity(0.8))
                        .frame(width: w * 0.28, height: s * 0.26)
                        .offset(x: -w * 0.02, y: s * 0.10)
                }
                .scaleEffect(x: 1, y: breathe, anchor: .bottom)
                .position(x: w * 0.40, y: s * 0.70)
                // Rear foot poking out front.
                Ellipse().fill(palette.furDark)
                    .frame(width: w * 0.13, height: s * 0.10)
                    .position(x: w * 0.24, y: s * 0.92)
                // Head resting on the ground.
                Circle().fill(LinearGradient(colors: [palette.furLight, palette.fur],
                                             startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.58, height: s * 0.58)
                    .position(x: w * 0.72, y: s * 0.66)
                // Ear.
                ZStack {
                    Circle().fill(palette.fur)
                    Circle().fill(palette.furDark)
                        .frame(width: s * 0.08, height: s * 0.08)
                }
                .frame(width: s * 0.17, height: s * 0.17)
                .position(x: w * 0.66, y: s * 0.40)
                // Cap, slid back on the resting head.
                ZStack {
                    UnevenRoundedRectangle(topLeadingRadius: s * 0.14, bottomLeadingRadius: s * 0.03,
                                           bottomTrailingRadius: s * 0.03, topTrailingRadius: s * 0.14,
                                           style: .continuous)
                        .fill(LinearGradient(colors: [palette.capBlue, palette.capBlue.opacity(0.88)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: s * 0.42, height: s * 0.22)
                    RoundedRectangle(cornerRadius: s * 0.03, style: .continuous)
                        .fill(palette.capDark)
                        .frame(width: s * 0.30, height: s * 0.07)
                        .offset(x: s * 0.14, y: s * 0.13)
                }
                .rotationEffect(.degrees(-22))
                .position(x: w * 0.63, y: s * 0.36)
                // Closed eye — a gentle downward curve.
                Capsule().fill(palette.pupil)
                    .frame(width: s * 0.14, height: s * 0.030)
                    .rotationEffect(.degrees(8))
                    .position(x: w * 0.76, y: s * 0.60)
                // Blush.
                Ellipse().fill(palette.blush.opacity(0.45))
                    .frame(width: w * 0.09, height: s * 0.07)
                    .position(x: w * 0.72, y: s * 0.72)
                // Muzzle in profile, nose up front, one tooth.
                Ellipse().fill(palette.muzzle)
                    .frame(width: w * 0.16, height: s * 0.22)
                    .position(x: w * 0.84, y: s * 0.72)
                RoundedRectangle(cornerRadius: s * 0.02, style: .continuous)
                    .fill(palette.nose)
                    .frame(width: w * 0.05, height: s * 0.07)
                    .position(x: w * 0.885, y: s * 0.62)
                RoundedRectangle(cornerRadius: s * 0.012, style: .continuous)
                    .fill(palette.teeth)
                    .frame(width: w * 0.035, height: s * 0.10)
                    .position(x: w * 0.845, y: s * 0.84)
            }
            .frame(width: w, height: s)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .aspectRatio(1.6, contentMode: .fit)
    }
}

/// A friendly full-pane placeholder: a gently bouncing Bob with a title and a
/// rotating playful caption, plus optional trailing content (buttons/spinner).
public struct BobPlaceholder<Trailing: View>: View {
    let title: String
    let lines: [String]
    let size: CGFloat
    let sleeping: Bool
    let trailing: Trailing

    @State private var windowVisible = true

    public init(title: String, lines: [String] = [], size: CGFloat = 96, sleeping: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.lines = lines; self.size = size
        self.sleeping = sleeping; self.trailing = trailing()
    }

    public var body: some View {
        Group {
            if windowVisible {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    content(bounce: CGFloat(sin(t * 2.0)) * 4,
                            idx: lines.isEmpty ? 0 : Int(t / 2.8) % lines.count)
                }
            } else {
                content(bounce: 0, idx: 0)
            }
        }
        .trackWindowVisibility { windowVisible = $0 }
    }

    private func content(bounce: CGFloat, idx: Int) -> some View {
        VStack(spacing: 14) {
            AnimatedBob(sleeping: sleeping).frame(width: size, height: size)
                .offset(y: sleeping ? 0 : bounce)
            VStack(spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if !lines.isEmpty {
                    Text(lines[idx]).font(.system(size: 12)).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.35), value: idx)
                }
            }
            trailing
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

extension BobPlaceholder where Trailing == EmptyView {
    init(title: String, lines: [String] = [], size: CGFloat = 96, sleeping: Bool = false) {
        self.init(title: title, lines: lines, size: size, sleeping: sleeping) { EmptyView() }
    }
}

/// Rotating captions for Bob's placeholders.
public enum BobLines {
    public static let loading = ["Gnawing through the data…", "Counting your hours…",
                          "Stacking today's logs…", "Consulting the dam records…",
                          "Fetching your timesheet…"]
    public static let signedOut = ["Bob's off the clock too", "No dam gets built without you",
                            "Clock's waiting…", "Punch in to get started",
                            "Rise and grind? Sign in first"]
}

/// Bob's face silhouette — the Mac menu-bar glyph's geometry as a
/// resolution-independent SwiftUI mark, so widgets and small chrome can use
/// Bob where an SF Symbol would go. Same unit coordinates as `BobIcon`,
/// flipped into SwiftUI's y-down space.
public struct BobFaceMark: View {
    /// What Bob's face says about the clock: eyes open while working,
    /// sunglasses on a break, eyes closed when clocked out.
    public enum Expression {
        case awake, shades, asleep
    }

    var color: Color
    var expression: Expression

    public init(color: Color = .primary, expression: Expression = .awake) {
        self.color = color
        self.expression = expression
    }

    public var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            func ell(_ ux: CGFloat, _ uy: CGFloat, _ uw: CGFloat, _ uh: CGFloat) -> CGRect {
                CGRect(x: (ux - uw / 2) * s, y: (1 - uy - uh / 2) * s,
                       width: uw * s, height: uh * s)
            }
            // Zoom around the face bundle's centre so ears/head/teeth fill
            // the canvas — mirrors the menu-bar glyph's transform.
            ctx.translateBy(x: 0.5 * s, y: 0.5 * s)
            ctx.scaleBy(x: 1.35, y: 1.35)
            ctx.translateBy(x: -0.5 * s, y: -(1 - 0.6575) * s)

            var face = Path()
            face.addEllipse(in: ell(0.24, 0.82, 0.17, 0.17))
            face.addEllipse(in: ell(0.76, 0.82, 0.17, 0.17))
            face.addEllipse(in: ell(0.5, 0.63, 0.58, 0.54))
            face.addRoundedRect(in: ell(0.5, 0.47, 0.16, 0.12),
                                cornerSize: CGSize(width: 0.02 * s, height: 0.02 * s))
            ctx.fill(face, with: .color(color))

            // Punch holes: the eyes (per expression) and the tooth gap.
            ctx.blendMode = .clear
            var holes = Path()
            switch expression {
            case .awake:
                holes.addEllipse(in: ell(0.39, 0.69, 0.15, 0.15))
                holes.addEllipse(in: ell(0.61, 0.69, 0.15, 0.15))
            case .shades:
                // One punched band across both eyes — reads as sunglasses
                // in silhouette.
                holes.addRoundedRect(in: ell(0.5, 0.69, 0.46, 0.13),
                                     cornerSize: CGSize(width: 0.04 * s, height: 0.04 * s))
            case .asleep:
                // Two thin slits: closed lids.
                holes.addRoundedRect(in: ell(0.39, 0.67, 0.15, 0.035),
                                     cornerSize: CGSize(width: 0.02 * s, height: 0.02 * s))
                holes.addRoundedRect(in: ell(0.61, 0.67, 0.15, 0.035),
                                     cornerSize: CGSize(width: 0.02 * s, height: 0.02 * s))
            }
            holes.addRect(ell(0.5, 0.45, 0.02, 0.10))
            ctx.fill(holes, with: .color(color))
        }
    }
}

#if os(macOS)
@MainActor
enum BobIcon {
    /// Corner badge: play while working, pause on a break, a lock when signed
    /// out, none when clocked out (plain Bob).
    enum StateBadge: String {
        case none, play, pause, lock
    }

    /// Cached template image of Bob for the menu bar.
    private static var cache: [String: NSImage] = [:]

    /// A one-colour Bob face silhouette (ears, head, teeth — matching the
    /// face-and-cap app icon) with the eyes and tooth gap punched out — drawn
    /// in Core Graphics so overlapping parts union cleanly (non-zero) and the
    /// holes are cut with a clear blend. Marked as a template so the menu bar
    /// tints it automatically.
    static func menuBar(height: CGFloat = 18, badge: StateBadge = .none) -> NSImage {
        let key = "\(Int(height * 4))-\(badge.rawValue)"
        if let img = cache[key] { return img }

        // Draw in points — AppKit renders the closure at the display's scale,
        // so there's no pixel/point size mismatch.
        let img = NSImage(size: CGSize(width: height, height: height), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let s = height
            // Centre-based ellipse / rounded-rect in unit coords, y up.
            func ell(_ ux: CGFloat, _ uy: CGFloat, _ uw: CGFloat, _ uh: CGFloat) -> CGRect {
                CGRect(x: (ux - uw / 2) * s, y: (uy - uh / 2) * s, width: uw * s, height: uh * s)
            }
            func round(_ r: CGRect, _ rad: CGFloat) -> CGPath {
                CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
            }
            // Face only, zoomed to fill (the app icon is face-and-cap now):
            // scale around the face bundle's centre so ears/head/teeth span
            // the canvas; the old full-body parts are gone.
            ctx.saveGState()
            ctx.translateBy(x: 0.5 * s, y: 0.5 * s)
            ctx.scaleBy(x: 1.35, y: 1.35)
            ctx.translateBy(x: -0.5 * s, y: -0.6575 * s)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.addEllipse(in: ell(0.24, 0.82, 0.17, 0.17))
            ctx.addEllipse(in: ell(0.76, 0.82, 0.17, 0.17))
            ctx.addEllipse(in: ell(0.5, 0.63, 0.58, 0.54))
            ctx.addPath(round(ell(0.5, 0.47, 0.16, 0.12), s * 0.02))
            ctx.fillPath()
            // Punch holes: two eyes and the vertical tooth gap.
            ctx.setBlendMode(.clear)
            ctx.addEllipse(in: ell(0.39, 0.69, 0.15, 0.15))
            ctx.addEllipse(in: ell(0.61, 0.69, 0.15, 0.15))
            ctx.addRect(ell(0.5, 0.45, 0.02, 0.10))
            ctx.fillPath()
            ctx.setBlendMode(.normal)
            ctx.restoreGState()

            // State badge in the bottom-right corner: a filled disc with the
            // glyph punched out, and a clear ring around it so it reads as its
            // own glyph where it overlaps Bob.
            if badge != .none {
                let cx: CGFloat = 0.78, cy: CGFloat = 0.22
                ctx.setBlendMode(.clear)
                ctx.addEllipse(in: ell(cx, cy, 0.56, 0.56))
                ctx.fillPath()
                ctx.setBlendMode(.normal)
                ctx.setFillColor(CGColor(gray: 0, alpha: 1))
                ctx.addEllipse(in: ell(cx, cy, 0.44, 0.44))
                ctx.fillPath()
                ctx.setBlendMode(.clear)
                switch badge {
                case .play:
                    let tri = CGMutablePath()
                    tri.move(to: CGPoint(x: (cx - 0.075) * s, y: (cy - 0.10) * s))
                    tri.addLine(to: CGPoint(x: (cx - 0.075) * s, y: (cy + 0.10) * s))
                    tri.addLine(to: CGPoint(x: (cx + 0.115) * s, y: cy * s))
                    tri.closeSubpath()
                    ctx.addPath(tri)
                case .pause:
                    ctx.addPath(round(ell(cx - 0.055, cy, 0.05, 0.20), s * 0.015))
                    ctx.addPath(round(ell(cx + 0.055, cy, 0.05, 0.20), s * 0.015))
                case .lock:
                    // Padlock: a rounded body, punched, with a stroked shackle
                    // arc above it. Drawn here (fill + stroke) so the shared
                    // fillPath below is a no-op for this case.
                    ctx.addPath(round(ell(cx, cy - 0.045, 0.20, 0.15), s * 0.03))
                    ctx.fillPath()
                    ctx.setLineWidth(s * 0.038)
                    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
                    ctx.addArc(center: CGPoint(x: cx * s, y: (cy + 0.03) * s),
                               radius: 0.062 * s, startAngle: 0, endAngle: .pi, clockwise: false)
                    ctx.strokePath()
                case .none:
                    break
                }
                ctx.fillPath()
                ctx.setBlendMode(.normal)
            }
            return true
        }
        img.isTemplate = true
        cache[key] = img
        return img
    }
}

extension NSImage {
    /// A colored copy of a template image (its alpha as a mask) — used to tint
    /// Bob's silhouette for the menu bar and the popover mark.
    func tinted(_ color: NSColor) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            color.set()
            rect.fill()
            self.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        img.isTemplate = false
        return img
    }
}
#endif
