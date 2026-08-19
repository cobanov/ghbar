import Foundation

/// Bir bolumun menude kac satir kaplayacagi.
struct SectionPlan: Sendable, Hashable {
    let section: MenuSection
    let visible: [Row]
    let overflow: [Row]
}

/// Menu yuksekligini bolum sayisindan bagimsiz tutar.
///
/// Butce bolum basina olsaydi her yeni bolum turu menuye kalici olarak
/// baslik + govde + "Mark All as Seen" + ayrac eklerdi; bes bolumle menu
/// 13 inc ekrana sigmiyor ve NSMenu'nun ok tuslu kaydirma moduna dusuyordu.
/// Burada butce menu geneli: yeni bir bolum turu mevcut govdeleri kisaltir.
enum MenuLayout {

    /// - Parameters:
    ///   - workRowBudget: Bolum govdeleri, basliklar ve ayraclar dahil hedef
    ///     satir sayisi.
    ///   - cap: Tek bir bolumun gosterebilecegi en fazla oge satiri.
    ///   - minimum: Her bolumun garanti satiri; kalabalik bir bolum alttaki
    ///     bolumu tamamen yutmasin diye var.
    static func plan(
        _ sections: [MenuSection],
        workRowBudget: Int,
        cap: Int,
        minimum: Int
    ) -> [SectionPlan] {
        guard !sections.isEmpty else { return [] }

        let cap = max(1, cap)
        let floor = max(1, Swift.min(minimum, cap))
        let counts = sections.map(\.rows.count)

        // Her bolum govdesinin disinda uc satir harciyor: baslik, ayrac ve
        // tasma varsa "N more…". Butceden bunlari dusmek, bolum sayisi
        // arttikca govdeleri kisaltiyor; toplam yukseklik yerinde kaliyor.
        // Taban her bolume birer satir.
        let itemBudget = max(sections.count, workRowBudget - 3 * sections.count)

        var allocation = counts.map { Swift.min(floor, $0) }
        var remaining = itemBudget - allocation.reduce(0, +)

        // Sirayla birer satir dagit. Onceligi olana hepsini vermek alttaki
        // bolumu gorunmez yapardi; sorunun yeni bir bicimi olurdu.
        while remaining > 0 {
            var gave = false
            for index in allocation.indices where remaining > 0 {
                guard allocation[index] < Swift.min(counts[index], cap) else { continue }
                allocation[index] += 1
                remaining -= 1
                gave = true
            }
            if !gave { break }
        }

        // "1 more…" satiri ogenin kendisi kadar yer kapliyor; ogeyi goster.
        for index in allocation.indices
        where counts[index] == allocation[index] + 1 && allocation[index] < cap {
            allocation[index] += 1
        }

        return zip(sections, allocation).map { section, take in
            SectionPlan(
                section: section,
                visible: Array(section.rows.prefix(take)),
                overflow: Array(section.rows.dropFirst(take))
            )
        }
    }
}
