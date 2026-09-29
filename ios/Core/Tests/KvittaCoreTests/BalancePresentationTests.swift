import Foundation
import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

@Suite("Balance presentation")
struct BalancePresentationTests {
    private let user = UserID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let me = MemberID(uuidString: "00000000-0000-0000-0000-000000000010")!

    @Test("Display prioritizes personal open balances, including zero-net debts")
    func openCurrenciesLead() {
        let friend = MemberID()
        let otherUser = UserID()
        let members = [me: Member(id: me, displayName: "Jag", linkedUserId: user),
                       friend: Member(id: friend, displayName: "Partner", linkedUserId: otherUser)]
        func group(_ currency: CurrencyCode, _ amount: Int64) -> BalanceBook.GroupSlice {
            .init(name: "Test", balances: GroupBalances(byCurrency: [
                Balances(currency: currency, byMember: [me: amount, friend: -amount])
            ]), members: members)
        }
        let offset = BalanceBook(groups: [group(.dkk, 0), group(.sek, 500), group(.sek, -500)])
        let summaries = offset.summariesForDisplay(userId: user)
        #expect(summaries.map(\.currency) == [.sek, .dkk])
        #expect(summaries.first?.netMinor == 0)
        #expect(summaries.first?.hasOpenBalances == true)
        #expect(summaries.first?.receivableMinor == 500)
        #expect(summaries.first?.payableMinor == 500)
        let mixed = BalanceBook(groups: [group(.dkk, 0), group(.sek, 500)])
        #expect(mixed.summariesForDisplay(userId: user).first?.currency == .sek)
        #expect(mixed.summariesForDisplay(userId: otherUser).first?.payableMinor == 500)
        #expect(mixed.summariesForDisplay(userId: UserID()).map(\.currency) == [.dkk, .sek])
        let both = BalanceBook(groups: [group(.sek, 500_000), group(.dkk, 1)])
        #expect(both.summariesForDisplay(userId: user).map(\.currency) == [.dkk, .sek])
        let settled = BalanceBook(groups: [group(.sek, 0), group(.dkk, 0)])
        #expect(settled.summariesForDisplay(userId: user).allSatisfy { !$0.hasOpenBalances })
        #expect(settled.summariesForDisplay(userId: user).map(\.currency) == [.dkk, .sek])
        #expect(BalanceBook(groups: []).summariesForDisplay(userId: user).isEmpty)
    }

    @Test("Summaries never mix currencies and agree with the net")
    func summariesAreCurrencyScoped() {
        let user = UserID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let me = MemberID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let friend = MemberID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let members = [me: Member(id: me, displayName: "Jag", linkedUserId: user),
                       friend: Member(id: friend, displayName: "Ellen")]
        let sek = GroupBalances(byCurrency: [Balances(currency: .sek, byMember: [me: 1_860, friend: -1_860])])
        let dkk = GroupBalances(byCurrency: [Balances(currency: .dkk, byMember: [me: -620, friend: 620])])
        let book = BalanceBook(groups: [
            .init(name: "Helg", balances: sek, members: members),
            .init(name: "Köpenhamn", balances: dkk, members: members)
        ])

        #expect(book.summary(for: .sek, userId: user).netMinor == 1_860)
        #expect(book.summary(for: .sek, userId: user).payableMinor == 0)
        #expect(book.summary(for: .dkk, userId: user).netMinor == -620)
        #expect(book.currencies.map(\.code) == ["DKK", "SEK"])
    }

    @Test("Offsetting debts remain visible as open person rows")
    func offsettingDebtsRemainOpen() {
        let user = UserID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let me = MemberID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let friend = MemberID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let members = [me: Member(id: me, displayName: "Jag", linkedUserId: user),
                       friend: Member(id: friend, displayName: "Anna")]
        let first = GroupBalances(byCurrency: [Balances(currency: .sek, byMember: [me: 500, friend: -500])])
        let second = GroupBalances(byCurrency: [Balances(currency: .sek, byMember: [me: -500, friend: 500])])
        let people = BalanceBook(groups: [.init(name: "A", balances: first, members: members),
                                          .init(name: "B", balances: second, members: members)])
            .people(for: .sek, userId: user)

        #expect(people.count == 1)
        #expect(people[0].amountMinor == 0)
        #expect(people[0].hasOpenBalance)
        #expect(people[0].receivableMinor == 500)
        #expect(people[0].payableMinor == 500)
    }

    @Test("Person direction follows the transfer, not the counterpart balance")
    func personDirectionIsTransferBased() {
        let friend = MemberID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let members = [me: Member(id: me, displayName: "Jag", linkedUserId: user),
                       friend: Member(id: friend, displayName: "Johan")]
        let book = BalanceBook(groups: [.init(name: "Middag", balances: GroupBalances(byCurrency: [
            Balances(currency: .sek, byMember: [me: -420, friend: 420])
        ]), members: members)])
        let person = book.people(for: .sek, userId: user)[0]
        #expect(person.amountMinor == -420)
        #expect(!person.isReceivable)
    }

