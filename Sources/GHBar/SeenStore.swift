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

    /// Kapanmis/merge olmus ogeleri duser; yoksa dosya sonsuza kadar buyur.
    func prune(keeping live: Set<String>) {
        state.seen = state.seen.filter { live.contains($0.key) }
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
