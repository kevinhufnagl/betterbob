import BetterBobShared
import SwiftUI

/// Editing a past day, restaged for the phone: the touch timeline in a glass
/// card, entries as native rows, and the wand fixes — all through the same
/// per-day engine calls the Mac's detail popover uses.
struct DayDetailScreen: View {
    @ObservedObject var state: BobState
    let dateKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var editingEntry: EntryEdit?

    private var day: DayEntries? { state.monthDays.first { $0.dateKey == dateKey } }
    private var dayEnd: Date {
        day?.entries.compactMap(\.end).max() ?? day?.date ?? Date()
    }
    private var title: String {
        guard let date = DayFmt.date(dateKey) else { return dateKey }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let day, !day.entries.isEmpty {
                        summaryRow(day)
                        timelineCard(day)
                        fixes(day)
                        entriesSection(day)
                    } else {
                        GlassCard {
                            Text("No entries recorded for this day.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .bobScreen(title: title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingEntry) { edit in
                if let day {
                    EntryEditSheet(entry: edit.entry,
                                   onSave: { start, end in
                                       state.updateEntryTimes(edit.entry, in: day.entries,
                                                              on: day.date, start: start, end: end)
                                   },
                                   onDelete: {
                                       state.deleteEntry(edit.entry, in: day.entries, on: day.date)
                                   })
                        .presentationDetents([.medium])
                }
            }
        }
    }

    private func summaryRow(_ day: DayEntries) -> some View {
        let worked = AttendanceLogic.workedToday(entries: day.entries, now: dayEnd)
        let breaks = day.entries.filter { $0.kind == .breakTime }
            .reduce(0.0) { $0 + (($1.end ?? dayEnd).timeIntervalSince($1.start)) }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                         spacing: 12) {
            StatTile(value: Fmt.hm(worked), caption: "Worked")
            StatTile(value: Fmt.hm(breaks), caption: "Breaks")
        }
    }

    private func timelineCard(_ day: DayEntries) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TIMELINE")
                    .font(.footnote.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                EditableDayStrip(entries: day.entries, now: Date(), height: 52) { updated in
                    state.saveDay(updated, on: day.date)
                }
                Text("Drag a break to move it, or grab a boundary to resize — later entries shift along.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func fixes(_ day: DayEntries) -> some View {
        if let shortfall = state.breakShortfall(day.entries) {
            Button {
                state.fixBreakGuideline(in: day.entries, on: day.date)
            } label: {
                Label("Fix break — \(Fmt.hm(shortfall)) short of the guideline",
                      systemImage: "wand.and.rays")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    private func entriesSection(_ day: DayEntries) -> some View {
        GlassGroupedSection(header: "Entries") {
            let sorted = day.entries.sorted { $0.start < $1.start }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, entry in
                GlassRow(showDivider: i > 0) {
                    entryRow(entry, day: day)
                }
            }
        }
    }

    private func entryRow(_ entry: AttendanceEntry, day: DayEntries) -> some View {
        let tint = entry.kind == .breakTime ? Color.bobOrange : Color.accentColor
        let duration = (entry.end ?? dayEnd).timeIntervalSince(entry.start)
        return HStack(spacing: 12) {
            Capsule().fill(tint).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.clock(entry.start)) – \(entry.end.map(Fmt.clock) ?? "open")")
                    .font(.body.monospacedDigit())
                Text("\(entry.kind == .breakTime ? "Break" : "Work") · \(Fmt.hm(duration))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let id = entry.id, state.deletingEntries.contains(id) {
                ProgressView().controlSize(.small)
            } else if entry.kind == .work {
                let hasReason = entry.reason?.isEmpty == false
                Menu {
                    ForEach(state.reasonOptions, id: \.name) { opt in
                        Button(opt.name) {
                            state.setReason(for: entry, in: day.entries, on: day.date, to: opt)
                        }
                    }
                } label: {
                    Text(hasReason ? entry.reason! : "Add reason")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(hasReason ? Color.primary : Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor.opacity(hasReason ? 0.10 : 0.16)))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editingEntry = EntryEdit(entry: entry) }
    }
}
