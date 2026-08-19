import Foundation

/// Kullaniciya gosterilecek hatalar.
///
/// Hicbiri sessizce yutulmaz: bos liste gostermek en kotu sonuc olurdu —
/// "bekleyen is yok" ile "bakamadim" ayirt edilemez hale gelir ve kullanici
/// ikincisini birincisi sanar.
enum AppError: Error, Equatable {
    /// Hata degil eyleme cagri: oturum yok, satira tiklamak hos geldin
    /// penceresini acar.
    case notSignedIn
    case ghNotFound
    case ghNotAuthenticated
    case network(String)
    case graphQL(String)
    case parse(String)
    case rateLimited(Date)
    case allowListEmpty
    case filtersDropped

    var menuText: String {
        switch self {
        case .notSignedIn:
            "Sign in to GitHub…"
        case .ghNotFound:
            "GitHub CLI not found — install gh"
        case .ghNotAuthenticated:
            "Not signed in — run: gh auth login"
        case .network:
            "No connection"
        case .graphQL(let message):
            "GitHub error: \(message)"
        case .parse:
            "Unexpected response from GitHub"
        case .rateLimited(let resetAt):
            "Rate limit reached · resets \(Self.clockText(resetAt))"
        case .allowListEmpty:
            "No repositories selected"
        case .filtersDropped:
            "Too many filters — some were dropped"
        }
    }

    /// DateFormatter bir sinif ve Sendable degil; statik olarak tutmak yerine
    /// yerelde uretiliyor. Nadiren cagrildigi icin maliyeti onemsiz.
    private static func clockText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
