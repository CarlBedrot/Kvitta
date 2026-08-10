import SwiftUI
import KvittaCore
import KvittaStorage
import KvittaSync

/// A throwaway in-memory ledger for Previews, populated through the real write path so what a
/// Preview renders is exactly what the app computes — including the 145,67 / 145,67 / 145,66
/// worked example from the design doc. Never used outside Previews.
@MainActor
enum PreviewLedger {
    static let userId = UserID()

    private static let configuration = SyncConfiguration(baseURL: URL(string: "http://localhost")!)

    /// A permanently disabled sync engine. Previews must never reach a network, and `.disabled`
    /// makes every entry point on the engine an immediate no-op.
    static func sync(_ ledger: LedgerStore) -> SyncEngine {
        SyncEngine(
            ledger: ledger,
            transport: HTTPSyncTransport(configuration: configuration, tokens: tokens()),
            userId: userId,
            settings: .disabled
        )
    }

    /// In-memory, never the Keychain: a Preview must not read or write the real session.
    static func tokens() -> AuthTokenProvider {
        AuthTokenProvider(
            store: InMemoryTokenStore(),
            refresher: HTTPAuthClient(configuration: configuration)
        )
    }

    static func invites(_ ledger: LedgerStore) -> InviteModel {
        InviteModel(
            transport: HTTPSyncTransport(configuration: configuration, tokens: tokens()),
            sync: sync(ledger),
            session: session(ledger),
            profile: UserProfile(defaults: .previewProfile)
        )
    }

    /// Signed out, so the syncer's guards make every call a no-op — Previews never reach a network.
    static func profiles(_ ledger: LedgerStore) -> ProfileSyncer {
        ProfileSyncer(
            transport: HTTPSyncTransport(configuration: configuration, tokens: tokens()),
            session: session(ledger),
            defaults: .previewProfile
        )
    }

    /// Same signed-out silence as `profiles`, and a throwaway image store.
    static func photos(_ ledger: LedgerStore) -> GroupPhotoSyncer {
        GroupPhotoSyncer(
            transport: HTTPSyncTransport(configuration: configuration, tokens: tokens()),
            session: session(ledger),
            images: GroupImageStore(defaults: .previewProfile)
        )
    }

    static func session(_ ledger: LedgerStore) -> SessionModel {
        let provider = AuthTokenProvider(
            store: InMemoryTokenStore(),
            refresher: HTTPAuthClient(configuration: configuration)
        )

        return SessionModel(
            tokens: provider,
            provider: DeveloperSignInProvider(
                client: HTTPAuthClient(configuration: configuration),
                userId: userId
            ),
            ledger: ledger,
            sync: sync(ledger)
        )
    }

    static func populated() -> LedgerStore {
        let ledger = empty()
        do {
            let malmo = try group(
                in: ledger, name: "🏖️ Malmö-gänget",
                members: [("Du", userId), ("Jonas", nil), ("Sara", nil), ("Ellen", nil)]
            )
            let apartment = try group(
                in: ledger, name: "🏠 Lägenheten",
                members: [("Du", userId), ("Alex", nil)]
            )

            try expense(in: ledger, group: malmo.0, description: "Systembolaget",
                        categoryId: "alkohol", totalMinor: 43_700,
                        paidBy: malmo.1[0], among: Array(malmo.1.prefix(3)))
            try expense(in: ledger, group: apartment.0, description: "Städgrejer",
                        categoryId: "groceries", totalMinor: 30_400,
                        paidBy: apartment.1[1], among: apartment.1)
        } catch {
            // A preview fixture that cannot build is a programmer error worth hearing about.
            assertionFailure(String(describing: error))
        }
        return ledger
    }

    static func empty() -> LedgerStore {
        // Force-try is acceptable here: an in-memory database that fails to open means the
        // preview host itself is broken.
        // swiftlint:disable:next force_try
        let ledger = LedgerStore(store: try! EventStore.inMemory(), authorId: userId)
        return ledger
    }

    private static func group(
        in ledger: LedgerStore, name: String, members: [(String, UserID?)]
    ) throws -> (GroupID, [MemberID]) {
        let groupId = GroupID()
        try ledger.record(
            .groupCreated(GroupCreatedPayload(name: name, currency: .sek)),
            entityId: groupId.rawValue, in: groupId
        )
        var memberIds: [MemberID] = []
        for (memberName, linked) in members {
            let memberId = MemberID()
            memberIds.append(memberId)
            try ledger.record(
                .memberAdded(MemberAddedPayload(displayName: memberName, linkedUserId: linked)),
                entityId: memberId.rawValue, in: groupId
            )
        }
        return (groupId, memberIds)
    }

