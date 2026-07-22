import BetterBobShared
import SwiftUI

/// Add an attendance entry by hand: pick Work or Break, a start and end, and
/// (for work) a reason. The times are wall-clock — the engine lands them on
/// the day being edited. Mirrors EntryEditSheet's look, minus delete.
struct NewEntrySheet: View {
    var reasonOptions: [ReasonOption] = []
    /// Sensible defaults for the day being edited (wall-clock times).
    let defaultStart: Date
    let defaultEnd: Date
    var onAdd: (AttendanceEntry.Kind, Date, Date, ReasonOption?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isBreak = false
    @State private var start: Date
    @State private var end: Date
    @State private var reasonName = ""

    init(reasonOptions: [ReasonOption] = [],
         defaultStart: Date, defaultEnd: Date,
         onAdd: @escaping (AttendanceEntry.Kind, Date, Date, ReasonOption?) -> Void) {
        self.reasonOptions = reasonOptions
        self.defaultStart = defaultStart
        self.defaultEnd = defaultEnd
        self.onAdd = onAdd
        _start = State(initialValue: defaultStart)
        _end = State(initialValue: defaultEnd)
    }

    private var kind: AttendanceEntry.Kind { isBreak ? .breakTime : .work }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlassGroupedSection(header: "Type") {
                        GlassRow(showDivider: false) {
                            Picker("Type", selection: $isBreak) {
                                Text("Work").tag(false)
                                Text("Break").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    GlassGroupedSection(header: kind == .breakTime ? "Break" : "Work") {
                        GlassRow(showDivider: false) {
                            DatePicker("Start", selection: $start,
                                       displayedComponents: .hourAndMinute)
                        }
                        GlassRow {
                            DatePicker("End", selection: $end, in: start...,
                                       displayedComponents: .hourAndMinute)
                        }
                        if kind == .work, !reasonOptions.isEmpty {
                            GlassRow {
                                Picker("Reason", selection: $reasonName) {
                                    Text("None").tag("")
                                    ForEach(reasonOptions, id: \.name) { opt in
                                        Text(opt.name).tag(opt.name)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }

                    Button {
                        let reason = reasonOptions.first { $0.name == reasonName }
                        onAdd(kind, start, end, kind == .work ? reason : nil)
                        dismiss()
                    } label: {
                        Text("Add entry")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(end <= start)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .bobScreen(title: "New entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
