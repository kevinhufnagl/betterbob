import SwiftUI

/// Bob's face for the wrist — the same silhouette-with-punched-holes drawing
/// as the shared BobFaceMark, copied rather than imported: the watch target
/// compiles no BetterBobShared (whose UI drags in WebKit-adjacent code), and
/// this Canvas is the one piece of it the wrist needs.
struct WatchBobFace: View {
    enum Expression {
        case awake, shades, asleep
    }

    var color: Color = .white
    var expression: Expression

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            func ell(_ ux: CGFloat, _ uy: CGFloat, _ uw: CGFloat, _ uh: CGFloat) -> CGRect {
                CGRect(x: (ux - uw / 2) * s, y: (1 - uy - uh / 2) * s,
                       width: uw * s, height: uh * s)
            }
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

            ctx.blendMode = .clear
            var holes = Path()
            switch expression {
            case .awake:
                holes.addEllipse(in: ell(0.39, 0.69, 0.15, 0.15))
                holes.addEllipse(in: ell(0.61, 0.69, 0.15, 0.15))
            case .shades:
                holes.addRoundedRect(in: ell(0.5, 0.69, 0.46, 0.13),
                                     cornerSize: CGSize(width: 0.04 * s, height: 0.04 * s))
            case .asleep:
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
