import SwiftUI
import KvittaCore

/// The split editor: pick the payer, pick a mode (Lika / Exakt / Procent / Andelar), and enter
/// the per-member detail. Every mode shows each person's resolved share live and gates "Klar" on
/// the same `SplitCalculator` call the expense will use, so what you see is exactly what saves.
///
/// This is where 437 kr in "Lika" among three reads 145,67 / 145,67 / 145,66.
struct SplitEditorSheet: View {
    @Bindable var model: NewExpenseModel
    @Environment(\.dismiss) private var dismiss

    private var shareMap: [MemberID: Int64] {
        let shares = model.draft.resolvedShares(totalMinor: model.amountMinor, members: model.memberIds) ?? []
        return Dictionary(uniqueKeysWithValues: shares.map { ($0.memberId, $0.amountMinor) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Betalade av") {
                    Picker("Betalade av", selection: $model.payerId) {
                        ForEach(model.members) { member in
                            Text(model.name(for: member)).tag(Optional(member.id))
                        }
                    }
                    .labelsHidden()
                }

                Section("Fördelning") {
                    Picker("Läge", selection: $model.draft.mode) {
                        ForEach(SplitDraft.Mode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    memberRows
                } footer: {
                    RemainderFooter(model: model)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Dela upp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                        .disabled(!model.draft.isBalanced(totalMinor: model.amountMinor, members: model.memberIds))
                }
            }
        }
    }

    // A switch over the mode returning concrete row views — never AnyView (CLAUDE.md).
    @ViewBuilder
    private var memberRows: some View {
        switch model.draft.mode {
        case .equal: EqualRows(model: model, shareMap: shareMap)
        case .exact: ExactRows(model: model, shareMap: shareMap)
        case .percentage: PercentRows(model: model, shareMap: shareMap)
        case .shares: ShareRows(model: model, shareMap: shareMap)
        }
    }
}

// MARK: - Per-mode rows

private struct EqualRows: View {
    @Bindable var model: NewExpenseModel
    let shareMap: [MemberID: Int64]

    var body: some View {
        ForEach(model.members) { member in
            Toggle(isOn: included(member.id)) {
                MemberRowLabel(name: model.name(for: member),
                               shareMinor: shareMap[member.id],
                               currency: model.currency)
            }
            // Stock iOS green is the one loud note in an otherwise warm palette. Sage is the
            // colour this app already uses to mean "counted in your favour".
            .tint(Theme.sage)
        }
    }

    private func included(_ id: MemberID) -> Binding<Bool> {
        Binding(
            get: { model.draft.included.contains(id) },
            set: { on in
                if on { model.draft.included.insert(id) } else { model.draft.included.remove(id) }
            }
        )
    }
}

private struct ExactRows: View {
    @Bindable var model: NewExpenseModel
    let shareMap: [MemberID: Int64]
    @State private var text: [MemberID: String]

    init(model: NewExpenseModel, shareMap: [MemberID: Int64]) {
        self.model = model
        self.shareMap = shareMap
        // Prefill from the draft so editing an existing expense shows its amounts, not blanks.
        _text = State(initialValue: model.draft.exactMinor.compactMapValues { minor in
            minor == 0 ? nil : SplitParse.text(fromMinor: minor)
        })
    }

