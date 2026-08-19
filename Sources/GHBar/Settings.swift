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
    var repoGroupThreshold: Int = 3
    var maxRowsPerSection: Int = 5

    static let `default` = Settings()
}
