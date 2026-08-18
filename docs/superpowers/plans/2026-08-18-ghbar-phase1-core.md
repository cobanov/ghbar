# GHBar Aşama 1 (Çekirdek) — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `swift run` ile çalışan, menü çubuğunda repolara gelen gerçek PR ve issue'ları gösteren, tıklayınca GitHub'da açan bir uygulama.

**Architecture:** `gh` CLI'den alınan token ile tek bir GraphQL isteği atılır; dönen veri saf fonksiyonlardan (ayrıştırma → filtreleme → gruplama) geçirilip `NSMenu`'ye çevrilir. Ağ, disk ve UI birbirinden ayrı; iş mantığının tamamı yan etkisiz fonksiyonlarda olduğu için test edilebilir.

**Tech Stack:** Swift 6.3, Swift Package Manager, AppKit (`NSStatusItem`/`NSMenu`), Swift Testing (`import Testing`, Swift 6 ile geliyor), `Foundation.URLSession`. **Harici bağımlılık yok.**

**Spec:** `docs/superpowers/specs/2026-08-18-ghbar-design.md`

## Global Constraints

Bu kısıtlar her görev için geçerlidir; tek tek tekrar edilmeyecek.

- **Platform:** `.macOS(.v14)`. `NSMenuItem.sectionHeader(title:)` macOS 14 ile geldi, alt sınır bu.
- **swift-tools-version:** `6.0`. Toolchain 6.3.2.
- **Harici bağımlılık yok.** `sindresorhus/Defaults` Aşama 3'e ait, şimdi eklenmeyecek.
- **Arayüz dili İngilizce.** Menüdeki her metin İngilizce: `Pull Requests`, `Issues`, `Review Requested`, `Mark All as Seen`, `Refresh`, `Quit GHBar`, `Open GitHub`, `Rate Limit`, `N more…`.
- **Kişiye özel varsayılan yok.** Hiçbir yerde `cobanov` veya `team-cobanov` yazmayacak. Varsayılan hesap `@me`.
- **`gh` arama sırası:** `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, sonra `PATH`. Sadece `PATH`'e güvenmek yasak.
- **`first: 100`** — GitHub aramanın üst sınırı. Sayfalama yok.
- **Sorgu uzunluk tavanı 4000 karakter.** Aşılırsa filtreler kırpılır ve bayrak kaldırılır.
- **Hiçbir hata sessizce yutulmaz.** Her hata menüde görünür bir satıra dönüşür.
- **Yaş biçimi İngilizce ve kısa:** `45m`, `3h`, `2d`, `3mo`.
- Aşama 1'de **ayarlar penceresi, OAuth, bildirim, paketleme yok.** Ayarlar kod içinde `Settings.default`.

## Dosya yapısı

| Dosya | Sorumluluk |
|---|---|
| `Package.swift` | Paket tanımı, hedefler |
| `Sources/GHBar/Models.swift` | `Item`, `Viewer`, `RateLimit`, `Snapshot`, `Section`, `Row`, `SectionKind` |
| `Sources/GHBar/Settings.swift` | Aşama 1'in sabit ayar yapısı |
| `Sources/GHBar/Formatting.swift` | Yaş metni, başlık kırpma, binlik ayraç |
| `Sources/GHBar/Query.swift` | Ayarlardan arama metinleri + GraphQL belgesi |
| `Sources/GHBar/ResponseParser.swift` | GraphQL JSON → `Snapshot` |
| `Sources/GHBar/Filtering.swift` | Bot elemesi, taslak, çakışma, sıralama, gruplama |
| `Sources/GHBar/SeenStore.swift` | Görülme durumu, disk |
| `Sources/GHBar/TokenProvider.swift` | `gh` bulma ve token alma |
| `Sources/GHBar/GitHubClient.swift` | HTTP isteği |
| `Sources/GHBar/AppError.swift` | Kullanıcıya gösterilecek hata tipleri |
| `Sources/GHBar/RowText.swift` | Satır metni üretimi (saf) |
| `Sources/GHBar/MenuBuilder.swift` | `NSMenu` kurulumu |
| `Sources/GHBar/AppDelegate.swift` | Durum çubuğu, yenileme döngüsü |
| `Sources/GHBar/main.swift` | Giriş noktası |

Testler `Tests/GHBarTests/` altında, kaynak dosyayla birebir eşleşen adlarla.

**Neden `ResponseParser` `GitHubClient`'tan ayrı:** ayrıştırma saf bir fonksiyon, ağ ise değil. Ayırınca ayrıştırmayı sabit JSON dosyalarıyla test edebiliyoruz; birleşik olsaydı her test ağ gerektirirdi.

---

### Task 1: Paket iskeleti ve `Formatting`

İlk görev hem paketi ayağa kaldırıyor hem de hiçbir şeye bağlı olmayan saf fonksiyonları yazıyor. Böylece test döngüsünün çalıştığı en baştan doğrulanmış oluyor.

**Files:**
- Create: `Package.swift`
- Create: `Sources/GHBar/Formatting.swift`
- Create: `.gitignore`
- Test: `Tests/GHBarTests/FormattingTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `enum Formatting`
  - `static func age(of date: Date, now: Date) -> String`
  - `static func truncate(_ text: String, limit: Int = 48) -> String`
  - `static func grouped(_ value: Int) -> String`

- [ ] **Step 1: `.gitignore` ve `Package.swift` yaz**

`.gitignore`:

```
.build/
.swiftpm/
*.xcodeproj
.DS_Store
```

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GHBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GHBar", path: "Sources/GHBar"),
        .testTarget(name: "GHBarTests", dependencies: ["GHBar"], path: "Tests/GHBarTests"),
    ]
)
```

- [ ] **Step 2: Başarısız testi yaz**

`Tests/GHBarTests/FormattingTests.swift`:

```swift
import Testing
import Foundation
@testable import GHBar

private func date(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    return f.date(from: iso)!
}

@Suite("Formatting.age")
struct FormattingAgeTests {
    let now = date("2026-08-18T12:00:00Z")

    @Test("dakikalar") func minutes() {
        #expect(Formatting.age(of: now.addingTimeInterval(-45 * 60), now: now) == "45m")
    }

    @Test("59 dakika hala dakika") func fiftyNineMinutes() {
        #expect(Formatting.age(of: now.addingTimeInterval(-59 * 60), now: now) == "59m")
    }

    @Test("60 dakika saate doner") func sixtyMinutes() {
        #expect(Formatting.age(of: now.addingTimeInterval(-60 * 60), now: now) == "1h")
    }

    @Test("saatler") func hours() {
        #expect(Formatting.age(of: now.addingTimeInterval(-3 * 3600), now: now) == "3h")
    }

    @Test("gunler") func days() {
        #expect(Formatting.age(of: now.addingTimeInterval(-2 * 86400), now: now) == "2d")
    }

    @Test("aylar") func months() {
        #expect(Formatting.age(of: now.addingTimeInterval(-90 * 86400), now: now) == "3mo")
    }

    @Test("gelecekteki tarih 0m verir, negatif metin uretmez") func future() {
        #expect(Formatting.age(of: now.addingTimeInterval(120), now: now) == "0m")
    }
}

@Suite("Formatting.truncate")
struct FormattingTruncateTests {
    @Test("sinirin altindaki metin degismez") func short() {
        #expect(Formatting.truncate("Short title", limit: 48) == "Short title")
    }

    @Test("uzun metin kelime ortasindan kesilmez") func wordBoundary() {
        let input = "Let the last row scroll clear of the floating tab bar"
        let out = Formatting.truncate(input, limit: 24)
        #expect(out == "Let the last row scroll…")
        #expect(!out.contains("scrol…"))
    }

    @Test("bosluksuz uzun kelime yine de kesilir") func noSpaces() {
        let out = Formatting.truncate(String(repeating: "a", count: 60), limit: 10)
        #expect(out.count == 11)          // 10 karakter + elipsis
        #expect(out.hasSuffix("…"))
    }
}

@Suite("Formatting.grouped")
struct FormattingGroupedTests {
    @Test("binlik ayrac") func thousands() {
        #expect(Formatting.grouped(4911) == "4,911")
        #expect(Formatting.grouped(5000) == "5,000")
    }

    @Test("dort haneden kucuk sayi ayracsiz") func small() {
        #expect(Formatting.grouped(42) == "42")
    }
}
```

- [ ] **Step 3: Testi çalıştır, başarısız olduğunu gör**

Run: `swift test --filter FormattingTests`
Expected: FAIL — `cannot find 'Formatting' in scope`

- [ ] **Step 4: En küçük uygulamayı yaz**

`Sources/GHBar/Formatting.swift`:

```swift
import Foundation

enum Formatting {
    /// Kisa, Ingilizce yas metni: 45m, 3h, 2d, 3mo
    static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<3600:
            return "\(Int(seconds / 60))m"
        case ..<86_400:
            return "\(Int(seconds / 3600))h"
        case ..<(86_400 * 30):
            return "\(Int(seconds / 86_400))d"
        default:
            return "\(Int(seconds / (86_400 * 30)))mo"
        }
    }

    /// Basligi kisaltir. Kelime ortasindan kesmemek icin son bosluga kadar geri gider;
    /// hic bosluk yoksa sert keser.
    static func truncate(_ text: String, limit: Int = 48) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        if let lastSpace = cut.lastIndex(of: " ") {
            let trimmed = cut[..<lastSpace]
            return "\(trimmed)…"
        }
        return "\(cut)…"
    }

    /// 4911 -> "4,911"
    static func grouped(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}
```

- [ ] **Step 5: Testleri çalıştır, geçtiğini gör**

Run: `swift test --filter FormattingTests`
Expected: PASS — 12 test

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources/GHBar/Formatting.swift Tests/GHBarTests/FormattingTests.swift
git commit -m "Paket iskeleti ve Formatting yardimcilari

Yas metni, baslik kirpma ve binlik ayrac. Baslik kirpma kelime
ortasindan kesmiyor; bosluksuz uzun kelimede sert kesiyor."
```

