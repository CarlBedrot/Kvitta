import Foundation

/// Which editor mode produced a split.
///
/// A raw string rather than an enum so an expense created by a newer client using a mode this
/// build has never heard of still decodes. Per design doc §3 rule 4, this is display-only: it
/// exists so the UI can reopen the split editor in the mode you left it in, and it is never used
/// for balance math.
public struct SplitMethod: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let equal = SplitMethod(rawValue: "equal")
    public static let exact = SplitMethod(rawValue: "exact")
    public static let percentage = SplitMethod(rawValue: "percentage")
    public static let shares = SplitMethod(rawValue: "shares")

    public var description: String { rawValue }
}

/// The un-resolved split as the user entered it, kept so the editor can be reopened.
///
/// Percentages are integer **basis points** — 50.25% is `5025` — because floats never touch money
/// in this codebase, not even on the input side where the rounding would be "harmless".
public enum SplitInput: Hashable, Sendable, Codable {
    case equal(among: [MemberID])
    case exact([MoneyLine])
    case percentage([WeightLine])
    case shares([WeightLine])
    /// A split shape this build does not understand, preserved verbatim so it survives a round
    /// trip. Cannot be resolved into shares — but it never needs to be, because the shares it
    /// produced are already stored on the event.
    case unrecognized(JSONValue)

    public static let percentageTotalBasisPoints: Int64 = 10_000

    public var method: SplitMethod {
        switch self {
        case .equal: return .equal
        case .exact: return .exact
        case .percentage: return .percentage
        case .shares: return .shares
        case .unrecognized(let raw):
            return SplitMethod(rawValue: raw["method"]?.stringValue ?? "unknown")
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case method, members, amounts, basisPoints, weights
    }

    public init(from decoder: any Decoder) throws {
        // Anything we cannot confidently interpret is kept whole rather than rejected: this field
        // drives the editor, so a bad guess here would silently change what the user sees.
        guard let container = try? decoder.container(keyedBy: CodingKeys.self),
              let method = try? container.decode(String.self, forKey: .method) else {
            self = .unrecognized(try JSONValue(from: decoder))
            return
        }

        switch method {
        case SplitMethod.equal.rawValue:
            guard let members = try? container.decode([MemberID].self, forKey: .members) else {
                break
            }
            self = .equal(among: members)
            return

        case SplitMethod.exact.rawValue:
            guard let amounts = try? container.decode([MoneyLine].self, forKey: .amounts) else {
                break
            }
            self = .exact(amounts)
            return

        case SplitMethod.percentage.rawValue:
            guard let points = try? container.decode([WeightLine].self, forKey: .basisPoints) else {
                break
            }
            self = .percentage(points)
            return

        case SplitMethod.shares.rawValue:
            guard let weights = try? container.decode([WeightLine].self, forKey: .weights) else {
                break
            }
            self = .shares(weights)
            return

        default:
            break
        }

        self = .unrecognized(try JSONValue(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        if case .unrecognized(let raw) = self {
            var single = encoder.singleValueContainer()
            try single.encode(raw)
            return
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method.rawValue, forKey: .method)
        switch self {
        case .equal(let members): try container.encode(members, forKey: .members)
        case .exact(let amounts): try container.encode(amounts, forKey: .amounts)
        case .percentage(let points): try container.encode(points, forKey: .basisPoints)
        case .shares(let weights): try container.encode(weights, forKey: .weights)
        case .unrecognized: break // handled above
        }
    }
}
