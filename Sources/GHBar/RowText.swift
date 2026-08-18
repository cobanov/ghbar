import Foundation

enum RowText {

    static let titleLimit = 48

    /// Tek hesap izleniyorsa her satirda kendi adini tekrar gormek gereksiz
    /// gurultu; sahip adi yalnizca birden fazla hesap izlenirken yazilir.
    static func parts(for item: Item, showOwner: Bool, now: Date)
        -> (label: String, detail: String, age: String)
    {
        (
            label: "\(showOwner ? item.repository : item.repositoryName) #\(item.number)",
            detail: Formatting.truncate(item.title, limit: titleLimit),
            age: Formatting.age(of: item.createdAt, now: now)
        )
    }

    static func groupLabel(repository: String, count: Int, kind: ItemKind, showOwner: Bool) -> String {
        let name = showOwner
            ? repository
            : (repository.split(separator: "/").last.map(String.init) ?? repository)

        let noun: String
        switch (kind, count) {
        case (.issue, 1):       noun = "issue"
        case (.issue, _):       noun = "issues"
        case (.pullRequest, 1): noun = "pull request"
        case (.pullRequest, _): noun = "pull requests"
        }
        return "\(name) — \(count) \(noun)"
    }
}
