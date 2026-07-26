import SwiftUI
import KvittaCore
import KvittaStorage

/// Gör upp: confirm one suggested transfer and record that the money moved.
///
/// The app never moves money (design doc §4) — this writes a `PaymentRecorded` event saying it
/// moved elsewhere. The Swish prefill deep link is Milestone 5; until then "Markera som betald"
/// is the whole flow, which is also exactly what the cash case needs forever.
struct SettleUpSheet: View {
    let ledger: LedgerStore
    let userId: UserID
    let groupId: GroupID
    let transfer: SuggestedTransfer

    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?
    @State private var settleTick = 0

    private var group: GroupState? { ledger.state[groupId] }

    var body: some View {
        VStack(spacing: 0) {
            Text("Gör upp")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 28)

            (Text(name(transfer.from)) + Text(verbatim: " → ") + Text(name(transfer.to)))
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .padding(.top, 4)

            amountSection
            Spacer()

            if let failure {
                Text(failure).font(.footnote).foregroundStyle(Theme.clay).padding(.bottom, 8)
            }

            Button(action: settle) {
                Text("Markera som betald")
                    .font(.headline)
                    .foregroundStyle(Color(hex: 0xF6F1E7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .glassEffect(.regular.tint(Theme.espresso).interactive(), in: .rect(cornerRadius: 24))
            .padding(.horizontal, 20)

            Button("Avbryt") { dismiss() }
                .foregroundStyle(Theme.clay)
                .padding(.top, 14)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(AmbientBackground())
        .sensoryFeedback(.success, trigger: settleTick)
    }

    private var amountSection: some View {
        let currency = group?.currency ?? .sek
        return VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(MoneyFormat.string(transfer.amountMinor, currency))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            ZeroLine(amountMinor: -transfer.amountMinor, scaleMinor: transfer.amountMinor * 2)
                .padding(.horizontal, 40)
            Text("Efter betalningen: 0 kr · ni är kvitt 🎉")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        }
        .padding(.top, 20)
    }

    private func name(_ memberId: MemberID) -> String {
        if memberId == group?.me(for: userId)?.id { return String(localized: "Du") }
        return group?.members[memberId]?.displayName ?? "?"
    }

    private func settle() {
        guard let group else { return }
        do {
            try ledger.record(
                .paymentRecorded(try PaymentRecordedPayload(
                    fromMemberId: transfer.from,
                    toMemberId: transfer.to,
                    currency: group.currency,
                    amountMinor: transfer.amountMinor,
                    date: CalendarDate(Date()),
                    method: .cash
                )),
                entityId: PaymentID().rawValue,
                in: groupId
            )
            settleTick += 1
            dismiss()
        } catch {
            // A failed local write stays on screen — never a silently lost payment (CLAUDE.md).
            failure = String(describing: error)
        }
    }
}
