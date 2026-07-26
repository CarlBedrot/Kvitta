import Foundation

/// An instant, stored as whole milliseconds since the Unix epoch, wire-encoded as RFC 3339 UTC.
///
/// Not a `Date`, for two reasons. `Date` is backed by a binary `Double`, so a value that goes out
/// as a string and comes back is not reliably the value you started with — and this type is
/// compared for equality all over the test suite. And formatting is done here with integer
/// arithmetic rather than `ISO8601DateFormatter`, so the wire format cannot drift with the host's
/// locale, calendar, or Foundation version.
///
/// `clientTimestamp` is display only (design doc §2). `serverSeq` is the only ordering that counts.
public struct Timestamp: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let epochMilliseconds: Int64

    public init(epochMilliseconds: Int64) {
        self.epochMilliseconds = epochMilliseconds
    }

    /// Truncates toward the past to whole milliseconds, so a round trip through the wire format
    /// returns exactly this value.
    public init(_ date: Date) {
        let seconds = date.timeIntervalSince1970
        self.epochMilliseconds = Int64((seconds * 1000).rounded(.down))
    }

    public var date: Date {
        // Exact: epoch milliseconds for any plausible date fit well inside a Double's mantissa.
        Date(timeIntervalSince1970: Double(epochMilliseconds) / 1000)
    }

    public static func < (lhs: Timestamp, rhs: Timestamp) -> Bool {
        lhs.epochMilliseconds < rhs.epochMilliseconds
    }

    public var description: String { iso8601 }

    // MARK: - RFC 3339

    public var iso8601: String {
        let (days, millisecondsOfDay) = Timestamp.floorDivide(epochMilliseconds, 86_400_000)
        let (year, month, day) = Timestamp.civilFromDays(days)

        let totalSeconds = millisecondsOfDay / 1000
        let milliseconds = millisecondsOfDay % 1000
        let hour = totalSeconds / 3600
        let minute = (totalSeconds % 3600) / 60
        let second = totalSeconds % 60

        let datePart = "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
        let timePart = "\(pad(Int(hour), 2)):\(pad(Int(minute), 2)):\(pad(Int(second), 2))"
        let fraction = milliseconds == 0 ? "" : ".\(pad(Int(milliseconds), 3))"
        return "\(datePart)T\(timePart)\(fraction)Z"
    }

    /// Accepts `2026-07-22T18:30:00Z`, fractional seconds, and `+HH:MM` / `-HHMM` offsets.
    public init?(iso8601: String) {
        let scalars = Array(iso8601.utf8)
        // Shortest legal form: 1970-01-01T00:00:00Z
        guard scalars.count >= 20 else { return nil }

        func number(_ range: Range<Int>) -> Int? {
            guard range.lowerBound >= 0, range.upperBound <= scalars.count else { return nil }
            var value = 0
            for index in range {
                let digit = Int(scalars[index]) - 48
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }

        guard scalars[4] == UInt8(ascii: "-"), scalars[7] == UInt8(ascii: "-"),
              scalars[10] == UInt8(ascii: "T") || scalars[10] == UInt8(ascii: " "),
              scalars[13] == UInt8(ascii: ":"), scalars[16] == UInt8(ascii: ":"),
              let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16),
              let second = number(17..<19),
              (1...12).contains(month),
              day >= 1, day <= CalendarDate.daysInMonth(year: year, month: month),
              hour < 24, minute < 60, second <= 60 else { return nil }

        var cursor = 19
        var milliseconds = 0
        if cursor < scalars.count, scalars[cursor] == UInt8(ascii: ".") {
            cursor += 1
            var digits = 0
            while cursor < scalars.count, (48...57).contains(scalars[cursor]) {
                // Anything finer than a millisecond is dropped, matching the stored precision.
                if digits < 3 { milliseconds = milliseconds * 10 + Int(scalars[cursor]) - 48 }
                digits += 1
                cursor += 1
            }
            guard digits > 0 else { return nil }
            while digits < 3 { milliseconds *= 10; digits += 1 }
        }

        var offsetMinutes = 0
        guard cursor < scalars.count else { return nil }
        switch scalars[cursor] {
        case UInt8(ascii: "Z"), UInt8(ascii: "z"):
            cursor += 1
        case UInt8(ascii: "+"), UInt8(ascii: "-"):
            let sign = scalars[cursor] == UInt8(ascii: "-") ? -1 : 1
            cursor += 1
            guard let offsetHour = number(cursor..<(cursor + 2)) else { return nil }
            cursor += 2
            if cursor < scalars.count, scalars[cursor] == UInt8(ascii: ":") { cursor += 1 }
            guard let offsetMinute = number(cursor..<(cursor + 2)) else { return nil }
            cursor += 2
            guard offsetHour < 24, offsetMinute < 60 else { return nil }
            offsetMinutes = sign * (offsetHour * 60 + offsetMinute)
        default:
            return nil
        }
        guard cursor == scalars.count else { return nil }

        let days = Timestamp.daysFromCivil(year: year, month: month, day: day)
        let secondsOfDay = hour * 3600 + minute * 60 + second - offsetMinutes * 60
        let total = Int64(days) * 86_400_000
            + Int64(secondsOfDay) * 1000
            + Int64(milliseconds)
        self.epochMilliseconds = total
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = Timestamp(iso8601: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an RFC 3339 timestamp, got \"\(raw)\"."
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso8601)
    }

    // MARK: - Integer calendar arithmetic

    private func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(abs(value))
        let padding = String(repeating: "0", count: Swift.max(0, width - digits.count))
        return (value < 0 ? "-" : "") + padding + digits
    }

    /// Division that rounds toward negative infinity, so dates before 1970 land on the right day.
    private static func floorDivide(_ value: Int64, _ divisor: Int64) -> (quotient: Int, remainder: Int64) {
        var quotient = value / divisor
        var remainder = value % divisor
        if remainder < 0 {
            quotient -= 1
            remainder += divisor
        }
        return (Int(quotient), remainder)
    }

    /// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = year - (month <= 2 ? 1 : 0)
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Inverse of `daysFromCivil` (Howard Hinnant's `civil_from_days`).
    static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPrime = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
        let month = monthPrime + (monthPrime < 10 ? 3 : -9)
        return (year + (month <= 2 ? 1 : 0), month, day)
    }
}
