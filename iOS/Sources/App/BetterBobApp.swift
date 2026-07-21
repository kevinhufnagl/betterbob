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
        } else if state.bootingUp || state.signedIn {
            // Booting the stored session, or signed in but the first reconcile
            // hasn't landed yet (connect() flips signedIn before ready).
            ZStack {
                BobBackdrop()
                BobPlaceholder(title: "Getting your day ready…", lines: BobLines.loading) {
                    ProgressView().controlSize(.small).padding(.top, 2)
                }
            }
        } else {
            OnboardingScreen(state: state, isDismissible: false) {
                OnboardingController.completed = true
            }
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