---

### Task 2: Veri modelleri ve GraphQL cevabının ayrıştırılması

**Files:**
- Create: `Sources/GHBar/Models.swift`
- Create: `Sources/GHBar/ResponseParser.swift`
- Create: `Tests/GHBarTests/Fixtures/response.json`
- Test: `Tests/GHBarTests/ResponseParserTests.swift`
- Modify: `Package.swift` (test hedefine kaynak dosya kopyalama)

**Interfaces:**
- Consumes: —
- Produces:
  - `enum ItemKind: String { case pullRequest, issue }`
  - `struct Item` — alanlar: `kind`, `repository`, `number`, `title`, `url`, `createdAt`, `isDraft`, `authorLogin`, `authorIsBot`; `id` hesaplanan (`url`)
  - `struct Viewer { login: String; name: String?; avatarURL: String }`
  - `struct RateLimit { limit: Int; remaining: Int; resetAt: Date }`
  - `enum SectionKind: String, CaseIterable { case pullRequests, issues, reviewRequested }` + `var title: String`
  - `struct Snapshot { viewer, prs, issues, review, rateLimit, truncated: Set<SectionKind> }`
  - `enum ResponseParser { static func parse(_ data: Data) throws -> Snapshot }`
  - `enum ParseError: Error, Equatable { case malformed(String); case graphQL(String) }`

- [ ] **Step 1: `Package.swift`'e test kaynağı ekle**

Test hedefinin `Fixtures/` klasörünü görebilmesi için:

```swift
.testTarget(
    name: "GHBarTests",
    dependencies: ["GHBar"],
    path: "Tests/GHBarTests",
    resources: [.copy("Fixtures")]
),
```

- [ ] **Step 2: Sabit cevap dosyasını yaz**

`Tests/GHBarTests/Fixtures/response.json` — kasten uç durumlar içeriyor: bir bot, yazarı `null` bir öğe, bir taslak, ve `prs` ile `review` içinde **aynı** PR.

```json
{
  "data": {
    "viewer": {
      "login": "alice",
      "name": "Alice Smith",
      "avatarUrl": "https://avatars.githubusercontent.com/u/1?v=4",
      "organizations": { "nodes": [{ "login": "acme" }] }
    },
    "prs": {
      "issueCount": 4,
      "nodes": [
        { "number": 55, "title": "Fix the floating tab bar", "url": "https://github.com/alice/webapp/pull/55",
          "createdAt": "2026-08-17T17:49:40Z", "isDraft": false,
          "author": { "login": "bob", "__typename": "User" },
          "repository": { "nameWithOwner": "alice/webapp" } },
        { "number": 56, "title": "Bump lodash from 4.17.20 to 4.17.21", "url": "https://github.com/alice/webapp/pull/56",
          "createdAt": "2026-08-17T10:00:00Z", "isDraft": false,
          "author": { "login": "dependabot", "__typename": "Bot" },
          "repository": { "nameWithOwner": "alice/webapp" } },
        { "number": 57, "title": "Work in progress", "url": "https://github.com/alice/webapp/pull/57",
          "createdAt": "2026-08-16T10:00:00Z", "isDraft": true,
          "author": { "login": "carol", "__typename": "User" },
          "repository": { "nameWithOwner": "alice/webapp" } },
        { "number": 204, "title": "Refactor auth middleware", "url": "https://github.com/acme/backend/pull/204",
          "createdAt": "2026-08-18T07:00:00Z", "isDraft": false,
          "author": { "login": "dave", "__typename": "User" },
          "repository": { "nameWithOwner": "acme/backend" } }
      ]
    },
    "issues": {
      "issueCount": 2,
      "nodes": [
        { "number": 12, "title": "Crash on cold start", "url": "https://github.com/alice/webapp/issues/12",
          "createdAt": "2026-08-16T09:00:00Z",
          "author": { "login": "erin", "__typename": "User" },
          "repository": { "nameWithOwner": "alice/webapp" } },
        { "number": 13, "title": "Yazari silinmis kullanici", "url": "https://github.com/alice/webapp/issues/13",
          "createdAt": "2026-08-15T09:00:00Z",
          "author": null,
          "repository": { "nameWithOwner": "alice/webapp" } }
      ]
    },
    "review": {
      "issueCount": 1,
      "nodes": [
        { "number": 204, "title": "Refactor auth middleware", "url": "https://github.com/acme/backend/pull/204",
          "createdAt": "2026-08-18T07:00:00Z", "isDraft": false,
          "author": { "login": "dave", "__typename": "User" },
          "repository": { "nameWithOwner": "acme/backend" } }
      ]
    },
    "rateLimit": {
      "limit": 5000,
      "remaining": 4911,
      "resetAt": "2026-08-18T13:00:00Z",
      "cost": 1
    }
  }
}
```

- [ ] **Step 3: Başarısız testi yaz**

`Tests/GHBarTests/ResponseParserTests.swift`:

```swift
import Testing
import Foundation
@testable import GHBar

private func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
    return try Data(contentsOf: url)
}

@Suite("ResponseParser")
struct ResponseParserTests {

    @Test("gercek bicimli cevabi cozer") func parsesFixture() throws {
        let snap = try ResponseParser.parse(fixture("response"))

        #expect(snap.viewer.login == "alice")
        #expect(snap.viewer.name == "Alice Smith")
        #expect(snap.prs.count == 4)
        #expect(snap.issues.count == 1)   // yazari null olan atildi
        #expect(snap.review.count == 1)
        #expect(snap.rateLimit.remaining == 4911)
    }

    @Test("bot bayragi __typename'den okunur") func botFlag() throws {
        let snap = try ResponseParser.parse(fixture("response"))
        let bot = snap.prs.first { $0.number == 56 }
        #expect(bot?.authorIsBot == true)
        let human = snap.prs.first { $0.number == 55 }
        #expect(human?.authorIsBot == false)
    }

    @Test("login sonu [bot] ise de bot sayilir") func botSuffix() throws {
        let json = """
        {"data":{"viewer":{"login":"a","name":null,"avatarUrl":"x"},
          "prs":{"issueCount":1,"nodes":[{"number":1,"title":"t","url":"u",
            "createdAt":"2026-08-18T07:00:00Z","isDraft":false,
            "author":{"login":"renovate[bot]","__typename":"User"},
            "repository":{"nameWithOwner":"a/b"}}]},
          "issues":{"issueCount":0,"nodes":[]},
          "review":{"issueCount":0,"nodes":[]},
          "rateLimit":{"limit":5000,"remaining":1,"resetAt":"2026-08-18T13:00:00Z"}}}
        """.data(using: .utf8)!
        let snap = try ResponseParser.parse(json)
        #expect(snap.prs.first?.authorIsBot == true)
    }

    @Test("issueCount 100'e dayaninca kirpilma bayragi kalkar") func truncation() throws {
        let json = """
        {"data":{"viewer":{"login":"a","name":null,"avatarUrl":"x"},
          "prs":{"issueCount":140,"nodes":[]},
          "issues":{"issueCount":3,"nodes":[]},
          "review":{"issueCount":0,"nodes":[]},
          "rateLimit":{"limit":5000,"remaining":1,"resetAt":"2026-08-18T13:00:00Z"}}}
        """.data(using: .utf8)!
        let snap = try ResponseParser.parse(json)
        #expect(snap.truncated.contains(.pullRequests))
        #expect(!snap.truncated.contains(.issues))
    }

    @Test("GraphQL hatasi tasinir") func graphQLError() throws {
        let json = #"{"errors":[{"message":"Bad credentials"}]}"#.data(using: .utf8)!
        #expect(throws: ParseError.graphQL("Bad credentials")) {
            try ResponseParser.parse(json)
        }
    }

    @Test("bozuk JSON malformed verir, cokmez") func malformed() throws {
        #expect(throws: (any Error).self) {
            try ResponseParser.parse(Data("not json".utf8))
        }
    }
}
```

- [ ] **Step 4: Testi çalıştır, başarısız olduğunu gör**

Run: `swift test --filter ResponseParser`
Expected: FAIL — `cannot find 'ResponseParser' in scope`

- [ ] **Step 5: Modelleri yaz**

`Sources/GHBar/Models.swift`:

```swift
import Foundation

enum ItemKind: String, Sendable, Hashable {
    case pullRequest
    case issue
}

struct Item: Sendable, Hashable, Identifiable {
    let kind: ItemKind
    let repository: String      // "owner/name"
    let number: Int
    let title: String
    let url: String
    let createdAt: Date
    let isDraft: Bool
    let authorLogin: String
    let authorIsBot: Bool

    var id: String { url }

    /// "owner/name" -> "name"
    var repositoryName: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}

struct Viewer: Sendable, Hashable {
    let login: String
    let name: String?
    let avatarURL: String

    var displayName: String { name ?? login }
    var profileURL: String { "https://github.com/\(login)" }
}

struct RateLimit: Sendable, Hashable {
    let limit: Int
    let remaining: Int
    let resetAt: Date

    var fraction: Double {
        limit > 0 ? Double(remaining) / Double(limit) : 1
    }
}

enum SectionKind: String, Sendable, Hashable, CaseIterable {
    case pullRequests
    case issues
    case reviewRequested

    var title: String {
        switch self {
        case .pullRequests:   "Pull Requests"
        case .issues:         "Issues"
        case .reviewRequested: "Review Requested"
        }
    }
}

/// Menude bir satir: ya tek bir oge, ya ayni repodan toplanmis bir grup.
enum Row: Sendable, Hashable {
    case item(Item)
    case group(repository: String, items: [Item])

    var items: [Item] {
        switch self {
        case .item(let i):        [i]
        case .group(_, let list): list
        }
    }
}

struct Section: Sendable, Hashable {
    let kind: SectionKind
    let rows: [Row]
    let truncated: Bool

    var items: [Item] { rows.flatMap(\.items) }
    var isEmpty: Bool { rows.isEmpty }
}

struct Snapshot: Sendable {
    let viewer: Viewer
    let prs: [Item]
    let issues: [Item]
    let review: [Item]
    let rateLimit: RateLimit
    let truncated: Set<SectionKind>
}
```

