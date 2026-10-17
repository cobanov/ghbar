import Testing
import Foundation
@testable import GHBar

private let sampleQueries = Queries(
    prs: "P", issues: "I", assignedIssues: "A", review: "R",
    changesRequested: "C", myPullRequests: "M",
    filtersDropped: false, allowListEmpty: false
)

@Suite("GitHubClient")
struct GitHubClientTests {

    @Test("istek dogru bicimde kurulur") func requestShape() throws {
        let client = GitHubClient(token: "secret-token")
        let request = try client.makeRequest(sampleQueries)

        #expect(request.url?.absoluteString == "https://api.github.com/graphql")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(request.timeoutInterval == 15)

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let variables = body["variables"] as! [String: Any]
        #expect(variables["prs"] as? String == "P")
        #expect(variables["issues"] as? String == "I")
        #expect(variables["assignedIssues"] as? String == "A")
        #expect(variables["review"] as? String == "R")
        #expect(variables["changesRequested"] as? String == "C")
        #expect(variables["myPullRequests"] as? String == "M")
        #expect(variables["first"] as? Int == 100)
    }

    @Test("401 oturum hatasina cevrilir") func unauthorized() throws {
        let client = GitHubClient(token: "bad")
        #expect(throws: AppError.unauthorized) {
            try client.validate(statusCode: 401)
        }
    }

    @Test("403 is a rate limit only when the headers say so") func rateLimited() throws {
        let client = GitHubClient(token: "t")
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(throws: AppError.rateLimited(Date(timeIntervalSince1970: 1_060))) {
            try client.validate(statusCode: 403, headers: ["retry-after": "60"], now: now)
        }
        #expect(throws: AppError.rateLimited(Date(timeIntervalSince1970: 5_000))) {
            try client.validate(statusCode: 403, headers: ["x-ratelimit-remaining": "0",
                                                           "x-ratelimit-reset": "5000"], now: now)
        }
        #expect(throws: AppError.forbidden) {
            try client.validate(statusCode: 403, headers: [:], now: now)
        }
    }

    @Test("200 gecer") func ok() throws {
        let client = GitHubClient(token: "t")
        try client.validate(statusCode: 200)
    }
}
