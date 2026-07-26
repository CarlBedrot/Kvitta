import Foundation
import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

@Suite("Money and currency")
struct MoneyTests {
    @Test("Money is minor units and stays exact where a Double would not")
    func exactArithmetic() {
        // 0.1 + 0.2 in kronor. In binary floating point this is famously not 0.30.
        let total = Money(amountMinor: 10, currency: .sek) + Money(amountMinor: 20, currency: .sek)
        #expect(total == Money(amountMinor: 30, currency: .sek))
    }

    @Test("Addition, subtraction, negation and scaling")
    func arithmetic() {
        let hundred = Money(amountMinor: 100, currency: .sek)
        #expect((hundred - Money(amountMinor: 40, currency: .sek)).amountMinor == 60)
        #expect((hundred * 3).amountMinor == 300)
        #expect((-hundred).amountMinor == -100)
        #expect(hundred.magnitude == hundred)
        #expect((-hundred).magnitude == hundred)
        #expect(Money.zero(.sek).isZero)
    }

    @Test("Currency codes must be three uppercase letters")
    func currencyValidation() {
        #expect(CurrencyCode("SEK") != nil)
        #expect(CurrencyCode("sek") == nil)
        #expect(CurrencyCode("SEKK") == nil)
        #expect(CurrencyCode("SE") == nil)
        #expect(CurrencyCode("S3K") == nil)
        #expect(CurrencyCode("") == nil)
        #expect(CurrencyCode.sek.code == "SEK")
    }

    @Test("A currency code the app has never heard of still decodes")
    func unfamiliarCurrencyDecodes() throws {
        let decoded = try JSONDecoder().decode(CurrencyCode.self, from: Data("\"ISK\"".utf8))
        #expect(decoded.code == "ISK")
    }
}

@Suite("Identifiers")
struct IdentifierTests {
    @Test("Ordering is by UUID bytes, so every device sorts members the same way")
    func byteOrdering() {
        #expect(Fixtures.member(1) < Fixtures.member(2))
        #expect(Fixtures.member(2) < Fixtures.member(3))
        #expect(!(Fixtures.member(3) < Fixtures.member(3)))
    }

    @Test("Identifiers encode as plain UUID strings")
    func codableAsString() throws {
        let id = Fixtures.member(1)
        let data = try JSONEncoder().encode(id)
        #expect(String(decoding: data, as: UTF8.self) == "\"\(id.rawValue.uuidString)\"")
        #expect(try JSONDecoder().decode(MemberID.self, from: data) == id)
    }
}

@Suite("CalendarDate")
struct CalendarDateTests {
    @Test("Round-trips through its wire format")
    func roundTrip() throws {
        let date = CalendarDate(year: 2026, month: 7, day: 21)
        #expect(date?.iso8601 == "2026-07-21")
        #expect(CalendarDate(iso8601: "2026-07-21") == date)
    }

    @Test("Rejects days that do not exist")
    func rejectsImpossibleDates() {
        #expect(CalendarDate(year: 2026, month: 2, day: 29) == nil)   // 2026 is not a leap year
        #expect(CalendarDate(year: 2024, month: 2, day: 29) != nil)   // 2024 is
        #expect(CalendarDate(year: 2000, month: 2, day: 29) != nil)   // divisible by 400
        #expect(CalendarDate(year: 1900, month: 2, day: 29) == nil)   // divisible by 100, not 400
        #expect(CalendarDate(year: 2026, month: 13, day: 1) == nil)
        #expect(CalendarDate(year: 2026, month: 4, day: 31) == nil)
        #expect(CalendarDate(year: 2026, month: 0, day: 1) == nil)
    }

    @Test("Rejects malformed strings")
    func rejectsMalformedStrings() {
        #expect(CalendarDate(iso8601: "2026-7-21") == nil)
        #expect(CalendarDate(iso8601: "21/07/2026") == nil)
        #expect(CalendarDate(iso8601: "2026-07-21T00:00:00Z") == nil)
        #expect(CalendarDate(iso8601: "") == nil)
    }

