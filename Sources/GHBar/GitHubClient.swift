import Foundation

struct GitHubClient {

    static let endpoint = URL(string: "https://api.github.com/graphql")!

    /// GitHub aramanin ust siniri. Sayfalama yapilmiyor; sinira dayanan arama
    /// menude uyari satirina donusuyor.
    static let pageSize = 100

    let token: String
    let session: URLSession

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func fetch(_ queries: Queries) async throws -> Snapshot {
        let request = try makeRequest(queries)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppError.network(error.localizedDescription)
        }

        try validate(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)

        do {
            return try ResponseParser.parse(data)
        } catch let error as ParseError {
            switch error {
            case .graphQL(let message):  throw AppError.graphQL(message)
            case .malformed(let detail): throw AppError.parse(detail)
            }
        }
    }

    // MARK: - Ag olmadan test edilebilen parcalar

    func makeRequest(_ queries: Queries) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        // Varsayilan 60 sn cok uzun: takili bir baglanti yenilemeyi bir dakika
        // kilitliyor (isRefreshing true kaldigi icin elle Refresh de calismiyor).
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("GHBar", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "query": Query.document,
            "variables": [
                "prs": queries.prs,
                "issues": queries.issues,
                "review": queries.review,
                "changesRequested": queries.changesRequested,
                "myPullRequests": queries.myPullRequests,
                "first": Self.pageSize,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func validate(statusCode: Int) throws {
        switch statusCode {
        case 200:
            return
        case 401:
            throw AppError.ghNotAuthenticated
        case 403, 429:
            // Gercek sifirlanma zamani cevap basliklarinda geliyor; Asama 1'de
            // bir saat sonrasi yeterince iyi bir tahmin.
            throw AppError.rateLimited(Date().addingTimeInterval(3600))
        default:
            throw AppError.network("HTTP \(statusCode)")
        }
    }
}
