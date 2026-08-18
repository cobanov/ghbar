import Foundation
import ServiceManagement

/// Girişte başlatma.
///
/// `SMAppService` macOS 13 ile geldi ve eski `LaunchAgent` plist'i yazma
/// yontemini tamamen degistirdi: artik uygulama kendi kaydini yapiyor,
/// kullanici da Sistem Ayarlari > Genel > Giris Ogeleri'nden gorup
/// kaldirabiliyor. Ayri bir yardimci uygulama veya plist gerekmiyor.
enum LaunchAtLogin {

    /// Paket disinda (swift run) kayit yapilamaz; SMAppService bir uygulama
    /// paketi bekliyor.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        guard isAvailable else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("GHBar: girişte başlatma degistirilemedi: \(error.localizedDescription)")
            return false
        }
    }
}

/// Uygulama surumu. Paket disinda "dev" doner.
enum AppVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
