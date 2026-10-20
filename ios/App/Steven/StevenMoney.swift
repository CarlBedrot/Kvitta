import SwiftUI
import KvittaCore

/// Steven's amount format: "53 545,08 kr", "368 kr". Same integer-only arithmetic as
/// `MoneyFormat` (it reuses its symbol and sign rules) plus the thousands grouping Steven shows.
/// Grouping and the gap before the unit are no-break spaces, so an amount never wraps mid-number.
enum StevenMoneyFormat {
    static let groupSeparator: Character = "\u{00A0}"

    static func string(
        _ amountMinor: Int64,
        _ currency: CurrencyCode,
        sign: MoneyFormat.SignStyle = .none,
        explicit: Bool = false
    ) -> String {
        // `magnitude` rather than `abs`: abs(Int64.min) traps.
        let magnitude = amountMinor.magnitude
        let kronor = magnitude / 100
        let ore = magnitude % 100
        let fraction = ore == 0 ? "" : ",\(ore < 10 ? "0" : "")\(ore)"
        let unit = explicit ? currency.code : MoneyFormat.symbol(currency)
        return "\(prefix(amountMinor, sign))\(grouped(kronor))\(fraction)\(groupSeparator)\(unit)"
    }

    /// `53545` → "53 545". Digits in threes from the right.
    static func grouped(_ value: UInt64) -> String {
        let digits = Array(String(value))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { out.append(groupSeparator) }
            out.append(digit)
        }
        return out
    }

    private static func prefix(_ amountMinor: Int64, _ sign: MoneyFormat.SignStyle) -> String {
        switch sign {
        case .none: ""
        case .negativeOnly: amountMinor < 0 ? "-" : ""
        case .always: amountMinor > 0 ? "+" : (amountMinor < 0 ? "-" : "")
        }
    }
}

extension Steven {

    /// Who owes whom in one currency, from the viewer's side. The three footer and card states
    /// of README §1.2; a group in several currencies shows one of these per currency.
    enum Balance: Equatable, Sendable {
        case theyOwe(amountMinor: Int64, currency: CurrencyCode)
        case youOwe(amountMinor: Int64, currency: CurrencyCode)
        case settled

        /// From a signed net balance: positive means the others owe you.
        init(netMinor: Int64, currency: CurrencyCode) {
            if netMinor > 0 { self = .theyOwe(amountMinor: netMinor, currency: currency) }
            else if netMinor < 0 { self = .youOwe(amountMinor: -netMinor, currency: currency) }
            else { self = .settled }
        }
    }

    /// An amount in Steven's format with monospaced digits. `tone` picks the colour; direction
    /// colours are never the only carrier of meaning — callers pair them with words (#139).
    struct MoneyText: View {
        enum Tone {
            case ink, muted, accent, bright, owe
            /// Accent when positive, coral when negative, ink at zero.
            case direction
        }

        let amountMinor: Int64
        let currency: CurrencyCode
        var font: StevenFont = .rowTitleBold
        var tone: Tone = .ink
        var sign: MoneyFormat.SignStyle = .none
        var explicit = false

        var body: some View {
            Text(verbatim: StevenMoneyFormat.string(amountMinor, currency, sign: sign, explicit: explicit))
                .stevenFont(font)
                .monospacedDigit()
                .foregroundStyle(color)
        }

        private var color: Color {
            switch tone {
            case .ink: StevenColor.ink
            case .muted: StevenColor.muted
            case .accent: StevenColor.accent
            case .bright: StevenColor.accentBright
            case .owe: StevenColor.owe
            case .direction:
                amountMinor > 0 ? StevenColor.accent : (amountMinor < 0 ? StevenColor.owe : StevenColor.ink)
            }
        }
    }

    /// "De är skyldiga **677 kr**" / "Du är skyldig **10 kr**" / "Kvitt" — the right-hand half of
    /// a group card's footer row (01).
    struct BalanceLabel: View {
        let state: Balance
        /// Settled cards say how to archive them (01: "Dra vänster för att arkivera").
        var showsArchiveHint = false

