import Foundation

/// SplitMix64. Small, fast, and — the only reason it is here rather than `SystemRandomNumberGenerator` —
/// completely reproducible.
///
/// A property test that fails on run 617 of 1000 is worthless if run 617 is different next time.
/// Every generated history in this suite is a pure function of its seed, so a failure reported as
/// "seed 617" can be reproduced exactly, forever, on any machine.
public struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        // Any seed is legal, including zero — SplitMix64 has no bad states.
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A UUID drawn from this generator rather than the system's, so identifiers — and therefore
    /// every tie-break that depends on their ordering — are reproducible too.
    public mutating func nextUUID() -> UUID {
        let high = next()
        let low = next()
        func byte(_ value: UInt64, _ index: Int) -> UInt8 {
            UInt8(truncatingIfNeeded: value >> UInt64(8 * index))
        }
        return UUID(uuid: (
            byte(high, 0), byte(high, 1), byte(high, 2), byte(high, 3),
            byte(high, 4), byte(high, 5), byte(high, 6), byte(high, 7),
            byte(low, 0), byte(low, 1), byte(low, 2), byte(low, 3),
            byte(low, 4), byte(low, 5), byte(low, 6), byte(low, 7)
        ))
    }

    public mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    public mutating func nextInt64(in range: ClosedRange<Int64>) -> Int64 {
        Int64.random(in: range, using: &self)
    }

    public mutating func chance(_ percent: Int) -> Bool {
        nextInt(in: 1...100) <= percent
    }

    public mutating func pick<T>(_ options: [T]) -> T {
        options[nextInt(in: 0...(options.count - 1))]
    }

    /// A subset of at least `minimum` elements, chosen by index so the result never depends on
    /// `Set` iteration order.
    public mutating func pickSome<T>(_ options: [T], atLeast minimum: Int = 1) -> [T] {
        precondition(minimum >= 1 && options.count >= minimum)
        var indices: [Int] = []
        for index in options.indices where chance(60) {
            indices.append(index)
        }
        // Top up deterministically rather than by rejection sampling, so this always terminates.
        while indices.count < minimum {
            guard let next = options.indices.first(where: { !indices.contains($0) }) else { break }
            indices.append(next)
        }
        indices.sort()
        return indices.map { options[$0] }
    }
}
