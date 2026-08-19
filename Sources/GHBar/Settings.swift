import Foundation

/// Asama 1'de ayarlar sabit. Asama 3'te bu yapi UserDefaults'a baglanacak;
/// alan adlari o zaman degismeyecek sekilde secildi.
struct Settings: Sendable, Equatable {
    var accounts: [String] = ["@me"]
    /// Secili organizasyonlar. Doluysa arama `org:` kullanir; `user:` ile
    /// ayni sorguda AND olur ve sonuc bos kalirdi, bu yuzden hesaplarin
    /// yerine gecer.
    var organizations: [String] = []
    var repoList: [String] = []
    var repoListIsAllowList: Bool = false
    var showBots: Bool = false
    var showDrafts: Bool = true
    var showPullRequests: Bool = true
    var showIssues: Bool = true
    var showReviewRequested: Bool = true
    var showChangesRequested: Bool = true
    var showMyPullRequests: Bool = true
    var repoGroupThreshold: Int = 3
    var maxRowsPerSection: Int = 5

    static let `default` = Settings()

    var visibleSections: Set<SectionKind> {
        var result: Set<SectionKind> = []
        if showPullRequests { result.insert(.pullRequests) }
        if showIssues { result.insert(.issues) }
        if showReviewRequested { result.insert(.reviewRequested) }
        if showChangesRequested { result.insert(.changesRequested) }
        if showMyPullRequests { result.insert(.myPullRequests) }
        return result
    }
}
