import AppKit
import Foundation
import Testing
@testable import GHBar

private func section(_ kind: SectionKind, numbers: [Int]) -> MenuSection {
    let rows = numbers.map { number in
        Row.item(Item(
            kind: .pullRequest,
            repository: "alice/webapp",
            number: number,
            title: "Title \(number)",
            url: "https://github.com/alice/webapp/pull/\(number)",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            isDraft: false,
            authorLogin: "bob",
            authorIsBot: false
        ))
    }
    return MenuSection(kind: kind, rows: rows, truncated: false)
}

private func limit(remaining: Int) -> RateLimit {
    RateLimit(limit: 5_000, remaining: remaining, resetAt: Date(timeIntervalSince1970: 1_800_003_600))
}

@MainActor
private func hasRateLimitRow(_ menu: NSMenu) -> Bool {
    menu.items.contains { $0.attributedTitle?.string.hasPrefix("Rate Limit") == true }
}

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

    @Test("bos menu org filtresini adiyla soyler ve geri almayi sunar")
    @MainActor
    func emptyStateNamesOrganization() {
        let menu = makeMenu(sections: [], selectedOrganizations: ["acme"])
        let titles = menu.items.map(\.title)

        #expect(titles.contains("No open work in acme"))
        #expect(titles.contains("Show All Organizations"))
        #expect(!titles.contains("You're all caught up"))

        let undo = menu.items.first { $0.title == "Show All Organizations" }
        #expect(undo?.isEnabled == true)
    }

    @Test("birden fazla org secildiginde sayiyi soyler")
    @MainActor
    func emptyStateCountsOrganizations() {
        let titles = makeMenu(sections: [], selectedOrganizations: ["acme", "widgets"])
            .items.map(\.title)
        #expect(titles.contains("No open work in 2 organizations"))
    }

    @Test("repo filtresi varken onu soyler") @MainActor
    func emptyStateNamesRepositoryFilter() {
        let titles = makeMenu(sections: [], repositoryFilterActive: true).items.map(\.title)
        #expect(titles.contains("No open work in the watched repositories"))
        #expect(titles.contains("Open Settings…"))
    }

    @Test("org filtresi repo filtresinden once soylenir") @MainActor
    func organizationOutranksRepositoryInEmptyState() {
        let titles = makeMenu(
            sections: [],
            selectedOrganizations: ["acme"],
            repositoryFilterActive: true
        ).items.map(\.title)
        #expect(titles.contains("No open work in acme"))
        #expect(!titles.contains("No open work in the watched repositories"))
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

    @Test("Mark All as Seen tek satir, altbilgide ve Option alternatifiyle")
    @MainActor
    func markAllSeenIsGlobal() {
        let menu = makeMenu(sections: [section(.pullRequests, numbers: [1, 2]),
                                       section(.issues, numbers: [3])])
        let titles = menu.items.map(\.title)

        #expect(titles.filter { $0 == "Mark All as Seen" }.count == 1)

        let index = titles.firstIndex(of: "Mark All as Seen")!
        #expect(titles[index - 1] == "Settings…")

        let alternate = menu.items[index + 1]
        #expect(alternate.title == "Mark as Seen")
        #expect(alternate.isAlternate)
        #expect(alternate.keyEquivalentModifierMask == .option)
        #expect(alternate.submenu?.items.map(\.title) == ["Pull Requests  2", "Issues  1"])
    }

    @Test("gorulmemis oge yoksa isaretleme satiri hic cikmaz")
    @MainActor
    func markAllSeenHiddenWhenNothingUnseen() {
        let menu = makeMenu(sections: [section(.pullRequests, numbers: [1])],
                            isSeen: { _ in true })
        let titles = menu.items.map(\.title)
        #expect(!titles.contains("Mark All as Seen"))
        #expect(!titles.contains("Mark as Seen"))
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

    @Test("kota bol oldugunda satir cizilmez, ipucunda kalir")
    @MainActor
    func rateLimitHiddenWhenPlentiful() {
        let menu = makeMenu(sections: [], rateLimit: limit(remaining: 4_900))

        #expect(!hasRateLimitRow(menu))
        #expect(!menu.items.map(\.title).contains("API"))
        #expect(menu.items.first { $0.title == "Refresh" }?.toolTip
            == "Rate limit 4,900 / 5,000")
    }

    @Test("kota azalinca satir cikar, basliksiz") @MainActor
    func rateLimitShownWhenLow() {
        let menu = makeMenu(sections: [], rateLimit: limit(remaining: 400))
        #expect(hasRateLimitRow(menu))
        #expect(!menu.items.map(\.title).contains("API"))
    }

    @Test("always secildiginde bol kotada da gorunur") @MainActor
    func rateLimitAlways() {
        #expect(hasRateLimitRow(makeMenu(sections: [], rateLimit: limit(remaining: 4_900),
                                         rateLimitVisibility: .always)))
    }

    @Test("never secildiginde az kotada bile gizli") @MainActor
    func rateLimitNever() {
        #expect(!hasRateLimitRow(makeMenu(sections: [], rateLimit: limit(remaining: 10),
                                          rateLimitVisibility: .never)))
    }

    @Test("oge satiri okunmamislik bilgisini metinle de tasir") @MainActor
    func itemRowHasAccessibilityLabel() {
        let unread = makeMenu(sections: [section(.pullRequests, numbers: [55])])
            .items.compactMap { $0.accessibilityLabel() }
            .first { $0.contains("number 55") }
        #expect(unread?.contains("unread") == true)
        #expect(unread?.contains("pull request") == true)
        #expect(unread?.contains("Title 55") == true)
        #expect(unread?.contains("by bob") == true)

        let read = makeMenu(sections: [section(.pullRequests, numbers: [55])],
                            isSeen: { _ in true })
            .items.compactMap { $0.accessibilityLabel() }
            .first { $0.contains("number 55") }
        #expect(read?.hasSuffix("read") == true)
        #expect(read?.contains("unread") == false)
    }

    @Test("organizasyon satiri aktif kapsami sagda gosterir") @MainActor
    func organizationRowShowsActiveScope() {
        func summary(_ selected: [String]) -> String? {
            makeMenu(sections: [], knownOrganizations: ["acme", "widgets", "zeta"],
                     selectedOrganizations: selected)
                .items.compactMap { $0.accessibilityLabel() }
                .first { $0.hasPrefix("Organizations, ") }
        }

        #expect(summary([]) == "Organizations, All")
        #expect(summary(["acme"]) == "Organizations, acme")
        #expect(summary(["widgets", "acme", "zeta"]) == "Organizations, acme +2")
    }

    @Test("Launch at Login menude degil, ayarlarda") @MainActor
    func launchAtLoginNotInMenu() {
        #expect(!makeMenu(sections: []).items.map(\.title).contains("Launch at Login"))
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
        isRefreshing: Bool = false,
        knownOrganizations: [String] = [],
        selectedOrganizations: [String] = [],
        repositoryFilterActive: Bool = false,
        isSeen: @escaping (String) -> Bool = { _ in false },
        rateLimit: RateLimit? = nil,
        rateLimitVisibility: RateLimitVisibility = .whenLow
    ) -> NSMenu {
        MenuBuilder(target: NSObject()).build(.init(
            viewer: Viewer(login: "alice", name: nil, avatarURL: "x"),
            sections: sections,
            rateLimit: rateLimit,
            errors: [],
            lastRefresh: Date(),
            isSignedOut: false,
            isRefreshing: isRefreshing,
            showOwner: false,
            knownOrganizations: knownOrganizations,
            selectedOrganizations: selectedOrganizations,
            repositoryFilterActive: repositoryFilterActive,
            visibleSections: visibleSections,
            showEmptySections: showEmptySections,
            rateLimitVisibility: rateLimitVisibility,
            maxRowsPerSection: 5,
            isSeen: isSeen,
            now: Date()
        ))
    }
}
