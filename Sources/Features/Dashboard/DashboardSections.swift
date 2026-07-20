import SwiftUI
import Charts
import AppKit

/// A clean, tabular list of the day's entries — type, time range, duration,
/// editable reason, delete. Replaces the timeline bar.
struct EntriesTable: View {
    @ObservedObject var state: BobState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Card(title: "Entries", symbol: "list.bullet") {
            if state.entries.isEmpty {
                Text("No entries yet today.").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            } else {
                DayEntriesList(state: state, entries: state.entries,
                               date: Calendar.current.startOfDay(for: Date()),
                               newestFirst: true)
            }
        }
    }
}

/// The editable list of one day's entries — reused by Today and the day sheet.
struct DayEntriesList: View {
    @ObservedObject var state: BobState
    let entries: [AttendanceEntry]
    let date: Date
    var newestFirst: Bool = false

    var body: some View {
        // `entries` stays chronological (dayEntries integrity); only the display
        // order flips. isLast tracks the chronologically last (open) entry.
        let display = newestFirst ? Array(entries.reversed()) : entries
        let lastChrono = entries.last
        VStack(spacing: 0) {
            ForEach(Array(display.enumerated()), id: \.offset) { i, e in
                if i > 0 { Divider().opacity(0.15) }
                EntryRowView(state: state, entry: e, dayEntries: entries, date: date,
                             isLast: e == lastChrono)
                    .transition(.bobBanner)
            }
        }
        .animation(Motion.standard, value: entries)
    }
}

struct EntryRowView: View {
    @ObservedObject var state: BobState
    let entry: AttendanceEntry
    var dayEntries: [AttendanceEntry]
    var date: Date
    var isLast: Bool = false
    @Environment(\.colorScheme) private var scheme
    @State private var editing = false
    @State private var editStart = Date()
    @State private var editEnd = Date()
    @State private var timeHover = false

    var body: some View {
        let e = entry
        let tint = e.kind == .breakTime ? Color.breakAccent(scheme) : Color.workAccent(scheme)
        let editable = e.id != nil
        HStack(spacing: 12) {
            Image(systemName: e.kind.icon)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(tint).frame(width: 18)
            Text(e.kind.label)
                .font(.system(size: 12, weight: .semibold)).frame(width: 52, alignment: .leading)

            Button {
                editStart = e.start; editEnd = e.end ?? Date()
                editing = true
            } label: {
                HStack(spacing: 5) {
                    Text("\(Fmt.clock(e.start)) – \(e.end.map(Fmt.clock) ?? "now")  (\(Fmt.hm((e.end ?? Date()).timeIntervalSince(e.start))))")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.primary.opacity(0.85))
                    if editable {
                        Image(systemName: "pencil").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary).opacity(timeHover ? 1 : 0)
                    }
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(timeHover ? 0.10 : 0)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(timeHover ? 0.18 : 0), lineWidth: 0.7))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!editable)
            .frame(width: 210, alignment: .leading)
            .onHover { h in
                guard editable else { return }
                timeHover = h
                if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
            .animation(.easeOut(duration: 0.12), value: timeHover)
            .popover(isPresented: $editing, arrowEdge: .bottom) { timeEditor(e) }

            if e.kind == .work { ReasonPicker(state: state, entry: e, dayEntries: dayEntries, date: date) }
            Spacer()
            if let eid = e.id {
                if state.deletingEntries.contains(eid) {
                    ProgressView().controlSize(.small).frame(width: 16)
                        .transition(.opacity)
                } else {
                    Button(role: .destructive) { state.deleteEntry(e, in: dayEntries, on: date) } label: {
                        Image(systemName: "trash").font(.system(size: 11))
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help("Delete entry")
                        .transition(.opacity)
                }
            }
        }
        .padding(.vertical, 9)
        .animation(Motion.quick, value: state.deletingEntries)
    }

    private func timeEditor(_ e: AttendanceEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adjust times").font(.system(size: 12, weight: .semibold))
            HStack { Text("Start").font(.system(size: 12)); Spacer()
                timeField($editStart) }
            if e.end != nil {
                HStack { Text("End").font(.system(size: 12)); Spacer()
                    timeField($editEnd) }
                if isLast {
                    Button {
                        // Clear the end → reopen the entry (revert a clock-out
                        // / end-break, so you're "still going").
                        state.updateEntryTimes(e, in: dayEntries, on: date, start: editStart, end: nil)
                        editing = false
                    } label: {
                        Label("Clear end (reopen)", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain).foregroundStyle(.blue)
                }
            } else {
                Text("Open entry — ends when you clock out.").font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { editing = false }
                Button("Save") {
                    state.updateEntryTimes(e, in: dayEntries, on: date,
                                           start: editStart, end: e.end == nil ? nil : editEnd)
                    editing = false
                }.buttonStyle(.borderedProminent)
                    .disabled(e.end != nil && editEnd <= editStart)
            }
        }
        .padding(16).frame(width: 240)
    }

    /// Inline HH:MM field — no nested popover (the pill's own popover rendered
    /// broken inside this one), no spinner arrows.
    private func timeField(_ value: Binding<Date>) -> some View {
        DatePicker("", selection: value, displayedComponents: .hourAndMinute)
            .datePickerStyle(.field).labelsHidden().fixedSize()
    }
}

