import SwiftUI
import AppKit

/// A to-scale day timeline you can drag breaks around on — and resize by the
/// edges. The drag gesture lives on the whole strip (stable), so re-flowing
/// the blocks under it never cancels it: as you drag, the entire day adjusts
/// live and a marker + time pill on top show where the grabbed point lands.
/// On release it reports the new day via `onChange` — the caller saves or
/// buffers.
///
/// Two grabs:
/// - A closed break's body moves the whole break (surrounding work resizes,
///   total worked time unchanged).
/// - A boundary between blocks resizes both neighbours: one lengthens exactly
///   as much as the other shortens and nothing else moves. The day's first
///   edge moves the clock-in, the last edge (when closed) the clock-out.
/// The open (ongoing) block's trailing "now" edge isn't draggable.
struct EditableDayStrip: View {
    let entries: [AttendanceEntry]
    let now: Date
    var height: CGFloat = 44
    var onChange: ([AttendanceEntry]) -> Void
    @Environment(\.colorScheme) private var scheme

    /// A grabbed (or hovered) resize handle: the boundary owned by `index` —
    /// its end edge for `.moveEnd`, the day-start edge for `.moveStart`.
    private struct Edge: Equatable {
        let index: Int
        let mode: AttendanceLogic.DragMode
    }

    @State private var dragID: String?
    @State private var grabStart: Date?
    @State private var edgeGrab: Edge?
    @State private var preview: [AttendanceEntry]?
    @State private var dropStart: Date?
    @State private var hoverID: String?
    @State private var hoverEdge: Edge?

    private let snap: TimeInterval = 300   // 5-minute grid
    private let edgeMargin: CGFloat = 5    // grab zone around a boundary

    private var sorted: [AttendanceEntry] { entries.sorted { $0.start < $1.start } }

    var body: some View {
        GeometryReader { geo in
            let shown = (preview ?? entries).sorted { $0.start < $1.start }
            let start = shown.map(\.start).min() ?? now
            let lastEnd = shown.compactMap(\.end).max()
            let hasOpen = shown.contains { $0.end == nil }
            let end = hasOpen ? max(now, lastEnd ?? now) : (lastEnd ?? now)
            let span = max(1, end.timeIntervalSince(start))
            let w = geo.size.width
            let radius = min(height / 3, 9)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                    .glassEffect(.regular, in: .rect(cornerRadius: radius))
                ForEach(Array(shown.enumerated()), id: \.offset) { i, e in
                    block(e, first: i == 0, last: i == shown.count - 1,
                          start: start, span: span, w: w, radius: radius)
                }
                if let he = hoverEdge, dragID == nil, edgeGrab == nil {
                    edgeHandle(he, shown: shown, start: start, span: span, w: w).zIndex(9)
                }
                if let dropStart {
                    marker(at: dropStart, start: start, span: span, w: w).zIndex(10)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard dragID == nil, edgeGrab == nil else { return }
                switch phase {
                case .active(let p):
                    if let edge = edgeAt(p.x, sorted, start: start, span: span, w: w) {
                        hoverEdge = edge; hoverID = nil
                        NSCursor.resizeLeftRight.set()
                    } else if let b = breakAt(p.x, sorted, start: start, span: span, w: w) {
                        hoverID = b.id; hoverEdge = nil
                        NSCursor.openHand.set()
                    } else {
                        hoverID = nil; hoverEdge = nil
                        NSCursor.arrow.set()
                    }
                case .ended:
                    hoverID = nil; hoverEdge = nil
                    NSCursor.arrow.set()
                }
            }
            .highPriorityGesture(drag(shown: sorted, geoStart: start, span: span, w: w))
        }
        .frame(height: height)
    }

    private func block(_ e: AttendanceEntry, first: Bool, last: Bool,
                       start: Date, span: TimeInterval, w: CGFloat, radius: CGFloat) -> some View {
        let accent = e.kind == .breakTime ? Color.breakAccent(scheme) : Color.workAccent(scheme)
        let bx = CGFloat(e.start.timeIntervalSince(start) / span) * w
        let bw = CGFloat((e.end ?? now).timeIntervalSince(e.start) / span) * w
        let isDragging = dragID == e.id
        let isHover = hoverID == e.id && !isDragging
        // Square inside edges; only the timeline's outer ends are rounded.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: first ? radius : 0, bottomLeadingRadius: first ? radius : 0,
            bottomTrailingRadius: last ? radius : 0, topTrailingRadius: last ? radius : 0,
            style: .continuous)
        return shape
            .fill(LinearGradient(colors: [accent.opacity(0.96), accent.opacity(0.78)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                // Glassy top light, like the system's liquid glass sheen.
                shape.fill(LinearGradient(colors: [.white.opacity(0.28), .clear],
                                          startPoint: .top, endPoint: .center))
            }
            .frame(width: max(2, bw), height: height)
            .overlay { if isHover { shape.fill(Color.white.opacity(0.16)) } }   // hover = draggable
            .overlay { if !isDragging { blockLabel(e, width: bw) } }
            .opacity(e.end == nil ? 0.82 : 1)
            .offset(x: bx)
            .zIndex(isDragging ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isHover)
    }

    private func drag(shown source: [AttendanceEntry], geoStart start: Date,
                      span: TimeInterval, w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                // First move: pick the edge or break under the start point.
                if dragID == nil && edgeGrab == nil {
                    if let edge = edgeAt(v.startLocation.x, source, start: start, span: span, w: w) {
                        edgeGrab = edge; hoverEdge = nil
                        NSCursor.resizeLeftRight.set()
                    } else if let hit = breakAt(v.startLocation.x, source, start: start, span: span, w: w) {
                        dragID = hit.id; grabStart = hit.start; hoverID = nil
                        NSCursor.closedHand.set()
                    } else { return }
                }
                let delta = TimeInterval(v.translation.width / max(1, w)) * span

                if let edge = edgeGrab {
                    // Resize: both share the snapping and the minGap clamps.
                    let p = edge.mode == .moveStart
                        ? AttendanceLogic.dragged(entries, index: edge.index, mode: .moveStart,
                                                  by: delta, now: now)
                        : AttendanceLogic.boundaryMoved(entries, after: edge.index,
                                                        by: delta, now: now)
                    preview = p
                    let ps = p.sorted { $0.start < $1.start }
                    guard ps.indices.contains(edge.index) else { return }
                    dropStart = edge.mode == .moveEnd ? ps[edge.index].end : ps[edge.index].start
                    return
                }

                guard let id = dragID, let base = grabStart,
                      let e = source.first(where: { $0.id == id }) else { return }
                let dayStart = source.map(\.start).min() ?? start
                let dayEnd = source.compactMap(\.end).max() ?? now
                let duration = (e.end ?? now).timeIntervalSince(e.start)
                let raw = base.addingTimeInterval(delta).timeIntervalSince(dayStart)
                var newStart = dayStart.addingTimeInterval((raw / snap).rounded() * snap)
                let latest = dayEnd.addingTimeInterval(-duration)
                if newStart < dayStart { newStart = dayStart }
                if newStart > latest { newStart = latest }
                dropStart = newStart
                preview = AttendanceLogic.moved(entries, id: id, toStart: newStart)
            }
            .onEnded { _ in
                NSCursor.arrow.set()
                if let p = preview { onChange(p) }
                dragID = nil; grabStart = nil; edgeGrab = nil
                preview = nil; dropStart = nil
            }
    }