    private static func expense(
        in ledger: LedgerStore, group groupId: GroupID, description: String,
        categoryId: String, totalMinor: Int64, paidBy: MemberID, among: [MemberID]
    ) throws {
        try ledger.record(
            .expenseCreated(try ExpensePayload.make(
                description: description,
                categoryId: categoryId,
                date: CalendarDate(Date()),
                total: Money(amountMinor: totalMinor, currency: .sek),
                paidBy: paidBy,
                splitEquallyAmong: among
            )),
            entityId: ExpenseID().rawValue, in: groupId
        )
    }
}

#Preview("Hem") {
    let ledger = PreviewLedger.populated()
    RootView(ledger: ledger, userId: PreviewLedger.userId, sync: PreviewLedger.sync(ledger),
             profile: UserProfile(defaults: .previewProfile), session: PreviewLedger.session(ledger),
             invites: PreviewLedger.invites(ledger), reminders: ReminderScheduler(),
             rates: RateStore(defaults: .previewProfile), profiles: PreviewLedger.profiles(ledger),
             photos: PreviewLedger.photos(ledger))
}

#Preview("Hem – tom") {
    let ledger = PreviewLedger.empty()
    RootView(ledger: ledger, userId: PreviewLedger.userId, sync: PreviewLedger.sync(ledger),
             profile: UserProfile(defaults: .previewProfile), session: PreviewLedger.session(ledger),
             invites: PreviewLedger.invites(ledger), reminders: ReminderScheduler(),
             rates: RateStore(defaults: .previewProfile), profiles: PreviewLedger.profiles(ledger),
             photos: PreviewLedger.photos(ledger))
}

#Preview("Ny utgift") {
    let ledger = PreviewLedger.populated()
    let groupId = ledger.state.groupsByLastActivity.first!.id
    NewExpenseSheet(
        model: NewExpenseModel(ledger: ledger, userId: PreviewLedger.userId, groupId: groupId)
    )
}

#Preview("Gruppvy") {
    let ledger = PreviewLedger.populated()
    // The Malmö group: four members, one 437 kr expense split among three.
    let group = ledger.state.groupsByLastActivity.first { $0.activeMembers.count == 4 }!
    NavigationStack {
        GroupDetailView(ledger: ledger, userId: PreviewLedger.userId, groupId: group.id,
                        invites: PreviewLedger.invites(ledger),
                        profile: UserProfile(defaults: .previewProfile),
                        photos: PreviewLedger.photos(ledger),
                        rates: RateStore(defaults: .previewProfile),
                        profiles: PreviewLedger.profiles(ledger))
    }
}

#Preview("Balansgranskning") {
    let ledger = PreviewLedger.populated()
    let group = ledger.state.groupsByLastActivity.first { $0.activeMembers.count == 4 }!
    BalanceAuditSheet(
        ledger: ledger,
        userId: PreviewLedger.userId,
        groupId: group.id,
        memberId: group.me(for: PreviewLedger.userId)!.id
    )
}

#Preview("Utgiftsdetalj") {
    let ledger = PreviewLedger.populated()
    let group = ledger.state.groupsByLastActivity.first { $0.activeMembers.count == 4 }!
    ExpenseDetailSheet(
        ledger: ledger,
        userId: PreviewLedger.userId,
        groupId: group.id,
        expenseId: group.visibleExpenses.first!.id
    )
}

#Preview("Aktivitet") {
    NavigationStack {
        ActivityView(
            ledger: PreviewLedger.populated(),
            userId: PreviewLedger.userId,
            // A throwaway suite, so a preview can never mark the simulator's real feed as read.
            unread: UnreadStore(defaults: UserDefaults(suiteName: "preview.unread") ?? .standard)
        )
    }
}

#Preview("Dela upp") {
    let ledger = PreviewLedger.populated()
    let groupId = ledger.state.groupsByLastActivity.first!.id
    let model = NewExpenseModel(ledger: ledger, userId: PreviewLedger.userId, groupId: groupId)
    let _ = { for d in "437" { model.amount.input(d) } }()
    SplitEditorSheet(model: model)
}
