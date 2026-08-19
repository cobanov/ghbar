import Testing
@testable import GHBar

/// `#expect` mutating metodu dogrudan cagiramiyor; sonuclar once yerel
/// degiskene aliniyor.
@Suite("RefreshGate")
struct RefreshGateTests {

    @Test("bos kapi yenilemeyi baslatir") func startsWhenIdle() {
        var gate = RefreshGate()
        let started = gate.begin()
        #expect(started)
    }

    @Test("calisirken ikinci istek baslatmaz") func blocksWhileRunning() {
        var gate = RefreshGate()
        _ = gate.begin()
        let second = gate.begin()
        #expect(!second)
    }

    @Test("cakisan istek kuyruga girer ve bitiste geri gelir") func replaysQueued() {
        var gate = RefreshGate()
        _ = gate.begin()
        _ = gate.begin()
        let replay = gate.finish()
        #expect(replay)
    }

    @Test("cakisma yoksa bitiste tekrar calismaz") func noReplayWithoutOverlap() {
        var gate = RefreshGate()
        _ = gate.begin()
        let replay = gate.finish()
        #expect(!replay)
    }

    @Test("ust uste yigilan istekler tek tekrara iner") func collapsesBurst() {
        var gate = RefreshGate()
        _ = gate.begin()
        _ = gate.begin()
        _ = gate.begin()
        let replay = gate.finish()
        #expect(replay)

        // Kuyruktan gelen yenileme: bitiminde yeni istek yoksa durmali.
        let restarted = gate.begin()
        let again = gate.finish()
        #expect(restarted)
        #expect(!again)
    }

    @Test("bittikten sonra kapi yeniden acilir") func reusableAfterFinish() {
        var gate = RefreshGate()
        _ = gate.begin()
        _ = gate.finish()
        let reopened = gate.begin()
        #expect(reopened)
    }
}
