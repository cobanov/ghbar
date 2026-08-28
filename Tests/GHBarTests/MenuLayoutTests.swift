import Testing
import Foundation
@testable import GHBar

private func section(_ kind: SectionKind, rows count: Int) -> MenuSection {
    let rows = (0..<count).map { index in
        Row.item(Item(
            kind: .pullRequest,
            repository: "alice/webapp",
            number: index,
            title: "Title \(index)",
            url: "https://github.com/alice/webapp/pull/\(index)",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            isDraft: false,
            authorLogin: "bob",
            authorIsBot: false
        ))
    }
    return MenuSection(kind: kind, rows: rows, truncated: false)
}

private func plan(_ sections: [MenuSection], budget: Int = 24, cap: Int = 5, minimum: Int = 1)
    -> [SectionPlan] {
    MenuLayout.plan(sections, workRowBudget: budget, cap: cap, minimum: minimum)
}

@Suite("MenuLayout")
struct MenuLayoutTests {

    @Test("bolum yoksa plan bos doner") func noSections() {
        #expect(plan([]).isEmpty)
    }

    @Test("tavanin altindaki bolum oldugu gibi gosterilir") func fitsUnderCap() {
        let plans = plan([section(.pullRequests, rows: 3)])
        #expect(plans[0].visible.count == 3)
        #expect(plans[0].overflow.isEmpty)
    }

    @Test("tek bolum tavani asamaz") func capBinds() {
        let plans = plan([section(.pullRequests, rows: 40)])
        #expect(plans[0].visible.count == 5)
        #expect(plans[0].overflow.count == 35)
    }

    @Test("bes dolu bolum butceyi asmaz") func budgetBinds() {
        let sections = SectionKind.allCases.map { section($0, rows: 40) }
        let plans = plan(sections)

        let bodyRows = plans.reduce(0) { $0 + $1.visible.count }
        let overflowRows = plans.filter { !$0.overflow.isEmpty }.count
        // Govde + "N more…" + baslik + Mark All as Seen, bolum basina.
        let total = bodyRows + overflowRows + 2 * plans.count
        #expect(total <= 24)
        #expect(plans.allSatisfy { !$0.visible.isEmpty })
    }

    @Test("kalabalik bolum alttakini yutmaz") func roundRobinFairness() {
        let plans = plan([
            section(.pullRequests, rows: 200),
            section(.issues, rows: 3),
        ])
        #expect(plans[1].visible.count == 3)
        #expect(plans[1].overflow.isEmpty)
    }

    @Test("bolum sayisi artinca govdeler kisalir") func budgetIsGlobal() {
        let two = plan([section(.pullRequests, rows: 40), section(.issues, rows: 40)])
        let five = plan(SectionKind.allCases.map { section($0, rows: 40) })

        let twoBody = two.reduce(0) { $0 + $1.visible.count }
        let fiveBody = five.reduce(0) { $0 + $1.visible.count }
        #expect(fiveBody < twoBody)
    }

    @Test("her bolum en az bir satir alir") func minimumHonoured() {
        let sections = SectionKind.allCases.map { section($0, rows: 40) }
        #expect(plan(sections, budget: 1).allSatisfy { $0.visible.count >= 1 })
    }

    @Test("tek ogelik artik icin 1 more satiri harcanmaz") func avoidsSingleOverflow() {
        // Butce 6'ya izin verse de tavan 5; artan tek oge "1 more…" yerine
        // dogrudan gosterilir cunku ikisi de ayni satiri kapliyor.
        let plans = plan([section(.pullRequests, rows: 4)], budget: 8, cap: 5, minimum: 3)
        #expect(plans[0].visible.count == 4)
        #expect(plans[0].overflow.isEmpty)
    }

    @Test("gorunen ve artan satirlar bolumun tamamini verir") func partitionIsTotal() {
        let sections = SectionKind.allCases.map { section($0, rows: 17) }
        for entry in plan(sections) {
            #expect(entry.visible.count + entry.overflow.count == entry.section.rows.count)
        }
    }
}
