import Foundation

/// A group's whole ledger as CSV — the product principle made file: every balance must be
/// auditable, and the audit you can open in a spreadsheet is the one nobody can argue with.
///
/// Format choices, all for the Nordic spreadsheet this will actually land in:
/// - **Semicolon separators and decimal commas**, because Swedish/Danish Excel splits on `;`
///   and reads `145,67` — a comma-separated file full of decimal commas turns into confetti.
/// - Amounts are rendered from integer minor units by string math. No `Double` anywhere,
///   same as every other place money becomes text.
/// - One row per expense and per payment, oldest first, deterministic order (date, then id) —
///   two exports of the same ledger are byte-identical.
/// - One column per member holding that row's net effect on them (paid minus share), so each
///   row's member columns sum to zero and the column totals are exactly the balances screen.
public enum GroupCSV {

    /// The full ledger for one currency bucket. Currency-scoped for the same reason
    /// `breakdown(for:in:)` is: a running column mixing SEK and DKK adds kronor to kroner.
    public static func file(
        for group: GroupState,
        in currency: CurrencyCode,
        asOf: CalendarDate
    ) -> String {
        let members = group.members.values.sorted { $0.id < $1.id }

        var lines: [String] = []
        lines.append((
            ["Datum", "Typ", "Beskrivning", "Valuta", "Belopp", "Status"]
            + members.map(\.displayName)
        ).map(escape).joined(separator: ";"))

        struct Row {
            let date: CalendarDate
            let id: UUID
            let fields: [String]
        }
        var rows: [Row] = []

        for expense in group.expenses.values where !expense.isDeleted && expense.currency == currency {
            rows.append(Row(
                date: expense.date,
                id: expense.id.rawValue,
                fields: [
                    expense.date.iso8601,
                    "Utgift",
                    expense.title,
                    currency.code,
                    decimal(expense.amountMinor),
                    ""
                ] + members.map { member in
                    delta(expense.payload.paid(by: member.id) - expense.payload.share(of: member.id))
                }
            ))
        }

        for payment in group.payments.values where payment.currency == currency {
            // Every payment appears — including pending and disputed ones — but says what it
            // is, and only counted ones carry member deltas. A disputed payment with money in
            // its columns would un-reconcile the export against the balances screen.
            let counts = payment.countsTowardBalances(asOf: asOf)
            rows.append(Row(
                date: payment.date,
                id: payment.id.rawValue,
                fields: [
                    payment.date.iso8601,
                    "Betalning",
                    payment.payload.note ?? "",
                    currency.code,
                    decimal(payment.amountMinor),
                    status(of: payment, counts: counts)
                ] + members.map { member in
                    guard counts else { return "" }
                    switch member.id {
                    case payment.fromMemberId: return delta(payment.amountMinor)
                    case payment.toMemberId: return delta(-payment.amountMinor)
                    default: return ""
                    }
                }
            ))
        }

        rows.sort { left, right in
            left.date == right.date
                ? left.id.uuidString < right.id.uuidString
                : left.date < right.date
        }
        lines.append(contentsOf: rows.map { $0.fields.map(escape).joined(separator: ";") })

        // The reconciliation row: these column totals are exactly the balances screen, öre for
        // öre — which is the whole point of exporting.
        if let balances = group.balances(asOf: asOf).balances(in: currency) {
            lines.append((
                ["", "Saldo", "", currency.code, "", ""]
                + members.map { delta(balances.amountMinor(for: $0.id)) }
            ).map(escape).joined(separator: ";"))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// `14567` → `"145,67"`, `-5` → `"-0,05"` — integer string math, decimal comma.
    static func decimal(_ minor: Int64) -> String {
        let sign = minor < 0 ? "-" : ""
        let magnitude = minor.magnitude
        return "\(sign)\(magnitude / 100),\(String(format: "%02d", magnitude % 100))"
    }

    private static func delta(_ minor: Int64) -> String {
        minor == 0 ? "" : decimal(minor)
    }

    private static func status(of payment: Payment, counts: Bool) -> String {
        switch payment.status {
        case .confirmed: return "bekräftad"
        case .disputed: return "bestriden"
        case .pending: return counts ? "bekräftad (auto)" : "väntar"
        }
    }

    /// Quote a field when it contains the separator, a quote, or a newline (RFC 4180 rules,
    /// semicolon dialect).
    private static func escape(_ field: String) -> String {
        guard field.contains(";") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