    var body: some View {
        ForEach(model.members) { member in
            HStack {
                Text(model.name(for: member))
                Spacer()
                TextField("0", text: field(member.id))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .monospacedDigit()
                Text(MoneyFormat.symbol(model.currency)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func field(_ id: MemberID) -> Binding<String> {
        Binding(
            get: { text[id] ?? "" },
            set: { newValue in
                text[id] = newValue
                model.draft.exactMinor[id] = SplitParse.minor(newValue)
            }
        )
    }
}

private struct PercentRows: View {
    @Bindable var model: NewExpenseModel
    let shareMap: [MemberID: Int64]
    @State private var text: [MemberID: String]

    init(model: NewExpenseModel, shareMap: [MemberID: Int64]) {
        self.model = model
        self.shareMap = shareMap
        // Prefill from the draft (basis points share the minor-units text shape: 5025 → "50,25").
        _text = State(initialValue: model.draft.basisPoints.compactMapValues { points in
            points == 0 ? nil : SplitParse.text(fromMinor: points)
        })
    }

    var body: some View {
        ForEach(model.members) { member in
            HStack {
                MemberRowLabel(name: model.name(for: member),
                               shareMinor: shareMap[member.id],
                               currency: model.currency)
                Spacer()
                TextField("0", text: field(member.id))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .monospacedDigit()
                Text(verbatim: "%").foregroundStyle(Theme.secondary)
            }
        }
    }

    private func field(_ id: MemberID) -> Binding<String> {
        Binding(
            get: { text[id] ?? "" },
            set: { newValue in
                text[id] = newValue
                // Percent with up to two decimals is basis points (50,25 % → 5025).
                model.draft.basisPoints[id] = SplitParse.minor(newValue)
            }
        )
    }
}

private struct ShareRows: View {
    @Bindable var model: NewExpenseModel
    let shareMap: [MemberID: Int64]

    var body: some View {
        ForEach(model.members) { member in
            Stepper(value: weight(member.id), in: 0...99) {
                HStack {
                    MemberRowLabel(name: model.name(for: member),
                                   shareMinor: shareMap[member.id],
                                   currency: model.currency)
                    Spacer()
                    Text("\(model.draft.weights[member.id] ?? 0) delar")
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func weight(_ id: MemberID) -> Binding<Int64> {
        Binding(
            get: { model.draft.weights[id] ?? 0 },
            set: { model.draft.weights[id] = $0 }
        )
    }
}

// MARK: - Shared pieces

/// A member's name with their resolved share alongside — the live preview of the split.
private struct MemberRowLabel: View {
    let name: String
    let shareMinor: Int64?
    let currency: CurrencyCode

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
            if let shareMinor {
                Text(MoneyFormat.string(shareMinor, currency))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// The remainder line under the member rows — the human-readable version of the invariant that
/// gates Spara.
private struct RemainderFooter: View {
    let model: NewExpenseModel

    var body: some View {
        let members = model.memberIds
        switch model.draft.mode {
        case .equal:
            Text("Delas lika mellan \(model.draft.included.count)")
        case .exact:
            let remainder = model.amountMinor - model.draft.exactSumMinor(members: members)
            Text("Kvar att fördela: \(MoneyFormat.string(remainder, model.currency, sign: .negativeOnly))")
                .foregroundStyle(remainder == 0 ? Theme.sage : Theme.clay)
        case .percentage:
            let remainingBp = SplitInput.percentageTotalBasisPoints - model.draft.basisPointsSum(members: members)
            Text("Kvar: \(SplitParse.percentString(remainingBp))")
                .foregroundStyle(remainingBp == 0 ? Theme.sage : Theme.clay)
        case .shares:
            let total = model.draft.weightsSum(members: members)
            Text(total > 0 ? "Delas i \(total) delar" : "Lägg till minst en andel")
                .foregroundStyle(total > 0 ? Theme.secondary : Theme.clay)
        }
    }
}

/// Parses the decimal-comma text the split fields use into integer minor units / basis points.
/// Integer arithmetic only — no `Double` touches these numbers.
enum SplitParse {
    /// Inverse of `minor(_:)` for prefilling fields: `14567` → "145,67", `14500` → "145".
    static func text(fromMinor minor: Int64) -> String {
        let whole = minor / 100
        let frac = minor % 100
        return frac == 0 ? "\(whole)" : "\(whole),\(frac < 10 ? "0" : "")\(frac)"
    }

    static func minor(_ raw: String) -> Int64 {
        let cleaned = raw.replacingOccurrences(of: ".", with: ",").filter { $0.isNumber || $0 == "," }
        guard !cleaned.isEmpty else { return 0 }
        let parts = cleaned.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        let kronor = Int64(parts[0]) ?? 0
        var ore: Int64 = 0
        if parts.count > 1, !parts[1].isEmpty {
            let frac = parts[1].prefix(2)
            let padded = frac.count == 1 ? "\(frac)0" : String(frac)
            ore = Int64(padded) ?? 0
        }
        return kronor * 100 + ore
    }

    /// Basis points → "50,25 %" style text.
    static func percentString(_ basisPoints: Int64) -> String {
        let whole = basisPoints / 100
        let frac = basisPoints % 100
        let number = frac == 0 ? "\(whole)" : "\(whole),\(frac < 10 ? "0" : "")\(frac)"
        return "\(number) %"
    }
}