/// Reason dropdown extracted so both popover and table can share the look.
struct ReasonPicker: View {
    @ObservedObject var state: BobState
    let entry: AttendanceEntry
    var dayEntries: [AttendanceEntry]
    var date: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let has = !(entry.reason ?? "").isEmpty
        let accent = Color.reasonAccent(scheme)
        Menu {
            ForEach(state.reasonOptions, id: \.self) { opt in
                Button {
                    state.setReason(for: entry, in: dayEntries, on: date, to: opt)
                } label: {
                    if opt.name == entry.reason { Label(opt.name, systemImage: "checkmark") }
                    else { Text(opt.name) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(has ? entry.reason! : "Set reason").font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)).opacity(0.7)
            }
            .foregroundStyle(has ? accent : Color.secondary)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(has ? accent.opacity(0.18) : Color.primary.opacity(0.07)))
            .overlay(Capsule(style: .continuous).strokeBorder((has ? accent : .primary).opacity(0.28), lineWidth: 0.8))
        }
        // No .fixedSize() — let the pill shrink and truncate rather than push the
        // row past the popover's width.
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .disabled(state.reasonOptions.isEmpty || entry.id == nil)
    }
}

// MARK: - Day detail (edit a past day)

struct DayDetailSheet: View {
    @ObservedObject var state: BobState
    let dateKey: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var day: DayEntries? { state.monthDays.first { $0.dateKey == dateKey } }
    private var worked: TimeInterval {
        (day?.entries ?? []).filter { $0.kind == .work }
            .reduce(0) { $0 + ($1.end ?? $1.start).timeIntervalSince($1.start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day?.date.formatted(.dateTime.weekday(.wide).day().month()) ?? "Day")
                        .font(.system(size: 16, weight: .bold))
                    if worked > 0 {
                        Text("\(Fmt.hm(worked)) worked").font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if state.busy || !state.deletingEntries.isEmpty {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Saving…").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .animation(.easeInOut(duration: 0.15), value: state.busy)

            if let day, state.hasOverLongStretch(day.entries) { wandBanner(day).transition(.bobBanner) }
            if let day, state.isOverDailyMax(day.entries) { overMaxBanner.transition(.bobBanner) }

            if let day, !day.entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    EditableDayStrip(entries: day.entries, now: Date(), height: 72) { updated in
                        state.saveDay(updated, on: day.date)
                    }
                    Text("Drag a break to move it, or grab a boundary to resize — later entries shift along.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                VStack(spacing: 0) {
                    DayEntriesList(state: state, entries: day.entries, date: day.date)
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
            } else {
                Text("No entries this day.").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            }

            Text("Edit times or reasons, drag breaks, or delete entries — changes save to HiBob for this day.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(20).frame(width: 560)
        .animation(Motion.standard, value: day?.entries)
    }

    /// Red and actionless — a day past the daily max can only be fixed by
    /// editing its entries, not by an automatic action.
    private var overMaxBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Fmt.hm(worked)) worked — over the \(Fmt.hm(Prefs.shared.maxDayLimit)) daily max")
                    .font(.system(size: 12, weight: .semibold))
                Text("Nothing to auto-fix here — shorten an entry below if this day is wrong.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.red.opacity(0.30), lineWidth: 0.8))
    }

    /// Wand to fix a too-long uninterrupted run on this (any) day.
    private func wandBanner(_ day: DayEntries) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("A stretch runs past your \(Fmt.hm(Prefs.shared.threshold)) max without a break")
                    .font(.system(size: 12, weight: .semibold))
                Text("Insert a \(Prefs.shared.breakMinutes)-min break mid-shift — clock-in/out stay put.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { state.addMissingBreak(in: day.entries, on: day.date) } label: {
                Label("Add break", systemImage: "wand.and.stars").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(Color.orange.opacity(0.45), lineWidth: 0.8))
                    .foregroundStyle(.orange)
            }.buttonStyle(.plain).disabled(state.busy)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.orange.opacity(0.30), lineWidth: 0.8))
    }
}

