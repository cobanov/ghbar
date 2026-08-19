import AppKit
import Foundation
import Testing
@testable import GHBar

@Suite("MenuBuilder")
struct MenuBuilderTests {

    @Test("bos sonuc tek satira iner, baslik birakmaz")
    @MainActor
    func emptySections() {
        let titles = makeMenu(sections: []).items.map(\.title)

        #expect(titles.contains("You're all caught up"))
        #expect(!titles.contains("None"))
        #expect(!titles.contains("Pull Requests"))
        #expect(!titles.contains("Issues"))
        #expect(!titles.contains("Review Requested"))
        #expect(!titles.contains("Changes Requested"))
        #expect(!titles.contains("My Pull Requests"))
    }

    @Test("ayar acikken bos bolumler None ile korunur")
    @MainActor
    func emptySectionsKeptWhenRequested() {
        let titles = makeMenu(sections: [], showEmptySections: true).items.map(\.title)

        #expect(titles.contains("Pull Requests"))
        #expect(titles.contains("My Pull Requests"))
        #expect(titles.filter { $0 == "None" }.count == 5)
        #expect(!titles.contains("You're all caught up"))
    }

    @Test("ayar acik ama tum bolumler gizliyken yine tek satir kalir")
    @MainActor
    func caughtUpWhenEverythingHidden() {
        let titles = makeMenu(sections: [], visibleSections: [], showEmptySections: true)
            .items.map(\.title)
        #expect(titles.contains("You're all caught up"))
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
        #expect(titles.contains("Pull Requests"))
        #expect(!titles.contains("None"))
        #expect(!titles.contains("You're all caught up"))
        #expect(titles.filter { $0 == "Mark All as Seen" }.count == 1)
    }

    @Test("ayar acikken gizlenen bolum yine hic cizilmez")
    @MainActor
    func hiddenSection() {
        let visible: Set<SectionKind> = [.pullRequests, .reviewRequested]
        let titles = makeMenu(sections: [], visibleSections: visible, showEmptySections: true)
            .items.map(\.title)

        #expect(titles.contains("Pull Requests"))
        #expect(titles.contains("Review Requested"))
        #expect(!titles.contains("Issues"))
        #expect(!titles.contains("Changes Requested"))
        #expect(!titles.contains("My Pull Requests"))
        #expect(titles.filter { $0 == "None" }.count == 2)
    }

    @Test("yenileme surerken durum satiri gorunur")
    @MainActor
    func refreshingRow() {
        #expect(makeMenu(sections: [], isRefreshing: true).items.map(\.title).contains("Refreshing…"))
        #expect(!makeMenu(sections: []).items.map(\.title).contains("Refreshing…"))
    }

    @MainActor
    private func makeMenu(
        sections: [MenuSection],
        visibleSections: Set<SectionKind> = Set(SectionKind.allCases),
        showEmptySections: Bool = false,
        isRefreshing: Bool = false
    ) -> NSMenu {
        MenuBuilder(target: NSObject()).build(.init(
            viewer: Viewer(login: "alice", name: nil, avatarURL: "x"),
            sections: sections,
            rateLimit: nil,
            errors: [],
            lastRefresh: Date(),
            isSignedOut: false,
            isRefreshing: isRefreshing,
            showOwner: false,
            knownOrganizations: [],
            selectedOrganizations: [],
            visibleSections: visibleSections,
            showEmptySections: showEmptySections,
            maxRowsPerSection: 5,
            isSeen: { _ in false },
            now: Date()
        ))
    }
}
