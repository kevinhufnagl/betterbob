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

    /// Bob's distance from the leading edge, tuned per surface.
    private var bobLeading: CGFloat {
        #if os(iOS)
        return 26
        #else
        return compact ? 30 : 72
        #endif
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        if let first = state.profile?.name.split(separator: " ").first {
            return "\(part), \(first)"
        }
        return part
    }

    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, compact ? 6 : 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    /// "Done by 17:23 if you start now", counting the auto-break the engine
    /// would owe along the way.
    private var doneByText: String? {
        guard target > 0 else { return nil }
        let prefs = Prefs.shared
        let pendingBreak = prefs.autoBreakEnabled && target > prefs.threshold
            ? prefs.breakLength : 0
        let done = Date().addingTimeInterval(target + pendingBreak)
        return "Done by \(Fmt.clock(done)) if you start now"
    }

    /// The cycle's running over/under, when the summary has arrived —
    /// fully worded: "1 hour 30 minutes behind this month".
    private var balanceText: String? {
        guard let minutes = state.cycleSummary?.overUnderMinutes, minutes != 0 else { return nil }
        return minutes > 0 ? "\(spoken(abs(minutes))) ahead this month"
                           : "\(spoken(abs(minutes))) behind this month"
    }

    /// Minutes → words: 90 → "1 hour 30 minutes".
    private func spoken(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60, m = totalMinutes % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour" + (h == 1 ? "" : "s")) }
        if m > 0 { parts.append("\(m) minute" + (m == 1 ? "" : "s")) }
        return parts.isEmpty ? "0 minutes" : parts.joined(separator: " ")
    }

    /// The next booked, still-active leave — something to look forward to.
    private var nextTimeOffText: String? {
        let today = Calendar.current.startOfDay(for: Date())
        let next = state.timeOffRequests
            .filter { r in
                let s = r.status.lowercased()
                return !s.contains("cancel") && !s.contains("declin") && !s.contains("reject")
            }
            .compactMap { r in DayFmt.date(r.startDate).map { (r, $0) } }
            .filter { $0.1 >= today }
            .min { $0.1 < $1.1 }
        guard let (request, start) = next else { return nil }
        let days = Calendar.current.dateComponents([.day], from: today, to: start).day ?? 0
        let when: String
        if days == 0 {
            when = "today"
        } else if days == 1 {
            when = "tomorrow"
        } else if Calendar(identifier: .iso8601).isDate(start, equalTo: today,
                                                        toGranularity: .weekOfYear) {
            // Same week: the weekday name beats counting days.
            when = "this \(start.formatted(.dateTime.weekday(.wide)))"
        } else {
            when = "in \(days) days"
        }
        return "\(request.typeName) \(when)"
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

                // Bob floats at the waterline, off to the side — clear of the
                // centered dock. The phone hugs him near the edge; the Mac's
                // wider surfaces sit him further in.
                HStack {
                    BuoyBob(size: compact ? 58 : 84)
                    Spacer()
                }
                .padding(.leading, bobLeading)
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
                    // Morning glanceables in one flow: the target plus what
                    // today could look like, where the cycle stands, and
                    // what there is to look forward to. Chips share a row
                    // when they fit, wrap when they don't — uniform spacing.
                    ChipFlow(spacing: 6) {
                        chip("\(spoken(Int(target / 60))) today", symbol: "target")
                        if let doneByText {
                            chip(doneByText, symbol: "clock.badge.checkmark")
                        }
                        if let balanceText {
                            chip(balanceText, symbol: "scalemass")
                        }
                        if let nextTimeOffText {
                            chip(nextTimeOffText, symbol: "sun.max")
                        }
                    }
                    .padding(.horizontal, 8)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, waterH)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Time off normally loads when its tab opens — fetch it here too, or
        // the next-time-off chip pops in late (or not at all) on a fresh day.
        .task {
            if state.timeOffRequests.isEmpty {
                await state.loadTimeOff()
            }
        }
    }
}

/// A centered flow: chips share a row while they fit the proposed width,
/// wrap to the next row when they don't. Rows are centered horizontally and
/// every gap — within and between rows — uses the same spacing.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for (i, subview) in subviews.enumerated() {
            let w = subview.sizeThatFits(.unspecified).width
            if rows[rows.count - 1].isEmpty {
                x = w
                rows[rows.count - 1].append(i)
            } else if x + spacing + w <= maxWidth {
                x += spacing + w
                rows[rows.count - 1].append(i)
            } else {
                rows.append([i])
                x = w
            }
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 600
        var width: CGFloat = 0, height: CGFloat = 0
        for (index, row) in rows(subviews, maxWidth: maxWidth).enumerated() {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            let rowWidth = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            width = max(width, rowWidth)
            height += (sizes.map(\.height).max() ?? 0) + (index > 0 ? spacing : 0)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, maxWidth: bounds.width) {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            let rowWidth = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            let rowHeight = sizes.map(\.height).max() ?? 0
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for (k, i) in row.enumerated() {
                subviews[i].place(at: CGPoint(x: x, y: y + (rowHeight - sizes[k].height) / 2),
                                  anchor: .topLeading, proposal: .unspecified)
                x += sizes[k].width + spacing
            }
            y += rowHeight + spacing
        }
    }
}
