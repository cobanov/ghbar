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
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SeenStore(url: url)
        store.markSeen(["https://example.com/1"], at: Date())
        try store.save()

        let reloaded = SeenStore(url: url)
        #expect(reloaded.isSeen("https://example.com/1") == true)
    }

    @Test("ilk calistirmada her sey gorulmus sayilir, yeni oge yok") func bootstrap() {
        let store = SeenStore(url: temporaryURL())
        #expect(store.isFirstRun == true)
        #expect(store.bootstrap(with: [makeItem(1), makeItem(2)], at: Date()) == true)
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
        #expect(store.newItems(among: [makeItem(1), makeItem(2), makeItem(3)]).map(\.number) == [2, 3])
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
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("this is not json".utf8).write(to: url)
        let store = SeenStore(url: url)
        #expect(store.isFirstRun == true)
        #expect(store.isSeen("anything") == false)
    }
}
