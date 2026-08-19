import Testing
@testable import GHBar

/// Gercek Keychain'e yazar. GUI disi oturumlarda (CI, uzak ajan) macOS
/// keychain yazmayi reddeder (errSecInteractionNotAllowed, -25308); orada
/// test atlanir. GUI'li gelistirici makinesinde tam calisir — kosul yazilim
/// hatasini degil ortam iznini olcuyor.
private let keychainAvailable: Bool = {
    let probe = "run.cobanov.ghbar.tests.probe"
    Keychain.save(token: "probe", service: probe)
    let ok = Keychain.token(service: probe) == "probe"
    Keychain.delete(service: probe)
    return ok
}()

@Suite("Keychain", .serialized)
struct KeychainTests {
    let service = "run.cobanov.ghbar.tests"

    @Test("yaz-oku-sil turu", .enabled(if: keychainAvailable))
    func roundTrip() {
        Keychain.delete(service: service)
        #expect(Keychain.token(service: service) == nil)

        Keychain.save(token: "tok_abc123", service: service)
        #expect(Keychain.token(service: service) == "tok_abc123")

        Keychain.save(token: "tok_replaced", service: service)   // ustune yazma
        #expect(Keychain.token(service: service) == "tok_replaced")

        Keychain.delete(service: service)
        #expect(Keychain.token(service: service) == nil)
    }
}
