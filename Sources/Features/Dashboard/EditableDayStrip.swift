import SwiftUI
import AppKit

/// A to-scale day timeline you can drag breaks around on. The drag gesture
/// lives on the whole strip (stable), so re-flowing the blocks under it never
/// cancels it: as you drag a break the entire day adjusts live (surrounding
/// work resizes) and a marker + time pill on top show where it lands. On
/// release it reports the new day via `onChange` — the caller saves or buffers.
/// Work and the open (ongoing) block aren't draggable.
struct EditableDayStrip: View {
    let entries: [AttendanceEntry]
    let now: Date
    var height: CGFloat = 44
    var onChange: ([AttendanceEntry]) -> Void
    @Environment(\.colorScheme) private var scheme

    @State private var dragID: String?
    @State private var grabStart: Date?
    @State private var preview: [AttendanceEntry]?
    @State private var dropStart: Date?
    @State private var hoverID: String?

    private let snap: TimeInterval = 300   // 5-minute grid

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
                    .fill(Color.primary.opacity(0.06))
                ForEach(Array(shown.enumerated()), id: \.offset) { i, e in
                    block(e, first: i == 0, last: i == shown.count - 1,
                          start: start, span: span, w: w, radius: radius)
                }
                if let dropStart {
                    marker(at: dropStart, start: start, span: span, w: w).zIndex(10)
                }
            }
            .contentShape(Rectangle())
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
        let draggable = e.kind == .breakTime && e.end != nil && e.id != nil
        let isHover = hoverID == e.id && !isDragging
        // Square inside edges; only the timeline's outer ends are rounded.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: first ? radius : 0, bottomLeadingRadius: first ? radius : 0,
            bottomTrailingRadius: last ? radius : 0, topTrailingRadius: last ? radius : 0,
            style: .continuous)
        return shape
            .fill(accent)
            .frame(width: max(2, bw), height: height)
            .overlay { if isHover { shape.fill(Color.white.opacity(0.16)) } }   // hover = draggable
            .overlay { if !isDragging { blockLabel(e, width: bw) } }
            .opacity(e.end == nil ? 0.82 : 1)
            .offset(x: bx)
            .zIndex(isDragging ? 1 : 0)
            .onHover { h in
                guard draggable else { return }
                hoverID = h ? e.id : (hoverID == e.id ? nil : hoverID)
                (h ? NSCursor.openHand : NSCursor.arrow).set()
            }
            .animation(.easeOut(duration: 0.12), value: isHover)
    }

    private func drag(shown source: [AttendanceEntry], geoStart start: Date,
                      span: TimeInterval, w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                // First move: pick the break under the start point.
                if dragID == nil {
                    guard let hit = breakAt(v.startLocation.x, source, start: start, span: span, w: w)
                    else { return }
                    dragID = hit.id; grabStart = hit.start
                    NSCursor.closedHand.set()
                }
                guard let id = dragID, let base = grabStart,
                      let e = source.first(where: { $0.id == id }) else { return }
                let dayStart = source.map(\.start).min() ?? start
                let dayEnd = source.compactMap(\.end).max() ?? now
                let duration = (e.end ?? now).timeIntervalSince(e.start)
                let delta = TimeInterval(v.translation.width / max(1, w)) * span
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
                dragID = nil; grabStart = nil; preview = nil; dropStart = nil
            }
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

    // Landing marker: a line at the drop start + a time pill, both above the blocks.
    private func marker(at when: Date, start: Date, span: TimeInterval, w: CGFloat) -> some View {
        let x = CGFloat(when.timeIntervalSince(start) / span) * w
        let dur = dragID.flatMap { id in entries.first { $0.id == id } }
            .map { ($0.end ?? now).timeIntervalSince($0.start) } ?? 0
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.accentColor).frame(width: 2, height: height)
                .offset(x: max(0, min(w - 2, x)))
            Text("\(Fmt.clock(when))–\(Fmt.clock(when.addingTimeInterval(dur)))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 0.8))
                .fixedSize()
                .offset(x: max(0, min(w - 92, x - 45)), y: -4)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func blockLabel(_ e: AttendanceEntry, width bw: CGFloat) -> some View {
        let dur = Fmt.hm((e.end ?? now).timeIntervalSince(e.start))
        // Show the duration as soon as there's room — it updates live as the
        // surrounding work resizes during a drag.
        let text: String? = bw > 96 ? "\(Fmt.clock(e.start))–\(e.end.map(Fmt.clock) ?? "now") · \(dur)"
            : bw > 34 ? dur : nil
        if let text {
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(.regularMaterial))
                .fixedSize()
        }
    }
}
