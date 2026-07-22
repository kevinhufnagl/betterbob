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
    // Real window visibility, from the root tracker below. The container
    // background's water can't track this itself — views hosted there never
    // get window callbacks, so its internal gate would stay open forever.
    @State private var windowVisible = true

    var body: some View {
        Group {
            if windowVisible {
                shell
            } else {
                // SwiftUI retains a closed window's view tree and keeps its
                // display links armed — and per-view visibility gating has
                // proven leaky (backing views get duplicated during scene
                // setup and lose their window observers). Tearing the whole
                // tree down while nobody can see it is the only airtight way
                // to stop every animation clock; reopening rebuilds it.
                Color.clear
            }
        }
        .onAppear { if !state.signedIn { tab = .settings } }
        .onChange(of: state.signedIn) { _, signedIn in
            if signedIn, tab == .settings { tab = .today }
        }
        // Only pull the heavy dashboard data (month grid, activity, time off)
        // while this window is actually on screen — see BobState.reconcile.
        .trackWindowVisibility {
            windowVisible = $0
            state.setDashboardActive($0)
        }
    }

    private var shell: some View {
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
                    // On a fresh day the window's container background paints
                    // the backdrop + water for the WHOLE window (sidebar and
                    // toolbar included) — an opaque pane background here
                    // would cover it up.
                    .background {
                        if !showFreshWelcome { DashboardBG().ignoresSafeArea() }
                    }
                    // Title bar shows the selected pane, like any sidebar app.
                    .navigationTitle(tab.title)
            }
            .frame(minWidth: 940, minHeight: 620)
            // The fresh-day pool as the window's own background, so the water
            // runs edge to edge — under the sidebar and up past the toolbar.
            .containerBackground(for: .window, alignment: .bottom) {
                if showFreshWelcome {
                    ZStack(alignment: .bottom) {
                        DashboardBG()
                        WaterBand(fill: 0.80, active: windowVisible)
                            .frame(height: 190)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .toolbarBackgroundVisibility(showFreshWelcome ? .hidden : .automatic, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { Task { await state.reconcile() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.help("Refresh")
                }
            }
            // The footer strip would sit between the water and the window's
            // bottom edge, breaking the waterline alignment — the welcome
            // owns the whole height on a fresh day.
            if !showFreshWelcome {
                FooterBar(state: state)
            }
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

    /// A fresh, clocked-out day on the Today tab — the welcome fills the whole
    /// pane (edge to edge, water at the very bottom), so it skips the padded
    /// ScrollView the other panes use.
    private var showFreshWelcome: Bool {
        tab == .today && state.signedIn && state.ready
            && state.entries.isEmpty && state.clockState == .clockedOut
    }

    @ViewBuilder private var detail: some View {
        if showFreshWelcome {
            // The window's container background draws the water; the welcome
            // just places Bob and the dock on the agreed 190pt waterline.
            FreshDayWelcome(state: state, showsWater: false, fixedWaterHeight: 190)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            scrollingDetail
        }
    }

    @ViewBuilder private var scrollingDetail: some View {
        ScrollView {
            // Pane swaps are instant — the only staged entrance is the
            // heroes' one-time water sweep, which the panes own themselves.
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
        BobPlaceholder(title: "Bob's off the clock", lines: BobLines.signedOut, sleeping: true) {
            VStack(spacing: 8) {
                if state.autoLoginInProgress {
                    AutoLoginInline(state: state)
                } else {
                    if state.canAutoSignIn {
                        // One button per second factor, like the popover — a
                        // bare "log in automatically" silently assumed Google
                        // Authenticator. Capped like AutoLoginInline so it
                        // doesn't stretch across the wide dashboard.
                        SignInFactorGroup(state: state)
                            .frame(maxWidth: 300)
                    } else {
                        // No stored credentials yet: the sign-in window is
                        // where they get set up.
                        Button { OnboardingController.shared.present() } label: {
                            Label("Set up sign-in…", systemImage: "person.badge.key.fill")
                        }.buttonStyle(.bordered)
                    }
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
                .contentTransition(.opacity)
            if state.clockState != .clockedOut {
                Text("· \(Fmt.hm(state.workedToday)) today")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .transition(.opacity)
            }
            if !state.queue.isEmpty { QueueChip(state: state).transition(.bobReplace) }
            Spacer()
            if state.busy || !state.deletingEntries.isEmpty {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("Saving…").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else if let err = state.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(Color.bobOrange).lineLimit(1)
            } else if let sync = state.lastSync {
                Text("Synced \(Fmt.clock(sync))")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text("v\(Updater.shared.currentVersion)")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(.thinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.4) }
        .animation(Motion.standard, value: state.clockState)
        .animation(Motion.standard, value: state.queue.isEmpty)
        .animation(Motion.quick, value: state.busy || !state.deletingEntries.isEmpty)
    }
}

/// The pending action queue, shown in the footer. Click to see each queued
/// punch, when it fires, and remove any before it does.
struct QueueChip: View {
    @ObservedObject var state: BobState
    @State private var show = false

    private func tint(_ a: PunchAction) -> Color {
        switch a {
        case .clockIn, .endBreak: return .bobTeal
        case .clockOut: return .bobRed
        case .startBreak: return .bobOrange
        }
    }

    var body: some View {
        Button { show.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "hourglass").font(.system(size: 9, weight: .bold))
                Text("\(state.queue.count) queued").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color.bobOrange)
            .padding(.horizontal, 8).frame(height: 18)
            .background(Capsule().fill(Color.bobOrange.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color.bobOrange.opacity(0.35), lineWidth: 0.7))
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
                        .transition(.bobBanner)
                    }
                    Text("HiBob allows one punch per minute — queued punches fire automatically.")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14).frame(width: 240)
            .animation(Motion.standard, value: state.queue)
        }
    }

    private func fireText(_ at: Date, now: Date, firing: Bool) -> String {
        let secs = Int(at.timeIntervalSince(now).rounded(.up))
        if secs <= 0 { return firing ? "firing now…" : "next up" }
        if secs < 60 { return "fires in \(secs)s · \(Fmt.clock(at))" }
        return "fires at \(Fmt.clock(at))"
    }
}
