import SwiftUI

// The Last-month pane: the previous cycle's finished timesheet, shown while
// HiBob still exposes it (between month end and submission). Summary hero +
// KPIs up top, the same calendar heatmap as This-month below — cells open the
// day editor, so a wrong day can be fixed before submitting. Submitting will
// become the pane's one action once the submit endpoint is captured.

public struct TimesheetPane: View {
    @ObservedObject var state: BobState
    @State private var confirmingSubmit = false

    public init(state: BobState) { self.state = state }

    /// The sheet is finished, unsubmitted, and HiBob says it would accept it.
    private var canSubmit: Bool {
        state.lastMonthCycle?.awaitsSubmission == true
            && state.lastMonthSummary?.isSubmittable == true
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                PaneHeader(title: "Last month", subtitle: subtitle)
                if let cycle = state.lastMonthCycle { statusChip(cycle) }
                if canSubmit { submitButton }
            }
            if let summary = state.lastMonthSummary {
                summaryContent(summary)
            } else if state.lastMonthLoaded {
                BobPlaceholder(title: "No timesheet here right now",
                               lines: ["HiBob isn't exposing a previous sheet at the moment."],
                               sleeping: true)
            } else {
                BobPlaceholder(title: "Fetching last month…", lines: BobLines.loading) {
                    ProgressView().controlSize(.small).padding(.top, 2)
                }
                .padding(.top, 40)
            }
        }
        .task { await state.loadLastMonth() }
    }

    private var subtitle: String {
        guard let c = state.lastMonthCycle,
              let start = DayFmt.date(c.start), let end = DayFmt.date(c.end)
        else { return "Previous timesheet cycle" }
        let month = start.formatted(.dateTime.month(.wide).year())
        var line = "\(start.formatted(.dateTime.day())) – \(end.formatted(.dateTime.day())) \(month)"
        if let lock = c.lockAt, lock > Date() {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: lock).day ?? 0
            line += " · locks \(lock.formatted(.dateTime.day().month()))"
            line += days > 0 ? " (\(days) days)" : " (today)"
        }
        return line
    }

    // MARK: - Status

    @ViewBuilder private func statusChip(_ cycle: CycleInfo) -> some View {
        if cycle.awaitsSubmission {
            chip(tint: .bobOrange, symbol: "hourglass", text: "Waiting for submission")
        } else if cycle.pendingApproval {
            chip(tint: .bobTeal, symbol: "paperplane.fill", text: "Pending approval")
        } else if cycle.locked || cycle.status.localizedCaseInsensitiveContains("approv") {
            chip(tint: .bobTeal, symbol: "checkmark.seal.fill", text: "Approved")
        } else if !cycle.status.isEmpty {
            chip(tint: .secondary, symbol: "doc.text", text: cycle.status)
        }
    }

    private var submitButton: some View {
        Button { confirmingSubmit = true } label: {
            Label("Submit timesheet", systemImage: "paperplane.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.9))
                .padding(.horizontal, 14).frame(height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Color.bobTeal.opacity(0.3)).interactive(), in: .capsule)
        .disabled(state.busy)
        .padding(.top, 2)
        .confirmationDialog("Submit last month's timesheet?",
                            isPresented: $confirmingSubmit, titleVisibility: .visible) {
            Button("Submit to manager") { Task { await state.submitLastMonth() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends the sheet to your manager for approval. There is no un-submit, so fix any days first.")
        }
    }

    private func chip(tint: Color, symbol: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9).frame(height: 20)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 0.7))
        .fixedSize()
        .padding(.top, 4)
    }

    // MARK: - Summary

    @ViewBuilder private func summaryContent(_ s: CycleSummary) -> some View {
        let workedSecs = workedSeconds(s)
        let targetSecs = targetSeconds(s)
        let timeOffSecs = TimeInterval(s.timeOffMinutes * 60)
        let payableSecs = workedSecs + timeOffSecs
        if targetSecs > 0 {
            // Big number and fill are payable time (worked + booked time off),
            // HiBob's own "Payable hours" — a day off is earned, not missing,
            // so the month doesn't read short by a holiday.
            LiquidHero(worked: workedSecs, target: targetSecs,
                       customFraction: min(1, payableSecs / targetSecs),
                       customBig: Fmt.hm(payableSecs),
                       customLine2: heroLine2(s, targetSecs: targetSecs, timeOffSecs: timeOffSecs),
                       customLine3: balanceLine(s))
                .frame(height: 150)
        }
        kpiGrid(s)
        CalendarHeatmap(state: state, source: .lastMonth)
        if let note = footnote {
            Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var footnote: String? {
        guard let c = state.lastMonthCycle else { return nil }
        if c.awaitsSubmission {
            return "Click a day to fix its entries before submitting."
        }
        if c.pendingApproval {
            var line = "Submitted"
            if let on = c.submittedOn, let date = DayFmt.date(on) {
                line += " on \(date.formatted(.dateTime.day().month(.wide)))"
            }
            return line + " · waiting for your manager's approval."
        }
        return nil
    }

    private func heroLine2(_ s: CycleSummary, targetSecs: TimeInterval,
                           timeOffSecs: TimeInterval) -> String {
        var line = "\(s.payableTimePercent)% of \(Fmt.hm(targetSecs))"
        if timeOffSecs > 0 { line += " · with \(Fmt.hm(timeOffSecs)) time off" }
        return line
    }

    private func balanceLine(_ s: CycleSummary) -> String {
        let mins = s.overUnderMinutes
        if mins == 0 { return "right on target" }
        let hm = Fmt.hm(TimeInterval(abs(mins) * 60))
        return mins < 0 ? "\(hm) short of target" : "\(hm) over target"
    }

    private func kpiGrid(_ s: CycleSummary) -> some View {
        let missing = missingDays(s).count
        let payable = TimeInterval(BobParsing.minutes(fromDisplay: s.totalHoursDisplay) * 60)
            + TimeInterval(s.timeOffMinutes * 60)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            // HiBob's "Payable hours": worked + booked time off — the figure
            // the web timesheet leads with, so months with a holiday don't
            // read short. The Time off tile next to it shows the split.
            StatTile(value: Fmt.hm(payable), caption: "Payable hours", symbol: "sum")
            StatTile(value: hoursText(Double(s.timeOffMinutes) / 60), caption: "Time off",
                     symbol: "beach.umbrella")
            StatTile(value: signedHours(Double(s.overUnderMinutes) / 60),
                     caption: "Final balance", symbol: "plusminus")
            StatTile(value: "\(missing)", caption: "Missing days",
                     tint: missing == 0 ? .primary : .bobOrange,
                     symbol: missing == 0 ? "checkmark.circle" : "calendar.badge.exclamationmark")
            StatTile(value: "\(s.breakViolations)", caption: "Break issues",
                     symbol: s.breakViolations == 0 ? "checkmark.shield" : "exclamationmark.shield")
        }
    }

    /// Days the sheet expected hours but recorded none — booked time off
    /// covers a day, so it doesn't count as missing.
    private func missingDays(_ s: CycleSummary) -> [DayHours] {
        s.days.filter { ($0.target ?? 0) > 0 && $0.worked == 0 && ($0.timeOff ?? 0) == 0 }
    }

    private func workedSeconds(_ s: CycleSummary) -> TimeInterval {
        let mins = BobParsing.minutes(fromDisplay: s.totalHoursDisplay)
        if mins > 0 { return TimeInterval(mins * 60) }
        return s.days.reduce(0) { $0 + $1.worked * 3600 }
    }

    private func targetSeconds(_ s: CycleSummary) -> TimeInterval {
        if s.potentialMinutes > 0 { return TimeInterval(s.potentialMinutes * 60) }
        return s.days.reduce(0) { $0 + ($1.target ?? 0) * 3600 }
    }
}
