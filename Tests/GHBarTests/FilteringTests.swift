import Testing
import Foundation
@testable import GHBar

private func makeItem(
    _ number: Int,
    repo: String = "alice/webapp",
    kind: ItemKind = .pullRequest,
    bot: Bool = false,
    draft: Bool = false,
    minutesAgo: Int = 0
) -> Item {
    Item(
        kind: kind,
        repository: repo,
        number: number,
        title: "Title \(number)",
        url: "https://github.com/\(repo)/pull/\(number)",
        createdAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(minutesAgo * 60)),
        isDraft: draft,
        authorLogin: bot ? "dependabot" : "bob",
        authorIsBot: bot
    )
}

private func snapshot(
    prs: [Item] = [],
    issues: [Item] = [],
    review: [Item] = [],
    changesRequested: [Item] = [],
    myPullRequests: [Item] = [],
    truncated: Set<SectionKind> = []
) -> Snapshot {
    Snapshot(
        viewer: Viewer(login: "alice", name: nil, avatarURL: "x"),
        prs: prs, issues: issues, review: review,
        changesRequested: changesRequested,
        myPullRequests: myPullRequests,
        rateLimit: RateLimit(limit: 5000, remaining: 5000, resetAt: Date()),
        truncated: truncated
    )
}

@Suite("Filtering")
struct FilteringTests {

    @Test("botlar varsayilan olarak elenir") func removesBots() {
        let snap = snapshot(prs: [makeItem(1), makeItem(2, bot: true)])
        let sections = Filtering.sections(from: snap, settings: .default)
        #expect(sections.first { $0.kind == .pullRequests }?.items.map(\.number) == [1])
    }

    @Test("showBots acikken botlar kalir") func keepsBots() {
        var s = Settings.default
        s.showBots = true
        let snap = snapshot(prs: [makeItem(1), makeItem(2, bot: true)])
        let sections = Filtering.sections(from: snap, settings: s)
        #expect(sections.first { $0.kind == .pullRequests }?.items.count == 2)
    }

    @Test("showDrafts kapaliyken taslaklar elenir") func hidesDrafts() {
        var s = Settings.default
        s.showDrafts = false
        let snap = snapshot(prs: [makeItem(1), makeItem(2, draft: true)])
        let sections = Filtering.sections(from: snap, settings: s)
        #expect(sections.first { $0.kind == .pullRequests }?.items.map(\.number) == [1])
    }

    @Test("ayni PR hem prs hem review'daysa yalniz Review Requested'da cikar") func dedup() {
        let shared = makeItem(204, repo: "acme/backend")
        let snap = snapshot(prs: [makeItem(1), shared], review: [shared])
        let sections = Filtering.sections(from: snap, settings: .default)

        #expect(sections.first { $0.kind == .pullRequests }?.items.map(\.number) == [1])
        #expect(sections.first { $0.kind == .reviewRequested }?.items.map(\.number) == [204])
    }

    @Test("Changes Requested ayni PR'in diger bolumlerdeki kopyalarini eler")
    func changesRequestedWins() {
        let shared = makeItem(204, repo: "acme/backend")
        let snap = snapshot(
            prs: [makeItem(1), shared],
            review: [shared],
            changesRequested: [shared]
        )
        let sections = Filtering.sections(from: snap, settings: .default)

        #expect(sections.first { $0.kind == .pullRequests }?.items.map(\.number) == [1])
        #expect(sections.first { $0.kind == .reviewRequested } == nil)
        #expect(sections.first { $0.kind == .changesRequested }?.items.map(\.number) == [204])
    }

    @Test("kendi PR'lari ayri bolume dusr") func myPullRequestsSection() {
        let mine = makeItem(91, repo: "other/project")
        let snap = snapshot(prs: [makeItem(1)], myPullRequests: [mine])
        let sections = Filtering.sections(from: snap, settings: .default)

        #expect(sections.map(\.kind) == [.pullRequests, .myPullRequests])
        #expect(sections.first { $0.kind == .myPullRequests }?.items.map(\.number) == [91])
    }

