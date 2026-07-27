import SwiftUI
#if os(macOS)
import AppKit

// SwiftUI keeps a closed window's view hierarchy alive, and TimelineView
// animation clocks keep firing in it — a closed dashboard would burn CPU
// forever. This tracker reports whether the hosting window is actually
// visible (not closed, miniaturized, or fully occluded) so animated views
// can drop to a static frame while nobody can see them.

struct WindowVisibility: NSViewRepresentable {
    var onChange: (Bool) -> Void
    /// When true (default), a fully-occluded window reports invisible — right
    /// for pausing animation clocks and heavy data loads. When false, only
    /// miniaturize/close report invisible, so a window merely covered by
    /// another app stays "visible": used for the shell teardown, so switching
    /// back is instant instead of rebuilding the whole tree.
    var occlusionCounts = true

    func makeNSView(context: Context) -> Tracker { Tracker(onChange: onChange, occlusionCounts: occlusionCounts) }
    func updateNSView(_ nsView: Tracker, context: Context) { nsView.onChange = onChange }

    final class Tracker: NSView {
        var onChange: (Bool) -> Void
        let occlusionCounts: Bool
        private var observers: [NSObjectProtocol] = []
        private var lastReported: Bool?

        init(onChange: @escaping (Bool) -> Void, occlusionCounts: Bool) {
            self.onChange = onChange
            self.occlusionCounts = occlusionCounts
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            // Detached: report nothing. SwiftUI transitions spawn duplicate
            // backing views, and a dying copy detaching last must not veto
            // the live, attached one — CPU safety is covered by the window
            // close/occlusion events on the attached tracker.
            guard let window else { return }
            report()
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.willCloseNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] note in
                    if note.name == NSWindow.willCloseNotification {
                        self?.push(false)
                    } else {
                        self?.report()
                    }
                })
            }
        }

        private func report() {
            let visible = window.map {
                (occlusionCounts ? $0.occlusionState.contains(.visible) : true) && !$0.isMiniaturized
            } ?? false
            push(visible)
        }

        private func push(_ visible: Bool) {
            guard visible != lastReported else { return }
            lastReported = visible
            // Async so state changes never land mid view-update.
            let onChange = onChange
            DispatchQueue.main.async { onChange(visible) }
        }
    }
}

extension View {
    /// Calls `onChange` whenever the hosting window's real visibility flips —
    /// attach to views driving animation clocks and pause them when false.
    /// `occlusionCounts: false` reports invisible only on miniaturize/close (a
    /// window merely covered by another app still reads visible), so hosts that
    /// tear down their whole tree stay rendered through an app switch.
    func trackWindowVisibility(occlusionCounts: Bool = true,
                               _ onChange: @escaping (Bool) -> Void) -> some View {
        background(WindowVisibility(onChange: onChange, occlusionCounts: occlusionCounts))
    }
}
#else
// iOS backgrounds/suspends the whole scene, so TimelineView clocks stop on
// their own; visibility only needs to track view appearance.
extension View {
    func trackWindowVisibility(occlusionCounts: Bool = true,
                               _ onChange: @escaping (Bool) -> Void) -> some View {
        self.onAppear { onChange(true) }
            .onDisappear { onChange(false) }
    }
}
#endif
