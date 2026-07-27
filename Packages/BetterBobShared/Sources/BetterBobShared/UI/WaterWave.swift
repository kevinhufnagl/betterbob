import CoreGraphics
import Foundation

// The hero's waterline, and a way for things floating on it to read the same
// wave the water is drawing. Pure and closed form — the surface at any instant
// is a function of time, nothing is integrated frame to frame — so the drawing,
// the swimmer and the unit tests all agree.

/// The waterline as a function: three sine components with incommensurate
/// wavelengths and speeds sum into an organic, never-quite-repeating edge (a
/// single sine reads as a rubber band). `asym` adds the lopsided slosh harmonic
/// during the arrival; amplitude 0 collapses to a straight line.
struct WaveField {
    var level: Double       // 0…1 of the width
    var amplitude: Double   // points
    var phase: Double
    var asym: Double = 0
    /// Seeded per appearance for variety.
    var freq: Double = 2.2
    var asymPhase: Double = 1.2
    var detail2 = 0.0
    var detail3 = 0.0

    /// The wave's displacement at `u` (0…1 down the waterline), in points.
    /// Positive is deeper water — the surface bulging toward the far wall.
    func wave(at u: Double) -> Double {
        let theta = u * .pi * freq + phase
        var w = sin(theta)
        w += 0.55 * sin(u * .pi * freq * 1.83 + phase * 1.31 + detail2)
        w += 0.30 * sin(u * .pi * freq * 3.10 + phase * 0.57 + detail3)
        w *= 0.54  // renormalize the component sum to ~unit amplitude
        w += asym * sin(2 * theta + asymPhase)
        return amplitude * w
    }

    func x(_ y: CGFloat, in rect: CGRect) -> CGFloat {
        let u = Double(y / rect.height)
        let edge = Double(rect.width) * min(1, level)
        return CGFloat(min(Double(rect.width), edge + wave(at: u)))
    }

    /// What a float riding at `u` feels: how far the water has carried it and how
    /// steeply the surface leans under it. Sampled from the same wave the user
    /// can see, so a swimmer moves in step with the ripples instead of on an idle
    /// animation of its own.
    func ride(at u: Double, height: Double) -> (drift: Double, slope: Double) {
        let du = 4 / max(1, height)
        let slope = (wave(at: u + du) - wave(at: u - du)) / (2 * du * height)
        return (wave(at: u), slope)
    }

    /// The waterline walked as points, top to bottom.
    func polyline(in rect: CGRect) -> [CGPoint] {
        guard rect.height > 0 else { return [] }
        var pts: [CGPoint] = []
        var y: CGFloat = 0
        while true {
            pts.append(CGPoint(x: x(y, in: rect), y: y))
            if y >= rect.height { break }
            y = min(y + 3, rect.height)
        }
        return pts
    }

    /// A wave that parallels this one without copying it — slower, shallower and
    /// out of step, for the light gathered under the surface. (The caller slides
    /// it into the water; a band that traced the waterline exactly would read as
    /// a drawn outline rather than light in the water.)
    var parallel: WaveField {
        var copy = self
        copy.phase = phase + 0.7
        copy.amplitude = amplitude * 0.82
        copy.freq = freq * 0.86
        copy.asym = asym * 0.5
        return copy
    }
}

/// The hero's live wave, shared between the water and whatever floats on it.
///
/// The hero records the exact wave it just drew; a swimmer samples that on its
/// own clock, so it rides the wave the user can see. It deliberately publishes
/// nothing — a 30fps `@Published` write would invalidate the whole pane every
/// frame — which is safe because every reader is already inside its own
/// per-frame `TimelineView`.
@MainActor public final class WaveModel {
    public init() {}

    private var size: CGSize = .zero
    private var field: WaveField?

    /// Called by the hero for the wave it drew this frame.
    func record(_ field: WaveField, in size: CGSize) {
        self.field = field
        self.size = size
    }

    /// The water at `y` down the card: how far the wave has carried a float there
    /// and how steeply the surface leans under it. Nil until the hero has drawn
    /// once.
    func ride(at y: CGFloat) -> (drift: Double, slope: Double)? {
        guard let field, size.height > 0 else { return nil }
        return field.ride(at: Double(y / size.height), height: Double(size.height))
    }
}
