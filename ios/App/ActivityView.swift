import SwiftUI
import KvittaCore
import KvittaStorage

/// Notiser (Steven tab 3, README §3.6, mockup 04): what other people did that touches you,
/// newest first. An expense somebody else put you on, a payment to or from you. Your own actions
/// are not news to you and are left out; everything else in the ledger is on the group screen.
/// No day grouping — Steven has none.
///
/// A card's colour *is* its read state (unread #FEEFE8, read white), set and cleared per entity
/// by `UnreadStore`, not by a dot frozen at the moment the screen appeared. Opening one card never
/// marks its neighbours; "Läs alla" is the only bulk action.
struct ActivityView: View {
    let ledger: LedgerStore
    let userId: UserID
    let unread: UnreadStore
    /// Where a card's tap goes while the Steven group screens (#148–#150) are still mid-rewrite:
    /// the group itself, not yet its exact expense detail sheet or BETALNINGAR flik.
    let onOpenGroup: (GroupID) -> Void

    var body: some View {
        let entries = FeedEntry.build(from: ledger.state, userId: userId)
        VStack(spacing: 0) {
            Steven.ScreenHeader(
                title: "Notiser",
                actionTitle: entries.isEmpty ? nil : "Läs alla",
                actionShowsPlus: false,
                action: { unread.markAllRead(from: ledger) }
            )
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Inga notiser än", systemImage: "bell")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: StevenMetric.cardGap) {
                        ForEach(entries) { entry in
                            FeedCard(entry: entry, isUnread: unread.isUnread(entry.id)) {
                                unread.markRead(entry.id)
                                onOpenGroup(entry.groupId)
                            }
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, StevenMetric.gutter)
                    .padding(.top, 4)
                }
            }
        }
        .background(StevenColor.screen)
        .navigationBarHidden(true)
    }
}

/// One feed line, precomputed so the row view just renders strings.
struct FeedEntry: Identifiable {
    enum Kind {
        case expense
        /// A repayment. Drawn differently: a payment is the ledger healing, not a new cost.
        case payment(incoming: Bool?)
    }

    let id: UUID
    let groupId: GroupID
    let timestamp: Timestamp
    let kind: Kind
    /// The expense's category, for its glyph. `nil` on a payment.
    let categoryId: String?
    let title: String
    let subtitle: String
    let amountMinor: Int64
    let currency: CurrencyCode
    /// The kr-collision rule: an amount not in its group's primary currency spells out its code.
    let explicit: Bool
    let wasEdited: Bool
    /// Set for payments only (M8): pending and disputed rows say so, because a payment that is
    /// visible but not yet in the balances would otherwise look like a bug.
    let paymentStatus: PaymentStatus?
    /// Who did this — the expense's last editor, or whoever recorded the payment. Always someone
    /// other than you: both loops below only include entries somebody else authored. Used for the
    /// Notiser card's avatar and the bold name at the start of its sentence (04).
    let actor: Member?

    enum Scope { case news, allActivity }

