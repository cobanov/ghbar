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

@Suite("Formatting.spokenAge")
struct SpokenAgeTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func spoken(minutesAgo: Int) -> String {
        Formatting.spokenAge(of: now.addingTimeInterval(-Double(minutesAgo * 60)), now: now)
    }

    @Test("tekil birim s almaz") func singular() {
        #expect(spoken(minutesAgo: 60) == "1 hour old")
        #expect(spoken(minutesAgo: 60 * 24) == "1 day old")
    }

    @Test("cogul birim s alir") func plural() {
        #expect(spoken(minutesAgo: 45) == "45 minutes old")
        #expect(spoken(minutesAgo: 60 * 5) == "5 hours old")
        #expect(spoken(minutesAgo: 60 * 24 * 90) == "3 months old")
    }

    @Test("gelecekteki tarih negatif okunmaz") func future() {
        #expect(spoken(minutesAgo: -100) == "0 minutes old")
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
