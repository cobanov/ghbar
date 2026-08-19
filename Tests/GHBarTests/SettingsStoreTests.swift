import Testing
import Defaults
@testable import GHBar

/// Defaults global durumda yasar; her test kendi anahtarlarini sifirlayarak
/// baslar ve biter, yoksa testler birbirine sizar.
@Suite("Settings.fromDefaults", .serialized)
struct SettingsStoreTests {

    private func resetAll() {
        Defaults.reset(.accounts, .organizations, .knownOrganizations,
                       .repoList, .repoListIsAllowList,
                       .showBots, .showDrafts, .showPullRequests, .showIssues,
                       .showReviewRequested, .showChangesRequested, .showMyPullRequests,
                       .showEmptySections, .menuRowBudget, .rateLimitVisibility,
                       .refreshMinutes,
                       .repoGroupThreshold, .notificationsEnabled)
    }

    @Test("varsayilanlar Asama 1 Settings.default ile ayni") func defaults() {
        resetAll()
        #expect(Settings.fromDefaults() == Settings.default)
    }

    @Test("degerler Defaults'tan okunur") func reads() {
        resetAll()
        defer { resetAll() }
        Defaults[.accounts] = ["alice", "acme"]
        Defaults[.organizations] = ["acme"]
        Defaults[.repoList] = ["alice/noisy"]
        Defaults[.repoListIsAllowList] = true
        Defaults[.showBots] = true
        Defaults[.showDrafts] = false
        Defaults[.showPullRequests] = false
        Defaults[.showIssues] = false
        Defaults[.showReviewRequested] = false
        Defaults[.showChangesRequested] = false
        Defaults[.showMyPullRequests] = false
        Defaults[.showEmptySections] = true
        Defaults[.menuRowBudget] = 32
        Defaults[.rateLimitVisibility] = RateLimitVisibility.always.rawValue
        Defaults[.repoGroupThreshold] = 10

        let s = Settings.fromDefaults()
        #expect(s.accounts == ["alice", "acme"])
        #expect(s.organizations == ["acme"])
        #expect(s.repoList == ["alice/noisy"])
        #expect(s.repoListIsAllowList == true)
        #expect(s.showBots == true)
        #expect(s.showDrafts == false)
        #expect(s.visibleSections.isEmpty)
        #expect(s.showEmptySections == true)
        #expect(s.menuRowBudget == 32)
        #expect(s.rateLimitVisibility == .always)
        #expect(s.repoGroupThreshold == 10)
    }

    @Test("bos hesap listesi @me'ye duser — sorgu hesapsiz kurulamaz") func emptyAccounts() {
        resetAll()
        defer { resetAll() }
        Defaults[.accounts] = []
        #expect(Settings.fromDefaults().accounts == ["@me"])
    }

    @Test("refreshMinutes 1'in altina inmez") func refreshFloor() {
        resetAll()
        defer { resetAll() }
        Defaults[.refreshMinutes] = 0
        #expect(Settings.refreshInterval() >= 60)
    }
}
