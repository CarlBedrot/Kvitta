import Foundation

/// A UUID wrapped in a type so an `ExpenseID` can never be passed where a `MemberID` belongs.
///
/// `Comparable` matters more here than it looks: sorting by identifier is the deterministic
/// tie-break behind both rounding remainder distribution and debt simplification. Two devices
/// replaying the same log must agree on that order, so it is defined over the UUID's raw bytes
/// and never over dictionary iteration order.
public protocol EntityIdentifier: RawRepresentable, Hashable, Sendable, Codable, Comparable,
                                  CustomStringConvertible where RawValue == UUID {
    init(rawValue: UUID)
}

extension EntityIdentifier {
    /// A fresh random identifier. Clients generate these; the server never does.
    public init() {
        self.init(rawValue: UUID())
    }

    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.init(rawValue: uuid)
    }

    public var description: String { rawValue.uuidString }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        UUIDOrdering.isLess(lhs.rawValue, rhs.rawValue)
    }
}

public struct GroupID: EntityIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct MemberID: EntityIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct ExpenseID: EntityIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct PaymentID: EntityIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct EventID: EntityIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct UserID: EntityIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

enum UUIDOrdering {
    /// Byte-wise lexicographic order. Stable across platforms and Foundation versions,
    /// unlike anything derived from string formatting or hashing.
    static func isLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
        withUnsafeBytes(of: lhs.uuid) { left in
            withUnsafeBytes(of: rhs.uuid) { right in
                for index in 0..<left.count where left[index] != right[index] {
                    return left[index] < right[index]
                }
                return false
            }
        }
    }
}
