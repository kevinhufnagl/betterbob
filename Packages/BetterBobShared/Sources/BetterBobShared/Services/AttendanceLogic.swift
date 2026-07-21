import Foundation

/// Pure attendance math — no clocks, no network, no state. Everything takes
/// today's entries plus an explicit `now`, so it's all unit-testable.
public enum AttendanceLogic {
    /// Current punch state, read straight from the entries: an entry with no
    /// end time is in progress. An open break means on break; an open work
    /// entry means working; everything closed means clocked out. This mirrors
    /// reality even when HiBob's `nextClockAction` is briefly confused (e.g. a
    /// day left in an inconsistent state), which is why we don't rely on it.
    public static func state(entries: [AttendanceEntry], now: Date) -> ClockState {
        if let openBreak = entries.last(where: { $0.kind == .breakTime && $0.end == nil }) {
            return .onBreak(since: openBreak.start)
        }
        if entries.contains(where: { $0.kind == .work && $0.end == nil }) {
            return .working(since: stretchStart(entries: entries) ?? now)
        }
        return .clockedOut
    }

    /// A clocked-out gap this long between work entries interrupts the
    /// uninterrupted-work stretch, exactly like a logged break — clocking out
    /// at 11:00 and back in at 23:00 starts a fresh run. Short accidental
    /// out/in blips (under 15 min) don't reset the counter. (This is only
    /// about the continuity counter; whether a pause satisfies the break
    /// guideline is `breakShortfall`'s stricter `required` minimum.)
    public static let gapResets: TimeInterval = 15 * 60

    /// Start of the current uninterrupted work stretch: the end of the most
    /// recent completed break, the far side of the most recent clocked-out
    /// gap, or — failing both — the first clock-in of the day. (The caller
    /// decides *whether* we're working; this only answers *since when*.)
    public static func stretchStart(entries: [AttendanceEntry]) -> Date? {
        let works = entries.filter { $0.kind == .work }.sorted { $0.start < $1.start }
        guard let first = works.first else { return nil }
        var runStart = first.start
        var runEnd = first.end ?? .distantFuture
        for w in works.dropFirst() {
            if w.start.timeIntervalSince(runEnd) >= gapResets {
                runStart = w.start
            }
            runEnd = max(runEnd, w.end ?? .distantFuture)
        }
        let lastBreakEnd = entries.compactMap { $0.kind == .breakTime ? $0.end : nil }.max()
        return max(runStart, lastBreakEnd ?? runStart)
    }

    /// Total time worked today: work periods minus any overlapping breaks.
    public static func workedToday(entries: [AttendanceEntry], now: Date) -> TimeInterval {
        let breaks = entries.filter { $0.kind == .breakTime }
        var total: TimeInterval = 0
        for entry in entries where entry.kind == .work {
            let start = entry.start
            let end = entry.end ?? now
            guard end > start else { continue }
            var span = end.timeIntervalSince(start)
            for b in breaks {
                let overlapStart = max(b.start, start)
                let overlapEnd = min(b.end ?? now, end)
                if overlapEnd > overlapStart {
                    span -= overlapEnd.timeIntervalSince(overlapStart)
                }
            }
            total += max(0, span)
        }
        return total
    }

    /// The action the engine should take right now, if any.
    /// `autoBreakStartedAt` is the start of a break *this app* began — nil
    /// means any open break is the user's own and is left alone.
    public static func action(entries: [AttendanceEntry],
                       autoBreakStartedAt: Date?,
                       threshold: TimeInterval,
                       breakLength: TimeInterval,
                       now: Date) -> AutoBreakAction? {
        switch state(entries: entries, now: now) {
        case .clockedOut:
            return nil

        case .onBreak:
            guard let autoStart = autoBreakStartedAt else { return nil }
            let end = autoStart.addingTimeInterval(breakLength)
            return now >= end ? .endBreak(at: end) : nil

        case .working(let since):
            let due = since.addingTimeInterval(threshold)
            guard now >= due else { return nil }
            // Always place the break at `due` (the max mark). If the whole window
            // already passed, close it and resume work; otherwise it's ongoing.
            let windowEnd = due.addingTimeInterval(breakLength)
            return .insertBreak(start: due, end: now >= windowEnd ? windowEnd : nil)
        }
    }

