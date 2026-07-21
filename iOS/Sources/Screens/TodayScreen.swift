import BetterBobShared
import SwiftUI

/// Today, restaged for the phone: the wave hero with swimming Bob up top,
/// full-width glass clock actions, the touch-editable timeline, and today's
/// entries as native rows. All state flows through the shared engine.
struct TodayScreen: View {
    @ObservedObject var state: BobState

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let vals = TodayVals(state, now: ctx.date)
                VStack(spacing: 16) {
                    hero(vals, now: ctx.date)
                    actions(vals)
                    if !state.entries.isEmpty {
                        timelineCard(now: ctx.date)
                    }
                    warnings
                    entriesSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .bobScreen(title: "Today")
        .refreshable { await state.reconcile() }
    }

    // MARK: Hero — the wave, untouched

    private func hero(_ v: TodayVals, now: Date) -> some View {
        LiquidHero(worked: v.worked, target: v.targetSecs, breakTotal: v.breakTotal,
                   compact: true, cornerRadius: 18)
            .statusTint(state.heroLimitTint)
            .frame(height: 190)
            .overlay(alignment: .topLeading) {
                if v.fraction >= 0.15 {
                    BuoyBob(sleeping: state.clockState == .clockedOut,
                            onBreak: v.onBreak, size: 52)
                        .padding(.leading, 18)
                        .offset(y: 8)
                }
            }
            .overlay(alignment: .topTrailing) {
                StatusPill(state: state)
                    .padding(12)
            }
            .glassSurface()
    }

    // MARK: Clock actions

    @ViewBuilder private func actions(_ v: TodayVals) -> some View {
        if !state.signedIn {
            signedOutCard
        } else {
            HStack(spacing: 10) {
                switch state.projectedClockState {
                case .clockedOut:
                    glassAction("Clock in", symbol: "play.fill", prominent: true) { state.clockIn() }
                case .working:
                    glassAction("Take a break", symbol: "pause.fill", prominent: false) { state.startManualBreak() }
                    glassAction("Clock out", symbol: "stop.fill", prominent: true) { state.clockOut() }
                case .onBreak:
                    glassAction("End break", symbol: "play.fill", prominent: true) { state.endBreak() }
                    glassAction("Clock out", symbol: "stop.fill", prominent: false) { state.clockOut() }
                }
            }
            if let queued = state.queue.first {
                Label("Queued — lands \(Fmt.clock(queued.fireAt))", systemImage: "clock.badge")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func glassAction(_ title: String, symbol: String, prominent: Bool,
                             action: @escaping () -> Void) -> some View {
        let label = Label(title, systemImage: symbol)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 30)
        if prominent {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .controlSize(.large)
        }
    }

    private var signedOutCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                AnimatedBob(sleeping: true).frame(width: 72, height: 72)
                Text("Bob's off the clock")
                    .font(.headline)
                if state.autoLoginInProgress {
                    AutoLoginInline(state: state, fillWidth: true)
                } else {
                    if state.canAutoSignIn {
                        SignInFactorGroup(state: state)
                    }
                    Button {
                        NotificationCenter.default.post(name: .presentOnboarding, object: nil)
                    } label: {
                        Label("Sign in…", systemImage: "arrow.right.circle.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Timeline strip (drag to edit — same math as the Mac)

    private func timelineCard(now: Date) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TIMELINE")
                    .font(.footnote.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                EditableDayStrip(entries: state.entries, now: now, height: 48) { updated in
                    state.saveDay(updated, on: Date())
                }
            }
        }
    }

    // MARK: Warnings

    @ViewBuilder private var warnings: some View {
        if state.signedIn {
            if let shortfall = state.breakGuidelineShortfall {
                warningRow("Break \(Fmt.hm(shortfall)) short of the guideline — tap the wand in the entry list to fix.",
                           symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
            if state.overDailyMax {
                warningRow("Past the daily limit — only clocking out helps.",
                           symbol: "exclamationmark.octagon.fill", tint: .red)
            }
        }
    }

    private func warningRow(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassSurface(cornerRadius: 14)
    }

    // MARK: Entries

    @ViewBuilder private var entriesSection: some View {
        if state.signedIn, !state.entries.isEmpty {
            GlassGroupedSection(header: "Entries") {
                let sorted = state.entries.sorted { $0.start > $1.start }
                ForEach(Array(sorted.enumerated()), id: \.element.id) { i, entry in
                    GlassRow(showDivider: i > 0) {
                        entryRow(entry)
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: AttendanceEntry) -> some View {
        let tint = entry.kind == .breakTime ? Color.bobOrange : Color.accentColor
        let end = entry.end
        let duration = (end ?? Date()).timeIntervalSince(entry.start)
        return HStack(spacing: 12) {
            Capsule().fill(tint).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.clock(entry.start)) – \(end.map(Fmt.clock) ?? "now")")
                    .font(.body.monospacedDigit())
                Text("\(entry.kind == .breakTime ? "Break" : "Work") · \(Fmt.hm(duration))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let id = entry.id, state.deletingEntries.contains(id) {
                ProgressView().controlSize(.small)
            } else if entry.kind == .work {
                reasonMenu(entry)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                state.deleteEntry(entry)
            } label: {
                Label("Delete entry", systemImage: "trash")
            }
        }
    }

    @ViewBuilder private func reasonMenu(_ entry: AttendanceEntry) -> some View {
        let hasReason = entry.reason?.isEmpty == false
        Menu {
            ForEach(state.reasonOptions, id: \.name) { opt in
                Button(opt.name) { state.setReason(for: entry, to: opt) }
            }
        } label: {
            Text(hasReason ? entry.reason! : "Add reason")
                .font(.footnote.weight(.medium))
                .foregroundStyle(hasReason ? Color.primary : Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.accentColor.opacity(hasReason ? 0.10 : 0.16)))
        }
    }
}
