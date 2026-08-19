import Foundation
import Defaults

/// Tum ayar anahtarlari tek yerde (spec §8). Anahtar adlari diskte
/// UserDefaults alan adi olur; degistirmek kullanicinin ayarini sifirlar.
extension Defaults.Keys {
    static let accounts = Key<[String]>("accounts", default: ["@me"])
    static let organizations = Key<[String]>("organizations", default: [])
    /// Uyelik listesi; Ayarlar ve menu secicisi bundan dolar. Her yenilemede
    /// `viewer.organizations` ile guncellenir.
    static let knownOrganizations = Key<[String]>("knownOrganizations", default: [])
    static let repoList = Key<[String]>("repoList", default: [])
    static let repoListIsAllowList = Key<Bool>("repoListIsAllowList", default: false)
    static let showBots = Key<Bool>("showBots", default: false)
    static let showDrafts = Key<Bool>("showDrafts", default: true)
    static let showPullRequests = Key<Bool>("showPullRequests", default: true)
    static let showIssues = Key<Bool>("showIssues", default: true)
    static let showReviewRequested = Key<Bool>("showReviewRequested", default: true)
    static let showChangesRequested = Key<Bool>("showChangesRequested", default: true)
    static let refreshMinutes = Key<Int>("refreshMinutes", default: 5)
    static let repoGroupThreshold = Key<Int>("repoGroupThreshold", default: 3)
    static let notificationsEnabled = Key<Bool>("notificationsEnabled", default: true)
    /// Son cekimlerde oge ureten repolar (repo -> oge sayisi). Ayarlar >
    /// Repositories bu listeden dolar; kullanici repo adini elle yazmak
    /// zorunda kalmaz (spec §8: yazim hatasi sessizce hicbir seyi filtrelemez).
    static let knownRepos = Key<[String: Int]>("knownRepos", default: [:])
    static let signedInLogin = Key<String?>("signedInLogin", default: nil)
    static let includePrivateRepos = Key<Bool>("includePrivateRepos", default: true)
}

extension Settings {
    /// Saf Settings struct'i korunur: Query/Filtering test edilebilir kalir,
    /// Defaults yalnizca kenarda okunur.
    static func fromDefaults() -> Settings {
        var settings = Settings()
        let accounts = Defaults[.accounts].filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        settings.accounts = accounts.isEmpty ? ["@me"] : accounts
        settings.organizations = Defaults[.organizations].filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        settings.repoList = Defaults[.repoList]
        settings.repoListIsAllowList = Defaults[.repoListIsAllowList]
        settings.showBots = Defaults[.showBots]
        settings.showDrafts = Defaults[.showDrafts]
        settings.showPullRequests = Defaults[.showPullRequests]
        settings.showIssues = Defaults[.showIssues]
        settings.showReviewRequested = Defaults[.showReviewRequested]
        settings.showChangesRequested = Defaults[.showChangesRequested]
        settings.repoGroupThreshold = Defaults[.repoGroupThreshold]
        return settings
    }

    /// Zamanlayici araligi, saniye. Taban 1 dakika: 0 veya negatif deger
    /// kendini bogan bir dongu yaratirdi.
    static func refreshInterval() -> TimeInterval {
        TimeInterval(max(1, Defaults[.refreshMinutes])) * 60
    }
}
