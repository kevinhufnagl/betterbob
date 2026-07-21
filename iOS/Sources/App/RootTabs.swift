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
                ScrollView {
                    CyclePane(state: state, onOpenToday: { tab = .today })
                        .padding(16)
                }
                .background(DashboardBG())
                .navigationTitle("Month")
                .toolbar {
                    NavigationLink {
                        ScrollView { ActivityPane(state: state).padding(16) }
                            .background(DashboardBG())
                            .navigationTitle("Activity")
                    } label: { Image(systemName: "clock.arrow.circlepath") }
                }
            }
            .tabItem { Label("Month", systemImage: "calendar") }
            .tag(BobTab.month)

            NavigationStack {
                ScrollView { TimeOffPane(state: state).padding(16) }
                    .background(DashboardBG())
                    .navigationTitle("Time Off")
            }
            .tabItem { Label("Time Off", systemImage: "sun.max.fill") }
            .tag(BobTab.timeOff)

            NavigationStack {
                ScrollView { SettingsPanel(state: state, prefs: prefs).padding(16) }
                    .background(DashboardBG())
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(BobTab.settings)
        }
    }
}
