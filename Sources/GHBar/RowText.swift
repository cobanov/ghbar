import Foundation

enum RowText {

    /// Bir satirda etiket + baslik icin toplam karakter butcesi.
    ///
    /// Menu genisligini en uzun satir belirliyor ve NSMenu'nun ayri bir
    /// genislik ayari yok. Basliga sabit bir sinir koymak yetmiyor cunku
    /// satirin obur yarisi olan repo adi degisken: "paul-graham-turkce #96"
    /// tek basina 22 karakter. Butceyi toplama koyunca uzun repo adli
    /// satirda baslik kendiliginde kisaliyor ve butun satirlar ayni
    /// genislikte oluyor.
    ///
    /// Menuyu darlastirmak/genisletmek icin degistirilecek tek sayi budur.
    static let rowBudget = 34

    /// Baslik bundan kisaya dusurulmez; asagisinda hicbir sey anlatmiyor.
    static let minimumTitle = 12

    /// Repo adi + numara icin ust sinir. Olmadiginda tek bir uzun repo adi
    /// ("pydantic-agent-template #2" = 26 karakter) butun butceyi yiyor ve
    /// basliga hicbir sey kalmiyor.
    static let labelCap = 20

    /// Tek hesap izleniyorsa her satirda kendi adini tekrar gormek gereksiz
    /// gurultu; sahip adi yalnizca birden fazla hesap izlenirken yazilir.
    static func parts(for item: Item, showOwner: Bool, now: Date)
        -> (label: String, detail: String, age: String)
    {
        // Numara her zaman gorunmeli — kirpma yalnizca repo adina uygulanir.
        let name = showOwner ? item.repository : item.repositoryName
        let suffix = " #\(item.number)"
        let nameRoom = max(6, labelCap - suffix.count)
        let label = (name.count > nameRoom ? "\(name.prefix(nameRoom - 1))…" : name) + suffix

        let allowance = max(minimumTitle, rowBudget - label.count)

        return (
            label: label,
            detail: Formatting.truncate(item.title, limit: allowance),
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