        var body: some View {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) { phrase; amount }
                VStack(alignment: .trailing, spacing: 2) { phrase; amount }
            }
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder private var phrase: some View {
            switch state {
            case .theyOwe: Text("De är skyldiga").stevenFont(.rowTitle).foregroundStyle(StevenColor.muted)
            case .youOwe: Text("Du är skyldig").stevenFont(.rowTitle).foregroundStyle(StevenColor.muted)
            case .settled:
                if showsArchiveHint {
                    Text("Dra vänster för att arkivera").stevenFont(.rowTitle).foregroundStyle(StevenColor.muted)
                }
            }
        }

        @ViewBuilder private var amount: some View {
            switch state {
            case .theyOwe(let minor, let currency):
                MoneyText(amountMinor: minor, currency: currency, tone: .bright)
            case .youOwe(let minor, let currency):
                MoneyText(amountMinor: minor, currency: currency, tone: .owe)
            case .settled:
                Text("Kvitt").stevenFont(.rowTitleBold).foregroundStyle(StevenColor.accent)
            }
        }
    }

    /// The group's fixed footer (08–10, decision 6.4): balance on the left, Betala or Påminn on
    /// the right, and the FAB riding over the top edge in the middle.
    struct BalanceFooter: View {
        /// One line per open currency; settled groups pass `[.settled]` (or nothing).
        let balances: [Balance]
        var onPay: () -> Void = {}
        var onRemind: () -> Void = {}
        var onAdd: () -> Void

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        BalanceLine(state: line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The FAB's slot: nothing may sit under it.
                Color.clear.frame(width: StevenMetric.fab, height: 1)
                actionButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, StevenMetric.gutter)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background {
                StevenColor.surface
                    .stevenShadow(.footer)
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) {
                FAB(action: onAdd)
                    .offset(y: -StevenMetric.fab / 2)
            }
        }

        private var lines: [Balance] {
            balances.isEmpty ? [.settled] : balances
        }

        /// "knappen gäller den första öppna" (6.4).
        @ViewBuilder private var actionButton: some View {
            switch lines.first(where: { $0 != .settled }) {
            case .youOwe?:
                Button("Betala", action: onPay)
                    .buttonStyle(FilledButtonStyle(height: StevenMetric.compactButtonHeight))
                    .frame(width: 110)
            case .theyOwe?:
                Button("Påminn", action: onRemind)
                    .buttonStyle(OutlineButtonStyle(height: StevenMetric.compactButtonHeight))
                    .frame(width: 110)
            case .settled?, nil:
                EmptyView()
            }
        }
    }

    /// Footer variant of the label: phrase above a 22 pt amount (08).
    private struct BalanceLine: View {
        let state: Balance

        var body: some View {
            switch state {
            case .theyOwe(let minor, let currency):
                VStack(alignment: .leading, spacing: 0) {
                    Text("De är skyldiga").stevenFont(.rowTitle).foregroundStyle(StevenColor.muted)
                    MoneyText(amountMinor: minor, currency: currency, font: .amountLarge, tone: .accent)
                }
                .accessibilityElement(children: .combine)
            case .youOwe(let minor, let currency):
                VStack(alignment: .leading, spacing: 0) {
                    Text("Du är skyldig").stevenFont(.rowTitle).foregroundStyle(StevenColor.muted)
                    MoneyText(amountMinor: minor, currency: currency, font: .amountLarge, tone: .owe)
                }
                .accessibilityElement(children: .combine)
            case .settled:
                Text("Kvitt").stevenFont(.amountLarge).foregroundStyle(StevenColor.accent)
            }
        }
    }
}

#Preview("Money – light") { StevenMoneyPreview() }
#Preview("Money – dark") { StevenMoneyPreview().preferredColorScheme(.dark) }

private struct StevenMoneyPreview: View {
    var body: some View {
        VStack(spacing: 24) {
            Steven.MoneyText(amountMinor: 5_354_508, currency: .sek, font: .groupTitle)
            Steven.MoneyText(amountMinor: -1_000, currency: .sek, tone: .direction, sign: .negativeOnly)
            Steven.BalanceLabel(state: .theyOwe(amountMinor: 67_700, currency: .sek))
            Steven.BalanceLabel(state: .youOwe(amountMinor: 1_000, currency: .sek))
            Steven.BalanceLabel(state: .settled, showsArchiveHint: true)
            Spacer()
            Steven.BalanceFooter(balances: [.theyOwe(amountMinor: 67_655, currency: .sek)], onAdd: {})
        }
        .padding(.top, 24)
        .background(StevenColor.content)
    }
}