    static func build(from state: LedgerState, userId: UserID, scope: Scope = .news) -> [FeedEntry] {
        var entries: [FeedEntry] = []

        for group in state.groups.values {
            let meId = group.me(for: userId)?.id
            let groupTitle = GroupBadge.title(of: group.name)

            func displayName(_ memberId: MemberID) -> String {
                if memberId == meId { return String(localized: "Du") }
                return group.members[memberId]?.displayName ?? "?"
            }

            func member(ofUser uid: UserID) -> Member? {
                group.members.values.first { $0.linkedUserId == uid }
            }

            // News excludes your own edits; the overview/report scope includes them.
            // In both scopes, the entry must involve you.
            for expense in group.visibleExpenses
            where (scope == .allActivity || expense.lastModifiedBy != userId) && expense.payload.involves(meId) {
                let payerName = expense.payload.payers.first.map { displayName($0.memberId) } ?? "?"
                entries.append(FeedEntry(
                    id: expense.id.rawValue,
                    groupId: group.id,
                    timestamp: expense.lastModifiedAt,
                    kind: .expense,
                    categoryId: expense.categoryId,
                    title: expense.title,
                    subtitle: "\(groupTitle) · \(String(localized: "\(payerName) betalade"))",
                    amountMinor: expense.amountMinor,
                    currency: expense.currency,
                    explicit: expense.currency != group.currency,
                    wasEdited: expense.wasEdited,
                    paymentStatus: nil,
                    actor: member(ofUser: expense.lastModifiedBy)
                ))
            }

            for payment in group.paymentsByDate
            where (scope == .allActivity || payment.recordedBy != userId) && (payment.toMemberId == meId || payment.fromMemberId == meId) {
                // Colour only when the money touched you: green coming in, red going out.
                // A payment between two others is news, not your money — it stays ink.
                let incoming: Bool? = switch (payment.toMemberId == meId, payment.fromMemberId == meId) {
                case (true, _): true
                case (_, true): false
                default: nil
                }
                entries.append(FeedEntry(
                    id: payment.id.rawValue,
                    groupId: group.id,
                    timestamp: payment.recordedAt,
                    kind: .payment(incoming: incoming),
                    categoryId: nil,
                    title: String(localized: "\(displayName(payment.fromMemberId)) betalade \(displayName(payment.toMemberId))"),
                    subtitle: groupTitle,
                    amountMinor: payment.amountMinor,
                    currency: payment.currency,
                    explicit: payment.currency != group.currency,
                    wasEdited: false,
                    paymentStatus: payment.status,
                    actor: member(ofUser: payment.recordedBy)
                ))
            }
        }

        // Newest first; id as tie-break so two devices with the same log agree on the order.
        return entries.sorted {
            $0.timestamp == $1.timestamp
                ? $0.id.uuidString > $1.id.uuidString
                : $0.timestamp > $1.timestamp
        }
    }
}

/// One notification (04): korall-tinted while unread, white once opened; the actor's avatar,
/// a sentence naming them and what happened, and a relative timestamp.
private struct FeedCard: View {
    let entry: FeedEntry
    let isUnread: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 6) {
                    sentence
                        .stevenFont(.rowTitle)
                        .foregroundStyle(StevenColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.timestamp.date, format: .relative(presentation: .named))
                        .stevenFont(.footnote)
                        .foregroundStyle(StevenColor.faint)
                }
                Spacer(minLength: 0)
            }
            .padding(StevenMetric.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isUnread ? StevenColor.unread : StevenColor.surface)
                    .clipShape(.rect(cornerRadius: StevenMetric.cardRadius))
                    .stevenShadow(.card)
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: StevenMetric.minimumHitTarget)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isUnread ? Text("Oläst") : Text(verbatim: ""))
    }

    @ViewBuilder private var avatar: some View {
        if let actor = entry.actor {
            Steven.AvatarView(member: actor, size: StevenMetric.avatarHeader)
        } else {
            Steven.AvatarView(name: "?", id: MemberID(), size: StevenMetric.avatarHeader)
        }
    }

    private var actorName: String { entry.actor?.displayName ?? String(localized: "Någon") }

    private var sentence: Text {
        switch entry.kind {
        case .expense:
            let verb: LocalizedStringKey = entry.wasEdited ? "ändrade utgiften" : "lade till dig i utgiften"
            return Text(verbatim: actorName).fontWeight(.bold)
                + Text(verbatim: " ")
                + Text(verb)
                + Text(verbatim: " \u{201C}")
                + Text(verbatim: entry.title).fontWeight(.bold)
                + Text(verbatim: "\u{201D}.")
        case .payment(let incoming):
            let verb: LocalizedStringKey = incoming == false
                ? "registrerade en betalning från dig."
                : "registrerade en betalning till dig."
            return Text(verbatim: actorName).fontWeight(.bold)
                + Text(verbatim: " ")
                + Text(verb)
        }
    }
}