- [ ] **Step 6: Ayrıştırıcıyı yaz**

`Sources/GHBar/ResponseParser.swift`:

```swift
import Foundation

enum ParseError: Error, Equatable {
    case malformed(String)
    case graphQL(String)
}

enum ResponseParser {

    /// GitHub aramanin dondurdugu en fazla sonuc. Bu sayiya dayanan bir arama
    /// kirpilmis demektir; kullaniciya soylemek gerekiyor.
    static let searchLimit = 100

    static func parse(_ data: Data) throws -> Snapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.malformed("root is not an object")
        }

        if let errors = root["errors"] as? [[String: Any]],
           let first = errors.first,
           let message = first["message"] as? String {
            throw ParseError.graphQL(message)
        }

        guard let payload = root["data"] as? [String: Any] else {
            throw ParseError.malformed("missing data")
        }

        guard let viewerObject = payload["viewer"] as? [String: Any],
              let login = viewerObject["login"] as? String,
              let avatar = viewerObject["avatarUrl"] as? String else {
            throw ParseError.malformed("missing viewer")
        }
        let viewer = Viewer(
            login: login,
            name: viewerObject["name"] as? String,
            avatarURL: avatar
        )

        var truncated: Set<SectionKind> = []

        func search(_ key: String, kind: ItemKind, section: SectionKind) throws -> [Item] {
            guard let object = payload[key] as? [String: Any] else {
                throw ParseError.malformed("missing \(key)")
            }
            if let count = object["issueCount"] as? Int, count >= searchLimit {
                truncated.insert(section)
            }
            let nodes = object["nodes"] as? [[String: Any]] ?? []
            return nodes.compactMap { item(from: $0, kind: kind) }
        }

        let prs    = try search("prs",    kind: .pullRequest, section: .pullRequests)
        let issues = try search("issues", kind: .issue,       section: .issues)
        let review = try search("review", kind: .pullRequest, section: .reviewRequested)

        guard let limitObject = payload["rateLimit"] as? [String: Any],
              let limit = limitObject["limit"] as? Int,
              let remaining = limitObject["remaining"] as? Int,
              let resetString = limitObject["resetAt"] as? String,
              let resetAt = iso.date(from: resetString) else {
            throw ParseError.malformed("missing rateLimit")
        }

        return Snapshot(
            viewer: viewer,
            prs: prs,
            issues: issues,
            review: review,
            rateLimit: RateLimit(limit: limit, remaining: remaining, resetAt: resetAt),
            truncated: truncated
        )
    }

    // MARK: - Private

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Yazari olmayan oge (silinmis hesap) nil doner ve listeden dusurulur:
    /// kime ait oldugu belli olmayan bir satir gostermenin anlami yok.
    private static func item(from node: [String: Any], kind: ItemKind) -> Item? {
        guard let number = node["number"] as? Int,
              let title = node["title"] as? String,
              let url = node["url"] as? String,
              let createdString = node["createdAt"] as? String,
              let createdAt = iso.date(from: createdString),
              let repositoryObject = node["repository"] as? [String: Any],
              let repository = repositoryObject["nameWithOwner"] as? String,
              let authorObject = node["author"] as? [String: Any],
              let authorLogin = authorObject["login"] as? String
        else { return nil }

        // GitHub botlari iki bicimde gonderiyor: __typename "Bot",
        // ya da login sonunda "[bot]". Ikisini de yakalamak gerekiyor.
        let isBot = (authorObject["__typename"] as? String) == "Bot"
            || authorLogin.hasSuffix("[bot]")

        return Item(
            kind: kind,
            repository: repository,
            number: number,
            title: title,
            url: url,
            createdAt: createdAt,
            isDraft: node["isDraft"] as? Bool ?? false,
            authorLogin: authorLogin,
            authorIsBot: isBot
        )
    }
}
```

- [ ] **Step 7: Testleri çalıştır, geçtiğini gör**

Run: `swift test --filter ResponseParser`
Expected: PASS — 6 test

- [ ] **Step 8: Commit**

```bash
git add Sources/GHBar/Models.swift Sources/GHBar/ResponseParser.swift Tests/GHBarTests Package.swift
git commit -m "Veri modelleri ve GraphQL cevap ayristirici

Ayristirma agdan ayri tutuldu ki sabit JSON dosyalariyla test
edilebilsin. Bot tespiti iki kosullu: __typename Bot veya login
sonu [bot] — GitHub ikisini de kullaniyor. Yazari null olan oge
(silinmis hesap) listeden dusuruluyor. issueCount 100'e dayanan
arama kirpilmis olarak isaretleniyor."
```

---

### Task 3: `Settings` ve sorgu üretimi

**Files:**
- Create: `Sources/GHBar/Settings.swift`
- Create: `Sources/GHBar/Query.swift`
- Test: `Tests/GHBarTests/QueryTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `struct Settings` — `accounts`, `repoList`, `repoListIsAllowList`, `showBots`, `showDrafts`, `repoGroupThreshold`, `maxRowsPerSection`; `static let `default``
  - `struct Queries: Equatable { prs, issues, review: String; filtersDropped: Bool; allowListEmpty: Bool }`
  - `enum Query { static let document: String; static let maxLength = 4000; static func build(_ settings: Settings) -> Queries }`

- [ ] **Step 1: Başarısız testi yaz**

`Tests/GHBarTests/QueryTests.swift`:

```swift
import Testing
@testable import GHBar

@Suite("Query.build")
struct QueryTests {

    @Test("varsayilan ayar @me kullanir, login gerektirmez") func defaults() {
        let q = Query.build(.default)
        #expect(q.prs    == "is:pr is:open user:@me -author:@me")
        #expect(q.issues == "is:issue is:open user:@me -author:@me")
        #expect(q.review == "is:pr is:open review-requested:@me")
        #expect(q.filtersDropped == false)
        #expect(q.allowListEmpty == false)
    }

    @Test("birden fazla hesap birden fazla user: parcasi verir") func multipleAccounts() {
        var s = Settings.default
        s.accounts = ["alice", "acme"]
        let q = Query.build(s)
        #expect(q.prs == "is:pr is:open user:alice user:acme -author:@me")
    }

    @Test("kara liste -repo: parcalari ekler") func denyList() {
        var s = Settings.default
        s.accounts = ["alice"]
        s.repoList = ["alice/noisy"]
        s.repoListIsAllowList = false
        let q = Query.build(s)
        #expect(q.prs == "is:pr is:open user:alice -author:@me -repo:alice/noisy")
        #expect(q.review == "is:pr is:open review-requested:@me -repo:alice/noisy")
    }

    @Test("egik cizgisiz repo girdisi ilk hesapla birlestirilir") func bareRepoName() {
        var s = Settings.default
        s.accounts = ["alice"]
        s.repoList = ["noisy"]
        let q = Query.build(s)
        #expect(q.prs.contains("-repo:alice/noisy"))
    }

    @Test("beyaz liste repo: kullanir ve user: parcalarini birakir") func allowList() {
        var s = Settings.default
        s.accounts = ["alice"]
        s.repoList = ["alice/one", "alice/two"]
        s.repoListIsAllowList = true
        let q = Query.build(s)
        #expect(q.prs == "is:pr is:open repo:alice/one repo:alice/two -author:@me")
        #expect(!q.prs.contains("user:"))
    }

    @Test("beyaz liste bos ise bayrak kalkar") func allowListEmpty() {
        var s = Settings.default
        s.repoList = []
        s.repoListIsAllowList = true
        let q = Query.build(s)
        #expect(q.allowListEmpty == true)
    }

    @Test("4000 karakteri asan filtre listesi kirpilir ve bayrak kalkar") func lengthCap() {
        var s = Settings.default
        s.accounts = ["alice"]
        s.repoList = (0..<300).map { "alice/repository-with-a-long-name-\($0)" }
        let q = Query.build(s)
        #expect(q.prs.count <= Query.maxLength)
        #expect(q.filtersDropped == true)
    }
}
```

- [ ] **Step 2: Testi çalıştır, başarısız olduğunu gör**

Run: `swift test --filter QueryTests`
Expected: FAIL — `cannot find 'Query' in scope`

- [ ] **Step 3: `Settings` yaz**

`Sources/GHBar/Settings.swift`:

```swift
import Foundation

/// Asama 1'de ayarlar sabit. Asama 3'te bu yapi UserDefaults'a baglanacak;
/// alan adlari o zaman degismeyecek sekilde secildi.
struct Settings: Sendable, Equatable {
    var accounts: [String] = ["@me"]
    var repoList: [String] = []
    var repoListIsAllowList: Bool = false
    var showBots: Bool = false
    var showDrafts: Bool = true
    var repoGroupThreshold: Int = 3
    var maxRowsPerSection: Int = 5

    static let `default` = Settings()
}
```

- [ ] **Step 4: `Query` yaz**

`Sources/GHBar/Query.swift`:

```swift
import Foundation

struct Queries: Sendable, Equatable {
    let prs: String
    let issues: String
    let review: String
    /// Uzunluk tavani yuzunden bazi filtreler dusuruldu.
    let filtersDropped: Bool
    /// Beyaz liste acik ama bos — hicbir sey gosterilmemeli.
    let allowListEmpty: Bool
}

enum Query {

    /// GitHub arama sorgusu icin guvenli ust sinir. Olculdu: GraphQL aramasi
    /// 3085 karakterde bile sorunsuz calisiyor ve en sondaki niteleyici
    /// uygulaniyor; 4000 rahat bir tavan.
    static let maxLength = 4000

