import Foundation
import Security

/// Tiny wrapper over the macOS login Keychain for the few secrets BetterBob
/// stores locally (the HiBob password + TOTP secret used to autofill sign-in).
/// Nothing here ever leaves the machine except into the HiBob login form.
public enum Keychain {
    private static let service = "k3n.betterbob.credentials"

    public enum Key: String {
        case password = "hibobPassword"
        // The authenticator secret for fully automatic sign-in (Advanced
        // settings, off by default): with it stored, codes are generated
        // locally and re-login needs no human. Same account name earlier
        // versions used, so an old grant carries over.
        case totpSecret = "hibobTOTPSecret"
    }

    public static func set(_ value: String?, for key: Key) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        refreshCreatorIfNeeded(key, value)
        return value
    }

    /// Re-create an item once per app version, right after a successful
    /// (user-authorized) read. The keychain grants silent access based on the
    /// binary that *created* an item — items made by an older build keep
    /// re-prompting after every update. Re-creating makes the current build
    /// the creator, whose cert-based signing requirement the next update
    /// satisfies too, so the grant finally sticks.
    private static func refreshCreatorIfNeeded(_ key: Key, _ value: String) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let marker = "keychainCreator-\(key.rawValue)"
        guard UserDefaults.standard.string(forKey: marker) != version else { return }
        UserDefaults.standard.set(version, forKey: marker)
        set(value, for: key)
    }

    public static func has(_ key: Key) -> Bool { get(key) != nil }


    /// Delete every item under the service in one call — the uninstaller's
    /// half of the cleanup. Silent, because this build created the items.
    static func wipeAll() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
    }
}