    /// True when the day's total worked time (breaks excluded, an open entry
    /// counted to `now`) is past the daily maximum. Warning only — unlike a
    /// missing break there is nothing to auto-fix.
    public static func overDailyMax(entries: [AttendanceEntry], max: TimeInterval, now: Date) -> Bool {
        workedToday(entries: entries, now: now) > max
    }

    /// The longest uninterrupted work run (consecutive work with no break in
    /// between) whose duration exceeds `threshold`, as `[start, end]` — or nil if
    /// every run is within the max. Works for any day: an open run is measured to
    /// `now`. This is what the "add a break" wand fixes.
    public static func overLongStretch(entries: [AttendanceEntry], threshold: TimeInterval,
                                now: Date) -> (start: Date, end: Date)? {
        let sorted = entries.sorted { $0.start < $1.start }
        var runStart: Date?
        var runEnd = Date.distantPast
        var best: (start: Date, end: Date)?
        func consider() {
            guard let s = runStart, runEnd.timeIntervalSince(s) > threshold else { return }
            if best == nil || runEnd.timeIntervalSince(s) > best!.end.timeIntervalSince(best!.start) {
                best = (s, runEnd)
            }
        }
        for entry in sorted {
            if entry.kind == .work {
                let end = entry.end ?? now
                if runStart == nil {
                    runStart = entry.start; runEnd = end
                } else if entry.start.timeIntervalSince(runEnd) >= gapResets {
                    // A clocked-out gap interrupts the run like a break does.
                    consider(); runStart = entry.start; runEnd = end
                } else {
                    runEnd = max(runEnd, end)
                }
            } else {
                consider(); runStart = nil
            }
        }
        consider()
        return best
    }

    /// HiBob's "Break not taken or doesn't meet guidelines": once the day's
    /// worked time passes `threshold`, at least `required` of pause has to be
    /// logged — and a single pause only counts if it is itself at least
    /// `required` long (the tenant's minimum break, the same value as the
    /// break-length setting), so two 15-minute breaks don't satisfy a
    /// 30-minute rule. Clocked-out gaps qualify like breaks. Returns how much
    /// pause is missing, or nil when the day complies (or hasn't reached the
    /// threshold yet).
    public static func breakShortfall(entries: [AttendanceEntry], threshold: TimeInterval,
                               required: TimeInterval, now: Date) -> TimeInterval? {
        guard required > 0,
              workedToday(entries: entries, now: now) > threshold else { return nil }
        let sorted = entries.sorted { $0.start < $1.start }
        var pause: TimeInterval = 0
        var lastEnd: Date?
        for e in sorted {
            if let le = lastEnd, e.start.timeIntervalSince(le) >= required {
                pause += e.start.timeIntervalSince(le)
            }
            if e.kind == .breakTime {
                let len = (e.end ?? now).timeIntervalSince(e.start)
                if len >= required { pause += len }
            }
            lastEnd = max(lastEnd ?? .distantPast, e.end ?? now)
        }
        return pause >= required ? nil : required - pause
    }

