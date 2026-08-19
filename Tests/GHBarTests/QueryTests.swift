import Testing
@testable import GHBar

@Suite("Query.build")
struct QueryTests {

    @Test("varsayilan ayar @me kullanir, login gerektirmez") func defaults() {
        let q = Query.build(.default)
        #expect(q.prs    == "is:pr is:open user:@me -author:@me")
        #expect(q.issues == "is:issue is:open user:@me -author:@me")
        #expect(q.review == "is:pr is:open review-requested:@me")
        #expect(q.changesRequested == "is:pr is:open author:@me review:changes_requested")
        #expect(q.myPullRequests == "is:pr is:open author:@me")
        #expect(q.filtersDropped == false)
        #expect(q.allowListEmpty == false)
    }

    @Test("secili org user: yerine org: kullanir") func organizationScope() {
        var s = Settings.default
        s.accounts = ["alice"]
        s.organizations = ["acme"]
        let q = Query.build(s)
        #expect(q.prs == "is:pr is:open org:acme assignee:@me")
        #expect(q.issues == "is:issue is:open org:acme assignee:@me")
        #expect(!q.prs.contains("user:"))
        #expect(!q.prs.contains("-author:"))
        #expect(q.review == "is:pr is:open review-requested:@me org:acme")
        #expect(q.changesRequested
            == "is:pr is:open author:@me review:changes_requested org:acme")
        #expect(q.myPullRequests == "is:pr is:open author:@me org:acme")
    }

    @Test("kendi PR'lari hesap kapsamiyla daraltilmaz") func authoredIgnoresAccountScope() {
        var s = Settings.default
        s.accounts = ["alice"]
        let q = Query.build(s)
        // user:alice eklenseydi alice'in baskasinin reposuna actigi PR kaybolurdu.
        #expect(q.myPullRequests == "is:pr is:open author:@me")
        #expect(!q.myPullRequests.contains("user:"))
    }

    @Test("birden fazla org ayni niteleyicide OR olur") func multipleOrganizations() {
        var s = Settings.default
        s.organizations = ["acme", "widgets"]
        let q = Query.build(s)
        #expect(q.prs == "is:pr is:open org:acme org:widgets assignee:@me")
        #expect(q.review == "is:pr is:open review-requested:@me org:acme org:widgets")
    }

    @Test("kara liste org kapsaminda da -repo: ekler") func denyListWithOrg() {
        var s = Settings.default
        s.organizations = ["acme"]
        s.repoList = ["acme/noisy"]
        let q = Query.build(s)
        #expect(q.prs == "is:pr is:open org:acme assignee:@me -repo:acme/noisy")
        #expect(q.review == "is:pr is:open review-requested:@me org:acme -repo:acme/noisy")
        #expect(q.changesRequested
            == "is:pr is:open author:@me review:changes_requested org:acme -repo:acme/noisy")
        #expect(q.myPullRequests == "is:pr is:open author:@me org:acme -repo:acme/noisy")
    }

    @Test("egik cizgisiz repo org seciliyse ilk orgla birlesir") func bareRepoNameUsesOrg() {
        var s = Settings.default
        s.accounts = ["alice"]
        s.organizations = ["acme"]
        s.repoList = ["noisy"]
        let q = Query.build(s)
        #expect(q.prs.contains("-repo:acme/noisy"))
    }

    @Test("beyaz liste org secili olsa da user/org parcalarini birakir") func allowListWinsOverOrg() {
        var s = Settings.default
        s.accounts = ["alice"]
        s.organizations = ["acme"]
        s.repoList = ["acme/one"]
        s.repoListIsAllowList = true
        let q = Query.build(s)
        #expect(q.prs == "is:pr is:open repo:acme/one assignee:@me")
        #expect(!q.prs.contains("org:"))
        #expect(!q.prs.contains("user:"))
        #expect(q.review == "is:pr is:open review-requested:@me org:acme")
        #expect(q.changesRequested
            == "is:pr is:open author:@me review:changes_requested repo:acme/one")
        #expect(q.myPullRequests == "is:pr is:open author:@me repo:acme/one")
    }

    @Test("birden fazla hesap birden fazla user: parcasi verir") func multipleAccounts() {
        var s = Settings.default
        s.accounts = ["alice", "acme"]
        let q = Query.build(s)
        #expect(q.prs == "is:pr is:open user:alice user:acme -author:@me")
    }

    @Test("kara liste -repo: parcalari ekler") func denyList() {
        var s = Settings.default
        s.accounts = ["alice"]
        s.repoList = ["alice/noisy"]
        s.repoListIsAllowList = false
        let q = Query.build(s)
        #expect(q.prs == "is:pr is:open user:alice -author:@me -repo:alice/noisy")
        #expect(q.review == "is:pr is:open review-requested:@me -repo:alice/noisy")
    }

    @Test("egik cizgisiz repo girdisi ilk hesapla birlestirilir") func bareRepoName() {
        var s = Settings.default
        s.accounts = ["alice"]
        s.repoList = ["noisy"]
        let q = Query.build(s)
        #expect(q.prs.contains("-repo:alice/noisy"))
    }

    @Test("beyaz liste repo: kullanir ve user: parcalarini birakir") func allowList() {
        var s = Settings.default
        s.accounts = ["alice"]
        s.repoList = ["alice/one", "alice/two"]
        s.repoListIsAllowList = true
        let q = Query.build(s)
        #expect(q.prs == "is:pr is:open repo:alice/one repo:alice/two -author:@me")
        #expect(!q.prs.contains("user:"))
    }

    @Test("beyaz liste bos ise bayrak kalkar") func allowListEmpty() {
        var s = Settings.default
        s.repoList = []
        s.repoListIsAllowList = true
        let q = Query.build(s)
        #expect(q.allowListEmpty == true)
    }

    @Test("4000 karakteri asan filtre listesi kirpilir ve bayrak kalkar") func lengthCap() {
        var s = Settings.default
        s.accounts = ["alice"]
        s.repoList = (0..<300).map { "alice/repository-with-a-long-name-\($0)" }
        let q = Query.build(s)
        #expect(q.prs.count <= Query.maxLength)
        #expect(q.filtersDropped == true)
    }
}