    static func build(_ settings: Settings) -> Queries {
        let repos = normalizedRepositories(settings)
        let allowListEmpty = settings.repoListIsAllowList && repos.isEmpty

        // Beyaz liste modunda repo listesi kapsami zaten belirliyor,
        // user: parcalari gereksiz ve yaniltici olur.
        let scope: [String] = settings.repoListIsAllowList
            ? repos.map { "repo:\($0)" }
            : settings.accounts.map { "user:\($0)" }

        let exclusions: [String] = settings.repoListIsAllowList
            ? []
            : repos.map { "-repo:\($0)" }

        var dropped = false

        func assemble(_ prefix: [String], scoped: Bool) -> String {
            var parts = prefix
            if scoped { parts += scope }
            parts.append("-author:@me")
            let (kept, wasDropped) = fit(parts, exclusions: exclusions)
            dropped = dropped || wasDropped
            return kept.joined(separator: " ")
        }

        // review sorgusu hesaplardan bagimsiz: sana review istenen her PR,
        // hangi repoda olursa olsun. Repo filtresi yine de uygulanir.
        var reviewParts = ["is:pr", "is:open", "review-requested:@me"]
        let (reviewKept, reviewDropped) = fit(reviewParts, exclusions: exclusions)
        reviewParts = reviewKept
        dropped = dropped || reviewDropped

        return Queries(
            prs:    assemble(["is:pr", "is:open"], scoped: true),
            issues: assemble(["is:issue", "is:open"], scoped: true),
            review: reviewParts.joined(separator: " "),
            filtersDropped: dropped,
            allowListEmpty: allowListEmpty
        )
    }

    /// Zorunlu parcalari korur, dislama parcalarini tavana sigdigi kadar ekler.
    /// Kirpma sessizce yapilmaz — geri donen bayrak menude uyariya donusur.
    private static func fit(_ required: [String], exclusions: [String]) -> ([String], Bool) {
        var parts = required
        var length = parts.joined(separator: " ").count
        var dropped = false

        for exclusion in exclusions {
            let addition = exclusion.count + 1
            if length + addition > maxLength {
                dropped = true
                break
            }
            parts.append(exclusion)
            length += addition
        }
        return (parts, dropped)
    }

    /// "noisy" -> "alice/noisy"; "alice/noisy" oldugu gibi kalir.
    private static func normalizedRepositories(_ settings: Settings) -> [String] {
        let owner = settings.accounts.first ?? "@me"
        return settings.repoList.compactMap { entry in
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return trimmed.contains("/") ? trimmed : "\(owner)/\(trimmed)"
        }
    }

    /// Tek istekte uc arama + profil + kota. Olculdu: toplam maliyeti 1 puan.
    static let document = """
    query($prs: String!, $issues: String!, $review: String!, $first: Int!) {
      viewer { login name avatarUrl }
      prs: search(query: $prs, type: ISSUE, first: $first) {
        issueCount
        nodes { ... on PullRequest {
          number title url createdAt isDraft
          author { login __typename }
          repository { nameWithOwner }
        } }
      }
      issues: search(query: $issues, type: ISSUE, first: $first) {
        issueCount
        nodes { ... on Issue {
          number title url createdAt
          author { login __typename }
          repository { nameWithOwner }
        } }
      }
      review: search(query: $review, type: ISSUE, first: $first) {
        issueCount
        nodes { ... on PullRequest {
          number title url createdAt isDraft
          author { login __typename }
          repository { nameWithOwner }
        } }
      }
      rateLimit { limit remaining resetAt cost }
    }
    """
}
```

**Not:** GraphQL belgesi ayrı bir `.graphql` dosyası yerine Swift metni olarak gömüldü. Spec §3 dosya olarak listelemişti; sapmanın sebebi Aşama 2'de `.app` paketi elle kurulacak ve `Bundle.module` kaynak paketinin de kopyalanmasını gerektirecek — gömülü metin bu arıza yolunu tamamen ortadan kaldırıyor.

- [ ] **Step 5: Testleri çalıştır, geçtiğini gör**

Run: `swift test --filter QueryTests`
Expected: PASS — 7 test

- [ ] **Step 6: Commit**

```bash
git add Sources/GHBar/Settings.swift Sources/GHBar/Query.swift Tests/GHBarTests/QueryTests.swift
git commit -m "Ayar yapisi ve arama sorgusu uretimi

Sorgu @me kisayolunu kullaniyor; boylece kullanicinin login'ini
bilmeye gerek kalmiyor ve iki asamali acilis ortadan kalkiyor.
Repo filtresi sorgunun icine gomuluyor cunku arama 100 sonuc
donduruyor: sonradan elemek gercek ogeleri pencerenin disina
itebilir. Uzunluk tavani asilirsa kirpma sessiz degil, bayrakli."
```

---

### Task 4: Filtreleme, çakışma ve gruplama

**Files:**
- Create: `Sources/GHBar/Filtering.swift`
- Test: `Tests/GHBarTests/FilteringTests.swift`

**Interfaces:**
- Consumes: `Item`, `Section`, `Row`, `SectionKind`, `Snapshot`, `Settings` (Task 2, 3)
- Produces: `enum Filtering { static func sections(from snapshot: Snapshot, settings: Settings) -> [Section] }`

- [ ] **Step 1: Başarısız testi yaz**

`Tests/GHBarTests/FilteringTests.swift`:

```swift
import Testing
import Foundation
@testable import GHBar

private func makeItem(
    _ number: Int,
    repo: String = "alice/webapp",
    kind: ItemKind = .pullRequest,
    bot: Bool = false,
    draft: Bool = false,
    minutesAgo: Int = 0
) -> Item {
    Item(
        kind: kind,
        repository: repo,
        number: number,
        title: "Title \(number)",
        url: "https://github.com/\(repo)/pull/\(number)",
        createdAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(minutesAgo * 60)),
        isDraft: draft,
        authorLogin: bot ? "dependabot" : "bob",
        authorIsBot: bot
    )
}

private func snapshot(prs: [Item] = [], issues: [Item] = [], review: [Item] = []) -> Snapshot {
    Snapshot(
        viewer: Viewer(login: "alice", name: nil, avatarURL: "x"),
        prs: prs, issues: issues, review: review,
        rateLimit: RateLimit(limit: 5000, remaining: 5000, resetAt: Date()),
        truncated: []
    )
}

@Suite("Filtering")
struct FilteringTests {

    @Test("botlar varsayilan olarak elenir") func removesBots() {
        let snap = snapshot(prs: [makeItem(1), makeItem(2, bot: true)])
        let sections = Filtering.sections(from: snap, settings: .default)
        let numbers = sections.first { $0.kind == .pullRequests }?.items.map(\.number)
        #expect(numbers == [1])
    }

    @Test("showBots acikken botlar kalir") func keepsBots() {
        var s = Settings.default
        s.showBots = true
        let snap = snapshot(prs: [makeItem(1), makeItem(2, bot: true)])
        let sections = Filtering.sections(from: snap, settings: s)
        #expect(sections.first { $0.kind == .pullRequests }?.items.count == 2)
    }

    @Test("showDrafts kapaliyken taslaklar elenir") func hidesDrafts() {
        var s = Settings.default
        s.showDrafts = false
        let snap = snapshot(prs: [makeItem(1), makeItem(2, draft: true)])
        let sections = Filtering.sections(from: snap, settings: s)
        #expect(sections.first { $0.kind == .pullRequests }?.items.map(\.number) == [1])
    }

    @Test("ayni PR hem prs hem review'daysa yalniz Review Requested'da cikar") func dedup() {
        let shared = makeItem(204, repo: "acme/backend")
        let snap = snapshot(prs: [makeItem(1), shared], review: [shared])
        let sections = Filtering.sections(from: snap, settings: .default)

        let prNumbers = sections.first { $0.kind == .pullRequests }?.items.map(\.number)
        let reviewNumbers = sections.first { $0.kind == .reviewRequested }?.items.map(\.number)
        #expect(prNumbers == [1])
        #expect(reviewNumbers == [204])
    }

    @Test("en yeni ustte siralanir") func sorting() {
        let snap = snapshot(prs: [
            makeItem(1, minutesAgo: 500),
            makeItem(2, minutesAgo: 10),
            makeItem(3, minutesAgo: 100),
        ])
        let sections = Filtering.sections(from: snap, settings: .default)
        #expect(sections.first { $0.kind == .pullRequests }?.items.map(\.number) == [2, 3, 1])
    }

    @Test("esigin ustundeki repo tek satira toplanir") func grouping() {
        var s = Settings.default
        s.repoGroupThreshold = 3
        let noisy = (1...5).map { makeItem($0, repo: "alice/noisy", kind: .issue) }
        let quiet = [makeItem(90, repo: "alice/webapp", kind: .issue)]
        let snap = snapshot(issues: noisy + quiet)

        let section = Filtering.sections(from: snap, settings: s).first { $0.kind == .issues }!
        let groups = section.rows.compactMap { row -> String? in
            if case .group(let repo, _) = row { return repo }
            return nil
        }
        let singles = section.rows.compactMap { row -> Int? in
            if case .item(let i) = row { return i.number }
            return nil
        }
        #expect(groups == ["alice/noisy"])
        #expect(singles == [90])
    }

    @Test("esigin altindaki repo toplanmaz") func noGroupingBelowThreshold() {
        var s = Settings.default
        s.repoGroupThreshold = 3
        let snap = snapshot(issues: (1...3).map { makeItem($0, repo: "alice/webapp", kind: .issue) })
        let section = Filtering.sections(from: snap, settings: s).first { $0.kind == .issues }!
        #expect(section.rows.count == 3)
        #expect(section.rows.allSatisfy { if case .item = $0 { true } else { false } })
    }

    @Test("bos bolum listeye hic girmez") func dropsEmptySections() {
        let snap = snapshot(prs: [makeItem(1)])
        let kinds = Filtering.sections(from: snap, settings: .default).map(\.kind)
        #expect(kinds == [.pullRequests])
    }

