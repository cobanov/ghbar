import Testing
import Foundation
@testable import GHBar

private func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
    return try Data(contentsOf: url)
}

@Suite("ResponseParser")
struct ResponseParserTests {

    @Test("gercek bicimli cevabi cozer") func parsesFixture() throws {
        let snap = try ResponseParser.parse(fixture("response"))

        #expect(snap.viewer.login == "alice")
        #expect(snap.viewer.name == "Alice Smith")
        #expect(snap.viewer.organizations == ["acme"])
        #expect(snap.prs.count == 4)
        #expect(snap.issues.count == 1)   // yazari null olan atildi
        #expect(snap.review.count == 1)
        #expect(snap.changesRequested.count == 1)
        #expect(snap.myPullRequests.count == 2)
        #expect(snap.rateLimit.remaining == 4911)
    }

    @Test("bot bayragi __typename'den okunur") func botFlag() throws {
        let snap = try ResponseParser.parse(fixture("response"))
        #expect(snap.prs.first { $0.number == 56 }?.authorIsBot == true)
        #expect(snap.prs.first { $0.number == 55 }?.authorIsBot == false)
    }

    @Test("login sonu [bot] ise de bot sayilir") func botSuffix() throws {
        let json = """
        {"data":{"viewer":{"login":"a","name":null,"avatarUrl":"x"},
          "prs":{"issueCount":1,"nodes":[{"number":1,"title":"t","url":"u",
            "createdAt":"2026-08-18T07:00:00Z","isDraft":false,
            "author":{"login":"renovate[bot]","__typename":"User"},
            "repository":{"nameWithOwner":"a/b"}}]},
          "issues":{"issueCount":0,"nodes":[]},
          "review":{"issueCount":0,"nodes":[]},
          "changesRequested":{"issueCount":0,"nodes":[]},
          "myPullRequests":{"issueCount":0,"nodes":[]},
          "rateLimit":{"limit":5000,"remaining":1,"resetAt":"2026-08-18T13:00:00Z"}}}
        """.data(using: .utf8)!
        let snap = try ResponseParser.parse(json)
        #expect(snap.prs.first?.authorIsBot == true)
    }

    @Test("organizations yoksa bos liste, cokmez") func missingOrganizations() throws {
        let json = """
        {"data":{"viewer":{"login":"a","name":null,"avatarUrl":"x"},
          "prs":{"issueCount":0,"nodes":[]},
          "issues":{"issueCount":0,"nodes":[]},
          "review":{"issueCount":0,"nodes":[]},
          "changesRequested":{"issueCount":0,"nodes":[]},
          "myPullRequests":{"issueCount":0,"nodes":[]},
          "rateLimit":{"limit":5000,"remaining":1,"resetAt":"2026-08-18T13:00:00Z"}}}
        """.data(using: .utf8)!
        let snap = try ResponseParser.parse(json)
        #expect(snap.viewer.organizations == [])
    }

    @Test("issueCount 100'e dayaninca kirpilma bayragi kalkar") func truncation() throws {
        let json = """
        {"data":{"viewer":{"login":"a","name":null,"avatarUrl":"x"},
          "prs":{"issueCount":140,"nodes":[]},
          "issues":{"issueCount":3,"nodes":[]},
          "review":{"issueCount":0,"nodes":[]},
          "changesRequested":{"issueCount":100,"nodes":[]},
          "myPullRequests":{"issueCount":0,"nodes":[]},
          "rateLimit":{"limit":5000,"remaining":1,"resetAt":"2026-08-18T13:00:00Z"}}}
        """.data(using: .utf8)!
        let snap = try ResponseParser.parse(json)
        #expect(snap.truncated.contains(.pullRequests))
        #expect(!snap.truncated.contains(.issues))
        #expect(snap.truncated.contains(.changesRequested))
    }

    @Test("GraphQL hatasi tasinir") func graphQLError() throws {
        let json = #"{"errors":[{"message":"Bad credentials"}]}"#.data(using: .utf8)!
        #expect(throws: ParseError.graphQL("Bad credentials")) {
            try ResponseParser.parse(json)
        }
    }

    @Test("bozuk JSON hata verir, cokmez") func malformed() throws {
        #expect(throws: (any Error).self) {
            try ResponseParser.parse(Data("not json".utf8))
        }
    }
}
