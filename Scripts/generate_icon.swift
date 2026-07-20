// One-shot tool: renders the BetterBob app icon — Bob the Beaver, the app's
// mascot (industrious, always on schedule), on a deep rose → amber gradient
// (a nod to HiBob's palette).
//
// Usage:
//   swift generate_icon.swift <outdir>   → writes AppIcon.iconset/*.png
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let outDir = args.count >= 2 ? args[1] : "AppIcon.iconset"

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let macSizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),       ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),       ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),    ("icon_512x512@2x.png", 1024),
]

func render(size px: Int) -> Data? {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let cs = CGColorSpaceCreateDeviceRGB()

    func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }
    // Ellipse/rect from a centre in unit (0…1) coords. y is up.
    func ell(_ ux: Double, _ uy: Double, _ uw: Double, _ uh: Double) -> CGRect {
        CGRect(x: (ux - uw / 2) * Double(s), y: (uy - uh / 2) * Double(s),
               width: uw * Double(s), height: uh * Double(s))
    }
    func fillEllipse(_ r: CGRect, _ col: CGColor) {
        ctx.setFillColor(col); ctx.addEllipse(in: r); ctx.fillPath()
    }
    func fillRoundRect(_ r: CGRect, _ rad: CGFloat, _ col: CGColor) {
        ctx.setFillColor(col)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil))
        ctx.fillPath()
    }
    // An uneven rounded rect: big top radius (rounded dome), small bottom radius
    // (flat where it meets the visor). CG coords are y-up, so maxY is the top.
    func domePath(_ r: CGRect, top rt: CGFloat, bottom rb: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX, y: r.minY + rb))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY),
                 tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rt) // top-left
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY),
                 tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: rt) // top-right
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY),
                 tangent2End: CGPoint(x: r.minX, y: r.minY), radius: rb) // bottom-right
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY),
                 tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: rb) // bottom-left
        p.closeSubpath()
        return p
    }

    // ── Background: rounded square, deep rose → amber diagonal gradient.
    let radius = s * 0.225
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()

    // Brand ramp — the liquid hero's deep blue → teal, diagonal.
    let bgColors = [
        c(0.04, 0.12, 0.26), c(0.06, 0.30, 0.36), c(0.12, 0.56, 0.58),
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 0.55, 1.0])!
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Faint horizontal timeline stripes — the timesheet Bob keeps.
    ctx.setStrokeColor(c(1, 1, 1, 0.05))
    ctx.setLineWidth(max(0.5, s * 0.0015))
    var gy: CGFloat = 0
    while gy <= s { ctx.move(to: .init(x: 0, y: gy)); ctx.addLine(to: .init(x: s, y: gy)); gy += s * 0.10 }
    ctx.strokePath()
    ctx.restoreGState()

    // Palette (matches BobPalette in the app).
    let furLight = c(0.64, 0.44, 0.28), fur = c(0.55, 0.36, 0.22), furDark = c(0.42, 0.27, 0.16)
    let muzzle = c(0.92, 0.82, 0.68), teeth = c(0.99, 0.98, 0.93)
    let nose = c(0.28, 0.18, 0.13), pupil = c(0.16, 0.10, 0.07)
    let blush = c(0.93, 0.55, 0.48), outline = c(0.20, 0.12, 0.07)

    // ── Little arms (behind the body).
    for ux in [0.24, 0.76] { fillEllipse(ell(ux, 0.31, 0.13, 0.18), fur) }

    // ── Body (rounded) with a lighter belly, behind the head.
    let bodyRect = ell(0.5, 0.27, 0.48, 0.44)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.04, color: c(0, 0, 0, 0.22))
    fillRoundRect(bodyRect, s * 0.20, fur)
    ctx.restoreGState()
    fillEllipse(ell(0.5, 0.23, 0.28, 0.30), muzzle.copy(alpha: 0.8)!)

    // ── Feet.
    for ux in [0.40, 0.60] { fillEllipse(ell(ux, 0.07, 0.16, 0.10), furDark) }

    // ── Ears — set wide so they poke out well beyond the cap's sides.
    for ux in [0.21, 0.79] {
        fillEllipse(ell(ux, 0.77, 0.18, 0.18), fur)
        fillEllipse(ell(ux, 0.76, 0.09, 0.09), furDark)
    }

    // ── Head with a soft shadow and a top→bottom fur gradient.
    let headRect = ell(0.5, 0.63, 0.58, 0.54)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.05, color: c(0, 0, 0, 0.25))
    ctx.addEllipse(in: headRect); ctx.setFillColor(fur); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: headRect); ctx.clip()
    let furGrad = CGGradient(colorsSpace: cs, colors: [furLight, fur] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(furGrad, start: CGPoint(x: 0, y: headRect.maxY),
                           end: CGPoint(x: 0, y: headRect.minY), options: [])
    ctx.restoreGState()

    // ── Teal cap that says "bob" (the brand primary): visor over the brow,
    //    a flatter crown, ears poking out at the sides. A touch brighter than
    //    the background ramp so it still reads as its own shape.
    let capBlue = c(0.15, 0.68, 0.70), capDark = c(0.08, 0.44, 0.47)
    // Visor — a wide, thin brim jutting over the brow.
    fillRoundRect(ell(0.5, 0.70, 0.72, 0.12), s * 0.05, capDark)
    // Crown — a rounded dome: fully round on top, flat where it meets the visor
    // (an ellipse pinches in at the bottom and reads as an egg/football).
    ctx.saveGState()
    let crown = ell(0.5, 0.82, 0.60, 0.34)
    let dome = domePath(crown, top: s * 0.29, bottom: s * 0.06)
    ctx.addPath(dome); ctx.clip()
    ctx.setFillColor(capBlue); ctx.fill(crown)
    let capGrad = CGGradient(colorsSpace: cs,
                             colors: [c(1, 1, 1, 0.20), c(1, 1, 1, 0.0)] as CFArray,
                             locations: [0, 1])!
    ctx.drawLinearGradient(capGrad, start: CGPoint(x: 0, y: crown.maxY),
                           end: CGPoint(x: 0, y: crown.midY), options: [])
    ctx.restoreGState()
    // Seam where the crown meets the visor.
    ctx.setStrokeColor(capDark)
    ctx.setLineWidth(max(1, s * 0.01)); ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: s * 0.5, y: s * 0.76), radius: s * 0.28,
               startAngle: .pi * 1.05, endAngle: .pi * 1.95, clockwise: false)
    ctx.strokePath()
    // Button on top.
    fillEllipse(ell(0.5, 0.99, 0.045, 0.045), capDark)
    // "bob" wordmark on the crown.
    let label = "bob" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: s * 0.15, weight: .heavy),
        .foregroundColor: NSColor.white,
    ]
    let tsize = label.size(withAttributes: attrs)
    label.draw(at: NSPoint(x: s * 0.5 - tsize.width / 2, y: s * 0.83 - tsize.height / 2),
               withAttributes: attrs)

    // ── Cheeks (blush).
    for ux in [0.32, 0.68] { fillEllipse(ell(ux, 0.54, 0.13, 0.085), blush.copy(alpha: 0.45)!) }

    // ── Eyes: white, pupil, catchlight (sit just below the visor).
    for ux in [0.39, 0.61] {
        fillEllipse(ell(ux, 0.65, 0.15, 0.15), c(1, 1, 1))
        ctx.setStrokeColor(outline.copy(alpha: 0.18)!); ctx.setLineWidth(max(0.4, s * 0.005))
        ctx.addEllipse(in: ell(ux, 0.65, 0.15, 0.15)); ctx.strokePath()
        fillEllipse(ell(ux, 0.625, 0.075, 0.075), pupil)
        fillEllipse(ell(ux - 0.018, 0.65, 0.026, 0.026), c(1, 1, 1, 0.9))
    }

    // ── Muzzle, nose, two big teeth.
    fillEllipse(ell(0.5, 0.52, 0.40, 0.30), muzzle)
    fillRoundRect(ell(0.5, 0.575, 0.12, 0.08), s * 0.03, nose)
    for ux in [0.468, 0.532] {
        let tr = ell(ux, 0.465, 0.062, 0.12)
        fillRoundRect(tr, s * 0.012, teeth)
        ctx.setStrokeColor(outline.copy(alpha: 0.18)!); ctx.setLineWidth(max(0.4, s * 0.004))
        ctx.addPath(CGPath(roundedRect: tr, cornerWidth: s * 0.012, cornerHeight: s * 0.012, transform: nil))
        ctx.strokePath()
    }

    // Inner edge stroke on the rounded square.
    ctx.setStrokeColor(c(1, 1, 1, 0.10))
    ctx.setLineWidth(max(1, s * 0.005))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: s - 1, height: s - 1),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for (name, px) in macSizes {
    guard let data = render(size: px) else {
        FileHandle.standardError.write("Failed to render \(name)\n".data(using: .utf8)!)
        continue
    }
    let path = "\(outDir)/\(name)"
    try? data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(data.count) bytes)")
}
