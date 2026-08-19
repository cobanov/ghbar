import Foundation

enum Filtering {

    static func sections(from snapshot: Snapshot, settings: Settings) -> [MenuSection] {
        // Ayni PR birden fazla aramada cikabilir; en guclu is sinyalini veren
        // bolumde kalir. Siralama: Changes Requested > Review Requested >
        // Pull Requests > My Pull Requests.
        var claimed: Set<String> = []
        func take(_ items: [Item]) -> [Item] {
            let kept = clean(items, settings: settings).filter { !claimed.contains($0.url) }
            claimed.formUnion(kept.map(\.url))
            return kept
        }

        let changesRequested = take(snapshot.changesRequested)
        let review = take(snapshot.review)
        let prs = take(snapshot.prs)
        let mine = take(snapshot.myPullRequests)
        // Issue'lar PR aramalariyla kesismiyor; sirasi onemsiz.
        let issues = clean(snapshot.issues, settings: settings)

        let candidates: [(SectionKind, [Item])] = [
            (.pullRequests, prs),
            (.issues, issues),
            (.reviewRequested, review),
            (.changesRequested, changesRequested),
            (.myPullRequests, mine),
        ]

        return candidates.compactMap { kind, items in
            guard settings.visibleSections.contains(kind) else { return nil }
            guard !items.isEmpty else { return nil }   // bos bolum hic gosterilmez
            return MenuSection(
                kind: kind,
                rows: rows(for: items, settings: settings),
                truncated: snapshot.truncated.contains(kind)
            )
        }
    }

    // MARK: - Private

    private static func clean(_ items: [Item], settings: Settings) -> [Item] {
        items
            .filter { settings.showBots || !$0.authorIsBot }
            .filter { settings.showDrafts || !$0.isDraft }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Tek bir repo bir bolumu bogdugunda kullanicinin ilk icgudusu onu tamamen
    /// dislamak oluyor — ama o zaman oradan gelen gercek katkiyi da kaciriyor.
    /// Gruplama gurultuyu tek satira indiriyor, hicbir seyi gizlemeden.
    ///
    /// Grup, o repodan gelen EN YENI ogenin bulundugu konuma yerlestirilir;
    /// boylece taze bir katki listenin dibine dusmez.
    private static func rows(for items: [Item], settings: Settings) -> [Row] {
        let threshold = settings.repoGroupThreshold
        guard threshold > 0 else { return items.map(Row.item) }

        var counts: [String: Int] = [:]
        for item in items { counts[item.repository, default: 0] += 1 }

        var result: [Row] = []
        var emitted: Set<String> = []

        for item in items {
            let repository = item.repository
            if counts[repository, default: 0] > threshold {
                guard !emitted.contains(repository) else { continue }
                emitted.insert(repository)
                result.append(.group(
                    repository: repository,
                    items: items.filter { $0.repository == repository }
                ))
            } else {
                result.append(.item(item))
            }
        }
        return result
    }
}
