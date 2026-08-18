import Foundation

enum ItemKind: String, Sendable, Hashable {
    case pullRequest
    case issue
}

struct Item: Sendable, Hashable, Identifiable {
    let kind: ItemKind
    let repository: String      // "owner/name"
    let number: Int
    let title: String
    let url: String
    let createdAt: Date
    let isDraft: Bool
    let authorLogin: String
    let authorIsBot: Bool

    var id: String { url }

    /// "owner/name" -> "name"
    var repositoryName: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}

struct Viewer: Sendable, Hashable {
    let login: String
    let name: String?
    let avatarURL: String

    var displayName: String { name ?? login }
    var profileURL: String { "https://github.com/\(login)" }
}

struct RateLimit: Sendable, Hashable {
    let limit: Int
    let remaining: Int
    let resetAt: Date

    var fraction: Double {
        limit > 0 ? Double(remaining) / Double(limit) : 1
    }
}

enum SectionKind: String, Sendable, Hashable, CaseIterable {
    case pullRequests
    case issues
    case reviewRequested

    var title: String {
        switch self {
        case .pullRequests:    "Pull Requests"
        case .issues:          "Issues"
        case .reviewRequested: "Review Requested"
        }
    }
}

/// Menude bir satir: ya tek bir oge, ya ayni repodan toplanmis bir grup.
enum Row: Sendable, Hashable {
    case item(Item)
    case group(repository: String, items: [Item])

    var items: [Item] {
        switch self {
        case .item(let i):        [i]
        case .group(_, let list): list
        }
    }
}

struct Section: Sendable, Hashable {
    let kind: SectionKind
    let rows: [Row]
    let truncated: Bool

    var items: [Item] { rows.flatMap(\.items) }
    var isEmpty: Bool { rows.isEmpty }
}

struct Snapshot: Sendable {
    let viewer: Viewer
    let prs: [Item]
    let issues: [Item]
    let review: [Item]
    let rateLimit: RateLimit
    let truncated: Set<SectionKind>
}