    /// Fix a break-guideline shortfall: grow the day's longest closed break by
    /// the missing amount (later entries stay put — `normalized` with the
    /// break as anchor reflows the neighbours), or, with no closed break to
    /// grow, splice a fresh `required`-long break into the middle of the
    /// longest work entry. Returns nil when the day already complies.
    public static func meetingBreakGuideline(entries: [AttendanceEntry], threshold: TimeInterval,
                                      required: TimeInterval, now: Date) -> [AttendanceEntry]? {
        guard let missing = breakShortfall(entries: entries, threshold: threshold,
                                           required: required, now: now) else { return nil }
        var out = entries.sorted { $0.start < $1.start }
        if let idx = out.indices
            .filter({ out[$0].kind == .breakTime && out[$0].end != nil })
            .max(by: { out[$0].end!.timeIntervalSince(out[$0].start)
                     < out[$1].end!.timeIntervalSince(out[$1].start) }) {
            // A break that already qualifies just grows by the shortfall. A
            // too-short one contributed nothing, so its whole new length must
            // cover the shortfall — and be at least `required` to count.
            let len = out[idx].end!.timeIntervalSince(out[idx].start)
            let targetLen = len >= required ? len + missing : max(missing, required)
            out[idx].end = out[idx].start.addingTimeInterval(targetLen)
            return normalized(out, anchor: out[idx].id)
        }
        guard let longest = out.indices
            .filter({ out[$0].kind == .work })
            .max(by: { (out[$0].end ?? now).timeIntervalSince(out[$0].start)
                     < (out[$1].end ?? now).timeIntervalSince(out[$1].start) })
        else { return nil }
        let w = out[longest]
        let mid = w.start.addingTimeInterval(((w.end ?? now).timeIntervalSince(w.start) - required) / 2)
        guard mid > w.start else { return nil }
        return insertingBreak(into: out, start: mid, end: mid.addingTimeInterval(required))
    }

    /// Rebuild the day's entries with a break spliced into the work entry that
    /// contains `start`. Splits that entry into work → break → (work). `end`
    /// nil leaves the break open/ongoing (no trailing work); a date closes it
    /// and resumes work (the trailing piece keeps the original's reason and
    /// open/closed end). Returns nil if no work entry contains `start`.
    public static func insertingBreak(into entries: [AttendanceEntry],
                               start: Date, end: Date?,
                               breakID: String? = nil, breakReason: String? = nil) -> [AttendanceEntry]? {
        guard let idx = entries.firstIndex(where: {
            $0.kind == .work && $0.start <= start && ($0.end ?? .distantFuture) >= start
        }) else { return nil }

        let work = entries[idx]
        var pieces: [AttendanceEntry] = [
            AttendanceEntry(kind: .work, start: work.start, end: start, id: work.id, reason: work.reason),
            AttendanceEntry(kind: .breakTime, start: start, end: end, id: breakID, reason: breakReason),
        ]
        if let end, work.end == nil || end < work.end! {
            pieces.append(AttendanceEntry(kind: .work, start: end, end: work.end,
                                          id: nil, reason: work.reason))
        }
        var rebuilt = entries
        rebuilt.replaceSubrange(idx...idx, with: pieces)
        return rebuilt
    }

    /// Insert as many breaks as it takes so no work run exceeds `threshold`,
    /// each placed at the edge of a max window (run start + threshold). Fixes a
    /// whole over-long day in one go — a 13h block gets two breaks. Returns nil
    /// if nothing needed fixing.
    public static func insertingAllBreaks(into entries: [AttendanceEntry], threshold: TimeInterval,
                                   breakLength: TimeInterval, now: Date) -> [AttendanceEntry]? {
        var current = entries.sorted { $0.start < $1.start }
        var changed = false
        for _ in 0..<12 {
            guard let stretch = overLongStretch(entries: current, threshold: threshold, now: now)
            else { break }
            // Break at the edge of the max, clamped so it fits inside the run.
            var breakStart = stretch.start.addingTimeInterval(threshold)
            let latest = stretch.end.addingTimeInterval(-breakLength)
            if breakStart > latest { breakStart = latest }
            guard breakStart > stretch.start,
                  let rebuilt = insertingBreak(into: current, start: breakStart,
                                               end: breakStart.addingTimeInterval(breakLength))
            else { break }
            current = rebuilt.sorted { $0.start < $1.start }
            changed = true
        }
        return changed ? current : nil
    }

