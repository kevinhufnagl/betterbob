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
    var onSave: (Date, Date?) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    private let isOpen: Bool

    init(entry: AttendanceEntry,
         onSave: @escaping (Date, Date?) -> Void,
         onDelete: @escaping () -> Void) {
        self.entry = entry
        self.onSave = onSave
        self.onDelete = onDelete
        _start = State(initialValue: entry.start)
        _end = State(initialValue: entry.end ?? Date())
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

                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Text("Delete entry")
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
