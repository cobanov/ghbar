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

        let http = response as? HTTPURLResponse
        try validate(statusCode: http?.statusCode ?? 0, headers: Self.headers(http))

        do {
            return try ResponseParser.parse(data)
        } catch let error as ParseError {
            switch error {
            case .graphQL(let message):  throw AppError.graphQL(message)
            case .malformed(let detail): throw AppError.parse(detail)
            case .rateLimited:           throw AppError.rateLimited(Self.resetDate(Self.headers(http)))
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
                "assignedIssues": queries.assignedIssues,
                "review": queries.review,
                "changesRequested": queries.changesRequested,
                "myPullRequests": queries.myPullRequests,
                "first": Self.pageSize,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// - Parameter headers: lower-cased response headers.
    func validate(statusCode: Int, headers: [String: String] = [:], now: Date = Date()) throws {
        switch statusCode {
        case 200:
            return
        case 401:
            throw AppError.unauthorized
        case 403, 429:
            // A 403 is a rate limit only when GitHub says so: no requests left, or a
            // retry-after for the secondary limit. Otherwise it is a refusal (SSO, IP list).
            if statusCode == 429 || headers["x-ratelimit-remaining"] == "0" || headers["retry-after"] != nil {
                throw AppError.rateLimited(Self.resetDate(headers, now: now))
            }
            throw AppError.forbidden
        default:
            throw AppError.network("HTTP \(statusCode)")
        }
    }

    /// When requests may start again: retry-after seconds, else x-ratelimit-reset, else an hour.
    static func resetDate(_ headers: [String: String], now: Date = Date()) -> Date {
        if let seconds = headers["retry-after"].flatMap(TimeInterval.init) {
            return now.addingTimeInterval(seconds)
        }
        if let epoch = headers["x-ratelimit-reset"].flatMap(TimeInterval.init) {
            return Date(timeIntervalSince1970: epoch)
        }
        return now.addingTimeInterval(3600)
    }

    private static func headers(_ response: HTTPURLResponse?) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in response?.allHeaderFields ?? [:] {
            if let key = key as? String, let value = value as? String { result[key.lowercased()] = value }
        }
        return result
    }
}
