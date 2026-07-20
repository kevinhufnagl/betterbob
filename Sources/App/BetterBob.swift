import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var titleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        BobState.shared.start()
        Updater.shared.start()
        PhoneView.shared.start()

        // Throwaway dev scaffold: `--capture-endpoints` opens the attendance
        // page in the signed-in browser and records the API calls so the
        // routes can be hardcoded. Removed once endpoints are pinned.
        if CommandLine.arguments.contains("--capture-endpoints") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                EndpointCaptureController.shared.present()
            }
        }
        if CommandLine.arguments.contains("--dashboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApp.setActivationPolicy(.regular)
                WindowOpener.shared.open?("main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // Content is built on show and torn down on close (see togglePopover /
        // popoverDidClose) so its SwiftUI view — and Bob's animation clock —
        // isn't kept alive burning CPU while the popover is closed.

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItem()
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        NotificationCenter.default.addObserver(
            forName: .closePopover, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.closePopoverIfShown() }
        }

        NotificationCenter.default.addObserver(
            forName: .updateStatusItem, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }

        // Keep the optional menu-bar label (worked time / countdown) fresh.
        titleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }

        if UserDefaults.standard.bool(forKey: "signedInViaSSO") {
            // Normal start (incl. launch-at-login): menu bar only. The main
            // window scene opens by default — close it again.
            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.main.async {
                NSApp.windows
                    .filter { $0.identifier?.rawValue.hasPrefix("main") == true }
                    .forEach { $0.close() }
            }
        } else if !OnboardingController.completed {
            // First run: guided welcome window instead of the raw main window.
            NSApp.setActivationPolicy(.regular)
            DispatchQueue.main.async {
                NSApp.windows
                    .filter { $0.identifier?.rawValue.hasPrefix("main") == true }
                    .forEach { $0.close() }
                OnboardingController.shared.present()
            }
        } else {
            // Onboarded but signed out (e.g. session cleared): main window to sign in.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            let host = NSHostingController(rootView: PopoverRootView(state: BobState.shared))
            host.sizingOptions = [.preferredContentSize]
            popover.contentViewController = host
            Task { await BobState.shared.reconcile() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func closePopoverIfShown() {
        if popover.isShown { popover.performClose(nil) }
    }

    // Tear down the popover's SwiftUI content when it closes, so no timers or
    // animations keep running in the background.
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let state = BobState.shared.clockState

        // Bob himself, as a template silhouette (auto-adapts to the menu bar),
        // with an optional play/pause corner badge while the clock is running.
        let onBreak: Bool = { if case .onBreak = state { return true }; return false }()
        let badge: BobIcon.StateBadge = !Prefs.shared.showStateBadge || state == .clockedOut
            ? .none : (onBreak ? .pause : .play)
        let bob = BobIcon.menuBar(height: 18, badge: badge)

        if Prefs.shared.colorMenuBarIcon, state != .clockedOut {
            // Tinted (non-template) Bob by clock state.
            button.image = bob.tinted(onBreak
                ? NSColor(red: 0.88, green: 0.47, blue: 0.24, alpha: 1)
                : NSColor(red: 0.11, green: 0.60, blue: 0.62, alpha: 1))
        } else {
            button.image = bob
        }

        if let text = BobState.shared.menuBarText() {
            button.title = " " + text
            button.imagePosition = .imageLeft
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }
}

@main
struct BetterBobApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("BetterBob", id: "main") {
            MainWindow(state: BobState.shared)
                .captureWindowOpener()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 680)
    }
}

/// Lets the AppDelegate open a window scene by id (used by the `--dashboard`
/// verification flag). Captured from a live view's environment.
final class WindowOpener {
    static let shared = WindowOpener()
    var open: ((String) -> Void)?
}


private struct CaptureWindowOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear { WindowOpener.shared.open = { openWindow(id: $0) } }
    }
}
extension View {
    func captureWindowOpener() -> some View { modifier(CaptureWindowOpener()) }
}
