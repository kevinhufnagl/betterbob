import BetterBobShared
import SwiftUI

enum BobTab: Hashable { case today, month, timeOff, settings }

struct RootTabs: View {
    @ObservedObject var state: BobState
    @ObservedObject var prefs = Prefs.shared
    @State private var tab: BobTab = .today

    var body: some View {
        tabs
            // A re-login can run while the tabs are up (expired session, or
            // sign-in setup closed mid-run). Its progress card — the step
            // line, the OTP field, the push wait — must stay visible
            // somewhere, or the flow looks dead until the fallback browser
            // sheet appears out of nowhere.
            .overlay(alignment: .top) {
                if state.autoLoginInProgress {
                    AutoLoginInline(state: state, fillWidth: true)
                        .glassSurface()
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85),
                       value: state.autoLoginInProgress)
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayScreen(state: state) }
                .tabItem { Label("Today", systemImage: "clock.fill") }
                .tag(BobTab.today)

            NavigationStack {
                MonthScreen(state: state, onOpenToday: { tab = .today })
            }
            .tabItem { Label("Month", systemImage: "calendar") }
            .tag(BobTab.month)

            NavigationStack {
                TimeOffScreen(state: state)
            }
            .tabItem { Label("Time Off", systemImage: "sun.max.fill") }
            .tag(BobTab.timeOff)

            NavigationStack {
                SettingsScreen(state: state, prefs: prefs)
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(BobTab.settings)
        }
    }
}
