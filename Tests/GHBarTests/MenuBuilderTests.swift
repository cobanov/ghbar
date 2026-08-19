import AppKit
import Foundation
import Testing
@testable import GHBar

@Suite("MenuBuilder")
struct MenuBuilderTests {

    @Test("basarili bos sonuc her bolumu None ile gosterir")
    @MainActor
    func emptySections() {
        let menu = makeMenu(sections: [])
        let titles = menu.items.map(\.title)

        #expect(titles.contains("Pull Requests"))
        #expect(titles.contains("Issues"))
        #expect(titles.contains("Review Requested"))
        #expect(titles.contains("Changes Requested"))
        #expect(titles.filter { $0 == "None" }.count == 4)
        #expect(!titles.contains("Nothing waiting"))
    }

    @Test("dolu bolum satirlari, bos bolumler None gosterir")
    @MainActor
    func mixedSections() {
        let item = Item(
            kind: .pullRequest,
            repository: "alice/webapp",
            number: 42,
            title: "Fix menu",
            url: "https://github.com/alice/webapp/pull/42",
            createdAt: Date(),
            isDraft: false,
            authorLogin: "bob",
            authorIsBot: false
        )
        let section = MenuSection(
            kind: .pullRequests,
            rows: [.item(item)],
            truncated: false
        )

        let titles = makeMenu(sections: [section]).items.map(\.title)
        #expect(titles.filter { $0 == "None" }.count == 3)
        #expect(titles.filter { $0 == "Mark All as Seen" }.count == 1)
    }

    @Test("gizlenen bolum basligi ve None satiri olusturmaz")
    @MainActor
    func hiddenSection() {
        let visible: Set<SectionKind> = [.pullRequests, .reviewRequested]
        let titles = makeMenu(sections: [], visibleSections: visible).items.map(\.title)

        #expect(titles.contains("Pull Requests"))
        #expect(titles.contains("Review Requested"))
        #expect(!titles.contains("Issues"))
        #expect(!titles.contains("Changes Requested"))
        #expect(titles.filter { $0 == "None" }.count == 2)
    }

    @MainActor
    private func makeMenu(
        sections: [MenuSection],
        visibleSections: Set<SectionKind> = Set(SectionKind.allCases)
    ) -> NSMenu {
        MenuBuilder(target: NSObject()).build(.init(
            viewer: Viewer(login: "alice", name: nil, avatarURL: "x"),
            sections: sections,
            rateLimit: nil,
            errors: [],
            lastRefresh: Date(),
            isSignedOut: false,
            showOwner: false,
            knownOrganizations: [],
            selectedOrganizations: [],
            visibleSections: visibleSections,
            maxRowsPerSection: 5,
            isSeen: { _ in false },
            now: Date()
        ))
    }
}