    @Test("Three-person simplification excludes transfers unrelated to the user")
    func unrelatedTransfersAreExcluded() {
        let anna = MemberID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let viktor = MemberID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let members = [me: Member(id: me, displayName: "Jag", linkedUserId: user),
                       anna: Member(id: anna, displayName: "Anna"), viktor: Member(id: viktor, displayName: "Viktor")]
        let book = BalanceBook(groups: [.init(name: "Helg", balances: GroupBalances(byCurrency: [
            Balances(currency: .sek, byMember: [me: 0, anna: -500, viktor: 500])
        ]), members: members)])
        #expect(book.people(for: .sek, userId: user).isEmpty)
        #expect(book.summary(for: .sek, userId: user).netMinor == 0)
    }

    @Test("Linked users merge across separate member ids")
    func linkedUsersMergeAcrossGroups() {
        let friendA = MemberID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let friendB = MemberID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let friendUser = UserID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let firstMembers = [me: Member(id: me, displayName: "Jag", linkedUserId: user),
                            friendA: Member(id: friendA, displayName: "Ellen", linkedUserId: friendUser)]
        let secondMembers = [me: Member(id: me, displayName: "Jag", linkedUserId: user),
                             friendB: Member(id: friendB, displayName: "Ellen", linkedUserId: friendUser)]
        let book = BalanceBook(groups: [
            .init(name: "A", balances: GroupBalances(byCurrency: [Balances(currency: .sek, byMember: [me: 500, friendA: -500])]), members: firstMembers),
            .init(name: "B", balances: GroupBalances(byCurrency: [Balances(currency: .sek, byMember: [me: 700, friendB: -700])]), members: secondMembers)
        ])
        let people = book.people(for: .sek, userId: user)
        #expect(people.count == 1)
        #expect(people[0].amountMinor == 1_200)
        #expect(people[0].groupCount == 2)
    }

    @Test("Cross-group summaries and person directions reconcile for generated balances")
    func generatedBalancesReconcile() {
        for seed in UInt64(0)..<200 {
            var random = SeededRandom(seed: seed)
            let users = (0..<4).map { _ in UserID(rawValue: random.nextUUID()) }
            var groups: [BalanceBook.GroupSlice] = []
            var expected: [CurrencyCode: Int64] = [:]
            for index in 0..<3 {
                let ids = users.map { _ in MemberID(rawValue: random.nextUUID()) }
                let members = Dictionary(uniqueKeysWithValues: zip(ids, users).enumerated().map { offset, pair in
                    (pair.0, Member(id: pair.0, displayName: "Person \(offset)", linkedUserId: pair.1))
                })
                let buckets = [CurrencyCode.sek, .dkk].map { currency in
                    var values = ids.dropLast().map { _ in random.nextInt64(in: -100_000...100_000) }
                    values.append(-values.reduce(0, +))
                    expected[currency, default: 0] += values[0]
                    return Balances(currency: currency, byMember: Dictionary(uniqueKeysWithValues: zip(ids, values)))
                }
                groups.append(.init(name: "Group \(index)", balances: GroupBalances(byCurrency: buckets), members: members))
            }
            let book = BalanceBook(groups: groups)
            let display = book.summariesForDisplay(userId: users[0])
            #expect(Set(display.map(\.currency)) == Set(book.currencies))
            #expect(display == BalanceBook(groups: groups.reversed()).summariesForDisplay(userId: users[0]))
            #expect(display.drop { $0.hasOpenBalances }.allSatisfy { !$0.hasOpenBalances })
            for currency in book.currencies {
                let summary = book.summary(for: currency, userId: users[0])
                #expect(display.first { $0.currency == currency } == summary)
                let people = book.people(for: currency, userId: users[0])
                #expect(summary.netMinor == expected[currency], "seed \(seed)")
                #expect(people.reduce(0) { $0 + $1.receivableMinor } == summary.receivableMinor, "seed \(seed)")
                #expect(people.reduce(0) { $0 + $1.payableMinor } == summary.payableMinor, "seed \(seed)")
                #expect(people.allSatisfy { $0.amountMinor == $0.receivableMinor - $0.payableMinor })
                let reversed = BalanceBook(groups: groups.reversed()).people(for: currency, userId: users[0])
                #expect(people.map(\.identity) == reversed.map(\.identity))
                #expect(people.map(\.receivableMinor) == reversed.map(\.receivableMinor))
                #expect(people.map(\.payableMinor) == reversed.map(\.payableMinor))
            }
        }
    }
}
