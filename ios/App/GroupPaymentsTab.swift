import SwiftUI
import KvittaCore

/// BETALNINGAR (10): an info-card explaining simplified debts and the 7-day auto-confirm, then
/// every payment in the group, newest first, in the same card style UTGIFTER uses (README §1.2,
/// §4.4's diff table).
///
/// **Not wired into `GroupDetailView` yet.** This tab lives behind Steven 4's (#148) `UnderlineTabs`
/// shell, which has not merged — `GroupDetailView` on `main` still uses the pre-Steven
/// `GroupSegment`/`GroupBottomBar` pair, so there is nowhere correct to mount this view today. Once
/// #148 lands, wire it in as the BETALNINGAR case, moving `PendingPaymentsCard` and
/// `GroupRepaymentHistory` out of `GroupDetailView.swift`/`GroupSpendingView.swift` in favour of
/// this file (per the issue's own "Filer" section), and passing it the same `LedgerStore`-derived
/// `group`/`meId` the other tabs already fold once per render, plus an `onAnswer` closure
/// equivalent to `GroupDetailView`'s existing `answer(_:confirmed:)`. Same pattern as
/// `GroupStandingTab` (#149, #167): a new, correct, unwired file rather than a guess at a shell
/// that does not exist on `main` yet.
struct GroupPaymentsTab: View {
    let group: GroupState
    let meId: MemberID?
    let failure: String?
    let onAnswer: (Payment, Bool) -> Void

    @State private var showingInfo = false

    var body: some View {
        LazyVStack(spacing: StevenMetric.cardGap) {
            Button {
                showingInfo = true
            } label: {
                Steven.InfoCard(title: "Så här beräknar vi betalningar", subtitle: "Läs mer här")
            }
            .buttonStyle(.plain)

            ForEach(group.paymentsByDate) { payment in
                PaymentCard(
                    group: group,
                    meId: meId,
                    payment: payment,
                    onConfirm: { onAnswer(payment, true) },
                    onDispute: { onAnswer(payment, false) }
                )
            }

            if let failure {
                Text(verbatim: failure).stevenFont(.footnote).foregroundStyle(StevenColor.owe)
            }
        }
        .padding(.horizontal, StevenMetric.gutter)
        .padding(.top, 12)
        .sheet(isPresented: $showingInfo) {
            PaymentsInfoSheet()
        }
    }
}

// MARK: - Payment card

/// One registered payment (10): a tonal arrow icon, "Carl → Ellen", the amount, the date and a
/// status word. The icon's tint follows who sent it, the same convention `ExpenseCard` uses for
/// who paid (README §2.4). A payee with a decision to make gets the two buttons below.
private struct PaymentCard: View {
    let group: GroupState
    let meId: MemberID?
    let payment: Payment
    let onConfirm: () -> Void
    let onDispute: () -> Void

    private var asOf: CalendarDate { CalendarDate(Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if awaitsMyConfirmation {
                HStack(spacing: 10) {
                    Button("Ja, jag har fått pengarna", action: onConfirm)
                        .buttonStyle(Steven.FilledButtonStyle(height: StevenMetric.compactButtonHeight))
                    Button("Nej", action: onDispute)
                        .buttonStyle(Steven.OutlineButtonStyle(height: StevenMetric.compactButtonHeight))
                }
            }
        }
        .padding(StevenMetric.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stevenCardBackground()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(StevenColor.ink)
                .frame(width: StevenMetric.iconCircle, height: StevenMetric.iconCircle)
                .background(iSent ? StevenColor.accentTint : StevenColor.oweTint, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(name(payment.fromMemberId)) → \(name(payment.toMemberId))")
                        .stevenFont(.rowTitleBold)
                        .foregroundStyle(StevenColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    Steven.MoneyText(
                        amountMinor: payment.amountMinor,
                        currency: payment.currency,
                        explicit: payment.currency != group.currency
                    )
                }
                HStack {
                    Text(verbatim: dateLabel).stevenFont(.footnote).foregroundStyle(StevenColor.muted)
                    Spacer(minLength: 8)
                    statusText
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var statusText: some View {
        switch PaymentDisplayStatus(payment, asOf: asOf) {
        case .waiting:
            Text("Väntar").stevenFont(.footnoteBold).foregroundStyle(StevenColor.muted)
        case .confirmed:
            Text("Bekräftad").stevenFont(.footnoteBold).foregroundStyle(StevenColor.accent)
        case .autoConfirmed:
            Text("Auto-bekräftad").stevenFont(.footnoteBold).foregroundStyle(StevenColor.accent)
        case .disputed:
            Text("Bestriden").stevenFont(.footnoteBold).foregroundStyle(StevenColor.owe)
        }
    }

    private var iSent: Bool {
        guard let meId else { return false }
        return payment.fromMemberId == meId
    }

    private var awaitsMyConfirmation: Bool {
        meId != nil && payment.toMemberId == meId && payment.awaitsConfirmation(asOf: asOf)
    }

    private func name(_ memberId: MemberID) -> String {
        if memberId == meId { return String(localized: "Du") }
        return group.members[memberId]?.displayName ?? "?"
    }

    /// "måndag, 19 okt." — the same weekday-plus-short-month shape `ExpenseCard` uses on UTGIFTER,
    /// so a payment and an expense read the same way next to each other.
    private var dateLabel: String {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let instant = Date(timeIntervalSince1970: Double(payment.date.dayNumber) * 86_400)
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: instant) - 1]
        let month = calendar.shortStandaloneMonthSymbols[payment.date.month - 1]
        return "\(weekday), \(payment.date.day) \(month)"
    }
}

/// The four states 10's acceptance criteria name, folded into one value: confirmed, waiting,
/// disputed, or pending but aged past the 7-day auto-confirm window. A pure function of the
/// payment's own status and today's date — same inputs `Payment.countsTowardBalances(asOf:)`
/// already takes — so it is unit-testable without a ledger.
enum PaymentDisplayStatus: Hashable {
    case waiting, confirmed, autoConfirmed, disputed

    init(_ payment: Payment, asOf: CalendarDate) {
        switch payment.status {
        case .disputed:
            self = .disputed
        case .confirmed:
            self = .confirmed
        case .pending:
            self = payment.countsTowardBalances(asOf: asOf) ? .autoConfirmed : .waiting
        }
    }
}

// MARK: - Info sheet

/// "Läs mer här" (10): what the simplified debts are, and the 7-day auto-confirm window — short,
/// since this is an aside, not an onboarding flow.
private struct PaymentsInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(leading: .close { dismiss() }) {
                Text("Så här beräknar vi betalningar")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Vi räknar ut vem som är skyldig vem och föreslår så få överföringar som möjligt, i stället för att reda ut varje utgift för sig.")
                    Text("En betalning väntar på mottagarens bekräftelse. Bestrider de den räknas den aldrig; svarar ingen alls räknas den ändå efter 7 dagar, så en skuld aldrig fastnar bara för att någon glömmer bekräfta.")
                }
                .stevenFont(.rowTitle)
                .foregroundStyle(StevenColor.ink)
                .padding(StevenMetric.gutter)
                .padding(.top, 8)
            }
        }
        .background(StevenColor.screen)
    }
}
