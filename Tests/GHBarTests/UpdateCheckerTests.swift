import Testing
import Foundation
@testable import GHBar

@Suite("UpdateChecker")
struct UpdateCheckerTests {

    @Test("yama surumu daha yeni") func patch() {
        #expect(UpdateChecker.isNewer("0.3.4", than: "0.3.3"))
        #expect(!UpdateChecker.isNewer("0.3.3", than: "0.3.4"))
    }

    @Test("ayni surum yeni degil") func same() {
        #expect(!UpdateChecker.isNewer("0.3.3", than: "0.3.3"))
        #expect(!UpdateChecker.isNewer("1.0", than: "1.0.0"))
    }

    @Test("sayisal karsilastirma, metin degil") func numeric() {
        #expect(UpdateChecker.isNewer("0.10.0", than: "0.9.9"))
    }

    @Test("v onekini yok sayar") func prefix() {
        #expect(UpdateChecker.isNewer("v0.4.0", than: "0.3.3"))
        #expect(UpdateChecker.normalized("v0.3.3") == "0.3.3")
    }

    @Test("release JSON'u cozulur") func decode() throws {
        let json = #"{"tag_name":"v0.4.0","html_url":"https://github.com/cobanov/ghbar/releases/tag/v0.4.0","draft":false}"#
        let release = try JSONDecoder().decode(UpdateChecker.Release.self, from: Data(json.utf8))
        #expect(release.tagName == "v0.4.0")
        #expect(release.htmlURL.absoluteString.hasSuffix("/v0.4.0"))
    }
}
