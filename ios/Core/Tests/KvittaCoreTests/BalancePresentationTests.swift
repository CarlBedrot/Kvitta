import Foundation
import Testing
@testable import KvittaCore

@Suite("Balance presentation")
struct BalancePresentationTests {
    private let user = UserID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let me = MemberID(uuidString: "00000000-0000-0000-0000-000000000010")!

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
}
