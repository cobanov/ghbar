import Foundation

enum Formatting {

    /// Kisa, Ingilizce yas metni: 45m, 3h, 2d, 3mo
    static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<3600:
            return "\(Int(seconds / 60))m"
        case ..<86_400:
            return "\(Int(seconds / 3600))h"
        case ..<(86_400 * 30):
            return "\(Int(seconds / 86_400))d"
        default:
            return "\(Int(seconds / (86_400 * 30)))mo"
        }
    }

    /// Basligi kisaltir. Kelime ortasindan kesmemek icin son bosluga kadar geri
    /// gider; hic bosluk yoksa sert keser.
    static func truncate(_ text: String, limit: Int = 48) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        if let lastSpace = cut.lastIndex(of: " ") {
            return "\(cut[..<lastSpace])…"
        }
        return "\(cut)…"
    }

    /// 4911 -> "4,911"
    static func grouped(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        // POSIX yerel ayarinda gruplama kapali gelir; groupingSeparator yalnizca
        // hangi karakterin kullanilacagini soyler, gruplamayi acmaz.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.groupingSize = 3
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}
