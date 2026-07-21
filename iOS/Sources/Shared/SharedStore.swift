import BetterBobShared
import Foundation
import WidgetKit

/// Cross-process handoff: the app writes a WidgetSnapshot after every
/// reconcile; the widget extension renders whatever is stored.
enum SharedStore {
    static let suite = "group.k3n.betterbob"
    private static let key = "widgetSnapshot"

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: suite)?.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: suite)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
