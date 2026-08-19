import Foundation
import Security

/// OAuth token'inin evi. Token asla UserDefaults'a veya diske duz metin
/// yazilmaz (spec §5). kSecClassGenericPassword; account sabit, service
/// parametre — testler ayri servis kullanir (Swift 6'da Sendable olmayan
/// mutable static yasak, enjeksiyon bu yuzden parametreyle).
enum Keychain {

    static let defaultService = "run.cobanov.ghbar"
    private static let account = "github-token"

    static func save(token: String, service: String = defaultService) {
        // SecItemUpdate + Add dansi yerine sil-ve-ekle: tek kayit, az kod.
        delete(service: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("GHBar: keychain yazilamadi: \(status)")
        }
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
