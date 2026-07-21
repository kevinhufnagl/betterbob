import SwiftUI
import UserNotifications

@main
struct BetterBobApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = !OnboardingController.completed

    var body: some Scene {
        WindowGroup {
            RootTabs(state: BobState.shared)
                .signInSheet()
                .fullScreenCover(isPresented: $showOnboarding) {
                    ScrollView {
                        OnboardingView(state: BobState.shared) {
                            OnboardingController.completed = true
                            showOnboarding = false
                        }
                        .padding(.vertical, 24)
                    }
                    .interactiveDismissDisabled(!BobState.shared.signedIn)
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

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BobState.shared.start()
        UNUserNotificationCenter.current().delegate = self
        BackgroundRefresh.register()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
