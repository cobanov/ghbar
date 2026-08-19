import Testing
import Foundation
@testable import GHBar

private let sampleQueries = Queries(
    prs: "P", issues: "I", review: "R",
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
        #expect(variables["review"] as? String == "R")
        #expect(variables["first"] as? Int == 100)
    }

    @Test("401 oturum hatasina cevrilir") func unauthorized() throws {
        let client = GitHubClient(token: "bad")
        #expect(throws: AppError.ghNotAuthenticated) {
            try client.validate(statusCode: 401)
        }
    }

    @Test("403 kota hatasina cevrilir") func rateLimited() throws {
        let client = GitHubClient(token: "t")
        #expect(throws: (any Error).self) {
            try client.validate(statusCode: 403)
        }
    }

    @Test("200 gecer") func ok() throws {
        let client = GitHubClient(token: "t")
        try client.validate(statusCode: 200)
    }
}
