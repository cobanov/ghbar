import Foundation

/// Kota satiri menude ne zaman gorunsun.
enum RateLimitVisibility: String, Sendable, CaseIterable {
    case never
    case whenLow
    case always

    /// Gostergenin turuncuya dondugu esik; sayinin eyleme donustugu nokta.
    static let lowThreshold = 0.25

    func shows(_ limit: RateLimit) -> Bool {
        switch self {
        case .never:   false
        case .whenLow: limit.fraction < Self.lowThreshold
        case .always:  true
        }
    }
}

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
    /// Bos bolumu basligiyla ve "None" satiriyla goster.
    var showEmptySections: Bool = false
    var repoGroupThreshold: Int = 3
    /// Menunun bolum satirlarina ayirdigi toplam butce.
    var menuRowBudget: Int = 24
    var rateLimitVisibility: RateLimitVisibility = .whenLow
    /// Tek bir bolumun tavani; butce bol olsa da bir bolum menuyu ele
    /// gecirmesin.
    var maxRowsPerSection: Int = 5
    var minRowsPerSection: Int = 1

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
