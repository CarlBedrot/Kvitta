import Foundation
import SwiftUI
import KvittaCore

/// The split editor's working state, and the bridge to `SplitCalculator`. It never divides money
/// itself — every mode funnels the user's input into a `SplitInput` and asks
/// `SplitCalculator.resolve` for the resolved shares (CLAUDE.md: never compute a split yourself).
///
/// The same call that produces the live per-member preview is what decides validity: if
/// `resolve` throws (exact doesn't sum to the total, percentages miss 100 %, no shares given),
/// the split simply isn't balanced yet and Spara stays disabled.
struct SplitDraft {
    enum Mode: String, CaseIterable, Identifiable {
        case equal, exact, percentage, shares
        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .equal: return "Lika"
            case .exact: return "Exakt"
            case .percentage: return "Procent"
            case .shares: return "Andelar"
            }
        }

        /// How the summary row reads it ("delas lika (4)").
        var sentenceLabel: LocalizedStringKey {
            switch self {
            case .equal: return "delas lika"
            case .exact: return "delas exakt"
            case .percentage: return "delas i procent"
            case .shares: return "delas i andelar"
            }
        }
    }

    var mode: Mode = .equal
    /// Who the cost is split among in "Lika".
    var included: Set<MemberID>
    var exactMinor: [MemberID: Int64]
    /// Percentage in basis points: 50,25 % → 5025.
    var basisPoints: [MemberID: Int64]
    var weights: [MemberID: Int64]

    init(members: [MemberID]) {
        included = Set(members)
        exactMinor = Dictionary(uniqueKeysWithValues: members.map { ($0, 0) })
        basisPoints = Dictionary(uniqueKeysWithValues: members.map { ($0, 0) })
        // Every share defaulting to 1 makes "Andelar" a valid even split out of the box.
        weights = Dictionary(uniqueKeysWithValues: members.map { ($0, 1) })
    }

    /// Reopens the editor in the mode the expense was created in — the whole reason `splitInput`
    /// is stored on the payload. An input this build cannot interpret (`unrecognized`, or a mode
    /// from a newer client) falls back to Exakt over the *resolved shares*, which reproduces the
    /// stored split precisely without guessing at the original intent.
    init(splitInput: SplitInput?, resolvedShares: [MoneyLine], members: [MemberID]) {
        self.init(members: members)
        switch splitInput {
        case .equal(let among):
            mode = .equal
            included = Set(among)
        case .exact(let amounts):
            mode = .exact
            for line in amounts { exactMinor[line.memberId] = line.amountMinor }
        case .percentage(let points):
            mode = .percentage
            for line in points { basisPoints[line.memberId] = line.weight }
        case .shares(let lines):
            mode = .shares
            for line in lines { weights[line.memberId] = line.weight }
        case .unrecognized, nil:
            mode = .exact
            for line in resolvedShares { exactMinor[line.memberId] = line.amountMinor }
        }
    }

    /// The un-resolved split as the user entered it, in the shape Core expects.
    func splitInput(members: [MemberID]) -> SplitInput {
        switch mode {
        case .equal:
            return .equal(among: members.filter { included.contains($0) })
        case .exact:
            return .exact(members.map { MoneyLine(memberId: $0, amountMinor: exactMinor[$0] ?? 0) })
        case .percentage:
            return .percentage(members.map { WeightLine(memberId: $0, weight: basisPoints[$0] ?? 0) })
        case .shares:
            return .shares(members.map { WeightLine(memberId: $0, weight: weights[$0] ?? 0) })
        }
    }

    /// Resolved shares for the current amount, or `nil` when the split isn't balanced yet. This is
    /// both the live preview and the validity gate — one source of truth via `SplitCalculator`.
    func resolvedShares(totalMinor: Int64, members: [MemberID]) -> [MoneyLine]? {
        try? SplitCalculator.resolve(totalMinor: totalMinor, input: splitInput(members: members))
    }

    func isBalanced(totalMinor: Int64, members: [MemberID]) -> Bool {
        resolvedShares(totalMinor: totalMinor, members: members) != nil
    }

    // MARK: - Sums for the remainder line

    func exactSumMinor(members: [MemberID]) -> Int64 {
        members.reduce(0) { $0 + (exactMinor[$1] ?? 0) }
    }

    func basisPointsSum(members: [MemberID]) -> Int64 {
        members.reduce(0) { $0 + (basisPoints[$1] ?? 0) }
    }

    func weightsSum(members: [MemberID]) -> Int64 {
        members.reduce(0) { $0 + (weights[$1] ?? 0) }
    }

    /// How many people the cost lands on, for the summary row ("delas lika (4)").
    func participantCount(totalMinor: Int64, members: [MemberID]) -> Int {
        preview(totalMinor: totalMinor, members: members).participants.count
    }

    // MARK: - The row under the sentence

    /// The split as the summary row *shows* it: who is in, and what each of them carries.
    struct Preview: Equatable {
        /// Everyone with a share, in the group's member order — the faces on the row.
        let participants: [MemberID]
        /// The resolved lines behind those faces, same order. Empty until there is an amount
        /// and the split balances, because then there is nothing honest to show yet.
        let shares: [MoneyLine]
        /// Set only when every participant carries the same amount — "120 kr var". 100 kr on
        /// three people is 33,34 + 33,33 + 33,33, and that has no single "var".
        let perPersonMinor: Int64?
    }

    /// Read off `SplitCalculator`'s resolved shares — the same lines the saved expense will
    /// carry — never from `amount / count`. The preview and the ledger can therefore not
    /// disagree by an öre, which is the whole point of showing it before Spara.
    ///
    /// With no amount yet the row still knows who is included (Lika) or who has been given
    /// anything (the other modes), so the faces are there before the first digit is typed.
    func preview(totalMinor: Int64, members: [MemberID]) -> Preview {
        if let resolved = resolvedShares(totalMinor: totalMinor, members: members) {
            let byMember = Dictionary(uniqueKeysWithValues: resolved.map { ($0.memberId, $0) })
            let shares = members.compactMap { byMember[$0] }.filter { $0.amountMinor > 0 }
            let amounts = Set(shares.map(\.amountMinor))
            return Preview(
                participants: shares.map(\.memberId),
                shares: shares,
                perPersonMinor: amounts.count == 1 ? amounts.first : nil
            )
        }
        let participants: [MemberID]
        switch mode {
        case .equal: participants = members.filter { included.contains($0) }
        case .exact: participants = members.filter { (exactMinor[$0] ?? 0) > 0 }
        case .percentage: participants = members.filter { (basisPoints[$0] ?? 0) > 0 }
        case .shares: participants = members.filter { (weights[$0] ?? 0) > 0 }
        }
        return Preview(participants: participants, shares: [], perPersonMinor: nil)
    }
}
