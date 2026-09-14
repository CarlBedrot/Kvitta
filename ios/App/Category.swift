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

    /// The SF Symbol for a category — what a row shows, the way Steven marks each expense with
    /// a small glyph. Emoji read as decoration; a symbol in the system's fill reads as the app.
    static func symbol(for categoryId: String) -> String {
        switch categoryId {
        case "groceries": return "cart"
        case "alkohol": return "wineglass"
        case "restaurang": return "fork.knife"
        case "fika": return "cup.and.saucer"
        case "brunch": return "cup.and.saucer"
        case "taxi": return "car"
        case "resa": return "airplane"
        case "boende": return "house"
        case "sport": return "figure.run"
        case "nöje": return "ticket"
        default: return "receipt"
        }
    }

    /// The emoji for a stored `categoryId`, or the "övrigt" receipt for anything unrecognised —
    /// tolerating unknown values rather than crashing, the same stance the event layer takes.
    static func emoji(for categoryId: String) -> String {
        all.first { $0.id == categoryId }?.emoji ?? "🧾"
    }
}

extension Categories {
    /// A category read off the description, so a row gets its emoji without anyone picking one.
    ///
    /// Plain substring matching on a short Nordic word list, first hit wins, `övrigt` when
    /// nothing hits. Deliberately dumb: "ICA" is groceries and "Systembolaget" is alcohol on
    /// every phone, and a wrong guess costs one emoji. Pure, so it is testable and never
    /// disagrees between two devices with the same log.
    static func infer(from title: String) -> String {
        let text = title.lowercased()
        for (id, keywords) in keywordsByCategory {
            if keywords.contains(where: { text.contains($0) }) { return id }
        }
        return fallbackId
    }

    /// Ordered: the more specific shop names first, the generic words last.
    private static let keywordsByCategory: [(String, [String])] = [
        ("alkohol", ["systembolaget", "systemet", "vinmonopolet", "drink", "öl", "vin", "bar ", "sprit", "bubbel"]),
        ("groceries", ["ica", "coop", "willys", "lidl", "hemköp", "city gross", "netto", "rema", "irma", "matvaror", "mat", "livs"]),
        ("fika", ["fika", "kaffe", "café", "cafe", "espresso", "bulle", "glass"]),
        ("brunch", ["brunch", "frukost"]),
        ("restaurang", ["middag", "lunch", "restaurang", "pizza", "sushi", "burg", "kebab", "thai", "krog", "tacos"]),
        ("taxi", ["taxi", "uber", "bolt"]),
        ("boende", ["hyra", "hotell", "airbnb", "boende", "stuga", "bredband", "internet", "elräkning"]),
        ("resa", ["resa", "flyg", "tåg", "sj ", "hyrbil", "bensin", "färja", "parkering", "buss"]),
        ("sport", ["gym", "padel", "tennis", "golf", "skidor", "liftkort", "bad", "träning"]),
        ("nöje", ["bio", "konsert", "biljett", "nöje", "fest", "klubb", "museum", "spel"]),
    ]
}