    /// Close the open (ongoing) break at `at` and resume work from there —
    /// the retroactive end for an auto-break that has run its length.
    public static func closingBreak(into entries: [AttendanceEntry], at: Date,
                             reason: String?) -> [AttendanceEntry]? {
        guard let idx = entries.firstIndex(where: { $0.kind == .breakTime && $0.end == nil })
        else { return nil }
        var out = entries
        out[idx].end = at
        out.append(AttendanceEntry(kind: .work, start: at, end: nil, id: nil, reason: reason))
        return out
    }

    /// After a clock-in that left a clocked-out hole behind it, make the day
    /// contiguous again: a hole after a closed break stretches that break to
    /// the clock-in (the auto-break's fixed end passed before the user
    /// actually returned); a hole after closed work becomes a new break
    /// covering it (clocked out at 2, back at 3 → a 2–3 break). Returns the
    /// fixed day, or nil when there is nothing to fix. Holes under a minute
    /// are left alone — not worth a whole-day rewrite.
    public static func fillingGapBeforeClockIn(entries: [AttendanceEntry]) -> [AttendanceEntry]? {
        let sorted = entries.sorted { $0.start < $1.start }
        guard sorted.count >= 2,
              let last = sorted.last, last.kind == .work, last.end == nil
        else { return nil }
        let prev = sorted[sorted.count - 2]
        guard let prevEnd = prev.end,
              last.start.timeIntervalSince(prevEnd) >= 60
        else { return nil }
        var fixed = sorted
        if prev.kind == .breakTime {
            fixed[fixed.count - 2].end = last.start
        } else {
            fixed.insert(AttendanceEntry(kind: .breakTime, start: prevEnd, end: last.start),
                         at: fixed.count - 1)
        }
        return fixed
    }

    /// Make a day's entries strictly contiguous — no gaps, no overlaps.
    /// Entries are sorted by start, then each is snapped to the end of the one
    /// before it. `anchor` (the id of the entry the user just edited) is
    /// authoritative: its start/end are kept and its neighbours move to meet it
    /// — the entry before it has its end trimmed/extended to the anchor's start,
    /// and entries after it snap to the anchor's end. A neighbour swallowed to
    /// zero/negative length is dropped. An open final entry (`end == nil`) stays
    /// open. With no `anchor`, this is a plain left-to-right contiguity chain:
    /// each entry's start snaps to the previous end, preserving the first
    /// clock-in and every entry's own end (so the clock-out is preserved).
    public static func normalized(_ entries: [AttendanceEntry], anchor: String? = nil) -> [AttendanceEntry] {
        let sorted = entries.sorted { $0.start < $1.start }
        var out: [AttendanceEntry] = []
        for entry in sorted {
            var e = entry
            let isAnchor = anchor != nil && e.id == anchor
            if !out.isEmpty {
                if isAnchor {
                    // Reconcile everything already placed so nothing crosses into
                    // the anchor's start: drop entries entirely at/after it, trim
                    // the one straddling it, then close any gap before it.
                    while let prev = out.last, (prev.end ?? prev.start) > e.start {
                        if prev.start >= e.start { out.removeLast() }
                        else { out[out.count - 1].end = e.start; break }
                    }
                    if let pe = out.last?.end, pe < e.start { out[out.count - 1].end = e.start }
                } else if let prevEnd = out.last?.end {
                    e.start = prevEnd                    // snap to the previous entry's end
                }
            }
            // A non-anchor entry snapped past its own end is swallowed — drop it.
            if !isAnchor, let end = e.end, end <= e.start { continue }
            out.append(e)
        }
        return out
    }

