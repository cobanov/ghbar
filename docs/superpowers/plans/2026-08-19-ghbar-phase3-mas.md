# GHBar Aşama 3 + MAS Varyantı — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `gh` kurulu olmayan makinede de çalışan GHBar v0.2.0: OAuth device flow ile giriş, üç sekmeli ayarlar penceresi, hoş geldin ekranı — ve bunların üstünde sandbox'lı, `.pkg` paketli Mac App Store varyantı (`-DMAS`).

**Architecture:** Kimlik zinciri Keychain → `gh` → yok olur (`#if MAS` gh adımını derleme dışı bırakır). Ayarlar `UserDefaults`'a (sindresorhus/Defaults) taşınır; saf `Settings` struct'ı korunur, her yenilemede `Settings.fromDefaults()` ile kurulur — Query/Filtering hiç değişmez. UI pencereleri SwiftUI ile yazılıp `NSHostingController` içinde açılır (uygulama `NSApplication` tabanlı; SwiftUI `Settings` sahnesi SwiftUI App yaşam döngüsü ister — **spec §8'den bilinçli sapma**, gerekçesi Task 6'da).

**Tech Stack:** Swift 6.3, SPM, AppKit + SwiftUI (`NSHostingController`), `sindresorhus/Defaults` 9.x (tek harici bağımlılık, spec §3 onaylı), Security.framework (Keychain), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-08-18-ghbar-design.md` — §5 (kimlik), §8 (ayarlar), §11 (hoş geldin), §20 (dağıtım varyantları + tek repo korkulukları).

## Global Constraints

- Platform tabanı `.macOS(.v14)`; Defaults 9.0.9 (macOS 11+) uyumlu — doğrulandı.
- Arayüz dili İngilizce.
- Swift 6 katı eşzamanlılık: `Sendable` olmayan tipte mutable static YASAK (NSFont/ISO8601DateFormatter dersleri); Keychain servisi parametreyle geçilir, statik mutable ile değil.
- `#if MAS` yalnızca **TokenProvider** içinde (spec §20 korkuluk #1). UI kodunda görülmesi tasarım hatası.
- `make check` iki varyantı da derler + testleri koşar (korkuluk #2). MAS derlemesi ayrı scratch path kullanır (`.build-mas`) — bayraklı/bayraksız nesneler karışmaz.
- Yayın hatları ayrı: `make publish` (Developer ID) / `make pkg` (Apple Distribution) (korkuluk #3).
- MAS varyantında yasak: `gh` alt süreci, kendi kendini güncelleme. (UpdateChecker henüz yok; eklendiğinde aynı bayrağın arkasına girecek.)
- OAuth Client ID: `Ov23lid00njVuTIgpnyF` (device flow açık, canlı doğrulandı; secret yok ve gerekmez).
- Kapsamlar (spec §5): özel repolar dahil → `repo read:org`; yalnız herkese açık → `public_repo read:org`.
- Hiçbir hata sessizce yutulmaz; oturum yokluğu hata satırı değil, eyleme çağıran "Sign in to GitHub…" satırıdır.

## Dosya yapısı

| Dosya | Sorumluluk |
|---|---|
| `Sources/GHBar/SettingsStore.swift` | Defaults anahtarları + `Settings.fromDefaults()` |
| `Sources/GHBar/Keychain.swift` | Token sakla/oku/sil (Security.framework) |
| `Sources/GHBar/DeviceFlowAuth.swift` | GitHub OAuth device flow (enjekte edilebilir taşıyıcı) |
| `Sources/GHBar/TokenProvider.swift` (değişir) | Zincir: Keychain → `#if !MAS` gh → nil |
| `Sources/GHBar/WelcomeWindow.swift` | Hoş geldin / giriş penceresi (SwiftUI) |
| `Sources/GHBar/SettingsWindow.swift` | Üç sekmeli ayarlar penceresi (SwiftUI) |
| `Sources/GHBar/AppDelegate.swift` (değişir) | Oturumsuz durum, Defaults gözlemi, zamanlayıcı, knownRepos |
| `Sources/GHBar/MenuBuilder.swift` (değişir) | Sign in satırı, Settings… öğesi |
| `Sources/GHBar/SeenStore.swift` (değişir) | `reset()` (çıkışta temizlik, spec §5) |
| `Packaging/GHBar-MAS.entitlements` | Sandbox + network.client + team id |
| `Makefile` (değişir) | `check`, `build-mas`, `bundle-mas`, `sign-mas`, `pkg` |

**Spec'ten belgeli sapmalar:**
1. §8 SwiftUI `Settings { }` sahnesi → `NSWindow` + `NSHostingController`. Uygulama `NSApplication` + AppDelegate tabanlı; `Settings` sahnesi SwiftUI App yaşam döngüsü olmadan çalışmaz. Görünüm birebir aynı (TabView), mimari maliyeti sıfır.
2. §8 Accounts sekmesindeki organizasyon otomatik listesi (`viewer.organizations`) v0.3'e ertelendi — GraphQL sorgusuna alan eklemeyi gerektiriyor; elle hesap ekleme bu sürümde yeterli. Sekmede elle ekleme/çıkarma var.
3. §8 `menuBarStyle` (avatar/ikon seçimi) v0.3'e ertelendi — mevcut ikon+sayı davranışı korunuyor.

---

### Task 1: Defaults bağımlılığı ve `SettingsStore`

**Files:**
- Modify: `Package.swift`
- Create: `Sources/GHBar/SettingsStore.swift`
- Test: `Tests/GHBarTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `Settings` (Aşama 1)
- Produces:
  - `Defaults.Keys` uzantısı: `.accounts [String]`, `.repoList [String]`, `.repoListIsAllowList Bool`, `.showBots Bool`, `.showDrafts Bool`, `.refreshMinutes Int`, `.repoGroupThreshold Int`, `.notificationsEnabled Bool`, `.knownRepos [String: Int]`, `.signedInLogin String?`, `.includePrivateRepos Bool`
  - `Settings.fromDefaults() -> Settings`

- [ ] **Step 1: Package.swift'e bağımlılığı ekle**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GHBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "GHBar",
            dependencies: [.product(name: "Defaults", package: "Defaults")],
            path: "Sources/GHBar"
        ),
        .testTarget(
            name: "GHBarTests",
            dependencies: ["GHBar"],
            path: "Tests/GHBarTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Başarısız testi yaz**

`Tests/GHBarTests/SettingsStoreTests.swift`:

```swift
import Testing
import Defaults
@testable import GHBar

/// Defaults global durumda yasar; her test kendi anahtarlarini sifirlayarak
/// baslar ve biter, yoksa testler birbirine sizar.
@Suite("Settings.fromDefaults", .serialized)
struct SettingsStoreTests {

    private func resetAll() {
        Defaults.reset(.accounts, .repoList, .repoListIsAllowList,
                       .showBots, .showDrafts, .refreshMinutes,
                       .repoGroupThreshold, .notificationsEnabled)
    }

    @Test("varsayilanlar Asama 1 Settings.default ile ayni") func defaults() {
        resetAll()
        let s = Settings.fromDefaults()
        #expect(s == Settings.default)
    }

    @Test("degerler Defaults'tan okunur") func reads() {
        resetAll()
        defer { resetAll() }
        Defaults[.accounts] = ["alice", "acme"]
        Defaults[.repoList] = ["alice/noisy"]
        Defaults[.repoListIsAllowList] = true
        Defaults[.showBots] = true
        Defaults[.showDrafts] = false
        Defaults[.repoGroupThreshold] = 10

        let s = Settings.fromDefaults()
        #expect(s.accounts == ["alice", "acme"])
        #expect(s.repoList == ["alice/noisy"])
        #expect(s.repoListIsAllowList == true)
        #expect(s.showBots == true)
        #expect(s.showDrafts == false)
        #expect(s.repoGroupThreshold == 10)
    }

    @Test("bos hesap listesi @me'ye duser — sorgu hesapsiz kurulamaz") func emptyAccounts() {
        resetAll()
        defer { resetAll() }
        Defaults[.accounts] = []
        #expect(Settings.fromDefaults().accounts == ["@me"])
    }

    @Test("refreshMinutes 1'in altina inmez") func refreshFloor() {
        resetAll()
        defer { resetAll() }
        Defaults[.refreshMinutes] = 0
        #expect(Settings.refreshInterval() >= 60)
    }
}
```

- [ ] **Step 3: Çalıştır, `cannot find` ile başarısız olduğunu gör**

Run: `swift test --filter SettingsStore`

- [ ] **Step 4: Uygulamayı yaz**

`Sources/GHBar/SettingsStore.swift`:

```swift
import Foundation
import Defaults

/// Tum ayar anahtarlari tek yerde (spec §8). Anahtar adlari diskte
/// UserDefaults alan adi olur; degistirmek kullanicinin ayarini sifirlar.
extension Defaults.Keys {
    static let accounts = Key<[String]>("accounts", default: ["@me"])
    static let repoList = Key<[String]>("repoList", default: [])
    static let repoListIsAllowList = Key<Bool>("repoListIsAllowList", default: false)
    static let showBots = Key<Bool>("showBots", default: false)
    static let showDrafts = Key<Bool>("showDrafts", default: true)
    static let refreshMinutes = Key<Int>("refreshMinutes", default: 5)
    static let repoGroupThreshold = Key<Int>("repoGroupThreshold", default: 3)
    static let notificationsEnabled = Key<Bool>("notificationsEnabled", default: true)
    /// Son cekimlerde oge ureten repolar (repo -> oge sayisi). Ayarlar >
    /// Repositories bu listeden dolar; kullanici repo adini elle yazmak
    /// zorunda kalmaz (spec §8: yazim hatasi sessizce hicbir seyi filtrelemez).
    static let knownRepos = Key<[String: Int]>("knownRepos", default: [:])
    static let signedInLogin = Key<String?>("signedInLogin", default: nil)
    static let includePrivateRepos = Key<Bool>("includePrivateRepos", default: true)
}

extension Settings {
    /// Saf Settings struct'i korunur: Query/Filtering test edilebilir kalir,
    /// Defaults yalnizca kenarda okunur.
    static func fromDefaults() -> Settings {
        var settings = Settings()
        let accounts = Defaults[.accounts].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        settings.accounts = accounts.isEmpty ? ["@me"] : accounts
        settings.repoList = Defaults[.repoList]
        settings.repoListIsAllowList = Defaults[.repoListIsAllowList]
        settings.showBots = Defaults[.showBots]
        settings.showDrafts = Defaults[.showDrafts]
        settings.repoGroupThreshold = Defaults[.repoGroupThreshold]
        return settings
    }

    /// Zamanlayici araligi, saniye. Taban 1 dakika: 0 veya negatif deger
    /// kendini bogan bir dongu yaratirdi.
    static func refreshInterval() -> TimeInterval {
        TimeInterval(max(1, Defaults[.refreshMinutes])) * 60
    }
}
```

- [ ] **Step 5: Çalıştır, geçtiğini gör** — `swift test --filter SettingsStore` (4 test) ve tam takım `swift test` (60 + 4).

- [ ] **Step 6: Commit** — "Ayarlar UserDefaults'a tasindi (Defaults); saf Settings korunuyor"

---

### Task 2: Keychain sarmalayıcı

**Files:**
- Create: `Sources/GHBar/Keychain.swift`
- Test: `Tests/GHBarTests/KeychainTests.swift`

**Interfaces:**
- Produces: `enum Keychain { static func save(token:service:) ; static func token(service:) -> String? ; static func delete(service:) }` — `service` varsayılanı `"run.cobanov.ghbar"`; testler ayrı servis adı geçirir (Swift 6'da mutable static yasak, parametre enjeksiyonu bu yüzden).

- [ ] **Step 1: Başarısız testi yaz**

`Tests/GHBarTests/KeychainTests.swift`:

```swift
import Testing
@testable import GHBar

/// Gercek Keychain'e yazar (ayni surec, izin penceresi acmaz). Test servisi
/// ayri: uygulamanin gercek kaydina dokunulmaz.
@Suite("Keychain", .serialized)
struct KeychainTests {
    let service = "run.cobanov.ghbar.tests"

    @Test("yaz-oku-sil turu") func roundTrip() {
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
```

- [ ] **Step 2: Çalıştır, başarısız gör** — `swift test --filter Keychain`

- [ ] **Step 3: Uygulamayı yaz**

`Sources/GHBar/Keychain.swift`:

```swift
import Foundation
import Security

/// OAuth token'inin evi. Token asla UserDefaults'a veya diske duz metin
/// yazilmaz (spec §5). kSecClassGenericPassword; account sabit, service
/// parametre — testler ayri servis kullanir.
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
```

- [ ] **Step 4: Çalıştır, geç** — `swift test --filter Keychain`
- [ ] **Step 5: Commit** — "Keychain sarmalayici: OAuth token'inin evi"

---

### Task 3: OAuth device flow

**Files:**
- Create: `Sources/GHBar/DeviceFlowAuth.swift`
- Test: `Tests/GHBarTests/DeviceFlowAuthTests.swift`

**Interfaces:**
- Produces:
  - `struct DeviceCodeGrant: Equatable, Sendable { deviceCode, userCode, verificationURI: String; interval: Int }`
  - `enum DeviceFlowError: Error, Equatable { denied, expired, network(String), malformed(String) }`
  - `struct DeviceFlowAuth { var clientID; var transport: Transport; var pollFloor: TimeInterval; func requestCode(includePrivate: Bool) async throws -> DeviceCodeGrant; func waitForToken(_:) async throws -> String }`
  - `typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)`

- [ ] **Step 1: Başarısız testi yaz**

`Tests/GHBarTests/DeviceFlowAuthTests.swift`:

```swift
import Testing
import Foundation
@testable import GHBar

/// Senaryolu tasiyici: her cagri sirayla bir cevap doner. Aga hic cikilmaz.
private actor Script {
    private var responses: [(String, Int)]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [(String, Int)]) { self.responses = responses }
    func next(_ request: URLRequest) -> (Data, Int) {
        requests.append(request)
        let (body, status) = responses.removeFirst()
        return (Data(body.utf8), status)
    }
}

private func auth(_ script: Script) -> DeviceFlowAuth {
    var flow = DeviceFlowAuth()
    flow.transport = { request in await script.next(request) }
    flow.pollFloor = 0   // testte bekleme yok
    return flow
}

@Suite("DeviceFlowAuth")
struct DeviceFlowAuthTests {

    @Test("kod istegi cozumlenir ve kapsam dogru gider") func requestCode() async throws {
        let script = Script([
            (#"{"device_code":"dev1","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","interval":0}"#, 200),
        ])
        let grant = try await auth(script).requestCode(includePrivate: true)
        #expect(grant.userCode == "ABCD-1234")
        #expect(grant.deviceCode == "dev1")

        let body = String(decoding: await script.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("client_id=Ov23lid00njVuTIgpnyF"))
        #expect(body.contains("scope=repo"))
    }

    @Test("yalniz herkese acik kapsami public_repo") func publicScope() async throws {
        let script = Script([
            (#"{"device_code":"d","user_code":"U","verification_uri":"v","interval":0}"#, 200),
        ])
        _ = try await auth(script).requestCode(includePrivate: false)
        let body = String(decoding: await script.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("public_repo"))
    }

    @Test("pending'ten sonra token gelir") func pollsUntilToken() async throws {
        let script = Script([
            (#"{"error":"authorization_pending"}"#, 200),
            (#"{"error":"authorization_pending"}"#, 200),
            (#"{"access_token":"gho_zzz","token_type":"bearer"}"#, 200),
        ])
        let grant = DeviceCodeGrant(deviceCode: "d", userCode: "U", verificationURI: "v", interval: 0)
        let token = try await auth(script).waitForToken(grant)
        #expect(token == "gho_zzz")
    }

    @Test("access_denied denied hatasina cevrilir") func denied() async throws {
        let script = Script([(#"{"error":"access_denied"}"#, 200)])
        let grant = DeviceCodeGrant(deviceCode: "d", userCode: "U", verificationURI: "v", interval: 0)
        await #expect(throws: DeviceFlowError.denied) {
            _ = try await auth(script).waitForToken(grant)
        }
    }

    @Test("expired_token expired hatasina cevrilir") func expired() async throws {
        let script = Script([(#"{"error":"expired_token"}"#, 200)])
        let grant = DeviceCodeGrant(deviceCode: "d", userCode: "U", verificationURI: "v", interval: 0)
        await #expect(throws: DeviceFlowError.expired) {
            _ = try await auth(script).waitForToken(grant)
        }
    }

    @Test("HTTP hatasi network hatasi olur") func httpError() async {
        let script = Script([("oops", 500)])
        await #expect(throws: DeviceFlowError.network("HTTP 500")) {
            _ = try await auth(script).requestCode(includePrivate: true)
        }
    }
}
```

- [ ] **Step 2: Çalıştır, başarısız gör** — `swift test --filter DeviceFlow`

- [ ] **Step 3: Uygulamayı yaz**

`Sources/GHBar/DeviceFlowAuth.swift`:

```swift
import Foundation

struct DeviceCodeGrant: Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let interval: Int
}

enum DeviceFlowError: Error, Equatable {
    case denied
    case expired
    case network(String)
    case malformed(String)
}

/// GitHub OAuth device flow (spec §5). Klasik web akisinin istedigi
/// client_secret dagitilan bir uygulamada sir olamaz; device flow secret
/// istemez — tam bu durum icin tasarlandi. Kullanici ekrandaki kodu
/// github.com/login/device'ta onaylar, biz arka planda yoklariz.
struct DeviceFlowAuth: Sendable {

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    static let defaultClientID = "Ov23lid00njVuTIgpnyF"

    var clientID = DeviceFlowAuth.defaultClientID
    var transport: Transport = DeviceFlowAuth.live
    /// Yoklama araliginin tabani; testler 0'a indirir.
    var pollFloor: TimeInterval = 1

    func requestCode(includePrivate: Bool) async throws -> DeviceCodeGrant {
        // repo: ozel repolardaki PR/issue'lar; read:org: organizasyon repolari.
        let scope = includePrivate ? "repo read:org" : "public_repo read:org"
        let data = try await post("https://github.com/login/device/code",
                                  form: ["client_id": clientID, "scope": scope])
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = object["device_code"] as? String,
              let user = object["user_code"] as? String,
              let uri = object["verification_uri"] as? String else {
            throw DeviceFlowError.malformed("device/code")
        }
        return DeviceCodeGrant(
            deviceCode: device,
            userCode: user,
            verificationURI: uri,
            interval: object["interval"] as? Int ?? 5
        )
    }

    /// Kullanici tarayicida onaylayana kadar yoklar. GitHub'in soyledigi
    /// araliga uyar; slow_down gelirse 5 sn ekler (RFC 8628).
    func waitForToken(_ grant: DeviceCodeGrant) async throws -> String {
        var interval = max(pollFloor, TimeInterval(grant.interval))
        while true {
            try await Task.sleep(for: .seconds(interval))
            let data = try await post("https://github.com/login/oauth/access_token", form: [
                "client_id": clientID,
                "device_code": grant.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw DeviceFlowError.malformed("access_token")
            }
            if let token = object["access_token"] as? String { return token }

            switch object["error"] as? String {
            case "authorization_pending": continue
            case "slow_down":             interval += 5
            case "expired_token":         throw DeviceFlowError.expired
            case "access_denied":         throw DeviceFlowError.denied
            case let other:               throw DeviceFlowError.malformed(other ?? "unknown")
            }
        }
    }

    // MARK: - Private

    private func post(_ address: String, form: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: address)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, status) = try await transport(request)
            guard status == 200 else { throw DeviceFlowError.network("HTTP \(status)") }
            return data
        } catch let error as DeviceFlowError {
            throw error
        } catch {
            throw DeviceFlowError.network(error.localizedDescription)
        }
    }

    static let live: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
```

- [ ] **Step 4: Çalıştır, geç** — `swift test --filter DeviceFlow` (6 test)
- [ ] **Step 5: Commit** — "OAuth device flow: enjekte edilebilir tasiyici, RFC 8628 hata haritasi"

---

### Task 4: Kimlik zinciri ve çıkış

**Files:**
- Modify: `Sources/GHBar/TokenProvider.swift`
- Modify: `Sources/GHBar/AppError.swift`
- Modify: `Sources/GHBar/SeenStore.swift`
- Test: `Tests/GHBarTests/TokenProviderTests.swift` (ekleme), `Tests/GHBarTests/SeenStoreTests.swift` (ekleme)

**Interfaces:**
- Produces:
  - `TokenProvider.current() -> String?` — Keychain → `#if !MAS` gh → nil
  - `TokenProvider.ghToken() throws -> String` (eski `token()`, yeniden adlandı; `#if !MAS` içinde)
  - `AppError.notSignedIn` — menuText `"Sign in to GitHub…"`
  - `SeenStore.reset()`

- [ ] **Step 1: Testleri yaz/güncelle**

`TokenProviderTests.swift`'e ekle (mevcut `locate` testleri kalır; `token()` adı `ghToken()` olur):

```swift
@Suite("TokenProvider.current")
struct TokenProviderChainTests {
    let service = "run.cobanov.ghbar.tests.chain"

    @Test("keychain'deki token zincirde birinci") func keychainWins() {
        Keychain.save(token: "gho_fromkeychain", service: service)
        defer { Keychain.delete(service: service) }
        #expect(TokenProvider.current(keychainService: service) == "gho_fromkeychain")
    }

    @Test("keychain bos ve gh yoksa nil") func nilWhenNothing() {
        Keychain.delete(service: service)
        // gh'siz durumu simule etmek icin bos PATH + var olmayan konumlar
        #expect(TokenProvider.current(keychainService: service,
                                      ghToken: { nil }) == nil)
    }

    @Test("keychain bosken gh token'i kullanilir (direct varyant)") func ghFallback() {
        Keychain.delete(service: service)
        let token = TokenProvider.current(keychainService: service,
                                          ghToken: { "gho_fromgh" })
        #if MAS
        #expect(token == nil)          // MAS'ta gh yolu derleme disi
        #else
        #expect(token == "gho_fromgh")
        #endif
    }
}
```

`SeenStoreTests.swift`'e ekle:

```swift
@Suite("SeenStore.reset")
struct SeenStoreResetTests {
    @Test("cikis her seyi sifirlar") func resets() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghbar-reset-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SeenStore(url: url)
        _ = store.markFirstRunDone()
        store.markSeen(["a"], at: Date())
        store.markNotified(["a"])
        try store.save()

        store.reset()
        #expect(store.isFirstRun == true)
        #expect(store.isSeen("a") == false)
        let reloaded = SeenStore(url: url)      // reset diske de yazilmis olmali
        #expect(reloaded.isFirstRun == true)
    }
}
```

- [ ] **Step 2: Çalıştır, başarısız gör**

- [ ] **Step 3: Uygula**

`TokenProvider.swift` — `token()` gövdesi `ghToken()` adını alır (içerik aynı), başına eklenir:

```swift
    /// Kimlik zinciri (spec §5): 1) Keychain — kullanici acikca giris yaptiysa
    /// o kazanir; 2) gh CLI — gelistirici icin sifir surtunme; 3) yok.
    ///
    /// MAS varyantinda gh adimi DERLEME DISI (#if MAS): sandbox alt surec
    /// calistiramaz, kacak bir cagri sessiz bozulma olurdu. Bu, #if MAS'in
    /// koddaki tek kullanim yeridir (spec §20 korkuluk #1).
    static func current(
        keychainService: String = Keychain.defaultService,
        ghToken: () -> String? = { try? TokenProvider.ghToken() }
    ) -> String? {
        if let token = Keychain.token(service: keychainService) { return token }
        #if !MAS
        if let token = ghToken() { return token }
        #endif
        return nil
    }
```

`AppError.swift` — case ekle: `case notSignedIn` → menuText `"Sign in to GitHub…"`.

`SeenStore.swift` — ekle:

```swift
    /// Cikis: durum tamamen sifirlanir ve diske yazilir (spec §5 — Sign Out
    /// seen.json'i temizler). Yeni hesap eski hesabin gorulmusluk kaydini
    /// devralmamali.
    func reset() {
        state = SeenState()
        needsNotificationBackfill = false
        try? save()
    }
```

- [ ] **Step 4: Tüm testler geçer**; mevcut `AppDelegate` hâlâ `TokenProvider.token()` çağırıyorsa `ghToken()`/`current()` uyumu Task 7'de tamamlanır — bu görevde derlemeyi kırmamak için `AppDelegate.refresh()` içindeki `try TokenProvider.token()` satırı şimdilik `guard let token = TokenProvider.current() else { throw AppError.notSignedIn }` yapılır.
- [ ] **Step 5: Commit** — "Kimlik zinciri: Keychain -> gh -> yok; MAS'ta gh derleme disi"

---

### Task 5: Hoş geldin penceresi

**Files:**
- Create: `Sources/GHBar/WelcomeWindow.swift`

**Interfaces:**
- Produces: `@MainActor final class WelcomeController { var onSignedIn: (() -> Void)?; func show(); func close() }`
- Consumes: `DeviceFlowAuth`, `Keychain`, `Defaults[.includePrivateRepos]`

UI otomatik test edilmez (Aşama 1 kararıyla tutarlı); Task 7 sonunda elle doğrulanır.

- [ ] **Step 1: Uygula**

`Sources/GHBar/WelcomeWindow.swift`:

```swift
import SwiftUI
import Defaults

/// Hos geldin / giris penceresi (spec §11). Token yokken menuden acilir.
@MainActor
final class WelcomeController {

    var onSignedIn: (() -> Void)?
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let root = WelcomeView { [weak self] in
            self?.close()
            self?.onSignedIn?()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Welcome to GHBar"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window?.close()
        window = nil
    }
}

private struct WelcomeView: View {

    enum Stage {
        case idle
        case requesting
        case waiting(DeviceCodeGrant)
        case failed(String)
    }

    var onSignedIn: () -> Void
    @State private var stage: Stage = .idle
    @Default(.includePrivateRepos) private var includePrivate

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text("GHBar").font(.title.bold())
            Text("Pull requests and issues from your\nrepositories, in the menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            switch stage {
            case .idle, .failed:
                if case .failed(let message) = stage {
                    Text(message).font(.callout).foregroundStyle(.red)
                }
                Button("Sign in with GitHub") { start() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Toggle("Include private repositories", isOn: $includePrivate)
                    .toggleStyle(.checkbox)
                Text(includePrivate
                     ? "Grants the \"repo\" scope."
                     : "Only public repositories will be shown.")
                    .font(.caption).foregroundStyle(.tertiary)

            case .requesting:
                ProgressView().controlSize(.small)

            case .waiting(let grant):
                Text("Enter this code on GitHub:")
                Text(grant.userCode)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                Button("Open github.com/login/device") {
                    if let url = URL(string: grant.verificationURI) {
                        NSWorkspace.shared.open(url)
                    }
                }
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for approval…").foregroundStyle(.secondary)
                }
            }
        }
        .padding(28)
        .frame(width: 340)
    }

    private func start() {
        stage = .requesting
        let auth = DeviceFlowAuth()
        let includePrivate = includePrivate
        Task { @MainActor in
            do {
                let grant = try await auth.requestCode(includePrivate: includePrivate)
                stage = .waiting(grant)
                // Kod panoya da konur: kullanici tarayicida yalnizca yapistirir.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(grant.userCode, forType: .string)
                if let url = URL(string: grant.verificationURI) {
                    NSWorkspace.shared.open(url)
                }
                let token = try await auth.waitForToken(grant)
                Keychain.save(token: token)
                onSignedIn()
            } catch DeviceFlowError.denied {
                stage = .failed("Access was denied on GitHub.")
            } catch DeviceFlowError.expired {
                stage = .failed("The code expired — try again.")
            } catch {
                stage = .failed("Couldn't reach GitHub. Check your connection.")
            }
        }
    }
}
```

- [ ] **Step 2: Derle** — `swift build` temiz.
- [ ] **Step 3: Commit** — "Hos geldin penceresi: device flow girisi, kod panoya kopyalanir"

---

### Task 6: Ayarlar penceresi

**Files:**
- Create: `Sources/GHBar/SettingsWindow.swift`

**Interfaces:**
- Produces: `@MainActor final class SettingsController { var onSignOut: (() -> Void)?; func show() }`
- Consumes: Task 1 Defaults anahtarları, `LaunchAtLogin`, `Keychain`

Spec §8 sapması (başta belgelendi): `Settings` sahnesi yerine `NSWindow` + `NSHostingController`; görünüm aynı TabView.

- [ ] **Step 1: Uygula**

`Sources/GHBar/SettingsWindow.swift`:

```swift
import SwiftUI
import Defaults

@MainActor
final class SettingsController {

    var onSignOut: (() -> Void)?
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let root = SettingsView(onSignOut: { [weak self] in self?.onSignOut?() })
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "GHBar Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private struct SettingsView: View {
    var onSignOut: () -> Void

    var body: some View {
        TabView {
            AccountsPane(onSignOut: onSignOut)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            RepositoriesPane()
                .tabItem { Label("Repositories", systemImage: "folder") }
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 440, height: 380)
    }
}

// MARK: - Accounts

private struct AccountsPane: View {
    var onSignOut: () -> Void
    @Default(.signedInLogin) private var signedInLogin
    @Default(.accounts) private var accounts
    @State private var newAccount = ""

    var body: some View {
        Form {
            Section {
                if let login = signedInLogin {
                    LabeledContent("Signed in as", value: "@\(login)")
                    Button("Sign Out", role: .destructive) { onSignOut() }
                } else {
                    // Direct varyantta gh token'iyla calisiyor olabiliriz.
                    Text("Using the GitHub CLI token (gh).")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Watched accounts") {
                ForEach(accounts, id: \.self) { account in
                    HStack {
                        Text(account)
                        Spacer()
                        if account != "@me" {
                            Button {
                                accounts.removeAll { $0 == account }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("user or org", text: $newAccount)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newAccount.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("@me is you. Add organizations to watch their repositories too.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let name = newAccount.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, !accounts.contains(name) else { return }
        accounts.append(name)
        newAccount = ""
    }
}

// MARK: - Repositories

private struct RepositoriesPane: View {
    @Default(.repoList) private var repoList
    @Default(.repoListIsAllowList) private var isAllowList
    @Default(.knownRepos) private var knownRepos
    @State private var newRepo = ""

    /// Gorulen repolar + listede olup artik oge uretmeyenler.
    private var rows: [String] {
        Array(Set(knownRepos.keys).union(repoList)).sorted { a, b in
            let (ca, cb) = (knownRepos[a] ?? 0, knownRepos[b] ?? 0)
            return ca != cb ? ca > cb : a < b
        }
    }

    var body: some View {
        Form {
            Section {
                // Maccy'nin ignoreAllAppsExceptListed kalibi (spec §8): TEK
                // liste, anlami tersine ceviren kutucuk. Kapaliyken isaretsiz
                // repolar dislanir; acikken yalniz isaretliler izlenir.
                Toggle("Watch only the listed repositories", isOn: $isAllowList)
                Text(isAllowList
                     ? "Only checked repositories are watched."
                     : "Unchecked repositories are hidden.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Section("Repositories") {
                if rows.isEmpty {
                    Text("Repositories appear here as GHBar sees activity in them.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.self) { repo in
                    Toggle(isOn: watchedBinding(repo)) {
                        HStack {
                            Text(repo)
                            Spacer()
                            if let count = knownRepos[repo] {
                                Text("\(count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                HStack {
                    TextField("owner/name", text: $newRepo)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(!newRepo.contains("/"))
                }
            }
        }
        .formStyle(.grouped)
    }

    /// listede = (allow modunda) izleniyor / (deny modunda) gizli.
    private func watchedBinding(_ repo: String) -> Binding<Bool> {
        Binding(
            get: { isAllowList ? repoList.contains(repo) : !repoList.contains(repo) },
            set: { watched in
                let shouldBeListed = isAllowList ? watched : !watched
                if shouldBeListed {
                    if !repoList.contains(repo) { repoList.append(repo) }
                } else {
                    repoList.removeAll { $0 == repo }
                }
            }
        )
    }

    private func add() {
        let name = newRepo.trimmingCharacters(in: .whitespaces)
        guard name.contains("/"), !repoList.contains(name) else { return }
        repoList.append(name)
        newRepo = ""
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Default(.refreshMinutes) private var refreshMinutes
    @Default(.notificationsEnabled) private var notificationsEnabled
    @Default(.showBots) private var showBots
    @Default(.showDrafts) private var showDrafts
    @Default(.repoGroupThreshold) private var groupThreshold

    var body: some View {
        Form {
            Picker("Refresh every", selection: $refreshMinutes) {
                Text("1 minute").tag(1)
                Text("5 minutes").tag(5)
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
                Text("1 hour").tag(60)
            }
            Toggle("Show notifications", isOn: $notificationsEnabled)
            Toggle("Show bot activity", isOn: $showBots)
            Toggle("Show draft pull requests", isOn: $showDrafts)
            Picker("Group repositories with more than", selection: $groupThreshold) {
                Text("3 items").tag(3)
                Text("5 items").tag(5)
                Text("10 items").tag(10)
                Text("Never group").tag(0)
            }
            if LaunchAtLogin.isAvailable {
                Toggle("Launch at login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { LaunchAtLogin.set($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }
}
```

**Not (`repoGroupThreshold = 0`):** `Filtering.rows` zaten `threshold > 0 değilse` gruplamayı atlıyor (Aşama 1) — "Never group" bedavaya çalışır.

- [ ] **Step 2: Derle** — `swift build` temiz.
- [ ] **Step 3: Commit** — "Ayarlar penceresi: uc sekme, Maccy kalibi repo listesi"

---

### Task 7: AppDelegate entegrasyonu

**Files:**
- Modify: `Sources/GHBar/AppDelegate.swift`
- Modify: `Sources/GHBar/MenuBuilder.swift`

**Interfaces:**
- Consumes: her şey. MenuBuilder.Input'a `isSignedOut: Bool` eklenir; `AppDelegate.openWelcome`, `AppDelegate.openSettings` selector'ları doğar.

- [ ] **Step 1: AppDelegate değişiklikleri**

```swift
// Alanlar:
    private let welcome = WelcomeController()
    private let settingsWindow = SettingsController()
    private var isSignedOut = false
    private var settingsObserver: Task<Void, Never>?

// applicationDidFinishLaunching icine (rebuildMenu'den once):
        welcome.onSignedIn = { [weak self] in self?.refresh() }
        settingsWindow.onSignOut = { [weak self] in self?.signOut() }

        // Ayar degisikligi aninda yansir (spec §8): Defaults yayinlarini dinle,
        // yarim saniye sakinlesince yenile. Zamanlayici da yeni araliga kurulur.
        settingsObserver = Task { [weak self] in
            for await _ in Defaults.updates([.accounts, .repoList, .repoListIsAllowList,
                                             .showBots, .showDrafts, .refreshMinutes,
                                             .repoGroupThreshold], initial: false) {
                guard let self else { return }
                self.scheduleTimer()
                self.refresh()
            }
        }
        scheduleTimer()

// Timer kurulumunu metoda cikar (300 sabitini kaldir):
    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Settings.refreshInterval(),
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

// refresh() basi degisir:
                guard let token = TokenProvider.current() else {
                    isSignedOut = true
                    sections = []
                    errors = []
                    rebuildMenu()
                    return
                }
                isSignedOut = false
                let settings = Settings.fromDefaults()      // sabit self.settings kalkar
                let queries = Query.build(settings)

// snapshot geldikten sonra (viewer atamalarinin yanina):
                Defaults[.signedInLogin] = Keychain.token() != nil ? snapshot.viewer.login : nil
                // Ayarlar > Repositories bu listeden dolar.
                Defaults[.knownRepos] = Dictionary(grouping: all, by: \.repository)
                    .mapValues(\.count)

// rebuildMenu Input'una: isSignedOut: isSignedOut,
//   showOwner: Settings.fromDefaults().accounts.count > 1,
//   maxRowsPerSection: Settings.default.maxRowsPerSection,

// notifier cagrisi kosullanir:
                if Defaults[.notificationsEnabled] { notifier.notify(about: fresh) }

// Yeni eylemler:
    @objc func openWelcome() { welcome.show() }
    @objc func openSettings() { settingsWindow.show() }

    private func signOut() {
        Keychain.delete()
        Defaults[.signedInLogin] = nil
        seenStore.reset()
        sections = []
        viewer = nil
        rateLimit = nil
        refresh()   // direct varyantta gh varsa zincir ona duser; yoksa signedOut
    }
```

Sınıf `settings` sabit alanını kaybeder; `rebuildMenu` içinde `Settings.fromDefaults()` kullanılır.

- [ ] **Step 2: MenuBuilder değişiklikleri**

```swift
// Input'a alan: var isSignedOut: Bool

// build() icinde, profil blogunun yerine gecen kosul:
        if input.isSignedOut {
            let signIn = action("Sign in to GitHub…", #selector(AppDelegate.openWelcome))
            signIn.image = Icons.symbol("person.crop.circle.badge.plus", color: .systemGreen)
            menu.addItem(signIn)
            menu.addItem(.separator())
        } else if let viewer = input.viewer { ... mevcut profil blogu ... }

// Alt blok: Refresh'ten sonra
        menu.addItem(action("Settings…", #selector(AppDelegate.openSettings), key: ","))

// signedOut iken "Nothing waiting" gosterilmez:
        if input.sections.isEmpty && input.errors.isEmpty && !input.isSignedOut { ... }
```

- [ ] **Step 3: Derle + tüm testler** — `swift test` (Task 1-4 testleri dahil hepsi yeşil).

- [ ] **Step 4: Elle doğrulama listesi** (`make install` sonrası)

- [ ] Keychain'de token yokken (`security delete-generic-password -s run.cobanov.ghbar` ile temizlenebilir) ve `gh` varken: uygulama gh ile çalışıyor, Accounts sekmesi "Using the GitHub CLI token (gh)." diyor
- [ ] Ayarlar ⌘, ile açılıyor; Refresh every değişince yenileme tetikleniyor
- [ ] Repositories sekmesinde `team-cobanov` işaretini kaldırınca menüden düşüyor (sorgu `-repo:` ile yeniden kuruluyor)
- [ ] "Watch only the listed repositories" açılınca liste anlamı tersine dönüyor
- [ ] Welcome: menüde oturum yokken "Sign in to GitHub…" satırı; tıklayınca pencere, kod panoda, tarayıcı açılıyor; onaydan sonra menü doluyor, Accounts "Signed in as @cobanov"
- [ ] Sign Out: Keychain temizleniyor; gh kuruluysa gh'a düşüyor (beklenen, spec §5 zincir sırası), gh yoksa "Sign in to GitHub…" durumuna dönüyor
- [ ] Bildirim aç/kapa çalışıyor

- [ ] **Step 5: Commit** — "Asama 3 entegrasyonu: oturumsuz durum, ayar gozlemi, cikis"

---

### Task 8: MAS varyantı ve paketleme

**Files:**
- Create: `Packaging/GHBar-MAS.entitlements`
- Modify: `Makefile`

- [ ] **Step 1: Entitlements**

`Packaging/GHBar-MAS.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.application-identifier</key>
    <string>6U58AKY6F8.run.cobanov.ghbar</string>
    <key>com.apple.developer.team-identifier</key>
    <string>6U58AKY6F8</string>
</dict>
</plist>
```

- [ ] **Step 2: Makefile hedefleri**

```make
# --- MAS varyanti ----------------------------------------------------------
# Ayri scratch path SART: -DMAS'li ve bayraksiz nesneler ayni .build'de
# karisirsa hangi ikilinin hangi bayrakla derlendigi belirsizlesir.
MAS_SCRATCH   := .build-mas
MASFLAGS      := -Xswiftc -DMAS
MAS_DIR       := $(BUILD_DIR)/mas
MAS_BUNDLE    := $(MAS_DIR)/$(APP).app
MAS_CONTENTS  := $(MAS_BUNDLE)/Contents
MAS_SIGN_ID   := Apple Distribution: AHMET MERT COBANOGLU (6U58AKY6F8)
MAS_PKG_ID    := 3rd Party Mac Developer Installer: AHMET MERT COBANOGLU (6U58AKY6F8)
MAS_PROFILE   := Packaging/GHBar_MAS.provisionprofile
PKG           := $(BUILD_DIR)/$(APP)-$(VERSION)-mas.pkg

# Iki varyanti da derle + testler. Yayin oncesi tek dogrulama kapisi
# (spec §20 korkuluk #2): MAS varyantini bozan degisiklik burada patlar.
check: test build build-mas
	@echo "check: iki varyant da derlendi, testler yesil"

build-mas:
	swift build -c release --scratch-path $(MAS_SCRATCH) $(MASFLAGS)

bundle-mas: build-mas $(ICNS)
	@rm -rf $(MAS_BUNDLE)
	@mkdir -p $(MAS_CONTENTS)/MacOS $(MAS_CONTENTS)/Resources
	cp $(MAS_SCRATCH)/release/$(APP) $(MAS_CONTENTS)/MacOS/$(APP)
	cp $(ICNS) $(MAS_CONTENTS)/Resources/$(APP).icns
	@printf '%s' 'APPL????' > $(MAS_CONTENTS)/PkgInfo
	@/usr/libexec/PlistBuddy -c "Clear dict" \
	  -c "Add :CFBundleName string $(APP)" \
	  -c "Add :CFBundleDisplayName string $(APP)" \
	  -c "Add :CFBundleIdentifier string $(BUNDLE_ID)" \
	  -c "Add :CFBundleExecutable string $(APP)" \
	  -c "Add :CFBundleIconFile string $(APP)" \
	  -c "Add :CFBundlePackageType string APPL" \
	  -c "Add :CFBundleShortVersionString string $(VERSION)" \
	  -c "Add :CFBundleVersion string $(VERSION)" \
	  -c "Add :LSMinimumSystemVersion string $(MIN_MACOS)" \
	  -c "Add :LSUIElement bool true" \
	  -c "Add :LSApplicationCategoryType string public.app-category.developer-tools" \
	  -c "Add :ITSAppUsesNonExemptEncryption bool false" \
	  -c "Add :NSHumanReadableCopyright string 'Copyright © 2026 Mert Cobanov.'" \
	  $(MAS_CONTENTS)/Info.plist >/dev/null
	@test -f $(MAS_PROFILE) \
	  && cp $(MAS_PROFILE) $(MAS_CONTENTS)/embedded.provisionprofile \
	  || echo "UYARI: $(MAS_PROFILE) yok — App Store yuklemesi provisioning profile ister"
	@echo "MAS paketi: $(MAS_BUNDLE)"

sign-mas: bundle-mas
	codesign --force --timestamp \
	  --entitlements Packaging/GHBar-MAS.entitlements \
	  --sign "$(MAS_SIGN_ID)" $(MAS_CONTENTS)/MacOS/$(APP)
	codesign --force --timestamp \
	  --entitlements Packaging/GHBar-MAS.entitlements \
	  --sign "$(MAS_SIGN_ID)" $(MAS_BUNDLE)
	codesign --verify --deep --strict $(MAS_BUNDLE)

# App Store'a gidecek .pkg. Yukleme Transporter.app ile yapilir (kullanici).
pkg: sign-mas
	@rm -f $(PKG)
	productbuild --component $(MAS_BUNDLE) /Applications \
	  --sign "$(MAS_PKG_ID)" $(PKG)
	@echo "App Store paketi: $(PKG) — Transporter.app ile yukle"
```

`.PHONY` satırına `check build-mas bundle-mas sign-mas pkg` eklenir. Ana `bundle` hedefine de `LSApplicationCategoryType` + `ITSAppUsesNonExemptEncryption` satırları eklenir (iki varyantta aynı).

- [ ] **Step 3: Doğrula** — `make check` (testler + iki derleme). `make bundle-mas` çalışır; `sign-mas`/`pkg` sertifika/profil gelene dek elle çağrılmaz.
- [ ] **Step 4: Commit** — "MAS varyanti: sandbox entitlements, -DMAS derleme, pkg hatti, make check"

---

### Task 9: v0.2.0 — sürüm, notlar, README/site

**Files:**
- Modify: `Makefile` (`VERSION := 0.2.0`)
- Create: `docs/release-notes/v0.2.0.md`
- Modify: `README.md`, `site/index.html`

- [ ] **Step 1: Sürüm + notlar**

`docs/release-notes/v0.2.0.md`:

```markdown
Sign in without the GitHub CLI, and a real settings window.

### New

- **Built-in GitHub sign-in.** GHBar can now authenticate on its own with
  GitHub's device flow — no `gh` required. If you do have `gh` signed in,
  GHBar still picks its token up automatically, exactly as before.
- **Settings window** (⌘,) with three tabs:
  - **Accounts** — watch additional users or organizations, sign out.
  - **Repositories** — every repository GHBar has seen, with a checkbox to
    hide the noisy ones; or flip one switch to watch only the repos you list.
  - **General** — refresh interval, notifications, bots, drafts, grouping,
    launch at login.
- Changes apply instantly — no restart.

### Install / upgrade

```bash
brew upgrade --cask ghbar        # or: brew install --cask cobanov/tap/ghbar
```
```

- [ ] **Step 2: README + site metni** — "Requirements"tan `gh` **zorunluluğu** kalkar: `gh` "otomatik algılanan kolaylık", OAuth ana yol olur. Sitedeki Requirements kartı ve "No account to create" kartı aynı dille güncellenir; `wrangler pages deploy` ile yayınlanır.
- [ ] **Step 3: `make check` + elle son tur** — Task 7 listesi bir kez daha.
- [ ] **Step 4: Commit + push.** Direct yayın (`make notarize && make publish`) kullanıcı komutu; MAS yükleme Task 10'a.

---

### Task 10: App Store teslimi (kod dışı görevler)

Sıralı kontrol listesi — hangisini kimin yapacağı işaretli:

- [ ] **[KULLANICI — bugün başlat]** App Store Connect → Business: **Paid Applications** sözleşmesi + banka + vergi. Apple onayı günler sürebilir; ücretli yayının uzun direği bu. (Banka/vergi bilgilerine Claude dokunamaz.)
- [ ] **[BERABER — tarayıcı]** developer.apple.com → Certificates: **Mac Installer Distribution** sertifikası (CSR üretimi + indirme + `ghbar-signing` keychain'ine aktarım — Developer ID'dekiyle aynı akış).
- [ ] **[BERABER — tarayıcı]** developer.apple.com → Identifiers: `run.cobanov.ghbar` App ID kaydı (yoksa); Profiles: **Mac App Store** provisioning profile → `Packaging/GHBar_MAS.provisionprofile` olarak kaydet (gitignore'a eklenir — profil kişisel).
- [ ] **[BERABER — tarayıcı]** App Store Connect → yeni macOS uygulaması: ad **GHBar**, bundle id `run.cobanov.ghbar`, SKU `ghbar`, fiyat **$4.99**, kategori Developer Tools.
- [ ] **[CLAUDE]** Ekran görüntüleri: 2880×1800 / 2560×1600 — açık menü + ayarlar penceresi kompozisyonları (`screencapture` + `statusItem performClick`).
- [ ] **[CLAUDE]** Metadata taslakları: açıklama, anahtar kelimeler, destek URL'i (`https://ghbar.cobanov.dev`), gizlilik politikası sayfası (site'ye `/privacy` — "no data collected").
- [ ] **[BERABER]** Gizlilik beyanı: **Data Not Collected** (telemetri yok — doğru beyan).
- [ ] **[KULLANICI]** `make pkg` çıktısını **Transporter.app** ile yükle (Mac App Store'dan ücretsiz iner; Apple ID girişi kullanıcının).
- [ ] **[BERABER]** İncelemeye gönder. Reviewer notu: "Sign in with any GitHub account via device flow; the app is a read-only client for the signed-in user's own repositories."

---

## Spec kapsam kontrolü

| Spec | Görev |
|---|---|
| §5 kimlik zinciri, kapsamlar, Keychain, çıkış, 401 | Task 2, 3, 4, 7 |
| §8 Defaults, üç sekme, Maccy kalıbı, anında uygulama | Task 1, 6, 7 |
| §8 org otomatik listesi / menuBarStyle | **v0.3'e ertelendi** (belgeli sapma 2, 3) |
| §11 hoş geldin, kapsam seçimi, gh varsa görünmez | Task 5, 7 |
| §20 varyantlar, korkuluklar, pkg | Task 8 |
| §14 kanal ayrımı | Task 8 (`pkg` ayrı hedef), Task 9 |
