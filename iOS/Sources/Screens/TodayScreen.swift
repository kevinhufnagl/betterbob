import BetterBobShared
import SwiftUI

/// Today, restaged for the phone: the wave hero with swimming Bob up top,
/// full-width glass clock actions, the touch-editable timeline, and today's
/// entries as native rows. All state flows through the shared engine.
struct TodayScreen: View {
    @ObservedObject var state: BobState
    @State private var editingEntry: EntryEdit?

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let vals = TodayVals(state, now: ctx.date)
                VStack(spacing: 16) {
                    if state.signedIn {
                        // The dock straddles the hero's bottom edge, like the
                        // Mac popover — the padding reserves its lower half.
                        hero(vals, now: ctx.date)
                            .padding(.bottom, 25)
                            .overlay(alignment: .bottom) {
                                ActionDock(state: state, now: ctx.date)
                            }
                        if let queued = state.queue.first {
                            Text("\(state.queue.count) queued · fires \(Fmt.clock(queued.fireAt))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        hero(vals, now: ctx.date)
                        signedOutCard
                    }
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
        .sheet(item: $editingEntry) { edit in
            EntryEditSheet(entry: edit.entry,
                           onSave: { start, end in
                               state.updateEntryTimes(edit.entry, start: start, end: end)
                           },
                           onDelete: { state.deleteEntry(edit.entry) })
                .presentationDetents([.medium])
        }
    }

    // MARK: Hero — the wave, untouched

    private func hero(_ v: TodayVals, now: Date) -> some View {
        // Tall enough that the text block clears the dock straddling the
        // bottom edge; bottomInset reserves the covered strip inside the hero.
        LiquidHero(worked: v.worked, target: v.targetSecs, breakTotal: v.breakTotal,
                   compact: true, cornerRadius: 18, bottomInset: 30)
            .statusTint(state.heroLimitTint)
            .frame(height: 215)
            .overlay(alignment: .topLeading) {
                if v.fraction >= 0.15 {
                    BuoyBob(sleeping: state.clockState == .clockedOut,
                            onBreak: v.onBreak, size: 72)
                        .padding(.leading, 18)
                        .offset(y: 10)
                }
            }
            .overlay(alignment: .topTrailing) {
                StatusPill(state: state)
                    .padding(12)
            }
            .glassSurface()
    }

    // MARK: Signed out

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
        .contentShape(Rectangle())
        .onTapGesture { editingEntry = EntryEdit(entry: entry) }
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
