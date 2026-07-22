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
    var onSave: (Date, Date?) -> Void
    var onReason: (ReasonOption) -> Void = { _ in }
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var reasonName: String
    private let isOpen: Bool

    init(entry: AttendanceEntry,
         reasonOptions: [ReasonOption] = [],
         isLast: Bool = false,
         onSave: @escaping (Date, Date?) -> Void,
         onReason: @escaping (ReasonOption) -> Void = { _ in },
         onDelete: @escaping () -> Void) {
        self.entry = entry
        self.reasonOptions = reasonOptions
        self.isLast = isLast
        self.onSave = onSave
        self.onReason = onReason
        self.onDelete = onDelete
        _start = State(initialValue: entry.start)
        _end = State(initialValue: entry.end ?? Date())
        _reasonName = State(initialValue: entry.reason ?? "")
        isOpen = entry.end == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlassGroupedSection(
                        header: entry.kind == .breakTime ? "Break" : "Work",
                        footer: isOpen ? "This entry is still running — only its start can move." : nil
                    ) {
                        GlassRow(showDivider: false) {
                            DatePicker("Start", selection: $start,
                                       displayedComponents: .hourAndMinute)
                        }
                        if !isOpen {
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
                        onSave(start, isOpen ? nil : end)
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

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