    /// Merge consecutive same-kind entries into one, closing the gaps between
    /// them — used after pulling a break out of the day so the work on either
    /// side of its old slot becomes one continuous block again.
    public static func coalesced(_ entries: [AttendanceEntry]) -> [AttendanceEntry] {
        let sorted = entries.sorted { $0.start < $1.start }
        var out: [AttendanceEntry] = []
        for e in sorted {
            if let last = out.last, last.kind == e.kind, last.end != nil {
                out[out.count - 1].end = e.end
            } else {
                out.append(e)
            }
        }
        return out
    }

    /// Move the break with `id` so it starts at `toStart`, keeping its length.
    /// The break is lifted out (its old slot becomes work again) and re-spliced
    /// at the new time, splitting whichever work block it lands in — so it can be
    /// dragged any distance, the day stays gap/overlap-free, and total worked
    /// time is unchanged. Non-break or open entries can't be repositioned this
    /// way; the day is just normalised.
    public static func moved(_ entries: [AttendanceEntry], id: String, toStart: Date) -> [AttendanceEntry] {
        guard let moving = entries.first(where: { $0.id == id }),
              moving.kind == .breakTime, let end = moving.end
        else { return normalized(entries, anchor: id) }
        let duration = end.timeIntervalSince(moving.start)
        let base = coalesced(entries.filter { $0.id != id })
        return insertingBreak(into: base, start: toStart, end: toStart.addingTimeInterval(duration),
                              breakID: id, breakReason: moving.reason) ?? base
    }

    /// Which part of a block a timeline drag is moving.
    public enum DragMode { case moveStart, moveEnd, translate }

    /// Edit an existing day by dragging one block on the timeline, ripple-style:
    /// the block and *everything to its right* shift by the same amount, so
    /// later entries move along instead of being compressed. `.moveEnd` resizes
    /// the block's end (its start stays put) and ripples the rest; `.moveStart`
    /// resizes the block from the left (only its start moves — nothing else
    /// shifts, so on the first block it moves the day's clock-in); `.translate`
    /// moves the whole block (keeping its duration) and ripples the rest.
    /// `delta` is the time shift (seconds); results snap to `snap`, keep at
    /// least `minGap`, and never overlap the block before it.
    public static func dragged(_ input: [AttendanceEntry], index: Int, mode: DragMode,
                        by delta: TimeInterval, now: Date,
                        minGap: TimeInterval = 300, snap: TimeInterval = 300) -> [AttendanceEntry] {
        var es = input.sorted { $0.start < $1.start }
        guard es.indices.contains(index) else { return input }

        func snapD(_ d: TimeInterval) -> TimeInterval {
            snap > 0 ? (d / snap).rounded() * snap : d
        }
        func shift(_ i: Int, _ d: TimeInterval) {
            es[i].start = es[i].start.addingTimeInterval(d)
            if let e = es[i].end { es[i].end = e.addingTimeInterval(d) }
        }

        let dayStart = es.first!.start
        var d = snapD(delta)
        let resizeEnd = (mode == .moveEnd) && es[index].end != nil

        if resizeEnd {
            // Grow/shrink the end, keeping at least minGap; ripple the tail.
            let minD = es[index].start.addingTimeInterval(minGap).timeIntervalSince(es[index].end!)
            if d < minD { d = minD }
            es[index].end = es[index].end!.addingTimeInterval(d)
            for k in (index + 1)..<es.count { shift(k, d) }
        } else if mode == .moveStart {
            // Resize from the left: only this block's start moves (an open
            // block is clamped against `now`). Nothing before or after shifts.
            let maxD = (es[index].end ?? now).addingTimeInterval(-minGap)
                .timeIntervalSince(es[index].start)
            if d > maxD { d = maxD }
            if index > 0 {
                let lower = es[index - 1].end ?? es[index - 1].start
                let minD = lower.timeIntervalSince(es[index].start)
                if d < minD { d = minD }
            }
            es[index].start = es[index].start.addingTimeInterval(d)
        } else {
            // Translate this block and everything after it; don't let it slide
            // back over the previous block (or before the day's start).
            let lower = index > 0 ? (es[index - 1].end ?? es[index - 1].start) : dayStart
            let minD = lower.timeIntervalSince(es[index].start)
            if d < minD { d = minD }
            for k in index..<es.count { shift(k, d) }
        }
        return es
    }

