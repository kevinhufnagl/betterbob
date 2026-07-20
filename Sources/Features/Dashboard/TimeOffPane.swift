import SwiftUI

/// An SF Symbol for a leave policy, chosen from its display name.
func policyIcon(_ name: String) -> String {
    let n = name.lowercased()
    if n.contains("holiday") || n.contains("vacation") || n.contains("sunny") { return "sun.max.fill" }
    if n.contains("sick") { return "cross.case.fill" }
    if n.contains("overtime") || n.contains("banked") { return "clock.arrow.2.circlepath" }
    if n.contains("compassion") { return "heart.fill" }
    if n.contains("doctor") || n.contains("admin") { return "stethoscope" }
    if n.contains("care") || n.contains("pflege") { return "figure.2.and.child.holdinghands" }
    if n.contains("travel") || n.contains("trip") || n.contains("business") { return "airplane" }
    if n.contains("duty") { return "briefcase.fill" }
    return "calendar"
}

struct TimeOffPane: View {
    @ObservedObject var state: BobState
    @Environment(\.colorScheme) private var scheme
    // A booking presented via `.sheet(item:)` — its unique id forces SwiftUI to
    // rebuild the sheet on every open, so the sheet's @State picks up the new
    // start/end. (`.sheet(isPresented:)` reuses stale @State → wrong prefilled day.)
    @State private var booking: BookingRange?

    private struct BookingRange: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PaneHeader(title: "Time off")
                Spacer()
                Button {
                    booking = BookingRange(start: Date(), end: Date())
                } label: {
                    Label("Request time off", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.timeOffPolicyTypes.isEmpty)
            }

