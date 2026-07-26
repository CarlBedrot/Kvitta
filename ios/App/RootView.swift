import SwiftUI
import KvittaCore
import KvittaStorage

/// A deliberately plain screen whose only job is to prove the stack works end to end.
///
/// The real screens — the zero line, amount-first entry, Balansgranskning — are built against
/// `docs/mockup.html` by the in-Xcode agent, which can see its own Previews. Nothing here is
/// meant to survive that.
struct RootView: View {
    let ledger: LedgerStore
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                if ledger.state.groups.isEmpty {
                    ContentUnavailableView(
                        "Inga grupper än",
                        systemImage: "person.2",
                        description: Text("Lägg till testdata för att se saldon.")
                    )
                } else {
                    ForEach(ledger.state.groupsByName) { group in
                        GroupSummaryRow(group: group)
                    }
                }

                DiagnosticsSection(ledger: ledger, failure: failure)
            }
            .navigationTitle("Grupper")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Debug", systemImage: "ladybug") {
                        Button("Bygg om projektioner från loggen", systemImage: "arrow.clockwise") {
                            perform { try ledger.rebuild() }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Testdata", systemImage: "plus") {
                        perform { try SeedData.insert(into: ledger) }
                    }
                }
            }
        }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            failure = nil
        } catch {
            // Sync failures must surface, never vanish (CLAUDE.md). Same rule for local ones.
            failure = String(describing: error)
        }
    }
}

private struct GroupSummaryRow: View {
    let group: GroupState

    var body: some View {
        Section(group.name) {
            ForEach(group.membersByName) { member in
                LabeledContent(member.displayName) {
                    Text(Self.format(group.balances().amountMinor(for: member.id), group.currency))
                        .monospacedDigit()
                        .foregroundStyle(colour(for: group.balances().amountMinor(for: member.id)))
                }
            }
            LabeledContent("Summa") {
                Text(Self.format(group.balances().totalMinor, group.currency))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            LabeledContent("Utgifter", value: "\(group.visibleExpenses.count)")
        }
    }

    private func colour(for amountMinor: Int64) -> Color {
        if amountMinor > 0 { return .green }
        if amountMinor < 0 { return .orange }
        return .secondary
    }

    /// Minor units to a readable string. Integer arithmetic only — no `Double` anywhere near it.
    static func format(_ amountMinor: Int64, _ currency: CurrencyCode) -> String {
        let sign = amountMinor < 0 ? "-" : ""
        let magnitude = abs(amountMinor)
        let fraction = magnitude % 100
        let padded = fraction < 10 ? "0\(fraction)" : "\(fraction)"
        return "\(sign)\(magnitude / 100),\(padded) \(currency.code)"
    }
}

private struct DiagnosticsSection: View {
    let ledger: LedgerStore
    let failure: String?

    var body: some View {
        Section("Diagnostik") {
            LabeledContent("Väntar på push", value: "\(pendingCount)")
            LabeledContent("Överhoppade händelser", value: "\(ledger.state.skipped.count)")
            LabeledContent("Olästa rader", value: "\(ledger.rejected.count)")
            if let failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var pendingCount: Int {
        (try? ledger.pendingPushCount()) ?? -1
    }
}
