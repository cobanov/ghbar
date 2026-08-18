import Foundation

struct Queries: Sendable, Equatable {
    let prs: String
    let issues: String
    let review: String
    /// Uzunluk tavani yuzunden bazi filtreler dusuruldu.
    let filtersDropped: Bool
    /// Beyaz liste acik ama bos — hicbir sey gosterilmemeli.
    let allowListEmpty: Bool
}

enum Query {

    /// GitHub arama sorgusu icin guvenli ust sinir. Olculdu: GraphQL aramasi
    /// 3085 karakterde bile sorunsuz calisiyor ve en sondaki niteleyici
    /// uygulaniyor. Belgelenen 256 karakter siniri REST/web aramasina ait.
    static let maxLength = 4000

    static func build(_ settings: Settings) -> Queries {
        let repos = normalizedRepositories(settings)
        let allowListEmpty = settings.repoListIsAllowList && repos.isEmpty

        // Beyaz liste modunda repo listesi kapsami zaten belirliyor;
        // user: parcalari gereksiz ve yaniltici olur.
        let scope: [String] = settings.repoListIsAllowList
            ? repos.map { "repo:\($0)" }
            : settings.accounts.map { "user:\($0)" }

        let exclusions: [String] = settings.repoListIsAllowList
            ? []
            : repos.map { "-repo:\($0)" }

        var dropped = false

        func assemble(_ prefix: [String]) -> String {
            // -author:@me : kendi actiklarini eler. @me kisayolu sayesinde
            // kullanicinin login'ini bilmeye gerek kalmiyor.
            let (kept, wasDropped) = fit(prefix + scope + ["-author:@me"], exclusions: exclusions)
            dropped = dropped || wasDropped
            return kept.joined(separator: " ")
        }

        // review sorgusu hesaplardan bagimsiz: sana review istenen her PR,
        // hangi repoda olursa olsun. Repo filtresi yine de uygulanir.
        let (reviewParts, reviewDropped) = fit(
            ["is:pr", "is:open", "review-requested:@me"],
            exclusions: exclusions
        )
        dropped = dropped || reviewDropped

        return Queries(
            prs:    assemble(["is:pr", "is:open"]),
            issues: assemble(["is:issue", "is:open"]),
            review: reviewParts.joined(separator: " "),
            filtersDropped: dropped,
            allowListEmpty: allowListEmpty
        )
    }

    /// Zorunlu parcalari korur, dislama parcalarini tavana sigdigi kadar ekler.
    /// Kirpma sessizce yapilmaz — geri donen bayrak menude uyariya donusur.
    private static func fit(_ required: [String], exclusions: [String]) -> ([String], Bool) {
        var parts = required
        var length = parts.joined(separator: " ").count
        var dropped = false

        for exclusion in exclusions {
            let addition = exclusion.count + 1
            if length + addition > maxLength {
                dropped = true
                break
            }
            parts.append(exclusion)
            length += addition
        }
        return (parts, dropped)
    }

    /// "noisy" -> "alice/noisy"; "alice/noisy" oldugu gibi kalir.
    private static func normalizedRepositories(_ settings: Settings) -> [String] {
        let owner = settings.accounts.first ?? "@me"
        return settings.repoList.compactMap { entry in
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return trimmed.contains("/") ? trimmed : "\(owner)/\(trimmed)"
        }
    }

    /// Tek istekte uc arama + profil + kota. Olculdu: toplam maliyeti 1 puan.
    ///
    /// Ayri bir .graphql dosyasi yerine gomulu metin: Asama 2'de .app paketi
    /// elle kurulacak ve Bundle.module kaynak paketinin de kopyalanmasini
    /// gerektirecekti. Gomulu metin bu ariza yolunu ortadan kaldiriyor.
    static let document = """
    query($prs: String!, $issues: String!, $review: String!, $first: Int!) {
      viewer { login name avatarUrl }
      prs: search(query: $prs, type: ISSUE, first: $first) {
        issueCount
        nodes { ... on PullRequest {
          number title url createdAt isDraft
          author { login __typename }
          repository { nameWithOwner }
        } }
      }
      issues: search(query: $issues, type: ISSUE, first: $first) {
        issueCount
        nodes { ... on Issue {
          number title url createdAt
          author { login __typename }
          repository { nameWithOwner }
        } }
      }
      review: search(query: $review, type: ISSUE, first: $first) {
        issueCount
        nodes { ... on PullRequest {
          number title url createdAt isDraft
          author { login __typename }
          repository { nameWithOwner }
        } }
      }
      rateLimit { limit remaining resetAt cost }
    }
    """
}
