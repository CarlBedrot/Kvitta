import Foundation

/// A calendar day with no time and no timezone, wire-encoded as `"2026-07-21"`.
///
/// An expense happens on a day, not at an instant. Storing it as a `Date` means the day an
/// expense belongs to depends on where the reader is standing, which is how you get an evening
/// purchase in Stockholm filed under the previous day for someone in Reykjavik.
public struct CalendarDate: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month),
              day >= 1,
              day <= CalendarDate.daysInMonth(year: year, month: month) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    private init(unchecked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static let epoch = CalendarDate(unchecked: 1970, 1, 1)

    /// The calendar day `date` falls on in `timeZone`, using the Gregorian calendar.
    public init(_ date: Date, in timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let resolved = CalendarDate(year: year, month: month, day: day) else {
            // The Gregorian calendar always yields these three components for any Date.
            self = .epoch
            return
        }
        self = resolved
    }

    public init?(iso8601: String) {
        let parts = iso8601.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    public var iso8601: String {
        let y = String(format: "%04d", year)
        let m = String(format: "%02d", month)
        let d = String(format: "%02d", day)
        return "\(y)-\(m)-\(d)"
    }

    public var description: String { iso8601 }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = CalendarDate(iso8601: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a YYYY-MM-DD calendar date, got \"\(raw)\"."
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso8601)
    }
}
