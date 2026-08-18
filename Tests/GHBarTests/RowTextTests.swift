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

    @Test("satirin toplam genisligi butceyi asmaz") func rowBudget() {
        let long = String(repeating: "word ", count: 40)
        for repo in ["a/b", "alice/webapp", "cobanov/paul-graham-turkce"] {
            let parts = RowText.parts(for: makeItem(repo: repo, title: long), showOwner: false, now: now)
            #expect(parts.label.count + parts.detail.count <= RowText.rowBudget + 1)  // +1 elipsis
            #expect(parts.detail.hasSuffix("…"))
        }
    }

    @Test("uzun repo adi basligi kisaltir, kisa ad uzun birakir") func budgetShifts() {
        let long = String(repeating: "word ", count: 40)
        let short = RowText.parts(for: makeItem(repo: "a/cli", title: long), showOwner: false, now: now)
        let wide  = RowText.parts(for: makeItem(repo: "a/paul-graham-turkce", title: long), showOwner: false, now: now)
        #expect(short.detail.count > wide.detail.count)
    }

    @Test("cok uzun repo adinda bile baslik asgari uzunlugu korur") func minimumTitle() {
        let long = String(repeating: "word ", count: 40)
        let parts = RowText.parts(
            for: makeItem(repo: "org/an-extremely-long-repository-name-here", title: long),
            showOwner: true, now: now
        )
        #expect(parts.detail.count >= RowText.minimumTitle - 4)
    }

    @Test("uzun repo adi kirpilir ama numara hep gorunur") func labelCapped() {
        let parts = RowText.parts(
            for: makeItem(repo: "a/pydantic-agent-template"),
            showOwner: false, now: now
        )
        #expect(parts.label.count <= RowText.labelCap)
        #expect(parts.label.hasSuffix("#55"))
        #expect(parts.label.contains("…"))
    }

    @Test("kisa repo adi kirpilmaz") func labelNotCapped() {
        let parts = RowText.parts(for: makeItem(repo: "a/cli"), showOwner: false, now: now)
        #expect(parts.label == "cli #55")
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
