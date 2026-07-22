import BetterBobShared
import SwiftUI

/// Wrapper so a tapped entry can drive `.sheet(item:)`.
struct EntryEdit: Identifiable {
    let id = UUID()
    let entry: AttendanceEntry
}

/// Tap-to-edit for one attendance entry: native time pickers for start/end
/// plus delete — the phone's stand-in for the Mac rows' inline editor.
struct EntryEditSheet: View {
    let entry: AttendanceEntry
    var reasonOptions: [ReasonOption] = []
    /// The day's chronologically last entry can be reopened (clear its end),
    /// like the Mac — reverts a clock-out / end-break so you're still going.
    var isLast: Bool = false
    /// Smart default End for closing an open entry (usual check-out → target →
    /// now on the entry's day). The caller computes it from BobState.
    var suggestedEnd: Date? = nil
    var onSave: (Date, Date?) -> Void
    var onReason: (ReasonOption) -> Void = { _ in }
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var reasonName: String
    /// An open entry the user chose to close by giving it an end time.
    @State private var endingOpen = false
    private let isOpen: Bool

    init(entry: AttendanceEntry,
         reasonOptions: [ReasonOption] = [],
         isLast: Bool = false,
         suggestedEnd: Date? = nil,
         onSave: @escaping (Date, Date?) -> Void,
         onReason: @escaping (ReasonOption) -> Void = { _ in },
         onDelete: @escaping () -> Void) {
        self.entry = entry
        self.reasonOptions = reasonOptions
        self.isLast = isLast
        self.suggestedEnd = suggestedEnd
        self.onSave = onSave
        self.onReason = onReason
        self.onDelete = onDelete
        _start = State(initialValue: entry.start)
        // Open entries default their end to a smart guess on the entry's OWN
        // day (usual check-out → target → now); the .hourAndMinute picker keeps
        // that date, so a forgotten past-day check-out lands on the right day.
        _end = State(initialValue: entry.end ?? suggestedEnd ?? entry.start)
        _reasonName = State(initialValue: entry.reason ?? "")
        isOpen = entry.end == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlassGroupedSection(
                        header: entry.kind == .breakTime ? "Break" : "Work",
                        footer: (isOpen && !endingOpen) ? "This entry is still running — end it to fix a forgotten check-out."
                              : (isOpen && endingOpen) ? "Suggested from your recent days — adjust if needed."
                              : nil
                    ) {
                        GlassRow(showDivider: false) {
                            DatePicker("Start", selection: $start,
                                       displayedComponents: .hourAndMinute)
                        }
                        if !isOpen || endingOpen {
                            GlassRow {
                                DatePicker("End", selection: $end, in: start...,
                                           displayedComponents: .hourAndMinute)
                            }
                        }
                        if entry.kind == .work, !reasonOptions.isEmpty {
                            GlassRow {
                                Picker("Reason", selection: $reasonName) {
                                    if reasonName.isEmpty { Text("None").tag("") }
                                    ForEach(reasonOptions, id: \.name) { opt in
                                        Text(opt.name).tag(opt.name)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: reasonName) { _, name in
                                    if let opt = reasonOptions.first(where: { $0.name == name }) {
                                        onReason(opt)
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        // Open entry stays open unless the user chose to end it.
                        onSave(start, (isOpen && !endingOpen) ? nil : end)
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    // End an open entry by giving it an end time — mirror of
                    // Reopen. Any open entry can be closed (fixing past data).
                    if isOpen, !endingOpen {
                        Button {
                            endingOpen = true
                        } label: {
                            Label("End entry", systemImage: "arrow.right.to.line")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(.glass)
                    }

                    // Reopen: clear the end so the entry is running again.
                    // Only the day's last entry — reopening a middle one would
                    // leave an open entry stranded between later ones.
                    if !isOpen, isLast {
                        Button {
                            onSave(start, nil)
                            dismiss()
                        } label: {
                            Label("Reopen — clear end time", systemImage: "arrow.uturn.backward")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(.glass)
                    }

                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete entry", systemImage: "trash")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .bobScreen(title: "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
