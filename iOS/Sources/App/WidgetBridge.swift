import BetterBobShared
import Combine
import Foundation

/// Mirrors engine state into the App Group after every poll so the widgets
/// (and later the Live Activity) always render the latest reconcile.
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()
    private var cancellables: Set<AnyCancellable> = []

    func start() {
        let state = BobState.shared
        state.$lastSync
            .combineLatest(state.$clockState, state.$signedIn)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.push() }
            .store(in: &cancellables)
    }

    func push() {
        let state = BobState.shared
        // The day's real target (from the cycle summary, like the app hero) —
        // NOT Prefs.threshold, which is the auto-break threshold.
        let target = TodayVals(state, now: Date()).targetSecs
        var snapshot = AttendanceLogic.widgetSnapshot(
            entries: state.entries, signedIn: state.signedIn,
            target: target, breakEnds: state.autoBreakEnds,
            breakDue: state.autoBreakDue,
            now: Date())
        fillExtras(&snapshot, state: state)
        SharedStore.save(snapshot)
        LiveActivityController.shared.sync(snapshot)
    }

    /// Engine-side facts the widgets can't derive from entries alone.
    private func fillExtras(_ snap: inout WidgetSnapshot, state: BobState) {
        // A break still owed pushes every done-by projection later.
        if state.autoBreakDue != nil {
            snap.pendingBreak = Prefs.shared.breakLength
        }

        if let summary = state.cycleSummary {
            let mins = BobParsing.minutes(fromDisplay: summary.totalHoursDisplay)
            snap.cycleWorkedMinutes = mins > 0 ? mins
                : Int(summary.days.reduce(0) { $0 + $1.worked * 60 })
            snap.cyclePotentialMinutes = summary.potentialMinutes > 0
                ? summary.potentialMinutes
                : Int(summary.days.reduce(0) { $0 + ($1.target ?? 0) * 60 })
            snap.cycleBalanceMinutes = summary.overUnderMinutes

            // Mon…Fri of the current week as worked/target fractions.
            let cal = Calendar(identifier: .iso8601)
            if let week = cal.dateInterval(of: .weekOfYear, for: Date()) {
                var fractions = [Double](repeating: 0, count: 5)
                for day in summary.days {
                    guard let date = DayFmt.date(day.date), week.contains(date) else { continue }
                    let weekday = (cal.component(.weekday, from: date) + 5) % 7   // Mon = 0
                    guard weekday < 5 else { continue }
                    fractions[weekday] = min(1, day.worked / max(day.target ?? 8, 0.1))
                }
                snap.weekFractions = fractions
            }
        }

        // The vacation-style balance, same pick as the Time Off pool.
        if let b = state.timeOffBalances.first(where: {
            let n = $0.displayName.lowercased()
            return n.contains("holiday") || n.contains("vacation")
                || n.contains("urlaub") || n.contains("sunny")
        }) ?? state.timeOffBalances.first {
            snap.holidayLeft = number(b.currentBalance)
            let carry = b.prevBalance.flatMap(number) ?? 0
            let annual = b.annualAllowance.flatMap(number) ?? number(b.totalAllowance) ?? 0
            snap.holidayTotal = annual + max(0, carry)
            snap.holidayUnit = b.unit
            snap.holidayName = b.displayName.replacingOccurrences(of: " (\(b.unit))", with: "")
        }

        // Next upcoming approved-ish time off, for the countdown widget.
        let today = Calendar.current.startOfDay(for: Date())
        let upcoming = state.timeOffRequests
            .compactMap { req -> (String, Date)? in
                guard let start = DayFmt.date(req.startDate), start >= today,
                      !req.status.lowercased().contains("cancel"),
                      !req.status.lowercased().contains("reject")
                else { return nil }
                return (req.typeName, start)
            }
            .min { $0.1 < $1.1 }
        snap.nextTimeOffName = upcoming?.0
        snap.nextTimeOffStart = upcoming?.1
    }

    private func number(_ s: String) -> Double? {
        let cleaned = s.filter { "0123456789.,-".contains($0) }
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }
}
