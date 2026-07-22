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
