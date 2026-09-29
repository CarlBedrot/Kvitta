import Foundation
import Testing
import KvittaCore
import KvittaStorage
@testable import Kvitta

@MainActor
struct ActivityScopeTests {
    @Test func ownAndPartnerEditsPaymentsAndDeletionStayScoped() throws {
        let store = try EventStore.inMemory()
        let me = UserID(), partner = UserID(), group = GroupID(), myMember = MemberID(), theirMember = MemberID()
        let mine = LedgerStore(store: store, authorId: me)
        let theirs = LedgerStore(store: store, authorId: partner)
        try mine.record(.groupCreated(GroupCreatedPayload(name: "Home", currency: .sek)), entityId: group.rawValue, in: group)
        try mine.record(.memberAdded(MemberAddedPayload(displayName: "Carl", linkedUserId: me)), entityId: myMember.rawValue, in: group)
        try mine.record(.memberAdded(MemberAddedPayload(displayName: "Partner", linkedUserId: partner)), entityId: theirMember.rawValue, in: group)
        func payload(_ name: String) throws -> ExpensePayload {
            try ExpensePayload.make(description: name, categoryId: "restaurang", date: CalendarDate(iso8601: "2026-09-29")!,
                                    total: Money(amountMinor: 12345, currency: .sek), paidBy: myMember,
                                    splitEquallyAmong: [myMember, theirMember])
        }
        let ownID = ExpenseID(), partnerID = ExpenseID()
        try mine.record(.expenseCreated(try payload("Own dinner")), entityId: ownID.rawValue, in: group)
        try theirs.rebuild()
        try theirs.record(.expenseCreated(try payload("Partner dinner")), entityId: partnerID.rawValue, in: group)
        try mine.rebuild()
        #expect(FeedEntry.build(from: mine.state, userId: me).map(\.id) == [partnerID.rawValue])
        #expect(FeedEntry.build(from: mine.state, userId: me, scope: .allActivity).count == 2)
        try mine.record(.expenseUpdated(try payload("Edited dinner")), entityId: ownID.rawValue, in: group)
        let edited = FeedEntry.build(from: mine.state, userId: me, scope: .allActivity).first { $0.id == ownID.rawValue }
        #expect(edited?.title == "Edited dinner")
        #expect(edited?.wasEdited == true)
        #expect(edited?.amountMinor == 12345)
        #expect(edited?.currency == .sek)
        let payment = PaymentID()
        try mine.record(.paymentRecorded(try PaymentRecordedPayload(fromMemberId: myMember, toMemberId: theirMember,
                                                                    currency: .sek, amountMinor: 500,
                                                                    date: CalendarDate(iso8601: "2026-09-29")!,
                                                                    method: PaymentMethod(rawValue: "swish"))),
                        entityId: payment.rawValue, in: group)
        let all = FeedEntry.build(from: mine.state, userId: me, scope: .allActivity)
        #expect(all.count == 3)
        #expect(all.first { $0.id == payment.rawValue }?.paymentStatus == .pending)
        #expect(FeedEntry.build(from: mine.state, userId: me).count == 1)
        #expect(all.map(\.id) == FeedEntry.build(from: mine.state, userId: me, scope: .allActivity).map(\.id))
        try mine.record(.expenseDeleted(EmptyPayload()), entityId: ownID.rawValue, in: group)
        #expect(!FeedEntry.build(from: mine.state, userId: me, scope: .allActivity).contains { $0.id == ownID.rawValue })
        #expect(FeedEntry.build(from: LedgerState(), userId: me, scope: .allActivity).isEmpty)
    }
}