    @Test("kirpilma bayragi bolume tasinir") func carriesTruncation() {
        var snap = snapshot(prs: [makeItem(1)])
        snap = Snapshot(viewer: snap.viewer, prs: snap.prs, issues: [], review: [],
                        rateLimit: snap.rateLimit, truncated: [.pullRequests])
        let section = Filtering.sections(from: snap, settings: .default).first!
        #expect(section.truncated == true)
    }
}
```

- [ ] **Step 2: Testi çalıştır, başarısız olduğunu gör**

Run: `swift test --filter FilteringTests`
Expected: FAIL — `cannot find 'Filtering' in scope`

- [ ] **Step 3: Uygulamayı yaz**

`Sources/GHBar/Filtering.swift`:

```swift
import Foundation

enum Filtering {

    static func sections(from snapshot: Snapshot, settings: Settings) -> [Section] {
        // Review istenmis olmak daha guclu bir sinyal: ayni PR iki aramada da
        // ciktiysa yalniz Review Requested'da gosterilir.
        let review = clean(snapshot.review, settings: settings)
        let reviewURLs = Set(review.map(\.url))

        let prs = clean(snapshot.prs, settings: settings)
            .filter { !reviewURLs.contains($0.url) }
        let issues = clean(snapshot.issues, settings: settings)

        let candidates: [(SectionKind, [Item])] = [
            (.pullRequests, prs),
            (.issues, issues),
            (.reviewRequested, review),
        ]

        return candidates.compactMap { kind, items in
            guard !items.isEmpty else { return nil }   // bos bolum hic gosterilmez
            return Section(
                kind: kind,
                rows: rows(for: items, settings: settings),
                truncated: snapshot.truncated.contains(kind)
            )
        }
    }

    // MARK: - Private

