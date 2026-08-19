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

    /// VoiceOver icin acik yas metni. Menudeki "3h" ekranda yeterli ama
    /// sesli okundugunda anlasilmiyor.
    static func spokenAge(of date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let value: Int
        let unit: String
        switch seconds {
        case ..<3600:
            (value, unit) = (Int(seconds / 60), "minute")
        case ..<86_400:
            (value, unit) = (Int(seconds / 3600), "hour")
        case ..<(86_400 * 30):
            (value, unit) = (Int(seconds / 86_400), "day")
        default:
            (value, unit) = (Int(seconds / (86_400 * 30)), "month")
        }
        return "\(value) \(unit)\(value == 1 ? "" : "s") old"
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
