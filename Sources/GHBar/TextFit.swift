import AppKit

/// Punto cinsinden metin olcumu ve kirpma.
///
/// Menu satirlarinin genisligi karakter sayisiyla kontrol edilemez: "iii" ile
/// "WWW" ayni karakter sayisinda ama bambaska genislikte. Onceki surum
/// karakter butcesi kullaniyordu ve sonuc iki turlu bozuluyordu — kimi satir
/// sekme duragindan cok once bitip ortada delik birakiyor, kimi duragi asip
/// yasin ustune yapisiyordu. Gercek yazi tipiyle olcunce her satir tam
/// "kalan bosluk kadar" metin tasiyor.
enum TextFit {

    static func width(of string: String, font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    /// Metni, cizildiginde `maxWidth` puntoya sigacak sekilde kirpar ve sonuna
    /// elipsis koyar. Siniri asmayan metin oldugu gibi doner.
    ///
    /// Ikili arama: prefix uzunlugu buyudukce genislik tekduze arttigi icin
    /// "sigan en uzun prefix" logaritmik adimda bulunuyor.
    static func truncate(_ string: String, font: NSFont, maxWidth: CGFloat) -> String {
        guard width(of: string, font: font) > maxWidth else { return string }

        let ellipsis = "…"
        var low = 0
        var high = string.count

        while low < high {
            let mid = (low + high + 1) / 2
            let candidate = String(string.prefix(mid)) + ellipsis
            if width(of: candidate, font: font) <= maxWidth {
                low = mid
            } else {
                high = mid - 1
            }
        }

        guard low > 0 else { return ellipsis }
        // Kesim noktasindaki sarkan bosluk elipsisin onunde cirkin duruyor.
        let head = String(string.prefix(low)).trimmingCharacters(in: .whitespaces)
        return head + ellipsis
    }
}
