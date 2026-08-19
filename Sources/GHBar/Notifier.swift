import AppKit
import UserNotifications

/// macOS bildirimleri.
///
/// UNUserNotificationCenter yalnizca imzali bir uygulama paketi icinde calisir;
/// `swift run` ile calistirildiginda sessizce devre disi kalir. Bu yuzden her
/// cagri `isAvailable` ile korunuyor — uygulamanin gelistirme modunda cokmesi
/// yerine bildirimsiz calismasi tercih edildi.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    /// Bildirime tiklandiginda cagrilir; URL'i acmak ve gorulmus isaretlemek
    /// AppDelegate'in isi.
    var onOpen: ((String) -> Void)?

    /// Ozet bildirimine ("12 new items") tiklandiginda cagrilir; tek bir URL
    /// olmadigi icin dogru davranis menuyu acmak.
    var onOpenSummary: (() -> Void)?

    private var authorized = false

    /// Paket kimligi yoksa (swift run) bildirim altyapisi hic kurulmaz.
    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func start() {
        guard isAvailable else {
            NSLog("GHBar: paket disinda calisiliyor, bildirimler kapali")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error { NSLog("GHBar: bildirim izni hatasi: \(error.localizedDescription)") }
            Task { @MainActor in self?.authorized = granted }
        }
    }

    /// Kullanici reddettiyse bir daha sormayiz; her acilista izin penceresi
    /// cikarmak rahatsiz edici olurdu.
    func notify(about items: [Item]) {
        guard isAvailable, authorized, !items.isEmpty else { return }

        // Cok sayida yeni oge geldiginde tek tek bildirim yagdirmak yerine
        // tek bir ozet gonderilir.
        if items.count > 5 {
            post(
                id: "summary-\(items.count)-\(items[0].id)",
                title: "\(items.count) new items",
                body: "Your repositories have \(items.count) new pull requests and issues.",
                url: nil,
                isSummary: true
            )
            return
        }

        for item in items {
            let kind = item.kind == .pullRequest ? "pull request" : "issue"
            post(
                id: item.url,
                title: "New \(kind) · \(item.repositoryName) #\(item.number)",
                body: "\(item.title)\n@\(item.authorLogin)",
                url: item.url
            )
        }
    }

    // MARK: - Private

    private func post(id: String, title: String, body: String, url: String?, isSummary: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url { content.userInfo = ["url": url] }
        if isSummary { content.userInfo = ["summary": true] }

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil)
        ) { error in
            if let error { NSLog("GHBar: bildirim gonderilemedi: \(error.localizedDescription)") }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Uygulama on planda olmasa da bildirim gosterilsin. GHBar bir menu cubugu
    /// uygulamasi; "on plan" kavrami onun icin pratikte hic olusmuyor.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if info["summary"] as? Bool == true {
            // Eski surumde ozet bildirimine tiklamak sessizce hicbir sey
            // yapmiyordu — URL olmadigi icin guard'dan donuyordu.
            await MainActor.run { self.onOpenSummary?() }
            return
        }
        guard let url = info["url"] as? String else { return }
        await MainActor.run { self.onOpen?(url) }
    }
}
