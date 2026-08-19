import Foundation

enum ParseError: Error, Equatable {
    case malformed(String)
    case graphQL(String)
}

enum ResponseParser {

    /// GitHub aramanin dondurdugu en fazla sonuc. Bu sayiya dayanan bir arama
    /// kirpilmis demektir ve kullaniciya soylenmesi gerekir.
    static let searchLimit = 100

    static func parse(_ data: Data) throws -> Snapshot {
        let decoded = try? JSONSerialization.jsonObject(with: data)
        guard let root = decoded as? [String: Any] else {
            throw ParseError.malformed("root is not an object")
        }

        if let errors = root["errors"] as? [[String: Any]],
           let message = errors.first?["message"] as? String {
            throw ParseError.graphQL(message)
        }

        guard let payload = root["data"] as? [String: Any] else {
            throw ParseError.malformed("missing data")
        }

        guard let viewerObject = payload["viewer"] as? [String: Any],
              let login = viewerObject["login"] as? String,
              let avatar = viewerObject["avatarUrl"] as? String else {
            throw ParseError.malformed("missing viewer")
        }
        let orgNodes = (viewerObject["organizations"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let viewer = Viewer(
            login: login,
            name: viewerObject["name"] as? String,
            avatarURL: avatar,
            organizations: orgNodes.compactMap { $0["login"] as? String }
        )

        var truncated: Set<SectionKind> = []

        func search(_ key: String, kind: ItemKind, section: SectionKind) throws -> [Item] {
            guard let object = payload[key] as? [String: Any] else {
                throw ParseError.malformed("missing \(key)")
            }
            if let count = object["issueCount"] as? Int, count >= searchLimit {
                truncated.insert(section)
            }
            let nodes = object["nodes"] as? [[String: Any]] ?? []
            return nodes.compactMap { item(from: $0, kind: kind) }
        }

        let prs    = try search("prs",    kind: .pullRequest, section: .pullRequests)
        let issues = try search("issues", kind: .issue,       section: .issues)
        let review = try search("review", kind: .pullRequest, section: .reviewRequested)
        let changesRequested = try search(
            "changesRequested",
            kind: .pullRequest,
            section: .changesRequested
        )

        guard let limitObject = payload["rateLimit"] as? [String: Any],
              let limit = limitObject["limit"] as? Int,
              let remaining = limitObject["remaining"] as? Int,
              let resetString = limitObject["resetAt"] as? String,
              let resetAt = parseDate(resetString) else {
            throw ParseError.malformed("missing rateLimit")
        }

        return Snapshot(
            viewer: viewer,
            prs: prs,
            issues: issues,
            review: review,
            changesRequested: changesRequested,
            rateLimit: RateLimit(limit: limit, remaining: remaining, resetAt: resetAt),
            truncated: truncated
        )
    }

    // MARK: - Private

    /// Deger tipi bir bicimlendirici: ISO8601DateFormatter bir sinif ve Sendable
    /// degil, bu yuzden Swift 6'da statik olarak tutulamiyor. ISO8601FormatStyle
    /// bir struct ve paylasilan degisebilir durum tasimiyor.
    private static let iso = Date.ISO8601FormatStyle()

    private static func parseDate(_ string: String) -> Date? {
        try? iso.parse(string)
    }

    /// Yazari olmayan oge (silinmis hesap) nil doner ve listeden dusurulur:
    /// kime ait oldugu belli olmayan bir satir gostermenin anlami yok.
    private static func item(from node: [String: Any], kind: ItemKind) -> Item? {
        guard let number = node["number"] as? Int,
              let title = node["title"] as? String,
              let url = node["url"] as? String,
              let createdString = node["createdAt"] as? String,
              let createdAt = parseDate(createdString),
              let repositoryObject = node["repository"] as? [String: Any],
              let repository = repositoryObject["nameWithOwner"] as? String,
              let authorObject = node["author"] as? [String: Any],
              let authorLogin = authorObject["login"] as? String
        else { return nil }

        // GitHub botlari iki bicimde gonderiyor: __typename "Bot", ya da login
        // sonunda "[bot]". Ikisini de yakalamak gerekiyor.
        let isBot = (authorObject["__typename"] as? String) == "Bot"
            || authorLogin.hasSuffix("[bot]")

        return Item(
            kind: kind,
            repository: repository,
            number: number,
            title: title,
            url: url,
            createdAt: createdAt,
            isDraft: node["isDraft"] as? Bool ?? false,
            authorLogin: authorLogin,
            authorIsBot: isBot
        )
    }
}
