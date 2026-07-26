import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

@Suite("Allocator")
struct AllocatorTests {

    @Test("437.00 kr three ways is 145.67 + 145.67 + 145.66, exactly as the design doc says")
    func designDocWorkedExample() throws {
        let members = [Fixtures.member(1), Fixtures.member(2), Fixtures.member(3)]
        let shares = try Allocator.allocate(
            totalMinor: 43_700,
            weights: members.map { WeightLine(memberId: $0, weight: 1) }
        )

        #expect(shares.map(\.amountMinor) == [14_567, 14_567, 14_566])
        #expect(shares.map(\.memberId) == members)
    }

    @Test("The leftover öre go to the lowest member ids, whatever order the input arrives in")
    func remainderGoesToLowestIdsRegardlessOfInputOrder() throws {
        let members = [Fixtures.member(1), Fixtures.member(2), Fixtures.member(3)]
        let forwards = try Allocator.allocate(
            totalMinor: 43_700,
            weights: members.map { WeightLine(memberId: $0, weight: 1) }
        )
        let backwards = try Allocator.allocate(
            totalMinor: 43_700,
            weights: members.reversed().map { WeightLine(memberId: $0, weight: 1) }
        )

        #expect(forwards == backwards)
        #expect(forwards.last?.amountMinor == 14_566)
    }

    @Test("Shares always add up to the total, for every remainder from 0 to 6")
    func sharesAlwaysSumToTotal() throws {
        let members = (1...7).map { Fixtures.member($0) }
        for total in Int64(1)...Int64(200) {
            let shares = try Allocator.allocate(
                totalMinor: total,
                weights: members.map { WeightLine(memberId: $0, weight: 1) }
            )
            #expect(shares.reduce(0) { $0 + $1.amountMinor } == total, "total \(total)")
        }
    }

    @Test("Weights split proportionally")
    func weightedSplit() throws {
        let shares = try Allocator.allocate(
            totalMinor: 1_000,
            weights: [
                WeightLine(memberId: Fixtures.member(1), weight: 3),
                WeightLine(memberId: Fixtures.member(2), weight: 1)
            ]
        )
        #expect(shares.map(\.amountMinor) == [750, 250])
    }

    @Test("A total smaller than the number of members leaves some at zero, and still balances")
    func totalSmallerThanMemberCount() throws {
        let members = (1...5).map { Fixtures.member($0) }
        let shares = try Allocator.allocate(
            totalMinor: 2,
            weights: members.map { WeightLine(memberId: $0, weight: 1) }
        )
        #expect(shares.map(\.amountMinor) == [1, 1, 0, 0, 0])
    }

    @Test("Zero splits into nothing at all")
    func zeroTotal() throws {
        let shares = try Allocator.allocate(
            totalMinor: 0,
            weights: (1...3).map { WeightLine(memberId: Fixtures.member($0), weight: 1) }
        )
        #expect(shares.allSatisfy { $0.amountMinor == 0 })
    }

    @Test("A member with zero weight pays nothing")
    func zeroWeightMemberPaysNothing() throws {
        let shares = try Allocator.allocate(
            totalMinor: 900,
            weights: [
                WeightLine(memberId: Fixtures.member(1), weight: 0),
                WeightLine(memberId: Fixtures.member(2), weight: 1),
                WeightLine(memberId: Fixtures.member(3), weight: 2)
            ]
        )
        #expect(shares.map(\.amountMinor) == [0, 300, 600])
    }

    @Test("Refuses an empty split")
    func emptySplitThrows() {
        #expect(throws: CoreError.emptySplit) {
            try Allocator.allocate(totalMinor: 100, weights: [])
        }
    }

    @Test("Refuses weights that add up to nothing")
    func zeroTotalWeightThrows() {
        #expect(throws: CoreError.self) {
            try Allocator.allocate(
                totalMinor: 100,
                weights: [WeightLine(memberId: Fixtures.member(1), weight: 0)]
            )
        }
    }

    @Test("Refuses a negative weight")
    func negativeWeightThrows() {
        #expect(throws: CoreError.self) {
            try Allocator.allocate(
                totalMinor: 100,
                weights: [
                    WeightLine(memberId: Fixtures.member(1), weight: -1),
                    WeightLine(memberId: Fixtures.member(2), weight: 2)
                ]
            )
        }
    }

    @Test("Refuses the same member twice")
    func duplicateMemberThrows() {
        #expect(throws: CoreError.duplicateMember(memberId: Fixtures.member(1), field: "split weights")) {
            try Allocator.allocate(
                totalMinor: 100,
                weights: [
                    WeightLine(memberId: Fixtures.member(1), weight: 1),
                    WeightLine(memberId: Fixtures.member(1), weight: 1)
                ]
            )
        }
    }

    @Test("Throws rather than trapping when the arithmetic would overflow")
    func overflowThrows() {
        #expect(throws: CoreError.self) {
            try Allocator.allocate(
                totalMinor: Int64.max,
                weights: [
                    WeightLine(memberId: Fixtures.member(1), weight: Int64.max),
                    WeightLine(memberId: Fixtures.member(2), weight: 1)
                ]
            )
        }
    }
}
