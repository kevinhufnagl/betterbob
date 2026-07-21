import BetterBobShared
import SwiftUI

/// Time off, restaged for the phone: balance cards up top, the shared
/// range-select calendar in a glass card, open requests as rows. Booking
/// goes through the shared sheet with native detents.
struct TimeOffScreen: View {
    @ObservedObject var state: BobState
    @State private var booking: BookingRange?

    private struct BookingRange: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                poolHero
                balanceGrid
                TimeOffCalendar(state: state) { start, end in
                    booking = BookingRange(start: start, end: end)
                }
                requestsSection
                bookButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .bobScreen(title: "Time Off")
        .refreshable { await state.loadTimeOff() }
        .task { await state.loadTimeOff() }
        .sheet(item: $booking) { range in
            BookingSheet(state: state, start: range.start, end: range.end)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Pool hero — the draining vacation pool, same math as the Mac

    /// The balance the pool shows: the vacation-style policy if there is
    /// one, otherwise the first balance HiBob returns.
    private var mainBalance: TimeOffBalance? {
        state.timeOffBalances.first {
            let n = $0.displayName.lowercased()
            return n.contains("holiday") || n.contains("vacation")
                || n.contains("urlaub") || n.contains("sunny")
        } ?? state.timeOffBalances.first
    }

    /// The year's whole pot: carryover plus this cycle's allowance, falling
    /// back to the plain allowance when the metrics are missing.
    private func poolTotal(for b: TimeOffBalance) -> Double {
        let carry = b.prevBalance.flatMap(number) ?? 0
        let annual = b.annualAllowance.flatMap(number)
            ?? number(b.totalAllowance) ?? 0
        return annual + max(0, carry)
    }

    @ViewBuilder private var poolHero: some View {
        if let b = mainBalance, let left = number(b.currentBalance) {
            let pot = poolTotal(for: b)
            LiquidHero(worked: 0, target: 0,
                       cornerRadius: 18,
                       customFraction: pot > 0 ? max(0, min(1, left / pot)) : 0,
                       customBig: trimmed(left),
                       customLine2: pot > 0 ? "of \(trimmed(pot)) \(b.unit) left"
                                            : "\(b.unit) left",
                       customLine3: b.displayName.replacingOccurrences(of: " (\(b.unit))", with: ""))
                .frame(height: 150)
                .glassSurface()
        }
    }

    /// First number in a HiBob balance string ("12.5", "12,5 days", "+26").
    private func number(_ s: String) -> Double? {
        let cleaned = s.filter { "0123456789.,-".contains($0) }
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: Balances

    @ViewBuilder private var balanceGrid: some View {
        if !state.timeOffBalances.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(state.timeOffBalances) { balance in
                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(balance.displayName.replacingOccurrences(of: " (\(balance.unit))", with: ""),
                                  systemImage: policyIcon(balance.displayName))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(balance.currentBalance)
                                .font(.title2.monospacedDigit().weight(.medium))
                            let pot = poolTotal(for: balance)
                            Text(pot > 0 ? "of \(trimmed(pot)) \(balance.unit)"
                                         : balance.cycleRange)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Requests

    @ViewBuilder private var requestsSection: some View {
        if !state.timeOffRequests.isEmpty {
            GlassGroupedSection(header: "Requests") {
                ForEach(Array(state.timeOffRequests.enumerated()), id: \.element.id) { i, request in
                    GlassRow(showDivider: i > 0) {
                        requestRow(request)
                    }
                }
            }
        }
    }

    private func requestRow(_ request: TimeOffRequest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: policyIcon(request.typeName))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.typeName).font(.body)
                Text("\(request.startDate) – \(request.endDate) · \(request.amount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.cancellingRequests.contains(request.id) {
                ProgressView().controlSize(.small)
            } else {
                Text(request.status.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                state.cancelTimeOff(request)
            } label: {
                Label("Cancel request", systemImage: "xmark.circle")
            }
        }
    }

    private var bookButton: some View {
        Button {
            booking = BookingRange(start: Date(), end: Date())
        } label: {
            Label("Book time off", systemImage: "plus")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}