// MARK: - This cycle

struct CyclePane: View {
    @ObservedObject var state: BobState
    var onOpenToday: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @State private var openDay: DayEntries?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(title: "This month", subtitle: cycleSubtitle)
            kpiGrid
            CalendarHeatmap(state: state, onOpenToday: onOpenToday)
            byDayList
            BalanceTrendCard(state: state)
            rhythm
            compliance
        }
    }

    private var byDayList: some View {
        Card(title: "By day", symbol: "calendar.day.timeline.left") {
            let days = state.monthDays.filter { !$0.entries.isEmpty }.reversed()
            if days.isEmpty {
                Text("No entries this month yet.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                        if i > 0 { Divider().opacity(0.15) }
                        dayRow(day)
                    }
                }
            }
        }
    }

    private func dayRow(_ day: DayEntries) -> some View {
        let worked = day.entries.filter { $0.kind == .work }
            .reduce(0.0) { $0 + ($1.end ?? $1.start).timeIntervalSince($1.start) }
        let isToday = day.dateKey == DayFmt.today()
        return Button {
            if isToday { onOpenToday() } else { openDay = day }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().month()))
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(worked > 0 ? Fmt.hm(worked) : "—") · \(day.entries.count) entr\(day.entries.count == 1 ? "y" : "ies")")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                ForEach(Array(day.entries.prefix(6).enumerated()), id: \.offset) { _, e in
                    Circle().fill(e.kind == .breakTime ? Color.breakAccent(scheme) : Color.workAccent(scheme))
                        .frame(width: 6, height: 6)
                }
                if isToday {
                    Text("Today").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.accentColor)
                }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { openDay?.dateKey == day.dateKey },
                                      set: { if !$0 { openDay = nil } }),
                 arrowEdge: .leading) {
            DayDetailSheet(state: state, dateKey: day.dateKey)
        }
    }

    private var rhythm: some View {
        let worked = (state.cycleSummary?.days ?? []).filter { $0.worked > 0 }
        let avg = worked.isEmpty ? 0 : worked.reduce(0) { $0 + $1.worked } / Double(worked.count)
        let longest = worked.map(\.worked).max() ?? 0
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            StatTile(value: hoursText(avg), caption: "Avg day", tint: .workAccent(scheme), symbol: "clock")
            StatTile(value: hoursText(longest), caption: "Longest day", symbol: "arrow.up.right")
            StatTile(value: "\(worked.count)", caption: "Days worked", symbol: "calendar")
        }
    }

    private var compliance: some View {
        let v = state.cycleSummary?.breakViolations ?? 0
        return Card(title: "Break compliance", symbol: "checkmark.shield") {
            HStack(spacing: 10) {
                Image(systemName: v == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(v == 0 ? .green : .orange).font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(v == 0 ? "No break violations this cycle" : "\(v) break violation\(v == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                    Text("Policy: a break of ≥30 min within 6 h — the rule BetterBob automates.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var cycleSubtitle: String {
        guard let c = state.cycle else { return "Timesheet cycle" }
        return "\(c.start) → \(c.end)"
    }

    private var kpiGrid: some View {
        let s = state.cycleSummary
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            StatTile(value: s?.totalHoursDisplay ?? "—", caption: "Month worked",
                     tint: .workAccent(scheme), symbol: "sum")
            StatTile(value: s.map { signedHours(Double($0.overUnderMinutes) / 60) } ?? "—",
                     caption: "Over / under",
                     tint: (s?.overUnderMinutes ?? 0) >= 0 ? .workAccent(scheme) : .breakAccent(scheme),
                     symbol: "plusminus")
            StatTile(value: s.map { "\($0.payableTimePercent)%" } ?? "—", caption: "Progress", symbol: "chart.pie")
            StatTile(value: deadlineText, caption: "Locks in", tint: .orange, symbol: "lock")
            StatTile(value: "\(s?.breakViolations ?? 0)", caption: "Break issues",
                     tint: (s?.breakViolations ?? 0) == 0 ? .green : .orange,
                     symbol: (s?.breakViolations ?? 0) == 0 ? "checkmark.shield" : "exclamationmark.shield")
        }
    }
    private var deadlineText: String {
        guard let lock = state.cycle?.lockAt else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: lock).day ?? 0
        return days > 0 ? "\(days) days" : "today"
    }
}

/// A proper month calendar: weekday columns, week rows, each day shaded by
/// hours worked with the number shown and today ringed.
struct CalendarHeatmap: View {
    @ObservedObject var state: BobState
    var onOpenToday: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @State private var hovered: String?
    @State private var selected: String?    // dateKey of the cell whose detail is open
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        Card(title: "Daily hours", symbol: "calendar") {
            if let days = state.cycleSummary?.days, !days.isEmpty {
                let maxWorked = max(days.map(\.worked).max() ?? 1, 1)
                VStack(spacing: 8) {
                    LazyVGrid(columns: cols, spacing: 6) {
                        ForEach(weekdays, id: \.self) { wd in
                            Text(wd).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        ForEach(0..<leadingBlanks(days), id: \.self) { _ in Color.clear.frame(height: 40) }
                        ForEach(days, id: \.date) { day in cell(day, maxWorked: maxWorked) }
                    }
                    legend
                }
            } else {
                Text("Loading cycle…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func leadingBlanks(_ days: [DayHours]) -> Int {
        guard let first = days.first.flatMap({ DayFmt.date($0.date) }) else { return 0 }
        return (Calendar(identifier: .gregorian).component(.weekday, from: first) + 5) % 7
    }

    private func cell(_ day: DayHours, maxWorked: Double) -> some View {
        let ratio = day.worked / maxWorked
        let isToday = day.date == DayFmt.today()
        let hasTarget = (day.target ?? 0) > 0
        let worked = day.worked > 0
        let hov = hovered == day.date
        // A day with an uninterrupted run past the max is flagged orange right
        // here, so the break issue is visible without opening the cell — the
        // wand inside fixes it. The whole cell just swaps its green accent for
        // orange, so the same tint/border/text language carries over. A day
        // past the daily max is red — the harder limit wins over orange.
        let breakIssue = state.monthDays
            .first(where: { $0.dateKey == day.date })
            .map { state.hasOverLongStretch($0.entries) } ?? false
        let overMax = state.monthDays
            .first(where: { $0.dateKey == day.date })
            .map { state.isOverDailyMax($0.entries) }
            ?? (day.worked * 3600 > Prefs.shared.maxDayLimit)
        let accent = overMax ? Color.red : breakIssue ? Color.orange : Color.workAccent(scheme)
        // Same language as the time-off calendar: subtle tinted fill + strong
        // border + bold tinted text — strengths scale with hours worked. On
        // hover a worked cell stays green, just a stronger tint (same as the
        // reserved cells in the time-off calendar).
        let fill = worked ? accent.opacity(0.08 + 0.20 * ratio + (hov ? 0.12 : 0))
                          : Color.primary.opacity(hov ? 0.09 : (hasTarget ? 0.04 : 0.015))
        // Today uses the same green, just a thicker border.
        let border = worked ? accent.opacity(0.30 + 0.45 * ratio + (hov ? 0.28 : 0))
                     : isToday ? accent.opacity(0.55)
                     : hov ? Color.primary.opacity(0.2)
                     : Color.clear
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .frame(height: 40)
            .overlay(alignment: .topLeading) {
                Text(dayNum(day.date))
                    .font(.system(size: 9, weight: worked || isToday ? .bold : .medium))
                    .foregroundStyle(worked || isToday ? accent : .secondary)
                    .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                if worked {
                    Text(hoursText(day.worked)).font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(accent).padding(3)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(border, lineWidth: isToday ? 2.5 : 1.2))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .animation(.easeOut(duration: 0.12), value: hov)
            .onHover { hovered = $0 ? day.date : (hovered == day.date ? nil : hovered) }
            .onTapGesture {
                if isToday { onOpenToday() } else { selected = day.date }
            }
            // Detail popover anchored to this exact cell; closes on outside click.
            .popover(isPresented: Binding(get: { selected == day.date },
                                          set: { if !$0 { selected = nil } }),
                     arrowEdge: .bottom) {
                DayDetailSheet(state: state, dateKey: day.date)
            }
            .help("\(day.date): \(hoursText(day.worked))" + (hasTarget ? " / \(hoursText(day.target!)) target" : "")
                  + (breakIssue ? " · break issue — needs a break" : "")
                  + (overMax ? " · over the daily max" : ""))
    }
    private func dayNum(_ s: String) -> String { String(s.suffix(2)).drop(while: { $0 == "0" }).description }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Fewer hours").font(.system(size: 9)).foregroundStyle(.tertiary)
            ForEach([0.18, 0.4, 0.65, 0.9], id: \.self) { o in
                RoundedRectangle(cornerRadius: 3).fill(Color.workAccent(scheme).opacity(o)).frame(width: 14, height: 10)
            }
            Text("More").font(.system(size: 9)).foregroundStyle(.tertiary)
            Spacer()
            RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.5)).frame(width: 14, height: 10)
            Text("Break issue").font(.system(size: 9)).foregroundStyle(.tertiary)
            RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.5)).frame(width: 14, height: 10)
            Text("Over daily max").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

struct BalanceTrendCard: View {
    @ObservedObject var state: BobState
    @Environment(\.colorScheme) private var scheme
    private struct Point: Identifiable { let id = UUID(); let date: Date; let balance: Double }

    private var points: [Point] {
        guard let days = state.cycleSummary?.days else { return [] }
        var running = 0.0; var out: [Point] = []
        for d in days {
            guard let date = DayFmt.date(d.date), (d.target ?? 0) > 0 || d.worked > 0 else { continue }
            if date > Date() { break }
            running += d.worked - (d.target ?? 0)
            out.append(Point(date: date, balance: running))
        }
        return out
    }

    var body: some View {
        Card(title: "Running over / under", symbol: "chart.xyaxis.line") {
            if points.count < 2 {
                Text("Not enough days yet.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Chart(points) { p in
                    AreaMark(x: .value("Date", p.date), yStart: .value("z", 0), yEnd: .value("Balance", p.balance))
                        .foregroundStyle((p.balance >= 0 ? Color.workAccent(scheme) : Color.breakAccent(scheme)).opacity(0.16))
                    LineMark(x: .value("Date", p.date), y: .value("Balance", p.balance))
                        .foregroundStyle(p.balance >= 0 ? Color.workAccent(scheme) : Color.breakAccent(scheme))
                        .interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartYAxis { AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel { if let h = v.as(Double.self) { Text("\(Int(h))h").font(.system(size: 9)) } } } }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                    AxisValueLabel(format: .dateTime.month().day()).font(.system(size: 9)) } }
                .frame(height: 160)
            }
        }
    }
}

// MARK: - Activity

struct ActivityPane: View {
    @ObservedObject var state: BobState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(title: "Activity", subtitle: "Today's clock & edit history")
            Card {
                if state.activity.isEmpty {
                    Text("No activity recorded today.").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(state.activity.enumerated()), id: \.offset) { i, ev in
                            if i > 0 { Divider().opacity(0.15) }
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: glyph(ev.kind)).font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(color(ev.kind)).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(label(ev.kind)).font(.system(size: 12, weight: .semibold))
                                    if !ev.detail.isEmpty {
                                        Text(ev.detail).font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Fmt.clock(ev.timestamp)).font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10)
                            .transition(.bobBanner)
                        }
                    }
                    .animation(Motion.standard, value: state.activity)
                }
            }
        }
    }
    private func glyph(_ k: ActivityEvent.Kind) -> String {
        switch k {
        case .clockedIn: return "play.circle.fill"
        case .clockedOut: return "stop.circle.fill"
        case .addedBreak: return "pause.circle.fill"
        case .edited: return "pencil.circle.fill"
        case .other: return "circle.fill"
        }
    }
    private func color(_ k: ActivityEvent.Kind) -> Color {
        switch k {
        case .clockedIn: return .green
        case .clockedOut: return .red
        case .addedBreak: return .orange
        case .edited: return .blue
        case .other: return .secondary
        }
    }
    private func label(_ k: ActivityEvent.Kind) -> String {
        switch k {
        case .clockedIn: return "Clocked in"
        case .clockedOut: return "Clocked out"
        case .addedBreak: return "Break added"
        case .edited: return "Entry edited"
        case .other: return "Update"
        }
    }
}

// MARK: - Shared bits

struct ProgressRing: View {
    let fraction: Double
    let center: String
    let tint: Color
    @State private var sweep = false

    var body: some View {
        let f = min(1, max(0, fraction))
        let done = fraction >= 1
        ZStack {
            Circle().stroke(Color.primary.opacity(0.07), lineWidth: 18)
            Circle()
                .trim(from: 0, to: sweep ? f : 0)
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.5), tint], center: .center),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.4), radius: 6)
            VStack(spacing: 3) {
                Text(center).font(.system(size: 27, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                HStack(spacing: 3) {
                    if done { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                    Text("\(Int((fraction * 100).rounded()))%").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(done ? tint : .secondary)
            }
        }
        .animation(.smooth(duration: 0.5), value: f)
        .onAppear { withAnimation(.smooth(duration: 0.7)) { sweep = true } }
    }
}

/// Fixed categorical order for reason colors (dataviz: assign in order, never cycle).
func reasonColor(_ index: Int) -> Color {
    let palette: [Color] = [.teal, .blue, .orange, .purple, .pink, .indigo, .mint]
    return index < palette.count ? palette[index] : .gray
}