    @Test("degisiklik istenen PR My Pull Requests'te tekrar etmez")
    func changesRequestedOutranksMine() {
        let shared = makeItem(88)
        let snap = snapshot(changesRequested: [shared], myPullRequests: [shared, makeItem(91)])
        let sections = Filtering.sections(from: snap, settings: .default)

        #expect(sections.first { $0.kind == .changesRequested }?.items.map(\.number) == [88])
        #expect(sections.first { $0.kind == .myPullRequests }?.items.map(\.number) == [91])
    }

    @Test("kendine atadigi PR yalniz Pull Requests'te cikar") func assignedOutranksMine() {
        let shared = makeItem(42)
        let snap = snapshot(prs: [shared], myPullRequests: [shared])
        let sections = Filtering.sections(from: snap, settings: .default)

        #expect(sections.map(\.kind) == [.pullRequests])
    }

    @Test("en yeni ustte siralanir") func sorting() {
        let snap = snapshot(prs: [
            makeItem(1, minutesAgo: 500),
            makeItem(2, minutesAgo: 10),
            makeItem(3, minutesAgo: 100),
        ])
        let sections = Filtering.sections(from: snap, settings: .default)
        #expect(sections.first { $0.kind == .pullRequests }?.items.map(\.number) == [2, 3, 1])
    }

    @Test("esigin ustundeki repo tek satira toplanir") func grouping() {
        var s = Settings.default
        s.repoGroupThreshold = 3
        let noisy = (1...5).map { makeItem($0, repo: "alice/noisy", kind: .issue) }
        let quiet = [makeItem(90, repo: "alice/webapp", kind: .issue)]
        let snap = snapshot(issues: noisy + quiet)

        let section = Filtering.sections(from: snap, settings: s).first { $0.kind == .issues }!
        let groups = section.rows.compactMap { row -> String? in
            if case .group(let repo, _) = row { return repo }
            return nil
        }
        let singles = section.rows.compactMap { row -> Int? in
            if case .item(let i) = row { return i.number }
            return nil
        }
        #expect(groups == ["alice/noisy"])
        #expect(singles == [90])
    }

    @Test("esigin altindaki repo toplanmaz") func noGroupingBelowThreshold() {
        var s = Settings.default
        s.repoGroupThreshold = 3
        let snap = snapshot(issues: (1...3).map { makeItem($0, repo: "alice/webapp", kind: .issue) })
        let section = Filtering.sections(from: snap, settings: s).first { $0.kind == .issues }!
        #expect(section.rows.count == 3)
        #expect(section.rows.allSatisfy { if case .item = $0 { true } else { false } })
    }

    @Test("bos bolum listeye hic girmez") func dropsEmptySections() {
        let snap = snapshot(prs: [makeItem(1)])
        #expect(Filtering.sections(from: snap, settings: .default).map(\.kind) == [.pullRequests])
    }

    @Test("kullanici tarafindan gizlenen bolum ve ogeleri islenmez")
    func dropsHiddenSections() {
        var settings = Settings.default
        settings.showPullRequests = false
        settings.showIssues = false
        let snap = snapshot(
            prs: [makeItem(1)],
            issues: [makeItem(2, kind: .issue)],
            review: [makeItem(3)]
        )

        let sections = Filtering.sections(from: snap, settings: settings)
        #expect(sections.map(\.kind) == [.reviewRequested])
        #expect(sections.flatMap(\.items).map(\.number) == [3])
    }

    @Test("bolumler aciliyet sirasiyla doner") func urgencyOrder() {
        let snap = snapshot(
            prs: [makeItem(1)],
            issues: [makeItem(2, kind: .issue)],
            review: [makeItem(3)],
            changesRequested: [makeItem(4)],
            myPullRequests: [makeItem(5)]
        )
        #expect(Filtering.sections(from: snap, settings: .default).map(\.kind)
            == [.changesRequested, .reviewRequested, .pullRequests, .issues, .myPullRequests])
    }

    @Test("displayOrder butun bolumleri kapsar") func displayOrderIsComplete() {
        #expect(Set(SectionKind.displayOrder) == Set(SectionKind.allCases))
        #expect(SectionKind.displayOrder.count == SectionKind.allCases.count)
    }

    @Test("kirpilma bayragi bolume tasinir") func carriesTruncation() {
        let snap = snapshot(prs: [makeItem(1)], truncated: [.pullRequests])
        #expect(Filtering.sections(from: snap, settings: .default).first?.truncated == true)
    }
}
