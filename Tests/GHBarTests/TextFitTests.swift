import Testing
import AppKit
@testable import GHBar

/// Olcum gercek yazi tipiyle yapildigi icin beklentiler mutlak degil,
/// iliskisel: "sonuc siniri asmiyor", "daha genis sinir daha uzun metin
/// birakiyor" gibi. Punto degerleri makineden makineye birebir ayni olmak
/// zorunda degil; bu testler her makinede gecerli kalan degismezleri olcuyor.
@Suite("TextFit")
struct TextFitTests {

    let font = NSFont.systemFont(ofSize: 13)

    @Test("sigan metin degismeden doner") func fits() {
        let text = "short"
        let width = TextFit.width(of: text, font: font)
        #expect(TextFit.truncate(text, font: font, maxWidth: width + 1) == "short")
    }

    @Test("kirpilmis metin siniri asmaz ve elipsisle biter") func truncates() {
        let text = String(repeating: "word ", count: 30)
        for maxWidth in [60.0, 120.0, 200.0] {
            let result = TextFit.truncate(text, font: font, maxWidth: maxWidth)
            #expect(TextFit.width(of: result, font: font) <= maxWidth)
            #expect(result.hasSuffix("…"))
        }
    }

    @Test("daha genis sinir daha uzun metin birakir") func monotonic() {
        let text = String(repeating: "word ", count: 30)
        let narrow = TextFit.truncate(text, font: font, maxWidth: 80)
        let wide = TextFit.truncate(text, font: font, maxWidth: 200)
        #expect(wide.count > narrow.count)
    }

    @Test("genis harfli metin dar harfliden az karakter tasir — olcum punto bazli") func widthNotChars() {
        // Karakter sayisiyla kirpan eski surumun tam olarak ayirt edemedigi durum.
        let wide = String(repeating: "W", count: 100)
        let narrow = String(repeating: "i", count: 100)
        let wideCut = TextFit.truncate(wide, font: font, maxWidth: 100)
        let narrowCut = TextFit.truncate(narrow, font: font, maxWidth: 100)
        #expect(narrowCut.count > wideCut.count)
    }

    @Test("sifira yakin sinirda cokmez") func degenerate() {
        let result = TextFit.truncate("anything", font: font, maxWidth: 1)
        #expect(result == "…")
    }

    @Test("kesim noktasindaki bosluk elipsise yapismaz") func trimsTrailingSpace() {
        let text = "alpha beta gamma delta epsilon zeta"
        for maxWidth in stride(from: 40.0, through: 180.0, by: 10) {
            let result = TextFit.truncate(text, font: font, maxWidth: maxWidth)
            #expect(!result.contains(" …"))
        }
    }
}
