import Foundation

/// The watch's own cross-process handoff, mirroring the phone's SharedStore:
/// the watch app writes the snapshot it received over WCSession into the
/// watch-side app group; the complications render whatever is stored. (A
/// watch shares no app group with its phone — this group is the same ID,
/// but a separate container on the wrist.)
enum WatchStore {
    static let suite = "group.k3n.betterbob.app"
    private static let key = "widgetSnapshot"

    static func save(_ data: Data) {
        UserDefaults(suiteName: suite)?.set(data, forKey: key)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: suite)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