            upcomingCard
            TimeOffCalendar(state: state) { start, end in
                booking = BookingRange(start: start, end: end)
            }
            balances
            requests
        }
        .task { await state.loadTimeOff() }
        .sheet(item: $booking) { b in
            TimeOffBookingSheet(state: state, start: b.start, end: b.end)
        }
    }

    // MARK: - Upcoming

    /// Future, still-active requests, soonest first.
    private var upcoming: [TimeOffRequest] {
        let today = Calendar.current.startOfDay(for: Date())
        return state.timeOffRequests
            .filter { r in
                let s = r.status.lowercased()
                return !s.contains("cancel") && !s.contains("declin") && !s.contains("reject")
            }
            .filter { (DayFmt.date($0.startDate) ?? .distantPast) >= today }
            .sorted { (DayFmt.date($0.startDate) ?? .distantFuture) < (DayFmt.date($1.startDate) ?? .distantFuture) }
    }

    private var upcomingCard: some View {
        Card(title: "Upcoming time off", symbol: "sun.max.fill") {
            if upcoming.isEmpty {
                HStack(spacing: 12) {
                    AnimatedBob().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing booked yet").font(.system(size: 13, weight: .semibold))
                        Text("You've earned a break — treat yourself")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upcoming.prefix(4).enumerated()), id: \.offset) { i, r in
                        if i > 0 { Divider().opacity(0.12) }
                        upcomingRow(r, hero: i == 0)
                    }
                }
            }
        }
    }

    private func upcomingRow(_ r: TimeOffRequest, hero: Bool) -> some View {
        let accent = Color.workAccent(scheme)
        let pending = r.status.lowercased().contains("pend")
        return HStack(spacing: 12) {
            Image(systemName: policyIcon(r.typeName))
                .font(.system(size: hero ? 18 : 13, weight: .semibold))
                .foregroundStyle(accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.typeName).font(.system(size: hero ? 14 : 12, weight: .semibold))
                Text(prettyRange(r) + (r.amount.isEmpty ? "" : " · \(r.amount)"))
                    .font(.system(size: hero ? 11 : 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if pending {
                Text("Pending").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.bobOrange)
            }
            Text(countdown(r))
                .font(.system(size: hero ? 12 : 10, weight: .bold))
                .foregroundStyle(accent)
                .padding(.horizontal, 8).padding(.vertical, hero ? 5 : 3)
                .background(Capsule().fill(accent.opacity(0.15)))
        }
        .padding(.vertical, hero ? 10 : 8)
    }

    private func prettyRange(_ r: TimeOffRequest) -> String {
        func fmt(_ s: String) -> String {
            (DayFmt.date(s)?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) ?? s
        }
        return r.startDate == r.endDate ? fmt(r.startDate) : "\(fmt(r.startDate)) → \(fmt(r.endDate))"
    }

    private func countdown(_ r: TimeOffRequest) -> String {
        guard let start = DayFmt.date(r.startDate) else { return "" }
        let days = Calendar.current.dateComponents([.day],
                    from: Calendar.current.startOfDay(for: Date()), to: start).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days < 14 { return "in \(days) days" }
        let weeks = Int((Double(days) / 7).rounded())
        return "in \(weeks) weeks"
    }

    private var balances: some View {
        Group {
            if state.timeOffBalances.isEmpty {
                Card { Text("Loading balances…").font(.system(size: 12)).foregroundStyle(.secondary) }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(state.timeOffBalances) { b in balanceCard(b) }
                }
            }
        }
    }

    private func balanceCard(_ b: TimeOffBalance) -> some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(b.displayName).font(.system(size: 13, weight: .semibold))
                    Text(b.cycleRange).font(.system(size: 10)).foregroundStyle(.tertiary)
                    if let taken = b.daysTaken {
                        // Drop the sign — "-4" reads better as "4 taken".
                        Text("\(taken.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))) taken")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(b.currentBalance).font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.workAccent(scheme))
                    Text("of \(b.totalAllowance) \(b.unit)").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var requests: some View {
        Card(title: "Requests", symbol: "calendar.badge.clock") {
            if state.timeOffRequests.isEmpty {
                Text("No time-off requests in range.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(state.timeOffRequests.enumerated()), id: \.offset) { i, r in
                        if i > 0 { Divider().opacity(0.15) }
                        HStack(spacing: 12) {
                            statusDot(r.status)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.typeName).font(.system(size: 12, weight: .semibold))
                                Text("\(r.startDate)\(r.endDate == r.startDate ? "" : " → \(r.endDate)")")
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !r.amount.isEmpty {
                                Text("\(r.amount)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text(r.status.capitalized).font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            // Only future, still-active requests can be cancelled.
                            if state.cancellingRequests.contains(r.id) {
                                ProgressView().controlSize(.small)
                            } else if canCancel(r) {
                                Button(role: .destructive) { state.cancelTimeOff(r) } label: {
                                    Image(systemName: "xmark.circle").font(.system(size: 12))
                                }.buttonStyle(.plain).foregroundStyle(.secondary).help("Cancel request")
                            }
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
        }
    }

    /// Cancellable only if not already cancelled and starting in the future.
    private func canCancel(_ r: TimeOffRequest) -> Bool {
        if r.status.lowercased().contains("cancel") { return false }
        guard let start = DayFmt.date(r.startDate) else { return false }
        return start > Calendar.current.startOfDay(for: Date())
    }

    private func statusDot(_ status: String) -> some View {
        let color: Color = status.lowercased().contains("approv") ? .green
            : status.lowercased().contains("declin") || status.lowercased().contains("reject") ? .bobRed
            : .bobOrange
        return Circle().fill(color).frame(width: 8, height: 8)
    }
}

/// Month calendar showing time off, with click-a-day and drag-to-select-range
/// to open the request modal with those dates preselected.
struct TimeOffCalendar: View {
    @ObservedObject var state: BobState
    var onSelect: (Date, Date) -> Void
    @Environment(\.colorScheme) private var scheme

    @State private var month = Date()
    @State private var dragStart: Int?
    @State private var dragEnd: Int?
    @State private var hovered: Int?
    @State private var cancelTarget: TimeOffRequest?

    private let cal = Calendar(identifier: .gregorian)
    private let spacing: CGFloat = 6
    private let cellH: CGFloat = 46
    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var monthStart: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
    }

    private var days: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
        let offset = (cal.component(.weekday, from: monthStart) + 5) % 7  // Mon = 0
        var arr: [Date?] = Array(repeating: nil, count: offset)
        for d in range { arr.append(cal.date(byAdding: .day, value: d - 1, to: monthStart)) }
        while arr.count % 7 != 0 { arr.append(nil) }
        return arr
    }

    var body: some View {
        Card {
            VStack(spacing: 10) {
                header
                HStack(spacing: spacing) {
                    ForEach(weekdays, id: \.self) {
                        Text($0).font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                    }
                }
                grid
                Text("Click a day — or drag across days — to request time off. Click a booked day to cancel it.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .confirmationDialog("Cancel time off?",
                            isPresented: Binding(get: { cancelTarget != nil },
                                                 set: { if !$0 { cancelTarget = nil } }),
                            presenting: cancelTarget) { r in
            Button("Cancel \(r.typeName) request", role: .destructive) {
                state.cancelTimeOff(r); cancelTarget = nil
            }
            Button("Keep it", role: .cancel) { cancelTarget = nil }
        } message: { r in
            Text(r.startDate == r.endDate ? r.startDate : "\(r.startDate) → \(r.endDate)")
        }
    }

    /// Future, still-active requests can be cancelled.
    private func canCancel(_ r: TimeOffRequest) -> Bool {
        if r.status.lowercased().contains("cancel") { return false }
        guard let start = DayFmt.date(r.startDate) else { return false }
        return start > cal.startOfDay(for: Date())
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(monthStart.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 14, weight: .bold))
                .contentTransition(.numericText())
            Spacer()
            navButton("chevron.left") { shift(-1) }
            Button("Today") { withAnimation(.snappy) { month = Date() } }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            navButton("chevron.right") { shift(1) }
        }
    }
    private func navButton(_ sym: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: sym).font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.secondary)
    }
    private func shift(_ n: Int) {
        withAnimation(.snappy) { month = cal.date(byAdding: .month, value: n, to: monthStart) ?? month }
    }

    private var grid: some View {
        let rows = max(1, days.count / 7)
        let gridHeight = CGFloat(rows) * (cellH + spacing) - spacing
        return GeometryReader { geo in
            let cellW = (geo.size.width - spacing * 6) / 7
            ZStack(alignment: .topLeading) {
                ForEach(days.indices, id: \.self) { i in
                    if let date = days[i] {
                        cell(date, index: i)
                            .frame(width: cellW, height: cellH)
                            .offset(x: CGFloat(i % 7) * (cellW + spacing),
                                    y: CGFloat(i / 7) * (cellH + spacing))
                    }
                }
            }
            // Explicit size so the hit area / contentShape covers the whole
            // grid — `.offset` alone leaves the layout bounds tiny.
            .frame(width: geo.size.width, height: gridHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard let idx = indexAt(v.location, cellW: cellW), days[idx] != nil else { return }
                        if dragStart == nil { dragStart = idx }
                        dragEnd = idx
                    }
                    .onEnded { _ in
                        if let s = dragStart, let e = dragEnd {
                            // Single tap on a reserved (cancellable) day → offer
                            // to cancel that whole request; else start a booking.
                            if s == e, let d = days[s], let r = requestFor(d), canCancel(r) {
                                cancelTarget = r
                            } else if let sd = days[min(s, e)], let ed = days[max(s, e)] {
                                onSelect(sd, ed)
                            }
                        }
                        dragStart = nil; dragEnd = nil
                    }
            )
        }
        .frame(height: gridHeight)
    }

    private func indexAt(_ loc: CGPoint, cellW: CGFloat) -> Int? {
        let col = Int(loc.x / (cellW + spacing))
        let row = Int(loc.y / (cellH + spacing))
        guard col >= 0, col < 7, row >= 0 else { return nil }
        let idx = row * 7 + col
        return idx < days.count ? idx : nil
    }

    private func inDrag(_ i: Int) -> Bool {
        guard let s = dragStart, let e = dragEnd else { return false }
        return i >= min(s, e) && i <= max(s, e)
    }

    private func cell(_ date: Date, index: Int) -> some View {
        let isToday = cal.isDateInToday(date)
        let req = requestFor(date)
        let selected = inDrag(index)
        let reserved = req != nil && !selected
        let reqColor: Color = req.map { $0.status.lowercased().contains("approv") ? .green : .bobOrange } ?? .clear
        let dayColor: Color = reserved ? reqColor : .primary

        return VStack(alignment: .leading, spacing: 2) {
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: 11, weight: reserved || isToday ? .bold : .medium))
                .foregroundStyle(dayColor)
            Spacer(minLength: 0)
            if let req {
                Text(req.typeName).font(.system(size: 8, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(reqColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(cellFill(selected: selected, reserved: reserved, reqColor: reqColor, index: index)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(cellBorder(selected: selected, reserved: reserved, reqColor: reqColor,
                                     isToday: isToday, index: index), lineWidth: 1.2))
        .animation(.snappy(duration: 0.12), value: selected)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
    }

    private func cellFill(selected: Bool, reserved: Bool, reqColor: Color, index: Int) -> Color {
        if selected { return Color.bobTeal.opacity(0.22) }
        // A reserved cell stays its own colour on hover — just a stronger tint.
        if reserved { return reqColor.opacity(hovered == index ? 0.28 : 0.16) }
        if hovered == index { return Color.primary.opacity(0.09) }
        return Color.primary.opacity(0.035)
    }

    private func cellBorder(selected: Bool, reserved: Bool, reqColor: Color,
                            isToday: Bool, index: Int) -> Color {
        if selected { return Color.bobTeal }
        if reserved { return reqColor.opacity(hovered == index ? 0.78 : 0.5) }
        if isToday { return Color.primary.opacity(0.55) }
        if hovered == index { return Color.primary.opacity(0.2) }
        return .clear
    }

    private func requestFor(_ date: Date) -> TimeOffRequest? {
        let d = cal.startOfDay(for: date)
        return state.timeOffRequests.first { r in
            guard !r.status.lowercased().contains("cancel"),
                  let s = DayFmt.date(r.startDate), let e = DayFmt.date(r.endDate) else { return false }
            return d >= cal.startOfDay(for: s) && d <= cal.startOfDay(for: e)
        }
    }
}

/// Modal to request time off: type + range, with a live preview and submit.
struct TimeOffBookingSheet: View {
    @ObservedObject var state: BobState
    @Environment(\.dismiss) private var dismiss
    @State private var policy: TimeOffPolicyType?
    @State private var start: Date
    @State private var end: Date

    init(state: BobState, start: Date = Date(), end: Date = Date()) {
        self.state = state
        _start = State(initialValue: start)
        _end = State(initialValue: end)
    }
    @State private var calc: TimeOffCalc?
    @State private var calcError: String?
    @State private var calculating = false
    @State private var submitting = false
    @State private var error: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Request time off").font(.system(size: 17, weight: .bold))

            typeHeader

            Menu {
                ForEach(state.timeOffPolicyTypes) { p in
                    Button {
                        withAnimation(.snappy) { policy = p }; recalc()
                    } label: { Label(p.displayName, systemImage: policyIcon(p.displayName)) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(policy?.displayName ?? "Choose a type")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.7)
                }
                .foregroundStyle(policy == nil ? Color.secondary : .primary)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.8))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()

            HStack(spacing: 10) {
                Text("From").font(.system(size: 12)).frame(width: 40, alignment: .leading)
                PillDateField(date: $start, components: .date)
                    .onChange(of: start) { _, v in if end < v { end = v }; recalc() }
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                PillDateField(date: $end, components: .date, range: start...Date.distantFuture)
                    .onChange(of: end) { _, _ in recalc() }
            }

            previewBlock
                .animation(.snappy, value: calc)
                .animation(.snappy, value: calculating)

            if let error {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.system(size: 11)).foregroundStyle(Color.bobRed)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button {
                    guard let policy else { return }
                    submitting = true; error = nil
                    Task {
                        error = await state.submitTimeOff(policyType: policy.requestValue, start: start, end: end)
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
                }
                .buttonStyle(.borderedProminent)
                .disabled(policy == nil || submitting || calc?.submittable == false)
            }
        }
        .padding(22)
        .frame(width: 400)
        .onAppear {
            if policy == nil {
                policy = state.timeOffPolicyTypes.first { $0.type == "Holiday" }
                    ?? state.timeOffPolicyTypes.first { $0.displayName.lowercased().contains("holiday") }
                recalc()
            }
        }
    }

    /// Icon badge + name + available balance for the selected type.
    private var typeHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.workAccent(scheme).opacity(0.15)).frame(width: 52, height: 52)
                Image(systemName: policy.map { policyIcon($0.displayName) } ?? "calendar")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.workAccent(scheme))
                    .id(policy?.id ?? "none")
                    .transition(.scale.combined(with: .opacity))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(policy?.displayName ?? "Pick a leave type")
                    .font(.system(size: 14, weight: .semibold))
                if let bal = selectedBalance {
                    Text("\(bal.currentBalance) \(bal.unit) available")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("Choose what kind of time off to request")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.6))
    }

    @ViewBuilder private var previewBlock: some View {
        if calculating {
            HStack(spacing: 8) { ProgressView().controlSize(.small)
                Text("Calculating…").font(.system(size: 11)).foregroundStyle(.secondary) }
        } else if let msg = calcError {
            noticeCard(msg, tint: .bobRed, icon: "xmark.octagon.fill")
        } else if let calc {
            let blocker = calc.rejectReason ?? calc.validation
            if !calc.submittable {
                VStack(alignment: .leading, spacing: 6) {
                    if let blocker {
                        Label(blocker, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    if needsHiBobWeb(calc) {
                        Label("This type needs \(requiredList(calc)) — request it in the HiBob web app.",
                              systemImage: "arrow.up.forward.app")
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(Color.bobOrange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.bobOrange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(calc.requestMessage.isEmpty
                         ? "\(calc.amount.formatted()) day(s)" : calc.requestMessage)
                        .font(.system(size: 13, weight: .semibold))
                    if !calc.forecast.isEmpty {
                        Text(calc.forecast).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.workAccent(scheme).opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func needsHiBobWeb(_ calc: TimeOffCalc) -> Bool {
        calc.requiredFields.contains { $0 == "attachments" || $0 == "reasonCode" }
    }
    private func requiredList(_ calc: TimeOffCalc) -> String {
        var parts: [String] = []
        if calc.requiredFields.contains("attachments") { parts.append("an attachment") }
        if calc.requiredFields.contains("reasonCode") { parts.append("a reason") }
        return parts.joined(separator: " and ")
    }

    private func noticeCard(_ text: String, tint: Color, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var selectedBalance: TimeOffBalance? {
        guard let policy else { return nil }
        return state.timeOffBalances.first { $0.type == policy.type }
    }

    private func recalc() {
        guard let policy else { calc = nil; calcError = nil; return }
        calculating = true
        Task {
            do {
                calc = try await state.previewTimeOff(policyType: policy.requestValue, start: start, end: end)
                calcError = nil
            } catch {
                calc = nil
                calcError = error.localizedDescription
            }
            calculating = false
        }
    }
}
