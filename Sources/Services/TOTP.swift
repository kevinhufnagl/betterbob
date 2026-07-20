import Foundation
import CryptoKit

/// RFC 6238 time-based one-time passwords (SHA-1, the near-universal default —
/// what Okta/Google Authenticator issue). Used to autofill the login OTP from a
/// secret the user stores in the Keychain.
enum TOTP {
    /// The current code for a base32 `secret`, or nil if the secret isn't valid
    /// base32. `digits`/`period` default to the standard 6 / 30s.
    /// Accept either a bare base32 secret or a full `otpauth://…?secret=…` URL
    /// (what many authenticator apps / QR exports hand out) and return just the
    /// base32 secret. Non-URLs are returned trimmed, unchanged.
    static func base32Secret(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("otpauth://"),
              let comps = URLComponents(string: trimmed),
              let secret = comps.queryItems?.first(where: { $0.name.lowercased() == "secret" })?.value
        else { return trimmed }
        return secret
    }

    static func code(secretBase32 secret: String, at date: Date = Date(),
                     period: TimeInterval = 30, digits: Int = 6) -> String? {
        guard let key = base32Decode(base32Secret(from: secret)), !key.isEmpty else { return nil }
        var counter = UInt64(date.timeIntervalSince1970 / period).bigEndian
        let counterData = Data(bytes: &counter, count: 8)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData,
                                                         using: SymmetricKey(data: key))
        let hash = Data(mac)
        let offset = Int(hash[hash.count - 1] & 0x0f)
        let binary = (UInt32(hash[offset] & 0x7f) << 24)
            | (UInt32(hash[offset + 1]) << 16)
            | (UInt32(hash[offset + 2]) << 8)
            | UInt32(hash[offset + 3])
        let mod = UInt32(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)d", binary % mod)
    }

    /// Decode RFC 4648 base32 (case-insensitive; spaces and `=` padding ignored),
    /// as authenticator secrets are shown. Returns nil on any invalid character.
    static func base32Decode(_ string: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var lookup = [Character: Int]()
        for (i, c) in alphabet.enumerated() { lookup[c] = i }
        let clean = string.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "=", with: "")
        guard !clean.isEmpty else { return nil }
        var bits = 0, value = 0
        var out = Data()
        for c in clean {
            guard let v = lookup[c] else { return nil }
            value = (value << 5) | v
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return out
    }
}
