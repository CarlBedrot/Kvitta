import Foundation

/// Every way this package refuses to build something invalid.
///
/// These are thrown at construction time. The point is that an expense violating the money
/// invariant never exists as a value, so no later code has to defend against one.
public enum CoreError: Error, Hashable, Sendable, CustomStringConvertible {
    /// `sum(payers) == sum(shares) == amountMinor` did not hold.
    case invariantViolated(amountMinor: Int64, payersTotal: Int64, sharesTotal: Int64)

    /// An amount that must be positive was zero or negative.
    case nonPositiveAmount(field: String, value: Int64)

    /// A share was negative. Zero is allowed (an exact split may genuinely assign nothing).
    case negativeShare(memberId: MemberID, value: Int64)

    /// The same member appeared twice in a payers or shares list.
    case duplicateMember(memberId: MemberID, field: String)

    /// A payers or shares list was empty.
    case emptyLineItems(field: String)

    /// Two amounts in different currencies were combined.
    case currencyMismatch(expected: CurrencyCode, found: CurrencyCode)

    /// Not a three-letter uppercase ISO-4217-shaped code.
    case invalidCurrencyCode(String)

    /// Split weights did not add up to what the method requires
    /// (10 000 basis points for percentage, a positive total for shares).
    case invalidSplitWeights(reason: String)

    /// An exact split's amounts did not add up to the expense total.
    case exactSplitMismatch(expected: Int64, found: Int64)

    /// A split named no members at all.
    case emptySplit

    /// Intermediate arithmetic left the range of `Int64`.
    /// Thrown rather than trapped so a hostile or corrupt payload cannot kill the app.
    case amountOverflow(context: String)

    /// A member referenced by a split is not one this expense knows about.
    case unknownMember(memberId: MemberID)

    /// A payment moved money from a member to themselves.
    case selfPayment(memberId: MemberID)

    public var description: String {
        switch self {
        case .invariantViolated(let amount, let payers, let shares):
            return """
                Money invariant violated: amountMinor=\(amount), \
                payers total=\(payers), shares total=\(shares). All three must be equal.
                """
        case .nonPositiveAmount(let field, let value):
            return "\(field) must be greater than zero, got \(value)."
        case .negativeShare(let memberId, let value):
            return "Share for member \(memberId) must not be negative, got \(value)."
        case .duplicateMember(let memberId, let field):
            return "Member \(memberId) appears more than once in \(field)."
        case .emptyLineItems(let field):
            return "\(field) must not be empty."
        case .currencyMismatch(let expected, let found):
            return "Currency mismatch: expected \(expected), found \(found)."
        case .invalidCurrencyCode(let raw):
            return "\"\(raw)\" is not a three-letter uppercase currency code."
        case .invalidSplitWeights(let reason):
            return "Invalid split weights: \(reason)"
        case .exactSplitMismatch(let expected, let found):
            return "Exact split must total \(expected) minor units, got \(found)."
        case .emptySplit:
            return "A split must name at least one member."
        case .amountOverflow(let context):
            return "Arithmetic overflow while computing \(context)."
        case .unknownMember(let memberId):
            return "Member \(memberId) is not part of this expense."
        case .selfPayment(let memberId):
            return "A payment cannot move money from member \(memberId) to themselves."
        }
    }
}