    /// The resize handle under `x`, if any: each closed block's end edge (the
    /// boundary it owns — for interior boundaries that's also the next block's
    /// start), plus the first block's start edge (the day's clock-in). A very
    /// thin break keeps its whole width grabbable as a body instead.
    private func edgeAt(_ x: CGFloat, _ source: [AttendanceEntry],
                        start: Date, span: TimeInterval, w: CGFloat) -> Edge? {
        if let hit = breakAt(x, source, start: start, span: span, w: w) {
            let bw = CGFloat((hit.end ?? now).timeIntervalSince(hit.start) / span) * w
            if bw <= 12 { return nil }
        }
        for (i, e) in source.enumerated() {
            guard let end = e.end else { continue }
            let ex = CGFloat(end.timeIntervalSince(start) / span) * w
            if abs(x - ex) <= edgeMargin { return Edge(index: i, mode: .moveEnd) }
        }
        if let first = source.first {
            let fx = CGFloat(first.start.timeIntervalSince(start) / span) * w
            if abs(x - fx) <= edgeMargin { return Edge(index: 0, mode: .moveStart) }
        }
        return nil
    }

    private func breakAt(_ x: CGFloat, _ source: [AttendanceEntry],
                         start: Date, span: TimeInterval, w: CGFloat) -> AttendanceEntry? {
        source.first { e in
            guard e.kind == .breakTime, e.end != nil, e.id != nil else { return false }
            let bx = CGFloat(e.start.timeIntervalSince(start) / span) * w
            let bw = CGFloat((e.end ?? now).timeIntervalSince(e.start) / span) * w
            return x >= bx - 4 && x <= bx + bw + 4   // small grab margin for thin breaks
        }
    }

    /// Hover affordance for a resize handle: a grip line on the boundary.
    private func edgeHandle(_ edge: Edge, shown: [AttendanceEntry],
                            start: Date, span: TimeInterval, w: CGFloat) -> some View {
        let when: Date? = shown.indices.contains(edge.index)
            ? (edge.mode == .moveEnd ? shown[edge.index].end : shown[edge.index].start)
            : nil
        let x = CGFloat((when ?? now).timeIntervalSince(start) / span) * w
        return Capsule()
            .fill(.white)
            .frame(width: 3, height: height - 10)
            .shadow(color: .black.opacity(0.35), radius: 1)
            .offset(x: max(0, min(w - 3, x - 1.5)), y: 5)
            .opacity(when == nil ? 0 : 0.95)
            .allowsHitTesting(false)
    }

    // Landing marker: a line at the grabbed point + a time pill, above the blocks.
    private func marker(at when: Date, start: Date, span: TimeInterval, w: CGFloat) -> some View {
        let x = CGFloat(when.timeIntervalSince(start) / span) * w
        let dur = dragID.flatMap { id in entries.first { $0.id == id } }
            .map { ($0.end ?? now).timeIntervalSince($0.start) } ?? 0
        let text = dur > 0 ? "\(Fmt.clock(when))–\(Fmt.clock(when.addingTimeInterval(dur)))"
                           : Fmt.clock(when)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.bobTeal).frame(width: 2, height: height)
                .offset(x: max(0, min(w - 2, x)))
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .glassEffect(.regular, in: .capsule)
                .overlay(Capsule().strokeBorder(Color.bobTeal.opacity(0.6), lineWidth: 0.8))
                .fixedSize()
                .offset(x: max(0, min(w - 92, x - (dur > 0 ? 45 : 22))), y: -4)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func blockLabel(_ e: AttendanceEntry, width bw: CGFloat) -> some View {
        // Just the duration, straight on the block — the boundary times live
        // under the strip. It updates live as the surrounding work resizes
        // during a drag.
        if bw > 40 {
            Text(Fmt.hm((e.end ?? now).timeIntervalSince(e.start)))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .fixedSize()
        }
    }
}
