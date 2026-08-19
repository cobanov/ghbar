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

    @Test("ilk calistirma isareti bir kez true, sonra false") func firstRunFlag() {
        let store = SeenStore(url: temporaryURL())
        #expect(store.isFirstRun == true)
        #expect(store.markFirstRunDone() == true)
        #expect(store.isFirstRun == false)
        #expect(store.markFirstRunDone() == false)
    }

    @Test("ilk calistirma ogeleri GORULMUS SAYMAZ") func firstRunLeavesItemsUnseen() {
        // Onceden burada her sey gorulmus isaretleniyordu; sonucu ilk acilista
        // her seyin gri baslamasi ve "Mark All as Seen"in bozuk gorunmesiydi.
        let store = SeenStore(url: temporaryURL())
        _ = store.markFirstRunDone()
        #expect(store.newItems(among: [makeItem(1), makeItem(2)]).count == 2)
        #expect(store.isSeen("https://example.com/1") == false)
    }

    @Test("gorulmemis ogeler dogru donuyor") func newItems() {
        let store = SeenStore(url: temporaryURL())
        store.markSeen(["https://example.com/1"], at: Date())
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

@Suite("SeenStore.notified")
struct SeenStoreNotifiedTests {

    @Test("bildirilmis oge bir daha bildirilmez") func onceOnly() {
        let store = SeenStore(url: temporaryURL())
        _ = store.markFirstRunDone()
        let items = [makeItem(1), makeItem(2)]
        #expect(store.unnotified(among: items).count == 2)
        store.markNotified(items.map(\.url))
        #expect(store.unnotified(among: items).isEmpty)
        // yeni oge gelince yalniz o doner
        #expect(store.unnotified(among: items + [makeItem(3)]).map(\.number) == [3])
    }

    @Test("bildirilmislik gorulmuslukten bagimsiz") func independentFromSeen() {
        let store = SeenStore(url: temporaryURL())
        store.markNotified([makeItem(1).url])
        #expect(store.isSeen(makeItem(1).url) == false)   // bildirildi ama gorulmedi
    }

    @Test("diske yazilip geri okunur") func persists() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SeenStore(url: url)
        _ = store.markFirstRunDone()
        store.markNotified(["https://example.com/1"])
        try store.save()
        let reloaded = SeenStore(url: url)
        #expect(reloaded.unnotified(among: [makeItem(1)]).isEmpty)
        #expect(reloaded.claimNotificationBackfill() == false)
    }

    @Test("prune bildirilmis kumesini de temizler") func pruneNotified() {
        let store = SeenStore(url: temporaryURL())
        store.markNotified(["a", "b"])
        store.prune(keeping: ["a"])
        // "b" dustu: ayni URL geri gelirse (reopen) yeniden bildirilebilir
        #expect(store.unnotified(among: [makeItem(1)]).count == 1)
    }

    @Test("v1 dosyasi (notified alani yok) yukseltme sayilir: TEK seferlik backfill") func v1Upgrade() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // Hatanin yasandigi gercek durum: bootstrapped=true, notified alani hic yok
        let v1 = #"{"version":1,"bootstrapped":true,"seen":{}}"#
        try Data(v1.utf8).write(to: url)

        let store = SeenStore(url: url)
        #expect(store.claimNotificationBackfill() == true)   // ilk yenileme: sustur
        #expect(store.claimNotificationBackfill() == false)  // sonrakiler: normal
        #expect(store.isFirstRun == false)
    }

    @Test("taze kurulumda backfill tetiklenmez") func freshInstallNoBackfill() {
        let store = SeenStore(url: temporaryURL())
        #expect(store.claimNotificationBackfill() == false)
    }
}
