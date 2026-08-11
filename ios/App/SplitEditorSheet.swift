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
                    PayerStrip(model: model)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
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

/// Who the bill is split between: faces you tap, not a column of switches.
///
/// A switch is a settings control — it asks "is this option on", one row at a time, and reading a
/// four-person split meant scanning four of them for a colour. Faces answer the actual question,
/// which is *who*, in one glance: the people who are in are lit and carry their share, the people
/// who are out have stepped back. It is also the same avatar that identifies these people
/// everywhere else in the app, so nobody has to read a name to know who they are looking at.
private struct EqualRows: View {
    @Bindable var model: NewExpenseModel
    let shareMap: [MemberID: Int64]

    private let columns = [GridItem(.adaptive(minimum: 78, maximum: 110), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(model.members) { member in
                PersonToggle(
                    name: model.name(for: member),
                    isMe: model.meId == member.id,
                    isOn: model.draft.included.contains(member.id),
                    shareMinor: shareMap[member.id],
                    currency: model.currency,
                    action: { toggle(member.id) }
                )
            }
        }
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .animation(.spring(duration: 0.28), value: model.draft.included)

        Button(allIncluded ? "Ingen" : "Alla") {
            if allIncluded {
                model.draft.included.removeAll()
            } else {
                model.draft.included = Set(model.memberIds)
            }
        }
        .font(.subheadline.weight(.medium))
    }

    private var allIncluded: Bool {
        !model.memberIds.isEmpty && model.draft.included.count == model.memberIds.count
    }

    private func toggle(_ id: MemberID) {
        if model.draft.included.contains(id) {
            model.draft.included.remove(id)
        } else {
            model.draft.included.insert(id)
        }
    }
}

/// One face in the split grid.
///
/// Selected is the loud state on purpose: an accent ring, a tick, and the share in full colour.
/// Deselected drains the colour out of the avatar rather than hiding the person, because who is
/// *not* in a split is information too — and a face that disappeared would read as a bug.
private struct PersonToggle: View {
    let name: String
    let isMe: Bool
    let isOn: Bool
    let shareMinor: Int64?
    let currency: CurrencyCode
    let action: () -> Void

    @Environment(\.myAvatarPhoto) private var myPhoto

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Avatar(name: name, photo: isMe ? myPhoto : nil, size: 54)
                        .saturation(isOn ? 1 : 0)
                        .opacity(isOn ? 1 : 0.45)
                        .overlay(
                            Circle().strokeBorder(Theme.accent, lineWidth: isOn ? 2.5 : 0)
                                .padding(-3)
                        )
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Theme.accent, in: .circle)
                            .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .scaleEffect(isOn ? 1 : 0.92)

                Text(name)
                    .font(.caption.weight(isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Theme.ink : Theme.tertiary)
                    .lineLimit(1)

                // The share keeps its slot when the person is out, so the grid does not reflow on
                // every tap — an en dash is the placeholder.
                Group {
                    if isOn, let shareMinor {
                        Text(MoneyFormat.string(shareMinor, currency))
                            .foregroundStyle(Theme.secondary)
                    } else {
                        Text(verbatim: "–").foregroundStyle(Theme.tertiary)
                    }
                }
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isOn ? "Ta bort ur fördelningen" : "Lägg till i fördelningen")
    }
}

/// Who paid, as a row of faces rather than a wheel.
///
/// Exactly one person is always chosen here, which is what separates it from the grid above: this
/// one never empties, so tapping the person who is already selected does nothing rather than
/// leaving the expense with no payer.
private struct PayerStrip: View {
    @Bindable var model: NewExpenseModel

    @Environment(\.myAvatarPhoto) private var myPhoto

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(model.members) { member in
                    let isPayer = model.payerId == member.id
                    Button {
                        model.payerId = member.id
                    } label: {
                        VStack(spacing: 6) {
                            Avatar(
                                name: model.name(for: member),
                                photo: model.meId == member.id ? myPhoto : nil,
                                size: 48
                            )
                            .opacity(isPayer ? 1 : 0.5)
                            .overlay(
                                Circle().strokeBorder(Theme.accent, lineWidth: isPayer ? 2.5 : 0)
                                    .padding(-3)
                            )
                            Text(model.name(for: member))
                                .font(.caption.weight(isPayer ? .semibold : .regular))
                                .foregroundStyle(isPayer ? Theme.ink : Theme.tertiary)
                                .lineLimit(1)
                        }
                        .frame(width: 68)
                        .contentShape(.rect)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel(model.name(for: member))
                    .accessibilityAddTraits(isPayer ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, 16)
        }
        .animation(.spring(duration: 0.28), value: model.payerId)
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
                MemberRowLabel(name: model.name(for: member),
                               isMe: model.meId == member.id,
                               shareMinor: nil,
                               currency: model.currency)
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
                               isMe: model.meId == member.id,
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
                                   isMe: model.meId == member.id,
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

/// A member's face and name with their resolved share under it — the live preview of the split.
///
/// The avatar is here for the same reason it is in the grid above: these rows are about people,
/// and the exact/procent/andelar modes should not suddenly become a list of strings just because
/// they happen to carry a text field.
private struct MemberRowLabel: View {
    let name: String
    var isMe = false
    let shareMinor: Int64?
    let currency: CurrencyCode

    @Environment(\.myAvatarPhoto) private var myPhoto

    var body: some View {
        HStack(spacing: 10) {
            Avatar(name: name, photo: isMe ? myPhoto : nil, size: 32)
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
