import BetterBobShared
import SwiftUI

enum BobTab: Hashable { case today, month, timeOff, settings }

struct RootTabs: View {
    @ObservedObject var state: BobState
    @ObservedObject var prefs = Prefs.shared
    @State private var tab: BobTab = .today

    var body: some View {
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
