import AppKit
import Defaults

/// Yeni surum cikinca bir pencereyle haber verir.
///
/// GitHub'in "latest release" ucuna gunde bir kez bakar; token kullanmaz (saatte
/// 60 kimliksiz istek bu is icin fazlasiyla yeter, kullanicinin kotasindan da
/// yemez). Indirip kurmaz: release sayfasini acar ya da Homebrew komutunu
/// gosterir. Kurulumu yapan install.sh / brew zaten imzayi dogruluyor.
///
/// MAS varyantinda hic kurulmaz: App Store kendi guncellemesini yapar ve
/// uygulama ici guncelleme bildirimi App Review'a takilir.
@MainActor
final class UpdateChecker {

    nonisolated static let endpoint = URL(string: "https://api.github.com/repos/cobanov/ghbar/releases/latest")!

    /// Kontroller arasi en az bu kadar sure.
    static let interval: TimeInterval = 24 * 3600

    private var timer: Timer?
    private var alertShowing = false

    /// Paket disinda (swift run) surum numarasi yok; kontrol de yok.
    private var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    func start() {
        guard currentVersion != nil else { return }
        // Acilista hemen degil: ilk yenileme ve giris penceresi once gelsin.
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        timer?.tolerance = 600
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            self?.checkIfDue()
        }
    }

    private func checkIfDue(now: Date = Date()) {
        guard Defaults[.checkForUpdates], !alertShowing else { return }
        if let last = Defaults[.lastUpdateCheck], now.timeIntervalSince(last) < Self.interval { return }
        Task { await check(now: now) }
    }

    private func check(now: Date) async {
        guard let current = currentVersion,
              let release = try? await Self.fetchLatest() else { return }
        Defaults[.lastUpdateCheck] = now
        let latest = Self.normalized(release.tagName)
        guard Self.isNewer(latest, than: current), Defaults[.skippedVersion] != latest else { return }
        showAlert(latest: latest, current: current, page: release.htmlURL)
    }

    private func showAlert(latest: String, current: String, page: URL) {
        alertShowing = true
        defer { alertShowing = false }

        let alert = NSAlert()
        alert.messageText = "GHBar \(latest) is available"
        alert.informativeText = Self.installedWithHomebrew
            ? "You have \(current). Update with:\n\nbrew upgrade --cask ghbar"
            : "You have \(current). Download the new version, or run the install command again."
        alert.addButton(withTitle: Self.installedWithHomebrew ? "Release Notes" : "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")

        // Menu cubugu uygulamasi on planda degil; onsuz pencere digerlerinin arkasinda kalir.
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:  NSWorkspace.shared.open(page)
        case .alertThirdButtonReturn:  Defaults[.skippedVersion] = latest
        default:                       break
        }
    }

    // MARK: - Ag olmadan test edilebilen parcalar

    nonisolated struct Release: Decodable, Equatable, Sendable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    nonisolated static func fetchLatest(session: URLSession = .shared) async throws -> Release {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GHBar", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    /// "v0.3.3" -> "0.3.3"
    nonisolated static func normalized(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Sayisal, parca parca: 0.10.0 > 0.9.9; eksik parca 0 sayilir (1.0 == 1.0.0).
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            normalized(s).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Cask ile kurulduysa zip indirmek yerine brew'u onermek gerekir; yoksa brew
    /// kendi kaydindaki surumu eski sanmaya devam eder.
    nonisolated static var installedWithHomebrew: Bool {
        ["/opt/homebrew/Caskroom/ghbar", "/usr/local/Caskroom/ghbar"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }
}
