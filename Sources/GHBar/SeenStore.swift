import Foundation

struct SeenState: Codable, Equatable {
    var version: Int = 2
    var bootstrapped: Bool = false
    var seen: [String: Date] = [:]
    /// Bir kez bildirilen ogeler. "Gorulmus"ten AYRI bir kume: gorulmus menude
    /// gri/yesil rengini belirler ve kullanici tiklayinca degisir; bildirilmis
    /// ise "bu oge icin bir kez bildirim atildi, bir daha atma" demek. Ikisi
    /// ayni kume sanildiginda su hata cikti: ogeler tiklanana kadar gorulmemis
    /// kaldigi icin her yenilemede ayni eski ogeler yeniden bildirildi.
    var notified: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case version, bootstrapped, seen, notified
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        bootstrapped = try c.decodeIfPresent(Bool.self, forKey: .bootstrapped) ?? false
        seen = try c.decodeIfPresent([String: Date].self, forKey: .seen) ?? [:]
        // v1 dosyalarinda notified yok; eksikligi SeenStore yukseltme olarak
        // algilar ve ilk yenilemede sessizce doldurur.
        notified = try c.decodeIfPresent(Set<String>.self, forKey: .notified) ?? []
    }
}

/// Gorulme durumunu diskte tutar.
///
/// gh-prs'in `~/.local/state/gh-prs/seen.txt` dosyasina KESINLIKLE dokunmaz.
/// Paylassalardi, Mac'te gorulen bir PR telefona hic bildirilmezdi; ayri
/// tutulunca iki kanal bagimsiz calisir.
final class SeenStore {

    private let url: URL
    private var state: SeenState
    /// v1 dosyasindan yukseltme: notified alani hic yoktu. Bir kerelik geri
    /// doldurma gerekiyor, yoksa yukseltmeden sonraki ilk yenileme mevcut her
    /// ogeyi "hic bildirilmemis" sayip bir kez daha bildirim yagdirir.
    private var needsNotificationBackfill: Bool

    init(url: URL) {
        self.url = url
        let loaded = Self.load(from: url)
        self.state = loaded
        self.needsNotificationBackfill = loaded.bootstrapped && loaded.notified.isEmpty
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

    /// Ilk yenilemeyi isaretler ve true doner; sonraki cagrilarda false.
    ///
    /// YALNIZCA bildirimleri susturmak icin. Ogeleri gorulmus SAYMAZ —
    /// once oyle yapiyordu ve sonucu suydu: ilk acilista her sey gri
    /// baslıyor, rozet sifir kaliyor ve "Mark All as Seen" degistirecek
    /// hicbir sey bulamadigi icin bozuk gorunuyordu. Artik her sey
    /// okunmamis basliyor, sadece bildirim yagmuru olmuyor.
    @discardableResult
    func markFirstRunDone() -> Bool {
        guard !state.bootstrapped else { return false }
        state.bootstrapped = true
        return true
    }

    // MARK: - Bildirim kaydi

    /// Daha once hic bildirilmemis ogeler.
    func unnotified(among items: [Item]) -> [Item] {
        items.filter { !state.notified.contains($0.url) }
    }

    func markNotified(_ urls: [String]) {
        state.notified.formUnion(urls)
    }

    /// Yukseltme geri doldurmasi gerekiyorsa true doner ve bayragi dusurur;
    /// cagiran taraf o turda bildirim atmaz, mevcut ogeleri isaretlemekle
    /// yetinir. Yalnizca bir kez true doner.
    func claimNotificationBackfill() -> Bool {
        defer { needsNotificationBackfill = false }
        return needsNotificationBackfill
    }

    /// Kapanmis/merge olmus ogeleri duser; yoksa dosya sonsuza kadar buyur.
    func prune(keeping live: Set<String>) {
        state.seen = state.seen.filter { live.contains($0.key) }
        state.notified = state.notified.filter { live.contains($0) }
    }

    /// Cikis: durum tamamen sifirlanir ve diske yazilir (spec §5 — Sign Out
    /// seen.json'i temizler). Yeni hesap eski hesabin gorulmusluk kaydini
    /// devralmamali.
    func reset() {
        state = SeenState()
        needsNotificationBackfill = false
        try? save()
    }

    func save() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GHBar/seen.json")
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
}
