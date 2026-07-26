import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

@Suite("SplitCalculator")
struct SplitCalculatorTests {
    private let members = (1...3).map { Fixtures.member($0) }

    @Test("Equal split resolves through the same rounding rule as the allocator")
    func equalSplit() throws {
        let shares = try SplitCalculator.resolve(
            total: Fixtures.money(43_700),
            input: .equal(among: members)
        )
        #expect(shares.map(\.amountMinor) == [14_567, 14_567, 14_566])
    }

    @Test("Exact split is taken as given, only reordered")
    func exactSplit() throws {
        let input = SplitInput.exact([
            MoneyLine(memberId: members[2], amountMinor: 1_000),
            MoneyLine(memberId: members[0], amountMinor: 2_500),
            MoneyLine(memberId: members[1], amountMinor: 500)
        ])
        let shares = try SplitCalculator.resolve(total: Fixtures.money(4_000), input: input)

        #expect(shares.map(\.memberId) == members)
        #expect(shares.map(\.amountMinor) == [2_500, 500, 1_000])
    }

    @Test("Exact split that does not add up to the total is rejected")
    func exactSplitMustMatchTotal() {
        let input = SplitInput.exact([
            MoneyLine(memberId: members[0], amountMinor: 100),
            MoneyLine(memberId: members[1], amountMinor: 100)
        ])
        #expect(throws: CoreError.exactSplitMismatch(expected: 500, found: 200)) {
            try SplitCalculator.resolve(total: Fixtures.money(500), input: input)
        }
    }

    @Test("Percentages are basis points and must total 100%")
    func percentageSplit() throws {
        let input = SplitInput.percentage([
            WeightLine(memberId: members[0], weight: 5_000),
            WeightLine(memberId: members[1], weight: 2_500),
            WeightLine(memberId: members[2], weight: 2_500)
        ])
        let shares = try SplitCalculator.resolve(total: Fixtures.money(10_000), input: input)
        #expect(shares.map(\.amountMinor) == [5_000, 2_500, 2_500])
    }

    @Test("Fractional percentages work because basis points are integers")
    func fractionalPercentage() throws {
        // 33.33% / 33.33% / 33.34% — expressible exactly in basis points, unlike in a Double.
        let input = SplitInput.percentage([
            WeightLine(memberId: members[0], weight: 3_333),
            WeightLine(memberId: members[1], weight: 3_333),
            WeightLine(memberId: members[2], weight: 3_334)
        ])
        let shares = try SplitCalculator.resolve(total: Fixtures.money(10_000), input: input)
        #expect(shares.reduce(0) { $0 + $1.amountMinor } == 10_000)
        #expect(shares.map(\.amountMinor) == [3_333, 3_333, 3_334])
    }

    @Test("Percentages that do not total 100% are rejected")
    func percentageMustTotalOneHundred() {
        let input = SplitInput.percentage([
            WeightLine(memberId: members[0], weight: 5_000),
            WeightLine(memberId: members[1], weight: 4_000)
        ])
        #expect(throws: CoreError.self) {
            try SplitCalculator.resolve(total: Fixtures.money(1_000), input: input)
        }
    }

    @Test("Share weights split proportionally")
    func sharesSplit() throws {
        let input = SplitInput.shares([
            WeightLine(memberId: members[0], weight: 2),
            WeightLine(memberId: members[1], weight: 1),
            WeightLine(memberId: members[2], weight: 1)
        ])
        let shares = try SplitCalculator.resolve(total: Fixtures.money(10_001), input: input)
        #expect(shares.reduce(0) { $0 + $1.amountMinor } == 10_001)
        // 5000.5 / 2500.25 / 2500.25 floors to 5000/2500/2500, leaving 1 öre for the lowest id.
        #expect(shares.map(\.amountMinor) == [5_001, 2_500, 2_500])
    }

    @Test("A total of zero or less is not an expense")
    func nonPositiveTotalRejected() {
        for total in [Int64(0), -1] {
            #expect(throws: CoreError.nonPositiveAmount(field: "amountMinor", value: total)) {
                try SplitCalculator.resolve(totalMinor: total, input: .equal(among: members))
            }
        }
    }

    @Test("A split with nobody in it is rejected")
    func emptySplitRejected() {
        #expect(throws: CoreError.emptySplit) {
            try SplitCalculator.resolve(total: Fixtures.money(100), input: .equal(among: []))
        }
    }

    @Test("A split mode this build does not understand cannot be resolved")
    func unrecognizedSplitCannotResolve() {
        let input = SplitInput.unrecognized(.object(["method": .string("byMoonPhase")]))
        #expect(input.method.rawValue == "byMoonPhase")
        #expect(throws: CoreError.self) {
            try SplitCalculator.resolve(total: Fixtures.money(100), input: input)
        }
    }

    @Test("The same input always produces the same shares, however the members are ordered")
    func resolutionIsOrderIndependent() throws {
        let forwards = try SplitCalculator.resolve(
            total: Fixtures.money(99_991),
            input: .equal(among: members)
        )
        let backwards = try SplitCalculator.resolve(
            total: Fixtures.money(99_991),
            input: .equal(among: members.reversed())
        )
        #expect(forwards == backwards)
    }
}
