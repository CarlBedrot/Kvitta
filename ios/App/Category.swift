import Foundation
import KvittaCore

/// A spending category with its default emoji. Emoji is **data** keyed by `categoryId`, not
/// decoration hardcoded in a view (ui-design.md), so the same id renders the same glyph in a row,
/// a chip, or a future detail screen — and a per-expense override can slot in later.
///
/// `name` is resolved through the String Catalog at table construction, so the type stays a plain
/// `Sendable` value under strict concurrency.
struct Category: Identifiable, Hashable, Sendable {
    let id: String
    let emoji: String
    let name: String
}

enum Categories {
    /// The v1 set from ui-design.md. `id` values match what the write path stores (e.g. the
    /// seed data writes `"alkohol"`).
    static let all: [Category] = [
        Category(id: "groceries", emoji: "🛒", name: String(localized: "Mat")),
        Category(id: "alkohol", emoji: "🍷", name: String(localized: "Alkohol")),
        Category(id: "restaurang", emoji: "🍽️", name: String(localized: "Restaurang")),
        Category(id: "fika", emoji: "☕️", name: String(localized: "Fika")),
        Category(id: "brunch", emoji: "🥞", name: String(localized: "Brunch")),
        Category(id: "taxi", emoji: "🚕", name: String(localized: "Taxi")),
        Category(id: "resa", emoji: "🏖️", name: String(localized: "Resa")),
        Category(id: "boende", emoji: "🏠", name: String(localized: "Boende")),
        Category(id: "sport", emoji: "🎾", name: String(localized: "Sport")),
        Category(id: "nöje", emoji: "🎉", name: String(localized: "Nöje")),
        Category(id: "övrigt", emoji: "🧾", name: String(localized: "Övrigt")),
    ]

    static let fallbackId = "övrigt"

    /// The emoji for a stored `categoryId`, or the "övrigt" receipt for anything unrecognised —
    /// tolerating unknown values rather than crashing, the same stance the event layer takes.
    static func emoji(for categoryId: String) -> String {
        all.first { $0.id == categoryId }?.emoji ?? "🧾"
    }
}

/// A description chip on the add sheet: tapping it fills the description and picks the category.
/// The group's own recent descriptions come first (see `suggestions(for:)`); the fixed starters
/// fill in behind them, so a fresh group still has something to tap.
///
/// The first set was three shop names — ICA, Systembolaget, Taxi — which only helped on the days
/// you happened to be in one of those. These are the *kinds* of thing a group splits, so a chip is
/// usually right and the description can be sharpened afterwards. ICA survives because it really
/// is the common case for groceries in Sweden.
struct DescriptionSuggestion: Identifiable {
    var id: String { text }
    let text: String
    let categoryId: String

    var emoji: String { Categories.emoji(for: categoryId) }

    static let starters: [DescriptionSuggestion] = [
        DescriptionSuggestion(text: String(localized: "Middag"), categoryId: "restaurang"),
        DescriptionSuggestion(text: "ICA", categoryId: "groceries"),
        DescriptionSuggestion(text: String(localized: "Drinkar"), categoryId: "alkohol"),
        DescriptionSuggestion(text: String(localized: "Fika"), categoryId: "fika"),
        DescriptionSuggestion(text: String(localized: "Taxi"), categoryId: "taxi"),
        DescriptionSuggestion(text: String(localized: "Boende"), categoryId: "boende"),
        DescriptionSuggestion(text: String(localized: "Nöje"), categoryId: "nöje"),
    ]

    /// How many of the group's own descriptions lead the row, and how long the row gets.
    private static let recentCap = 5
    private static let totalCap = 8

    /// The chips for one group: what this group actually buys, then the starters.
    ///
    /// A household ends up with "Hyra · Internet · ICA" and a trip with "Middag · Taxi · Hotell"
    /// without anyone configuring anything — the ledger already knows. Ordered by the expense's
    /// own date, newest first (an old receipt entered today is still an old receipt), with the
    /// write time as a tiebreak so two expenses on the same day keep a stable order. A text that
    /// differs only in case or surrounding whitespace is the same chip, and the group's own
    /// spelling wins over the starter's. Pure: same group, same chips.
    static func suggestions(for group: GroupState) -> [DescriptionSuggestion] {
        let recent = group.visibleExpenses
            .sorted { a, b in
                a.date != b.date ? a.date > b.date : a.lastModifiedAt > b.lastModifiedAt
            }

        var seen = Set<String>()
        var result: [DescriptionSuggestion] = []

        for expense in recent where result.count < recentCap {
            let text = expense.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { continue }
            result.append(DescriptionSuggestion(text: text, categoryId: expense.categoryId))
        }
        for starter in starters where result.count < totalCap {
            guard seen.insert(starter.text.lowercased()).inserted else { continue }
            result.append(starter)
        }
        return result
    }
}
