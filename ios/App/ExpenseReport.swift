import Foundation
import KvittaCore

/// Read-only report data. Currency buckets never mix, and only non-deleted projected expenses
/// participate. The report shows shared group spending, not a person's net debt or income.
struct ExpenseReport {
    struct Item: Identifiable, Hashable {
        let id: ExpenseID
        let groupId: GroupID
        let groupName: String
        let title: String
        let categoryId: String
        let date: CalendarDate
        let amountMinor: Int64
        let currency: CurrencyCode
        let author: String
    }

    let items: [Item]
    private let knownCurrencies: Set<CurrencyCode>

    init(groups: [GroupState]) {
        knownCurrencies = Set(groups.flatMap { group in
            [group.currency] + group.visibleExpenses.map(\.currency) + group.paymentsByDate.map(\.currency)
        })
        var result: [Item] = []
        for group in groups {
            for expense in group.visibleExpenses {
                let author = group.members.values.first { $0.linkedUserId == expense.createdBy }?.displayName ?? "—"
                result.append(Item(id: expense.id, groupId: group.id, groupName: group.name,
                                   title: expense.title, categoryId: expense.categoryId,
                                   date: expense.date, amountMinor: expense.amountMinor,
                                   currency: expense.currency, author: author))
            }
        }
        items = result.sorted {
            if $0.date == $1.date { return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
            return $0.date > $1.date
        }
    }

    init(items: [Item]) {
        self.items = items
        knownCurrencies = Set(items.map(\.currency))
    }

    var currencies: [CurrencyCode] {
        let codes = knownCurrencies.sorted { $0.code < $1.code }
        return codes.isEmpty ? [.sek] : codes
    }

    func filtered(currency: CurrencyCode, days: ClosedRange<Int>? = nil,
                  category: String? = nil, search: String = "") -> [Item] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter {
            $0.currency == currency && (days?.contains($0.date.dayNumber) ?? true)
                && (category == nil || category == $0.categoryId)
                && (query.isEmpty || ($0.title + " " + $0.groupName).localizedCaseInsensitiveContains(query))
        }
    }

    static func total(_ items: [Item]) -> Int64? {
        var result: Int64 = 0
        for item in items {
            let next = result.addingReportingOverflow(item.amountMinor)
            guard !next.overflow else { return nil }
            result = next.partialValue
        }
        return result
    }

    /// Monday–Sunday, independent of device locale and time zone after resolving today's day.
    static func week(containing date: CalendarDate, offset: Int = 0) -> ClosedRange<Int> {
        let weekday = ((date.dayNumber + 3) % 7 + 7) % 7
        let first = date.dayNumber - weekday + offset * 7
        return first...(first + 6)
    }

    static func label(for dayNumber: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        return formatter.string(from: date(for: dayNumber))
    }

    static func dayLabel(_ dayNumber: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date(for: dayNumber))
    }

    static func date(for dayNumber: Int) -> Date {
        // This conversion is for date labels only. All monetary arithmetic above stays Int64.
        Date(timeIntervalSince1970: Double(dayNumber) * 86_400)
    }
}
