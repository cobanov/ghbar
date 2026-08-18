import Testing
import Foundation
@testable import GHBar

private func date(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    return f.date(from: iso)!
}

@Suite("Formatting.age")
struct FormattingAgeTests {
    let now = date("2026-08-18T12:00:00Z")

    @Test("dakikalar") func minutes() {
        #expect(Formatting.age(of: now.addingTimeInterval(-45 * 60), now: now) == "45m")
    }

    @Test("59 dakika hala dakika") func fiftyNineMinutes() {
        #expect(Formatting.age(of: now.addingTimeInterval(-59 * 60), now: now) == "59m")
    }

    @Test("60 dakika saate doner") func sixtyMinutes() {
        #expect(Formatting.age(of: now.addingTimeInterval(-60 * 60), now: now) == "1h")
    }

    @Test("saatler") func hours() {
        #expect(Formatting.age(of: now.addingTimeInterval(-3 * 3600), now: now) == "3h")
    }

    @Test("gunler") func days() {
        #expect(Formatting.age(of: now.addingTimeInterval(-2 * 86400), now: now) == "2d")
    }

    @Test("aylar") func months() {
        #expect(Formatting.age(of: now.addingTimeInterval(-90 * 86400), now: now) == "3mo")
    }

    @Test("gelecekteki tarih 0m verir, negatif metin uretmez") func future() {
        #expect(Formatting.age(of: now.addingTimeInterval(120), now: now) == "0m")
    }
}

@Suite("Formatting.grouped")
struct FormattingGroupedTests {
    @Test("binlik ayrac") func thousands() {
        #expect(Formatting.grouped(4911) == "4,911")
        #expect(Formatting.grouped(5000) == "5,000")
    }

    @Test("dort haneden kucuk sayi ayracsiz") func small() {
        #expect(Formatting.grouped(42) == "42")
    }
}
