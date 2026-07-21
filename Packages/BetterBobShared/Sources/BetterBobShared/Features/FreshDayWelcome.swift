import SwiftUI

// The empty-day welcome, shared by both apps: a greeting, today's target,
// Bob, and the clock-in dock, over a calm band of the same water the hero
// uses — the real sharp-edged wave, laid horizontally along the bottom.

/// A horizontal band of the app's water: the same summed-sine waterline and
/// crisp rim highlight as the hero, transposed so it fills from the bottom
/// up. Transparent above the line, so it lays over any background.
public struct WaterBand: View {
    /// Water depth as a fraction of the band's height.
    var fill: Double
    var amplitude: CGFloat

    public init(fill: Double = 0.55, amplitude: CGFloat = 5) {
        self.fill = fill
        self.amplitude = amplitude
    }

    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    private var hue: Double { Color.accentHue }

    private var waterGradient: LinearGradient {
        let stops = dark
            ? [Color.hued(hue, sat: 0.72, bri: 0.44), Color.hued(hue, sat: 0.76, bri: 0.28)]
            : [Color.hued(hue, sat: 0.30, bri: 0.88), Color.hued(hue, sat: 0.32, bri: 0.80)]
        return LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }
    private var glowColor: Color {
        dark ? Color.hued(hue, sat: 0.45, bri: 0.88) : Color.hued(hue, sat: 0.14, bri: 0.99)
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let field = HWaveField(fill: fill, amplitude: Motion.reduce ? 0 : amplitude,
                                   phase: t * 0.6)
            let shape = HWaterShape(field: field)
            // The waterline sits at this fraction from the top.
            let line = 1 - min(1, fill)
            ZStack(alignment: .top) {
                shape.fill(waterGradient)
                // The signature glow: a vertical gradient over the water body
                // that ramps to a bright band right at the waterline and
                // fades down into the water — the hero's look, transposed.
                shape.fill(LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: glowColor.opacity(0), location: max(0, line - 0.05)),
                        .init(color: glowColor.opacity(0.14), location: max(0.001, line - 0.014)),
                        .init(color: glowColor.opacity(0.50), location: max(0.002, line)),
                        .init(color: glowColor.opacity(0), location: min(1, line + 0.18)),
                    ]),
                    startPoint: .top, endPoint: .bottom))
                // Crisp rim highlight along the waterline itself.
                HWaterEdgeShape(field: field)
                    .stroke(glowColor.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

/// A horizontal waterline: y as a function of x, water below. The same
/// three-sine sum and renormalization as the hero's vertical `WaveField`.
private struct HWaveField {
    var fill: Double
    var amplitude: CGFloat
    var phase: Double
    var freq: Double = 2.2

    func y(_ x: CGFloat, in rect: CGRect) -> CGFloat {
        let u = Double(x / rect.width)
        let theta = u * .pi * freq + phase
        var w = sin(theta)
        w += 0.55 * sin(u * .pi * freq * 1.83 + phase * 1.31)
        w += 0.30 * sin(u * .pi * freq * 3.10 + phase * 0.57)
        w *= 0.54
        let line = rect.height * (1 - min(1, fill))
        return max(0, min(rect.height, line + amplitude * CGFloat(w)))
    }
}

private struct HWaterShape: Shape {
    var field: HWaveField
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard rect.width > 0 else { return p }
        p.move(to: CGPoint(x: 0, y: field.y(0, in: rect)))
        var x: CGFloat = 0
        while x < rect.width {
            x = min(x + 3, rect.width)
            p.addLine(to: CGPoint(x: x, y: field.y(x, in: rect)))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

private struct HWaterEdgeShape: Shape {
    var field: HWaveField
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard rect.width > 0 else { return p }
        p.move(to: CGPoint(x: 0, y: field.y(0, in: rect)))
        var x: CGFloat = 0
        while x < rect.width {
            x = min(x + 3, rect.width)
            p.addLine(to: CGPoint(x: x, y: field.y(x, in: rect)))
        }
        return p
    }
}

/// Greeting + target + Bob + clock-in dock over the water band. Both apps
/// show this in place of an empty hero on a fresh, clocked-out day.
public struct FreshDayWelcome: View {
    @ObservedObject var state: BobState
    /// Compact drops Bob's size and the spacing for the Mac popover.
    var compact: Bool

    public init(state: BobState, compact: Bool = false) {
        self.state = state
        self.compact = compact
    }

    private var target: TimeInterval { TodayVals(state, now: Date()).targetSecs }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        if let first = state.profile?.name.split(separator: " ").first {
            return "\(part), \(first)"
        }
        return part
    }

    public var body: some View {
        // A pool scene, not a banner: the lower part of the page IS the
        // water, Bob floats in it waiting, the clock-in dock rides the
        // waterline like it rides the hero's edge, and the greeting centers
        // in the sky above. Fills a wide pane and a phone alike.
        GeometryReader { geo in
            let waterH: CGFloat = compact ? 118 : max(220, geo.size.height * 0.42)
            let line = waterH * 0.80   // waterline height from the bottom
            ZStack(alignment: .bottom) {
                WaterBand(fill: 0.80, amplitude: compact ? 4 : 6)
                    .frame(height: waterH)
                    .frame(maxWidth: .infinity)

                // Bob floats at the waterline, off to the side.
                HStack {
                    BuoyBob(size: compact ? 58 : 84)
                    Spacer()
                }
                .padding(.leading, compact ? 28 : 56)
                .padding(.bottom, line - (compact ? 24 : 36))

                // The dock straddles the waterline, centered.
                ActionDock(state: state, now: Date())
                    .padding(.bottom, line - (compact ? 20 : 24))

                // Greeting block, centered in the sky above the water.
                VStack(spacing: compact ? 6 : 10) {
                    Spacer()
                    Text(greeting)
                        .font(compact ? .title2.bold() : .largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Ready when you are")
                        .font(compact ? .footnote : .body)
                        .foregroundStyle(.secondary)
                    Spacer().frame(height: compact ? 10 : 16)
                    Label("\(Fmt.hm(target)) today", systemImage: "target")
                        .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, waterH)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
