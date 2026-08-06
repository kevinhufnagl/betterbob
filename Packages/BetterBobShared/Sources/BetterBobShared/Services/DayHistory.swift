import Foundation

/// A small rolling store of `DayFact`s in `UserDefaults` — the app's only
/// durable record of past days' shapes (HiBob drops last cycle's sheet once
/// the month rolls over). One JSON blob under a single key, self-capped to the
/// most recent `maxDays`, so it never grows unbounded and needs no cleanup.
public enum DayHistory {
    static let key = "dayHistoryV1"
    static let maxDays = 120

    public static func load(_ defaults: UserDefaults = .standard) -> [DayFact] {
        guard let data = defaults.data(forKey: key),
              let facts = try? JSONDecoder().decode([DayFact].self, from: data) else { return [] }
        return facts
    }

    /// Upsert `incoming` facts by date (fresh data refines a day already on
    /// record), keep only the most recent `maxDays`, and persist. Stored in
    /// chronological order.
    public static func merge(_ incoming: [DayFact], into defaults: UserDefaults = .standard) {
        guard !incoming.isEmpty else { return }
        var byDate = Dictionary(load(defaults).map { ($0.date, $0) }, uniquingKeysWith: { _, new in new })
        for f in incoming { byDate[f.date] = f }
        let kept = byDate.values.sorted { $0.date > $1.date }.prefix(maxDays)
        let out = kept.sorted { $0.date < $1.date }
        if let data = try? JSONEncoder().encode(out) { defaults.set(data, forKey: key) }
    }
}

/// The same durable trick for per-day STATED targets (date → hours): the
/// summary stops stating targets after today and HiBob drops the sheet at
/// rollover, so the week-left fill's weekday precedent (the 6.5h Friday) must
/// survive across cycles — a cycle's first Friday has no precedent inside it.
public enum TargetHistory {
    static let key = "targetHistoryV1"
    static let maxDays = 180

    public static func load(_ defaults: UserDefaults = .standard) -> [String: Double] {
        guard let data = defaults.data(forKey: key),
              let map = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return map
    }

    /// Upsert stated targets by date, keep only the most recent `maxDays`,
    /// and persist.
    public static func merge(_ incoming: [String: Double], into defaults: UserDefaults = .standard) {
        guard !incoming.isEmpty else { return }
        var map = load(defaults)
        for (date, hours) in incoming { map[date] = hours }
        if map.count > maxDays {
            for date in map.keys.sorted(by: >).dropFirst(maxDays) { map[date] = nil }
        }
        if let data = try? JSONEncoder().encode(map) { defaults.set(data, forKey: key) }
    }

    /// True once every working weekday (Mon–Fri) has at least one recorded
    /// stated target — the seed fetch of last month's sheet can stop then.
    public static func hasWeekdayPrecedent(_ defaults: UserDefaults = .standard,
                                           calendar: Calendar = Calendar(identifier: .iso8601)) -> Bool {
        var seen = Set<Int>()
        for dateKey in load(defaults).keys {
            guard let date = DayFmt.date(dateKey) else { continue }
            seen.insert(calendar.component(.weekday, from: date))
        }
        return (2...6).allSatisfy(seen.contains)
    }
}
