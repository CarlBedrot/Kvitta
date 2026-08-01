import Foundation
import Testing
import KvittaCore
import KvittaStorage
import KvittaSync
@testable import Kvitta

/// The felrapport must be safe to forward without thinking — that property is the feature,
/// so it gets a test rather than a promise.
@MainActor
struct DiagnosticReportTests {

    @Test("The report carries state but never names or amounts")
    func reportLeaksNothing() throws {
        let ledger = LedgerStore(store: try EventStore.inMemory(), authorId: UserID())
        let groupId = GroupID()
        try ledger.record(
            .groupCreated(GroupCreatedPayload(name: "Hemliga Gänget", currency: .sek)),
            entityId: groupId.rawValue, in: groupId
        )
        let member = MemberID()
        try ledger.record(
            .memberAdded(MemberAddedPayload(displayName: "Hemlig Person")),
            entityId: member.rawValue, in: groupId
        )
        try ledger.record(
            .expenseCreated(try ExpensePayload.make(
                description: "Hemlig Krog",
                categoryId: "restaurang",
                date: CalendarDate(year: 2026, month: 7, day: 21)!,
                total: Money(amountMinor: 123_456, currency: .sek),
                paidBy: member,
                splitEquallyAmong: [member]
            )),
            entityId: ExpenseID().rawValue, in: groupId
        )

        let configuration = SyncConfiguration(baseURL: URL(string: "http://localhost")!)
        let sync = SyncEngine(
            ledger: ledger,
            transport: HTTPSyncTransport(
                configuration: configuration,
                tokens: AuthTokenProvider(
                    store: InMemoryTokenStore(),
                    refresher: HTTPAuthClient(configuration: configuration)
                )
            ),
            userId: UserID(),
            settings: .disabled
        )
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!

        let report = DiagnosticReport.text(
            ledger: ledger,
            sync: sync,
            rates: RateStore(defaults: suite),
            signedIn: false
        )

        // It says what happened…
        #expect(report.contains("Grupper: 1"))
        #expect(report.contains("1 medlemmar, 1 utgifter"))
        #expect(report.contains("utloggad"))

        // …and nothing about whom or how much.
        #expect(!report.contains("Hemlig"))
        #expect(!report.contains("1234,56"))
        #expect(!report.contains("123456"))
    }
}
