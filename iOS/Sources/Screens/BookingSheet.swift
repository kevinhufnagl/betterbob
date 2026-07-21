import BetterBobShared
import SwiftUI

/// Booking time off, restaged for the phone: native pickers in glass rows,
/// HiBob's live preview underneath, one prominent request button. Same
/// engine calls as the Mac's booking sheet.
struct BookingSheet: View {
    @ObservedObject var state: BobState
    @Environment(\.dismiss) private var dismiss

    @State private var policy: TimeOffPolicyType?
    @State private var start: Date
    @State private var end: Date
    @State private var calc: TimeOffCalc?
    @State private var calculating = false
    @State private var submitting = false
    @State private var error: String?

    init(state: BobState, start: Date = Date(), end: Date = Date()) {
        self.state = state
        _start = State(initialValue: start)
        _end = State(initialValue: end)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    requestSection
                    previewSection
                    if let error {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.bobRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    submitButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .bobScreen(title: "Book time off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if policy == nil {
                policy = state.timeOffPolicyTypes.first {
                    $0.displayName.lowercased().contains("holiday")
                } ?? state.timeOffPolicyTypes.first
                recalc()
            }
        }
    }

    private var requestSection: some View {
        GlassGroupedSection(header: "Request") {
            GlassRow(showDivider: false) {
                HStack {
                    Text("Type")
                    Spacer()
                    Menu {
                        ForEach(state.timeOffPolicyTypes) { p in
                            Button {
                                policy = p
                                recalc()
                            } label: {
                                Label(p.displayName, systemImage: policyIcon(p.displayName))
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(policy?.displayName ?? "Choose a type")
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .foregroundStyle(policy == nil ? Color.accentColor : Color.secondary)
                    }
                }
            }
            GlassRow {
                DatePicker("From", selection: $start, displayedComponents: .date)
                    .onChange(of: start) { _, v in
                        if end < v { end = v }
                        recalc()
                    }
            }
            GlassRow {
                DatePicker("Until", selection: $end, in: start...Date.distantFuture,
                           displayedComponents: .date)
                    .onChange(of: end) { _, _ in recalc() }
            }
        }
    }

    @ViewBuilder private var previewSection: some View {
        if calculating {
            GlassCard(padding: 14) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking with HiBob…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let calc {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(calc.requestMessage)
                        .font(.body.weight(.semibold))
                    if !calc.forecast.isEmpty {
                        Text(calc.forecast)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let validation = calc.validation {
                        Label(validation, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if let reject = calc.rejectReason {
                        Label(reject, systemImage: "xmark.octagon.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.bobRed)
                    }
                }
            }
        }
    }

    private var submitButton: some View {
        Button {
            guard let policy else { return }
            submitting = true
            error = nil
            Task {
                error = await state.submitTimeOff(policyType: policy.requestValue,
                                                  start: start, end: end)
                submitting = false
                if error == nil { dismiss() }
            }
        } label: {
            HStack(spacing: 6) {
                if submitting {
                    ProgressView().controlSize(.small)
                    Text("Requesting…")
                } else {
                    Text("Request")
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(policy == nil || submitting || calc?.submittable == false)
    }

    private func recalc() {
        guard let policy else { return }
        calculating = true
        Task {
            calc = try? await state.previewTimeOff(policyType: policy.requestValue,
                                                   start: start, end: end)
            calculating = false
        }
    }
}