    private static func clean(_ items: [Item], settings: Settings) -> [Item] {
        items
            .filter { settings.showBots || !$0.authorIsBot }
            .filter { settings.showDrafts || !$0.isDraft }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Tek bir repo bir bolumu bogdugunda kullanicinin ilk icgudusu onu tamamen
    /// dislamak oluyor — ama o zaman oradan gelen gercek katkiyi da kaciriyor.
    /// Gruplama gurultuyu tek satira indiriyor, hicbir seyi gizlemeden.
    private static func rows(for items: [Item], settings: Settings) -> [Row] {
        let threshold = settings.repoGroupThreshold
        guard threshold > 0 else { return items.map(Row.item) }

        var counts: [String: Int] = [:]
        for item in items { counts[item.repository, default: 0] += 1 }

        var result: [Row] = []
        var emittedGroups: Set<String> = []

        for item in items {
            let repository = item.repository
            if counts[repository, default: 0] > threshold {
                guard !emittedGroups.contains(repository) else { continue }
                emittedGroups.insert(repository)
                result.append(.group(
                    repository: repository,
                    items: items.filter { $0.repository == repository }
                ))
            } else {
                result.append(.item(item))
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Testleri çalıştır, geçtiğini gör**

Run: `swift test --filter FilteringTests`
Expected: PASS — 9 test

- [ ] **Step 5: Commit**

```bash
git add Sources/GHBar/Filtering.swift Tests/GHBarTests/FilteringTests.swift
git commit -m "Filtreleme, cakisma cozumu ve repo gruplama

Ayni PR hem repo aramasinda hem review aramasinda ciktiginda
yalniz Review Requested'da gosteriliyor. Bir repodan esigin
ustunde oge varsa tek satira toplaniyor: amac gurultuyu
azaltirken hicbir seyi gizlememek. Bos bolum hic olusturulmuyor."
```

---

### Task 5: Görülme durumu

**Files:**
- Create: `Sources/GHBar/SeenStore.swift`
- Test: `Tests/GHBarTests/SeenStoreTests.swift`

**Interfaces:**
- Consumes: `Item` (Task 2)
- Produces:
  - `final class SeenStore` — `init(url: URL)`, `isSeen(_:) -> Bool`, `markSeen(_ urls: [String], at: Date)`, `newItems(among: [Item]) -> [Item]`, `bootstrap(with: [Item], at: Date) -> Bool`, `prune(keeping: Set<String>)`, `save() throws`, `var isFirstRun: Bool`

- [ ] **Step 1: Başarısız testi yaz**

`Tests/GHBarTests/SeenStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import GHBar

private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ghbar-test-\(UUID().uuidString).json")
}

private func makeItem(_ n: Int) -> Item {
    Item(kind: .pullRequest, repository: "alice/webapp", number: n,
         title: "t", url: "https://example.com/\(n)",
         createdAt: Date(), isDraft: false,
         authorLogin: "bob", authorIsBot: false)
}

@Suite("SeenStore")
struct SeenStoreTests {

    @Test("isaretle ve oku") func markAndRead() throws {
        let store = SeenStore(url: temporaryURL())
        #expect(store.isSeen("https://example.com/1") == false)
        store.markSeen(["https://example.com/1"], at: Date())
        #expect(store.isSeen("https://example.com/1") == true)
    }

    @Test("diske yazip geri okur") func roundTrip() throws {
        let url = temporaryURL()
        let store = SeenStore(url: url)
        store.markSeen(["https://example.com/1"], at: Date())
        try store.save()

        let reloaded = SeenStore(url: url)
        #expect(reloaded.isSeen("https://example.com/1") == true)
        try? FileManager.default.removeItem(at: url)
    }

    @Test("ilk calistirmada her sey gorulmus sayilir, yeni oge yok") func bootstrap() {
        let store = SeenStore(url: temporaryURL())
        #expect(store.isFirstRun == true)
        let didBootstrap = store.bootstrap(with: [makeItem(1), makeItem(2)], at: Date())
        #expect(didBootstrap == true)
        #expect(store.newItems(among: [makeItem(1), makeItem(2)]).isEmpty)
        #expect(store.isFirstRun == false)
    }

    @Test("ikinci cagride bootstrap bir sey yapmaz") func bootstrapOnce() {
        let store = SeenStore(url: temporaryURL())
        _ = store.bootstrap(with: [makeItem(1)], at: Date())
        #expect(store.bootstrap(with: [makeItem(2)], at: Date()) == false)
        #expect(store.newItems(among: [makeItem(2)]).map(\.number) == [2])
    }

    @Test("gorulmemis ogeler dogru donuyor") func newItems() {
        let store = SeenStore(url: temporaryURL())
        _ = store.bootstrap(with: [makeItem(1)], at: Date())
        let fresh = store.newItems(among: [makeItem(1), makeItem(2), makeItem(3)])
        #expect(fresh.map(\.number) == [2, 3])
    }

    @Test("listede olmayan kayitlar temizlenir") func prune() {
        let store = SeenStore(url: temporaryURL())
        store.markSeen(["a", "b", "c"], at: Date())
        store.prune(keeping: ["a", "c"])
        #expect(store.isSeen("a") == true)
        #expect(store.isSeen("b") == false)
        #expect(store.isSeen("c") == true)
    }

    @Test("bozuk dosya cokmez, sifirlanir") func corruptFile() throws {
        let url = temporaryURL()
        try Data("this is not json".utf8).write(to: url)
        let store = SeenStore(url: url)
        #expect(store.isFirstRun == true)
        #expect(store.isSeen("anything") == false)
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 2: Testi çalıştır, başarısız olduğunu gör**

Run: `swift test --filter SeenStore`
Expected: FAIL — `cannot find 'SeenStore' in scope`

- [ ] **Step 3: Uygulamayı yaz**

`Sources/GHBar/SeenStore.swift`:

```swift
import Foundation

struct SeenState: Codable, Equatable {
    var version: Int = 1
    var bootstrapped: Bool = false
    var seen: [String: Date] = [:]
}

/// Gorulme durumunu diskte tutar.
///
/// gh-prs'in `~/.local/state/gh-prs/seen.txt` dosyasina KESINLIKLE dokunmaz.
/// Paylassalardi, Mac'te gorulen bir PR telefona hic bildirilmezdi; ayri
/// tutulunca iki kanal bagimsiz calisir.
final class SeenStore {

    private let url: URL
    private var state: SeenState

    init(url: URL) {
        self.url = url
        self.state = Self.load(from: url)
    }

    var isFirstRun: Bool { !state.bootstrapped }

    func isSeen(_ url: String) -> Bool {
        state.seen[url] != nil
    }

    func markSeen(_ urls: [String], at now: Date) {
        for url in urls { state.seen[url] = now }
    }

    func newItems(among items: [Item]) -> [Item] {
        items.filter { !isSeen($0.url) }
    }

    /// Ilk calistirmada mevcut her sey gorulmus sayilir; aksi halde uygulamayi
    /// kuran biri ilk saniyede onlarca bildirimle karsilasirdi.
    /// Yalnizca bir kez etki eder; ikinci cagride false doner.
    @discardableResult
    func bootstrap(with items: [Item], at now: Date) -> Bool {
        guard !state.bootstrapped else { return false }
        markSeen(items.map(\.url), at: now)
        state.bootstrapped = true
        return true
    }

    /// Kapanmis/merge olmus ogeleri duser; yoksa dosya sonsuza kadar buyur.
    func prune(keeping live: Set<String>) {
        state.seen = state.seen.filter { live.contains($0.key) }
    }

    func save() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    // MARK: - Private

    /// Bozuk dosya sessizce sifirlanir. Yan etkisi bir kerelik fazla bildirim;
    /// alternatifi uygulamanin hic acilmamasi olurdu.
    private static func load(from url: URL) -> SeenState {
        guard let data = try? Data(contentsOf: url) else { return SeenState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(SeenState.self, from: data) else {
            NSLog("GHBar: seen.json okunamadi, sifirlaniyor")
            return SeenState()
        }
        return state
    }

    static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GHBar/seen.json")
    }
}
```

- [ ] **Step 4: Testleri çalıştır, geçtiğini gör**

Run: `swift test --filter SeenStore`
Expected: PASS — 7 test

- [ ] **Step 5: Commit**

```bash
git add Sources/GHBar/SeenStore.swift Tests/GHBarTests/SeenStoreTests.swift
git commit -m "Gorulme durumu deposu

Ilk calistirmada mevcut her sey gorulmus sayiliyor, yoksa kurulumun
ilk saniyesinde onlarca bildirim yagardi. Kapanan ogeler her
yenilemede temizleniyor. gh-prs'in state dosyasina dokunulmuyor:
paylassalardi Mac'te gorulen bir PR telefona hic dusmezdi."
```

---

### Task 6: `gh` bulma ve token alma

**Files:**
- Create: `Sources/GHBar/AppError.swift`
- Create: `Sources/GHBar/TokenProvider.swift`
- Test: `Tests/GHBarTests/TokenProviderTests.swift`

**Interfaces:**
- Consumes: —
- Produces:
  - `enum AppError: Error, Equatable` — `ghNotFound`, `ghNotAuthenticated`, `network(String)`, `graphQL(String)`, `rateLimited(Date)`, `allowListEmpty`, `filtersDropped`, `parse(String)`; `var menuText: String`
  - `enum TokenProvider` — `static let knownPaths: [String]`, `static func locate(fileExists: (String) -> Bool, pathEnvironment: String?) -> String?`, `static func token() throws -> String`

- [ ] **Step 1: Başarısız testi yaz**

`Tests/GHBarTests/TokenProviderTests.swift`:

```swift
import Testing
@testable import GHBar

@Suite("TokenProvider.locate")
struct TokenProviderLocateTests {

    @Test("Apple Silicon konumu once denenir") func homebrewFirst() {
        let found = TokenProvider.locate(
            fileExists: { $0 == "/opt/homebrew/bin/gh" || $0 == "/usr/local/bin/gh" },
            pathEnvironment: nil
        )
        #expect(found == "/opt/homebrew/bin/gh")
    }

    @Test("Intel konumuna duser") func intelFallback() {
        let found = TokenProvider.locate(
            fileExists: { $0 == "/usr/local/bin/gh" },
            pathEnvironment: nil
        )
        #expect(found == "/usr/local/bin/gh")
    }

    @Test("bilinen konumlar yoksa PATH taranir") func pathFallback() {
        let found = TokenProvider.locate(
            fileExists: { $0 == "/custom/bin/gh" },
            pathEnvironment: "/nope:/custom/bin"
        )
        #expect(found == "/custom/bin/gh")
    }

    @Test("hicbir yerde yoksa nil doner, cokmez") func notFound() {
        let found = TokenProvider.locate(fileExists: { _ in false }, pathEnvironment: "/a:/b")
        #expect(found == nil)
    }

    @Test("PATH bos olabilir — .app icinde oyle olur") func emptyPath() {
        let found = TokenProvider.locate(fileExists: { _ in false }, pathEnvironment: nil)
        #expect(found == nil)
    }
}

@Suite("AppError")
struct AppErrorTests {
    @Test("her hatanin kullaniciya gosterilecek metni var") func menuText() {
        #expect(AppError.ghNotFound.menuText == "GitHub CLI not found — install gh")
        #expect(AppError.ghNotAuthenticated.menuText == "Not signed in — run: gh auth login")
        #expect(AppError.allowListEmpty.menuText == "No repositories selected")
    }
}
```

- [ ] **Step 2: Testi çalıştır, başarısız olduğunu gör**

Run: `swift test --filter TokenProvider`
Expected: FAIL — `cannot find 'TokenProvider' in scope`

- [ ] **Step 3: `AppError` yaz**

`Sources/GHBar/AppError.swift`:

```swift
import Foundation

/// Kullaniciya gosterilecek hatalar. Hicbiri sessizce yutulmaz: bos liste
/// gostermek en kotu sonuc olurdu — "bekleyen is yok" ile "bakamadim" ayirt
/// edilemez hale gelir ve kullanici ikincisini birincisi sanar.
enum AppError: Error, Equatable {
    case ghNotFound
    case ghNotAuthenticated
    case network(String)
    case graphQL(String)
    case parse(String)
    case rateLimited(Date)
    case allowListEmpty
    case filtersDropped

    var menuText: String {
        switch self {
        case .ghNotFound:
            "GitHub CLI not found — install gh"
        case .ghNotAuthenticated:
            "Not signed in — run: gh auth login"
        case .network:
            "No connection"
        case .graphQL(let message):
            "GitHub error: \(message)"
        case .parse:
            "Unexpected response from GitHub"
        case .rateLimited(let resetAt):
            "Rate limit reached · resets \(Self.clock.string(from: resetAt))"
        case .allowListEmpty:
            "No repositories selected"
        case .filtersDropped:
            "Too many filters — some were dropped"
        }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
```

- [ ] **Step 4: `TokenProvider` yaz**

`Sources/GHBar/TokenProvider.swift`:

```swift
import Foundation

enum TokenProvider {

    /// `.app` icinden baslatilan bir surec kabuk ortamini miras almaz — PATH
    /// neredeyse bostur. Bu yuzden tam yol denemesi sart; sadece PATH'e
    /// guvenmek cogu makinede sessizce basarisiz olur.
    static let knownPaths = [
        "/opt/homebrew/bin/gh",   // Apple Silicon
        "/usr/local/bin/gh",      // Intel
    ]

    static func locate(
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> String? {
        if let known = knownPaths.first(where: fileExists) { return known }

        guard let pathEnvironment else { return nil }
        for directory in pathEnvironment.split(separator: ":") {
            let candidate = "\(directory)/gh"
            if fileExists(candidate) { return candidate }
        }
        return nil
    }

    static func token() throws -> String {
        guard let executable = locate() else { throw AppError.ghNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["auth", "token"]

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw AppError.ghNotFound
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        _ = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let token = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0, !token.isEmpty else {
            throw AppError.ghNotAuthenticated
        }
        return token
    }
}
```

- [ ] **Step 5: Testleri çalıştır, geçtiğini gör**

Run: `swift test --filter "TokenProvider|AppError"`
Expected: PASS — 6 test

- [ ] **Step 6: Commit**

```bash
git add Sources/GHBar/TokenProvider.swift Sources/GHBar/AppError.swift Tests/GHBarTests/TokenProviderTests.swift
git commit -m "gh konumu bulma ve token alma

.app icinden calisan surecte PATH bos oldugu icin once tam yollar
deneniyor, PATH en son care. Konum bulma saf fonksiyon olarak
ayrildi ve dosya varligi enjekte edilerek test ediliyor."
```

---

### Task 7: GitHub istemcisi

**Files:**
- Create: `Sources/GHBar/GitHubClient.swift`
- Test: `Tests/GHBarTests/GitHubClientTests.swift`

**Interfaces:**
- Consumes: `Queries` (Task 3), `Snapshot`/`ResponseParser` (Task 2), `AppError` (Task 6)
- Produces: `struct GitHubClient { init(token: String, session: URLSession = .shared); func fetch(_ queries: Queries) async throws -> Snapshot }`

- [ ] **Step 1: Başarısız testi yaz**

Ağa çıkmadan test etmek için `URLProtocol` yerine basit bir enjekte edilebilir taşıyıcı kullanıyoruz — daha az kurulum, daha okunur test.

`Tests/GHBarTests/GitHubClientTests.swift`:

```swift
import Testing
import Foundation
@testable import GHBar

@Suite("GitHubClient")
struct GitHubClientTests {

    @Test("istek dogru bicimde kurulur") func requestShape() throws {
        let client = GitHubClient(token: "secret-token")
        let request = try client.makeRequest(Queries(
            prs: "P", issues: "I", review: "R",
            filtersDropped: false, allowListEmpty: false
        ))

        #expect(request.url?.absoluteString == "https://api.github.com/graphql")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let variables = body["variables"] as! [String: Any]
        #expect(variables["prs"] as? String == "P")
        #expect(variables["issues"] as? String == "I")
        #expect(variables["review"] as? String == "R")
        #expect(variables["first"] as? Int == 100)
    }

    @Test("401 oturum hatasina cevrilir") func unauthorized() throws {
        let client = GitHubClient(token: "bad")
        #expect(throws: AppError.ghNotAuthenticated) {
            try client.validate(statusCode: 401, data: Data())
        }
    }

    @Test("403 kota hatasina cevrilir") func rateLimited() throws {
        let client = GitHubClient(token: "t")
        #expect(throws: (any Error).self) {
            try client.validate(statusCode: 403, data: Data())
        }
    }

    @Test("200 gecer") func ok() throws {
        let client = GitHubClient(token: "t")
        try client.validate(statusCode: 200, data: Data())
    }
}
```

- [ ] **Step 2: Testi çalıştır, başarısız olduğunu gör**

Run: `swift test --filter GitHubClient`
Expected: FAIL — `cannot find 'GitHubClient' in scope`

- [ ] **Step 3: Uygulamayı yaz**

`Sources/GHBar/GitHubClient.swift`:

```swift
import Foundation

struct GitHubClient {

    static let endpoint = URL(string: "https://api.github.com/graphql")!
    /// GitHub aramanin ust siniri. Sayfalama yapilmiyor; sinira dayanan arama
    /// menude uyari satirina donusuyor.
    static let pageSize = 100

    let token: String
    let session: URLSession

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func fetch(_ queries: Queries) async throws -> Snapshot {
        let request = try makeRequest(queries)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppError.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        try validate(statusCode: status, data: data)

        do {
            return try ResponseParser.parse(data)
        } catch let error as ParseError {
            switch error {
            case .graphQL(let message): throw AppError.graphQL(message)
            case .malformed(let detail): throw AppError.parse(detail)
            }
        }
    }

    // MARK: - Test edilebilir parcalar

    func makeRequest(_ queries: Queries) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("GHBar", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "query": Query.document,
            "variables": [
                "prs": queries.prs,
                "issues": queries.issues,
                "review": queries.review,
                "first": Self.pageSize,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func validate(statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200:
            return
        case 401:
            throw AppError.ghNotAuthenticated
        case 403, 429:
            throw AppError.rateLimited(Date().addingTimeInterval(3600))
        default:
            throw AppError.network("HTTP \(statusCode)")
        }
    }
}
```

- [ ] **Step 4: Testleri çalıştır, geçtiğini gör**

Run: `swift test --filter GitHubClient`
Expected: PASS — 4 test

- [ ] **Step 5: Commit**

```bash
git add Sources/GHBar/GitHubClient.swift Tests/GHBarTests/GitHubClientTests.swift
git commit -m "GraphQL istemcisi

Istek kurulumu ve durum kodu dogrulamasi ag cagrisindan ayri
metotlara alindi; boylece ikisi de ag olmadan test edilebiliyor.
401 oturum hatasina, 403/429 kota hatasina cevriliyor."
```

---

### Task 8: Satır metni ve menü kurulumu

**Files:**
- Create: `Sources/GHBar/RowText.swift`
- Create: `Sources/GHBar/MenuBuilder.swift`
- Test: `Tests/GHBarTests/RowTextTests.swift`

**Interfaces:**
- Consumes: `Item`, `Section`, `Row`, `Viewer`, `RateLimit` (Task 2), `Formatting` (Task 1), `AppError` (Task 6)
- Produces:
  - `enum RowText { static func parts(for item: Item, showOwner: Bool, now: Date) -> (label: String, detail: String, age: String) }`
  - `enum RowText { static func groupLabel(repository: String, count: Int, kind: ItemKind, showOwner: Bool) -> String }`
  - `@MainActor final class MenuBuilder` — `init(target: AnyObject)`, `func build(...) -> NSMenu`

- [ ] **Step 1: Başarısız testi yaz**

`Tests/GHBarTests/RowTextTests.swift`:

```swift
import Testing
import Foundation
@testable import GHBar

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func makeItem(repo: String = "alice/webapp", title: String = "Fix the floating tab bar") -> Item {
    Item(kind: .pullRequest, repository: repo, number: 55, title: title,
         url: "u", createdAt: now.addingTimeInterval(-3600),
         isDraft: false, authorLogin: "bob", authorIsBot: false)
}

@Suite("RowText")
struct RowTextTests {

    @Test("tek hesap izlenirken sadece repo adi gosterilir") func singleAccount() {
        let parts = RowText.parts(for: makeItem(), showOwner: false, now: now)
        #expect(parts.label == "webapp #55")
    }

    @Test("cok hesap izlenirken tam ad gosterilir") func multipleAccounts() {
        let parts = RowText.parts(for: makeItem(repo: "acme/backend"), showOwner: true, now: now)
        #expect(parts.label == "acme/backend #55")
    }

    @Test("baslik kirpilir") func truncatesTitle() {
        let long = String(repeating: "word ", count: 40)
        let parts = RowText.parts(for: makeItem(title: long), showOwner: false, now: now)
        #expect(parts.detail.count <= 49)
        #expect(parts.detail.hasSuffix("…"))
    }

    @Test("yas hesaplanir") func age() {
        let parts = RowText.parts(for: makeItem(), showOwner: false, now: now)
        #expect(parts.age == "1h")
    }

    @Test("grup etiketi tekil ve cogul dogru") func groupLabel() {
        #expect(RowText.groupLabel(repository: "alice/notes", count: 1, kind: .issue, showOwner: false)
                == "notes — 1 issue")
        #expect(RowText.groupLabel(repository: "alice/notes", count: 18, kind: .issue, showOwner: false)
                == "notes — 18 issues")
        #expect(RowText.groupLabel(repository: "alice/notes", count: 4, kind: .pullRequest, showOwner: true)
                == "alice/notes — 4 pull requests")
    }
}
```

- [ ] **Step 2: Testi çalıştır, başarısız olduğunu gör**

Run: `swift test --filter RowText`
Expected: FAIL — `cannot find 'RowText' in scope`

- [ ] **Step 3: `RowText` yaz**

`Sources/GHBar/RowText.swift`:

```swift
import Foundation

enum RowText {

    static let titleLimit = 48

    /// Tek hesap izleniyorsa her satirda kendi adini tekrar gormek gereksiz
    /// gurultu; o yuzden sahip adi yalnizca birden fazla hesap izlenirken yazilir.
    static func parts(for item: Item, showOwner: Bool, now: Date) -> (label: String, detail: String, age: String) {
        let repository = showOwner ? item.repository : item.repositoryName
        return (
            label: "\(repository) #\(item.number)",
            detail: Formatting.truncate(item.title, limit: titleLimit),
            age: Formatting.age(of: item.createdAt, now: now)
        )
    }

    static func groupLabel(repository: String, count: Int, kind: ItemKind, showOwner: Bool) -> String {
        let name = showOwner ? repository : (repository.split(separator: "/").last.map(String.init) ?? repository)
        let noun: String
        switch (kind, count) {
        case (.issue, 1):       noun = "issue"
        case (.issue, _):       noun = "issues"
        case (.pullRequest, 1): noun = "pull request"
        case (.pullRequest, _): noun = "pull requests"
        }
        return "\(name) — \(count) \(noun)"
    }
}
```

- [ ] **Step 4: Testleri çalıştır, geçtiğini gör**

Run: `swift test --filter RowText`
Expected: PASS — 5 test

- [ ] **Step 5: `MenuBuilder` yaz**

Menü çizimi test edilmiyor — otomatik test maliyeti değmiyor; elle doğrulanacak.

`Sources/GHBar/MenuBuilder.swift`:

```swift
import AppKit

@MainActor
final class MenuBuilder {

    /// Menu ogelerinin hedefi. Tiklama eylemleri AppDelegate'te.
    private weak var target: AnyObject?

    init(target: AnyObject) {
        self.target = target
    }

    struct Input {
        var viewer: Viewer?
        var sections: [Section]
        var rateLimit: RateLimit?
        var errors: [AppError]
        var showOwner: Bool
        var maxRowsPerSection: Int
        var isSeen: (String) -> Bool
        var now: Date
    }

    func build(_ input: Input) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let viewer = input.viewer {
            menu.addItem(profileItem(viewer))
            menu.addItem(.separator())
        }

        for error in input.errors {
            menu.addItem(errorItem(error))
        }
        if !input.errors.isEmpty {
            menu.addItem(.separator())
        }

        for section in input.sections {
            menu.addItem(.sectionHeader(title: section.kind.title))
            addRows(of: section, to: menu, input: input)
            if section.truncated {
                menu.addItem(disabled("Showing first 100 — narrow your filters"))
            }
            menu.addItem(markAllSeenItem(for: section))
            menu.addItem(.separator())
        }

        if let rateLimit = input.rateLimit {
            menu.addItem(.sectionHeader(title: "API"))
            menu.addItem(rateLimitItem(rateLimit, now: input.now))
            menu.addItem(.separator())
        }

        menu.addItem(action("Open GitHub", #selector(AppDelegate.openProfile), key: "o"))
        menu.addItem(action("Refresh", #selector(AppDelegate.refreshNow), key: "r"))
        menu.addItem(action("Quit GHBar", #selector(AppDelegate.quit), key: "q"))
        return menu
    }

    // MARK: - Parcalar

    private func addRows(of section: Section, to menu: NSMenu, input: Input) {
        let visible = section.rows.prefix(input.maxRowsPerSection)
        for row in visible {
            menu.addItem(item(for: row, section: section, input: input))
        }
        let overflow = section.rows.count - visible.count
        guard overflow > 0 else { return }

        let more = NSMenuItem(title: "\(overflow) more…", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for row in section.rows.dropFirst(visible.count) {
            submenu.addItem(item(for: row, section: section, input: input))
        }
        more.submenu = submenu
        menu.addItem(more)
    }

    private func item(for row: Row, section: Section, input: Input) -> NSMenuItem {
        switch row {
        case .item(let entry):
            return itemRow(entry, input: input)
        case .group(let repository, let items):
            let unseen = items.contains { !input.isSeen($0.url) }
            let title = RowText.groupLabel(
                repository: repository,
                count: items.count,
                kind: items[0].kind,
                showOwner: input.showOwner
            )
            let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            menuItem.image = Icons.folder(unseen: unseen)
            let submenu = NSMenu()
            for entry in items { submenu.addItem(itemRow(entry, input: input)) }
            menuItem.submenu = submenu
            return menuItem
        }
    }

    private func itemRow(_ entry: Item, input: Input) -> NSMenuItem {
        let parts = RowText.parts(for: entry, showOwner: input.showOwner, now: input.now)
        let seen = input.isSeen(entry.url)

        // Raycast'in menulerindeki temizligin sirri: deger, etiketin hemen
        // devami olarak akiyor — sutun hizalama veya saga yaslama yok.
        let text = NSMutableAttributedString(
            string: parts.label,
            attributes: [.foregroundColor: seen ? NSColor.secondaryLabelColor : NSColor.labelColor]
        )
        text.append(NSAttributedString(
            string: "  \(parts.detail)   \(parts.age)",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        ))

        let menuItem = NSMenuItem(title: "", action: #selector(AppDelegate.openItem(_:)), keyEquivalent: "")
        menuItem.attributedTitle = text
        menuItem.target = target
        menuItem.representedObject = entry
        menuItem.image = Icons.forItem(entry, seen: seen)
        return menuItem
    }

    private func profileItem(_ viewer: Viewer) -> NSMenuItem {
        let text = NSMutableAttributedString(
            string: viewer.displayName,
            attributes: [.foregroundColor: NSColor.labelColor]
        )
        text.append(NSAttributedString(
            string: "  @\(viewer.login)",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        ))
        let item = NSMenuItem(title: "", action: #selector(AppDelegate.openProfile), keyEquivalent: "")
        item.attributedTitle = text
        item.target = target
        return item
    }

    private func rateLimitItem(_ limit: RateLimit, now: Date) -> NSMenuItem {
        let resets = Formatting.age(of: now, now: limit.resetAt)
        let text = NSMutableAttributedString(
            string: "Rate Limit",
            attributes: [.foregroundColor: NSColor.labelColor]
        )
        text.append(NSAttributedString(
            string: "  \(Formatting.grouped(limit.remaining)) / \(Formatting.grouped(limit.limit))   resets \(resets)",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        ))
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = text
        item.isEnabled = false
        item.image = Icons.gauge(fraction: limit.fraction)
        return item
    }

    private func markAllSeenItem(for section: Section) -> NSMenuItem {
        let item = NSMenuItem(
            title: "Mark All as Seen",
            action: #selector(AppDelegate.markSectionSeen(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = section.kind.rawValue
        item.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
        return item
    }

    private func errorItem(_ error: AppError) -> NSMenuItem {
        let item = NSMenuItem(title: error.menuText, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        item.isEnabled = false
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = target
        return item
    }
}

/// Ayri bir "okunmadi" noktasi cizilmiyor — ikonun rengi bu isi goruyor.
enum Icons {
    static func forItem(_ item: Item, seen: Bool) -> NSImage? {
        let symbol = item.kind == .pullRequest
            ? "arrow.trianglehead.pull"
            : "smallcircle.filled.circle"
        let color: NSColor = item.isDraft ? .tertiaryLabelColor
                           : (seen ? .secondaryLabelColor : .systemGreen)
        return tinted(symbol, color)
    }

    static func folder(unseen: Bool) -> NSImage? {
        tinted("folder", unseen ? .systemGreen : .secondaryLabelColor)
    }

    static func gauge(fraction: Double) -> NSImage? {
        let color: NSColor = fraction < 0.10 ? .systemRed
                           : (fraction < 0.25 ? .systemOrange : .secondaryLabelColor)
        return tinted("gauge.with.needle", color)
    }

    private static func tinted(_ symbol: String, _ color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}
```

- [ ] **Step 6: Derlendiğini doğrula**

Run: `swift build`
Expected: `AppDelegate` henüz yok — bu adımda derleme **hata verecek**. Task 9 tamamlanınca geçecek. Sadece `swift test --filter RowText` çalıştırıp devam et.

- [ ] **Step 7: Commit**

```bash
git add Sources/GHBar/RowText.swift Sources/GHBar/MenuBuilder.swift Tests/GHBarTests/RowTextTests.swift
git commit -m "Satir metni ve menu kurulumu

Satirlar tek bir NSAttributedString icinde iki renk kullaniyor:
etiket normal, deger gri, arka arkaya. Sutun hizalama yok —
Raycast menulerindeki temiz gorunumun sebebi bu.
Okunmadi isareti ayri bir nokta yerine ikon rengiyle veriliyor."
```

---

### Task 9: Uygulamayı birleştir ve çalıştır

**Files:**
- Create: `Sources/GHBar/AppDelegate.swift`
- Create: `Sources/GHBar/main.swift`

**Interfaces:**
- Consumes: hepsi
- Produces: çalışan uygulama

- [ ] **Step 1: `AppDelegate` yaz**

`Sources/GHBar/AppDelegate.swift`:

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var menuBuilder: MenuBuilder!
    private let seenStore = SeenStore(url: SeenStore.defaultURL)
    private let settings = Settings.default

    private var sections: [Section] = []
    private var viewer: Viewer?
    private var rateLimit: RateLimit?
    private var errors: [AppError] = []
    private var lastRefresh: Date?
    private var isRefreshing = false
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock'ta ikon gosterme. Asama 2'de .app paketine LSUIElement
        // eklenecek; bu satir swift run ile calistirirken ayni isi goruyor.
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "arrow.trianglehead.pull",
            accessibilityDescription: "GHBar"
        )
        menuBuilder = MenuBuilder(target: self)
        rebuildMenu()

        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        // Uykudan uyaninca yenile; onsuz kapagi actiginda saatler oncesinin
        // verisini gorursun ve bayat oldugunu anlamanin yolu yoktur.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        refresh()
    }

    // MARK: - Yenileme

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task { @MainActor in
            defer { isRefreshing = false }
            do {
                let token = try TokenProvider.token()
                let queries = Query.build(settings)

                var collected: [AppError] = []
                if queries.allowListEmpty { collected.append(.allowListEmpty) }
                if queries.filtersDropped { collected.append(.filtersDropped) }

                guard !queries.allowListEmpty else {
                    errors = collected
                    sections = []
                    rebuildMenu()
                    return
                }

                let snapshot = try await GitHubClient(token: token).fetch(queries)
                let built = Filtering.sections(from: snapshot, settings: settings)

                let all = built.flatMap(\.items)
                seenStore.bootstrap(with: all, at: Date())
                seenStore.prune(keeping: Set(all.map(\.url)))
                try? seenStore.save()

                viewer = snapshot.viewer
                rateLimit = snapshot.rateLimit
                sections = built
                errors = collected
                lastRefresh = Date()
            } catch let error as AppError {
                errors = [error]
            } catch {
                errors = [.network(error.localizedDescription)]
            }
            rebuildMenu()
        }
    }

    private func rebuildMenu() {
        let unseenCount = sections
            .flatMap(\.items)
            .filter { !seenStore.isSeen($0.url) }
            .count

        statusItem.button?.title = unseenCount > 0 ? " \(unseenCount)" : ""

        let menu = menuBuilder.build(MenuBuilder.Input(
            viewer: viewer,
            sections: sections,
            rateLimit: rateLimit,
            errors: errors,
            showOwner: settings.accounts.count > 1,
            maxRowsPerSection: settings.maxRowsPerSection,
            isSeen: { [seenStore] in seenStore.isSeen($0) },
            now: Date()
        ))
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Menu eylemleri

    @objc func openItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? Item,
              let url = URL(string: item.url) else { return }
        // Tiklamak hem aciyor hem gorulmus isaretliyor; ayrica isaretlemeye
        // gerek kalmiyor.
        seenStore.markSeen([item.url], at: Date())
        try? seenStore.save()
        NSWorkspace.shared.open(url)
        rebuildMenu()
    }

    @objc func markSectionSeen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = SectionKind(rawValue: raw),
              let section = sections.first(where: { $0.kind == kind }) else { return }
        seenStore.markSeen(section.items.map(\.url), at: Date())
        try? seenStore.save()
        rebuildMenu()
    }

    @objc func openProfile() {
        guard let login = viewer?.login,
              let url = URL(string: "https://github.com/\(login)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func refreshNow() { refresh() }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: - NSMenuDelegate

    /// Menuyu art arda acip kapatmak gereksiz istek uretmesin diye 30 saniyelik
    /// alt sinir var.
    func menuWillOpen(_ menu: NSMenu) {
        guard let last = lastRefresh else { return }
        if Date().timeIntervalSince(last) > 30 { refresh() }
    }
}
```

- [ ] **Step 2: `main.swift` yaz**

`Sources/GHBar/main.swift`:

```swift
import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
```

- [ ] **Step 3: Derle**

Run: `swift build`
Expected: başarılı, uyarı yok

- [ ] **Step 4: Tüm testleri çalıştır**

Run: `swift test`
Expected: PASS — 56 test

- [ ] **Step 5: Elle doğrula**

Run: `swift run GHBar`

Kontrol listesi:
- [ ] Menü çubuğunda ikon ve sayı belirdi
- [ ] Menü açılınca profil satırı, `Pull Requests` ve `Issues` bölümleri göründü
- [ ] Okunmamış satırların ikonu yeşil
- [ ] Bir satıra tıklayınca tarayıcıda doğru sayfa açıldı ve ikon griye döndü
- [ ] `Mark All as Seen` o bölümü griye çevirdi
- [ ] `Rate Limit` satırı sayı gösteriyor
- [ ] ⌘R yeniledi, ⌘Q kapattı
- [ ] Bir repodan 3'ten fazla öğe varsa tek satıra toplandı ve alt menüde hepsi var

Hata yolunu da bir kez dene: `PATH= /usr/bin/env -i swift run GHBar` ile `gh` bulunamadığında menüde `GitHub CLI not found — install gh` satırının çıktığını doğrula.

- [ ] **Step 6: Commit**

```bash
git add Sources/GHBar/AppDelegate.swift Sources/GHBar/main.swift
git commit -m "Uygulamayi birlestir: durum cubugu, yenileme dongusu, menu eylemleri

Yenileme tetikleyicileri: 5 dakikalik zamanlayici, uykudan uyanma,
menu acilisi (30 sn alt siniriyla) ve elle yenileme. Ayni anda
ikinci yenileme baslatilmiyor. Bir satira tiklamak hem aciyor hem
gorulmus isaretliyor."
```

---

## Aşama 1 bittiğinde elinde ne var

`swift run GHBar` ile çalışan, gerçek verini gösteren bir menü çubuğu uygulaması. Henüz `.app` değil (terminal kapanınca ölür), bildirim atmıyor, ayarları kod içinde. Aşama 2 bunları çözüyor.

## Spec kapsam kontrolü

Aşama 1 kapsamındaki her spec maddesi bir göreve bağlandı:

| Spec | Görev |
|---|---|
| §6 GraphQL sorgusu, `@me`, uzunluk tavanı | Task 3 |
| §6 sorgu içi repo filtresi, beyaz/kara liste | Task 3 |
| §7 bot elemesi (iki koşullu) | Task 2 (bayrak), Task 4 (eleme) |
| §7 yazarsız öğe atılır | Task 2 |
| §7 sıralama, çakışma çözümü | Task 4 |
| §7 repo gruplama | Task 4 |
| §9 görülme durumu, ilk çalıştırma, temizlik | Task 5 |
| §10 bölüm başlıkları, iki renkli satır, ikon renkleri, taşma | Task 8 |
| §10 tıklama davranışı | Task 9 |
| §5 `gh` konumları, boş `PATH` | Task 6 |
| §12 yenileme tetikleyicileri | Task 9 |
| §13 hata satırları | Task 6 (metinler), Task 9 (gösterim) |

**Aşama 1 kapsamı dışında bilerek bırakılanlar:** OAuth device flow (§5), ayarlar penceresi (§8), bildirimler (§11), üstel geri çekilme (§13), paketleme ve noterleme (§14), avatar indirme (§10), güncelleme kontrolü (§14). Bunlar Aşama 2–4'e ait.
