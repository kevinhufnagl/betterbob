import Foundation
import Security

/// Tiny wrapper over the macOS login Keychain for the few secrets BetterBob
/// stores locally (the HiBob password + TOTP secret used to autofill sign-in).
/// Nothing here ever leaves the machine except into the HiBob login form.
enum Keychain {
    private static let service = "k3n.betterbob.credentials"

    enum Key: String {
        case password = "hibobPassword"
        case totpSecret = "hibobTOTPSecret"
    }

    static func set(_ value: String?, for key: Key) {
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

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func has(_ key: Key) -> Bool { get(key) != nil }
}