    /// Move the boundary between block `index` and the one after it: the left
    /// block's end and the right block's start both become the new time, so
    /// one lengthens exactly as much as the other shortens — nothing else
    /// moves. On the last block it just moves the day's clock-out. Snapped to
    /// `snap`; both blocks keep at least `minGap`. No-op if `index` is open.
    public static func boundaryMoved(_ input: [AttendanceEntry], after index: Int,
                              by delta: TimeInterval, now: Date,
                              minGap: TimeInterval = 300, snap: TimeInterval = 300) -> [AttendanceEntry] {
        var es = input.sorted { $0.start < $1.start }
        guard es.indices.contains(index), let end = es[index].end else { return input }
        var boundary = end.addingTimeInterval(snap > 0 ? (delta / snap).rounded() * snap : delta)
        let earliest = es[index].start.addingTimeInterval(minGap)
        if boundary < earliest { boundary = earliest }
        if es.indices.contains(index + 1) {
            let latest = (es[index + 1].end ?? now).addingTimeInterval(-minGap)
            if boundary > latest { boundary = latest }
        }
        es[index].end = boundary
        if es.indices.contains(index + 1) { es[index + 1].start = boundary }
        return es
    }

    /// When the next scheduled transition (auto-break start or end) is due,
    /// so the engine can arm a precise timer instead of relying on polling.
    public static func nextEvent(entries: [AttendanceEntry],
                          autoBreakStartedAt: Date?,
                          threshold: TimeInterval,
                          breakLength: TimeInterval,
                          now: Date) -> Date? {
        switch state(entries: entries, now: now) {
        case .clockedOut:
            return nil
        case .working(let since):
            return since.addingTimeInterval(threshold)
        case .onBreak:
            guard let autoStart = autoBreakStartedAt else { return nil }
            return autoStart.addingTimeInterval(breakLength)
        }
    }

    // MARK: - iOS widget / background support

    /// Snapshot of the current attendance state for the widgets and Live
    /// Activity. `breakEnds` is engine state (BobState.autoBreakEnds), not
    /// derivable from entries, so it's passed through.
    public static func widgetSnapshot(entries: [AttendanceEntry], signedIn: Bool,
                               target: TimeInterval, breakEnds: Date?,
                               now: Date) -> WidgetSnapshot {
        guard signedIn else {
            return WidgetSnapshot(state: .signedOut, stretchStart: nil, workedBase: 0,
                                  target: target, breakEnds: nil, updatedAt: now)
        }
        let worked = workedToday(entries: entries, now: now)
        switch state(entries: entries, now: now) {
        case .working(let since):
            return WidgetSnapshot(state: .working, stretchStart: since,
                                  workedBase: worked - now.timeIntervalSince(since),
                                  target: target, breakEnds: nil, updatedAt: now)
        case .onBreak:
            return WidgetSnapshot(state: .onBreak, stretchStart: nil, workedBase: worked,
                                  target: target, breakEnds: breakEnds, updatedAt: now)
        case .clockedOut:
            return WidgetSnapshot(state: .clockedOut, stretchStart: nil, workedBase: worked,
                                  target: target, breakEnds: nil, updatedAt: now)
        }
    }

    /// When the next background refresh should run: at the auto-break
    /// boundary when that's sooner than the regular cadence, but never
    /// sooner than a minute from now.
    public static func nextBackgroundRefresh(now: Date, breakDue: Date?,
                                      cadence: TimeInterval = 15 * 60) -> Date {
        let regular = now.addingTimeInterval(cadence)
        guard let due = breakDue, due < regular else { return regular }
        return max(due, now.addingTimeInterval(60))
    }
}
