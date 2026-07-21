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
            TimeOffBookingSheet(state: state, start: range.start, end: range.end)
                .presentationDetents([.medium, .large])
                .presentationBackground(.thinMaterial)
        }
    }

    // MARK: Pool hero — the draining vacation pool, same wave as the Mac

    @ViewBuilder private var poolHero: some View {
        if let main = state.timeOffBalances.first,
           let left = number(main.currentBalance) {
            let total = number(main.totalAllowance) ?? 0
            LiquidHero(worked: 0, target: 0,
                       cornerRadius: 18,
                       customFraction: total > 0 ? max(0, min(1, left / total)) : 0,
                       customBig: main.currentBalance,
                       customLine2: total > 0 ? "of \(main.totalAllowance) \(main.unit) left"
                                              : "\(main.unit) left",
                       customLine3: main.displayName)
                .frame(height: 150)
                .glassSurface()
        }
    }

    private func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".")
                 .filter { "0123456789.".contains($0) })
    }

    // MARK: Balances

    @ViewBuilder private var balanceGrid: some View {
        if !state.timeOffBalances.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(state.timeOffBalances) { balance in
                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(balance.displayName, systemImage: policyIcon(balance.displayName))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(balance.currentBalance)
                                .font(.title2.monospacedDigit().weight(.medium))
                            Text("of \(balance.totalAllowance) \(balance.unit)")
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
