import BetterBobShared
import SwiftUI
import UserNotifications

@main
struct BetterBobApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .signInSheet()
                // Sign-in setup opened from Settings while signed in — the
                // signed-out state is handled by RootView itself.
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingScreen(state: BobState.shared) {
                        OnboardingController.completed = true
                        showOnboarding = false
                    }
                    .signInSheet()
                }
                .onReceive(NotificationCenter.default.publisher(for: .presentOnboarding)) { _ in
                    showOnboarding = true
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                BobState.shared.setDashboardActive(true)
                // A sign-in that completed while we were away (approving the
                // Okta push in Okta Verify) is picked up here, so the hidden
                // web view doesn't have to re-drive the whole flow.
                SSOSignInController.shared.resumeCheck()
                Task { await BobState.shared.reconcile() }
            case .background:
                BobState.shared.setDashboardActive(false)
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }
}

/// The app's trunk, Colimate-style: signed out means the sign-in page IS the
/// app — no tabs, no hero, just Bob and the options. Tabs only exist with a
/// session (or while the boot probe is still deciding).
private struct RootView: View {
    @ObservedObject var state = BobState.shared

    var body: some View {
        if state.signedIn && state.ready {
            RootTabs(state: state)
        } else if state.autoLoginInProgress {
            // An interactive sign-in is running: its inline card (OTP field /
            // "approve the push" status) MUST be visible — the loader would
            // cover it and strand the user mid sign-in.
            OnboardingScreen(state: state, isDismissible: false) {
                OnboardingController.completed = true
            }
        } else if state.bootingUp || state.signedIn {
            // Booting the stored session, or signed in but the first reconcile
            // hasn't landed yet (connect() flips signedIn before ready).
            BootLoader(state: state)
        } else {
            OnboardingScreen(state: state, isDismissible: false) {
                OnboardingController.completed = true
            }
        }
    }
}

/// The launch loading screen — with an escape hatch. If boot hasn't resolved
/// after a few seconds (a stalled probe, a half-established session), offer a
/// way back to the sign-in screen so the loader can never become a trap.
private struct BootLoader: View {
    @ObservedObject var state: BobState
    @State private var showEscape = false

    var body: some View {
        ZStack {
            BobBackdrop()
            BobPlaceholder(title: "Getting your day ready…", lines: BobLines.loading) {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.small).padding(.top, 2)
                    if showEscape {
                        Button("Taking too long? Sign in again") {
                            state.signOut()   // clears the stuck SSO flag → sign-in screen
                        }
                        .font(.callout)
                        .buttonStyle(.glass)
                        .transition(.opacity)
                    }
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            withAnimation { showEscape = true }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BobState.shared.start()
        WidgetBridge.shared.start()
        UNUserNotificationCenter.current().delegate = self
        BackgroundRefresh.register()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