    @Test("Sorts chronologically")
    func ordering() {
        #expect(CalendarDate(year: 2025, month: 12, day: 31)! < CalendarDate(year: 2026, month: 1, day: 1)!)
        #expect(CalendarDate(year: 2026, month: 7, day: 1)! < CalendarDate(year: 2026, month: 7, day: 2)!)
    }
}

@Suite("Timestamp")
struct TimestampTests {
    @Test("The epoch is where it should be")
    func epoch() {
        #expect(Timestamp(epochMilliseconds: 0).iso8601 == "1970-01-01T00:00:00Z")
        #expect(Timestamp(iso8601: "1970-01-01T00:00:00Z")?.epochMilliseconds == 0)
    }

    @Test("Round-trips exactly, which a Double-backed Date does not always manage")
    func roundTripIsExact() {
        for milliseconds in [Int64(0), 1, 999, 1_000, 1_784_000_000_123, -86_400_000] {
            let stamp = Timestamp(epochMilliseconds: milliseconds)
            #expect(Timestamp(iso8601: stamp.iso8601) == stamp, "\(milliseconds)")
        }
    }

    @Test("Fractional seconds are kept to the millisecond and no further")
    func fractionalSeconds() {
        // One decimal place means tenths of a second, not milliseconds.
        #expect(Timestamp(iso8601: "2026-07-21T18:30:00.5Z")
            == Timestamp(iso8601: "2026-07-21T18:30:00.500Z"))
        #expect(Timestamp(iso8601: "2026-07-21T18:30:00.123456Z")
            == Timestamp(iso8601: "2026-07-21T18:30:00.123Z"))
        #expect(Timestamp(iso8601: "2026-07-21T18:30:00.500Z")?.iso8601 == "2026-07-21T18:30:00.500Z")
    }

    @Test("Offsets are normalised to UTC")
    func offsets() {
        let utc = Timestamp(iso8601: "2026-07-21T18:30:00Z")
        #expect(Timestamp(iso8601: "2026-07-21T20:30:00+02:00") == utc)
        #expect(Timestamp(iso8601: "2026-07-21T20:30:00+0200") == utc)
        #expect(Timestamp(iso8601: "2026-07-21T16:30:00-02:00") == utc)
    }

    @Test("Rejects things that are not timestamps")
    func rejectsGarbage() {
        #expect(Timestamp(iso8601: "2026-07-21") == nil)
        #expect(Timestamp(iso8601: "2026-07-21T18:30:00") == nil)      // no zone
        #expect(Timestamp(iso8601: "2026-13-21T18:30:00Z") == nil)     // month 13
        #expect(Timestamp(iso8601: "2026-07-21T25:30:00Z") == nil)     // hour 25
        #expect(Timestamp(iso8601: "2026-02-30T18:30:00Z") == nil)     // no such day
        #expect(Timestamp(iso8601: "not a timestamp at all") == nil)
        #expect(Timestamp(iso8601: "2026-07-21T18:30:00Z ") == nil)    // trailing junk
    }

    @Test("Dates before the epoch work")
    func preEpoch() {
        let stamp = Timestamp(iso8601: "1969-07-20T20:17:00Z")
        #expect(stamp != nil)
        #expect((stamp?.epochMilliseconds ?? 0) < 0)
        #expect(stamp?.iso8601 == "1969-07-20T20:17:00Z")
    }
}

@Suite("JSONValue")
struct JSONValueTests {
    @Test("Arbitrary JSON survives a round trip")
    func roundTrip() throws {
        let json = """
            {"a":1,"b":[true,null,"x"],"c":{"d":-42},"e":"åäö"}
            """
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let reencoded = try JSONDecoder().decode(
            JSONValue.self,
            from: try JSONEncoder().encode(decoded)
        )
        #expect(reencoded == decoded)
        #expect(decoded["a"]?.intValue == 1)
        #expect(decoded["c"]?["d"]?.intValue == -42)
        #expect(decoded["e"]?.stringValue == "åäö")
    }

    @Test("Whole numbers stay whole — they never round-trip via a Double")
    func largeIntegersKeepPrecision() throws {
        // 2^53 + 1 is the first integer a Double cannot represent.
        let json = "{\"amountMinor\":9007199254740993}"
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(decoded["amountMinor"]?.intValue == 9_007_199_254_740_993)
    }
}
