import SwiftUI

/// The one watch screen: Bob wearing the clock state, the live timer, the
/// target progress with its done-by projection, and the punch buttons —
/// each action performed on the phone, which owns the session.
struct WatchHome: View {
    @ObservedObject var session: WatchSession

    var body: some View {
        ScrollView {
            if let snap = session.snapshot, snap.state != .signedOut {
                day(snap)
            } else {
                signedOut
            }
        }
    }

    // MARK: Signed out / no data yet

    private var signedOut: some View {
        VStack(spacing: 10) {
            WatchBobFace(expression: .asleep)
                .frame(width: 56, height: 56)
                .padding(.top, 8)
            Text("Open BetterBob on your iPhone and sign in — the watch follows along.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
    }

    // MARK: The day

    @ViewBuilder
    private func day(_ snap: WidgetSnapshot) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                WatchBobFace(expression: expression(snap))
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title(snap))
                        .font(.headline)
                    Text("Updated \(snap.updatedAt, style: .time)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            timer(snap)
                .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)

            if snap.state != .clockedOut {
                progress(snap)
            }

            buttons(snap)

            if let err = session.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 2)
    }

    private func expression(_ snap: WidgetSnapshot) -> WatchBobFace.Expression {
        switch snap.state {
        case .working: return .awake
        case .onBreak: return .shades
        default: return .asleep
        }
    }

    private func title(_ snap: WidgetSnapshot) -> String {
        switch snap.state {
        case .working: return "Working"
        case .onBreak: return "On a break"
        default: return "Clocked out"
        }
    }

    /// Always the day's worked total, breaks excluded — ticking while
    /// working, frozen otherwise (the progress line carries back-at/done-by).
    @ViewBuilder
    private func timer(_ snap: WidgetSnapshot) -> some View {
        if snap.state == .working, let start = snap.stretchStart {
            Text(timerInterval: start.addingTimeInterval(-snap.workedBase)...Date.distantFuture,
                 countsDown: false)
        } else {
            Text(hm(snap.workedTotal(now: snap.updatedAt)))
        }
    }

    @ViewBuilder
    private func progress(_ snap: WidgetSnapshot) -> some View {
        let worked = snap.workedTotal(now: Date())
        VStack(spacing: 3) {
            ProgressView(value: min(1, worked / max(snap.target, 1)))
                .tint(snap.state == .onBreak ? .orange : .accentColor)
            HStack {
                Text("\(hm(worked)) of \(hm(snap.target))")
                Spacer()
                if let done = snap.doneBy(now: Date()) {
                    Text("done \(done, style: .time)")
                } else if snap.state == .onBreak, let ends = snap.breakEnds {
                    Text("back \(ends, style: .time)")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func buttons(_ snap: WidgetSnapshot) -> some View {
        if session.punching {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        } else {
            switch snap.state {
            case .clockedOut:
                Button("Clock in") { session.punch("clockIn") }
                    .buttonStyle(.borderedProminent)
            case .working:
                HStack(spacing: 6) {
                    Button("Break") { session.punch("startBreak") }
                    Button("Clock out") { session.punch("clockOut") }
                        .buttonStyle(.borderedProminent)
                }
            case .onBreak:
                Button("End break") { session.punch("endBreak") }
                    .buttonStyle(.borderedProminent)
            case .signedOut:
                EmptyView()
            }
        }
    }

    private func hm(_ interval: TimeInterval) -> String {
        let m = Int(interval / 60)
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}
