import SwiftUI
import AppKit

enum MainTab: String, CaseIterable, Identifiable {
    case today, cycle, timeOff, activity, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .cycle: return "This month"
        case .timeOff: return "Time off"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .today: return "clock.fill"
        case .cycle: return "calendar"
        case .timeOff: return "beach.umbrella"
        case .activity: return "list.bullet.rectangle"
        case .settings: return "gearshape.fill"
        }
    }
}

/// The main app window: a sidebar-navigated dashboard (BetterVPN-style),
/// with Settings living inside it rather than a popover button.
struct MainWindow: View {
    @ObservedObject var state: BobState
    @ObservedObject var prefs = Prefs.shared
    @State private var tab: MainTab = .today

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $tab) {
                    Section("BetterBob") {
                        ForEach([MainTab.today, .cycle, .timeOff, .activity]) { row($0) }
                    }
                    Section("App") {
                        row(.settings)
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            } detail: {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DashboardBG().ignoresSafeArea())
            }
            .frame(minWidth: 940, minHeight: 620)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { Task { await state.reconcile() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.help("Refresh")
                }
            }
            FooterBar(state: state)
        }
        .onAppear { if !state.signedIn { tab = .settings } }
        .onChange(of: state.signedIn) { _, signedIn in
            if signedIn, tab == .settings { tab = .today }
        }
    }

    private func row(_ t: MainTab) -> some View {
        Label {
            HStack {
                Text(t.title)
                Spacer()
                if t == .activity, !state.activity.isEmpty {
                    Text("\(state.activity.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: t.icon)
        }
        .tag(t)
    }

    @ViewBuilder private var detail: some View {
        ScrollView {
            Group {
                if tab == .settings {
                    SettingsPanel(state: state, prefs: prefs)
                } else if !state.signedIn {
                    signedOutPlaceholder
                } else if !state.ready {
                    BobPlaceholder(title: "Getting your day ready…", lines: BobLines.loading) {
                        ProgressView().controlSize(.small).padding(.top, 2)
                    }
                    .padding(.top, 40)
                } else {
                    switch tab {
                    case .cycle:    CyclePane(state: state, onOpenToday: { tab = .today })
                    case .timeOff:  TimeOffPane(state: state)
                    case .activity: ActivityPane(state: state)
                    default:        TodayTimeline(state: state)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var signedOutPlaceholder: some View {
        BobPlaceholder(title: "Bob's off the clock", lines: BobLines.signedOut) {
            VStack(spacing: 8) {
                if state.autoLoginInProgress {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(state.autoLoginStatus.isEmpty ? "Signing you in…" : state.autoLoginStatus)
                            .font(.system(size: 12))
                    }
                } else {
                    if state.canAutoSignIn {
                        Button { state.startAutoSignIn() } label: {
                            Label("Log in automatically", systemImage: "wand.and.rays")
                        }.buttonStyle(.borderedProminent)
                    }
                    Button { state.startSSOSignIn() } label: {
                        Label("Sign in with browser…", systemImage: "safari")
                    }.buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        }
        .padding(.top, 40)
    }
}

/// Thin status strip pinned to the window bottom.
struct FooterBar: View {
    @ObservedObject var state: BobState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(state.clockState.tint).frame(width: 8, height: 8)
            Text(state.clockState.title).font(.system(size: 11, weight: .medium))
            if state.clockState != .clockedOut {
                Text("· \(Fmt.hm(state.workedToday)) today")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            if !state.queue.isEmpty { QueueChip(state: state) }
            Spacer()
            if let err = state.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1)
            } else if let sync = state.lastSync {
                Text("Synced \(Fmt.clock(sync))")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            }
            Text("v\(Updater.shared.currentVersion)")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(.thinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.4) }
    }
}

/// The pending action queue, shown in the footer. Click to see each queued
/// punch, when it fires, and remove any before it does.
struct QueueChip: View {
    @ObservedObject var state: BobState
    @State private var show = false

    private func tint(_ a: PunchAction) -> Color {
        switch a {
        case .clockIn, .endBreak: return .green
        case .clockOut: return .red
        case .startBreak: return .orange
        }
    }

    var body: some View {
        Button { show.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "hourglass").font(.system(size: 9, weight: .bold))
                Text("\(state.queue.count) queued").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 8).frame(height: 18)
            .background(Capsule().fill(Color.orange.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .top) { queuePopover }
    }

    private var queuePopover: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 10) {
                Text("Action queue").font(.system(size: 12, weight: .semibold))
                if state.queue.isEmpty {
                    Text("Nothing queued.").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(state.queue.enumerated()), id: \.element.id) { i, item in
                        HStack(spacing: 8) {
                            Image(systemName: item.action.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(tint(item.action)).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.action.label).font(.system(size: 12, weight: .semibold))
                                Text(fireText(item.fireAt, now: ctx.date, firing: i == 0))
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 16)
                            Button { state.removeQueued(item.id) } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }.buttonStyle(.plain).help("Remove")
                        }
                    }
                    Text("HiBob allows one punch per minute — queued punches fire automatically.")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14).frame(width: 240)
        }
    }

    private func fireText(_ at: Date, now: Date, firing: Bool) -> String {
        let secs = Int(at.timeIntervalSince(now).rounded(.up))
        if secs <= 0 { return firing ? "firing now…" : "next up" }
        if secs < 60 { return "fires in \(secs)s · \(Fmt.clock(at))" }
        return "fires at \(Fmt.clock(at))"
    }
}
