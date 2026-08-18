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
        #expect(RowText.parts(for: makeItem(), showOwner: false, now: now).label == "webapp #55")
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
        #expect(RowText.parts(for: makeItem(), showOwner: false, now: now).age == "1h")
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
