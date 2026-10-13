import Foundation
import Security

/// OAuth token'inin evi. Token asla UserDefaults'a veya diske duz metin
/// yazilmaz (spec §5). kSecClassGenericPassword; account sabit, service
/// parametre — testler ayri servis kullanir (Swift 6'da Sendable olmayan
/// mutable static yasak, enjeksiyon bu yuzden parametreyle).
enum Keychain {

    static let defaultService = "run.cobanov.ghbar"
    private static let account = "github-token"

    /// Replaces the stored token. Updates in place, so a failed write leaves the old one.
    @discardableResult
    static func save(token: String, service: String = defaultService) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(token.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            NSLog("GHBar: keychain yazilamadi: \(status)")
        }
        return status == errSecSuccess
    }

    static func token(service: String = defaultService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(service: String = defaultService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
