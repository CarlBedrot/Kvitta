import SwiftUI
import UIKit
import KvittaCore
import KvittaStorage

/// Gör upp: confirm one suggested transfer and record that the money moved.
///
/// The app never moves money (design doc §11) — it hands the amount to Swish or MobilePay and then
/// writes a `PaymentRecorded` event saying the money moved. "Markera som betald" stays the whole
/// flow for cash, and is the fallback whenever the payment app is not installed.
struct SettleUpSheet: View {
    let ledger: LedgerStore
    let userId: UserID
    let groupId: GroupID
    let transfer: SuggestedTransfer
    let payees: PayeeDirectory
    let profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var failure: String?
    @State private var settleTick = 0

    /// Set when we hand off to a payment app, so coming back can ask whether it worked.
    ///
    /// Pre-staged rather than written on the way out: nothing about opening Swish means the money
    /// moved. People change their mind at the confirm screen, and a payment recorded for a
    /// transfer that never happened is worse than one that is missing — the missing one is
    /// obvious, and the phantom one quietly makes the books wrong for everybody.
    @State private var awaitingReturn: PaymentMethod?
    @State private var askingToConfirm = false
    @State private var swishNumber = ""
    @State private var askingForNumber = false
    @State private var copiedAmount = false

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

            if copiedAmount {
                Text("Beloppet är kopierat — klistra in det i MobilePay.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(.bottom, 8)
            }

            if let failure {
                Text(failure).font(.footnote).foregroundStyle(Theme.clay).padding(.bottom, 8)
            }

            if theyOweMe {
                // Only SEK has a link worth sending. In any other currency the person paying
                // arranges it themselves and "Markera som betald" below is the whole flow —
                // offering MobilePay here would invite you to pay a debt owed *to* you.
                if transfer.currency == .sek {
                    RequestPaymentButton(link: requestLink)
                }
            } else if let link = paymentLink {
                // Swish pink, deliberately off-palette: recognition beats palette purity for a
                // button whose whole job is to look like the app it opens (ui-design.md).
                Button(link.method == .swish ? "Öppna Swish" : "Öppna MobilePay") {
                    handOff(to: link)
                }
                .buttonStyle(PrimaryButtonStyle(
                    fill: link.method == .swish ? Color(hex: 0xEE4A9B) : Color(hex: 0x5A78FF)
                ))
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            } else if needsNumber {
                Button("Öppna Swish") { askingForNumber = true }
                    .buttonStyle(PrimaryButtonStyle(fill: Color(hex: 0xEE4A9B)))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            Button("Markera som betald") { settle(method: .cash) }
                .buttonStyle(PrimaryButtonStyle(fill: Theme.ink))
                .padding(.horizontal, 20)

            Button("Avbryt") { dismiss() }
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 14)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(AmbientBackground())
        .sensoryFeedback(.success, trigger: settleTick)
        .onChange(of: scenePhase) { _, phase in
            // Back from the payment app. Asking is the point — see `awaitingReturn`.
            guard phase == .active, awaitingReturn != nil else { return }
            askingToConfirm = true
        }
        .alert("Swish-nummer", isPresented: $askingForNumber) {
            TextField("07XX XXX XX XX", text: $swishNumber)
                .keyboardType(.phonePad)
            Button("Öppna Swish") {
                payees.remember(swishNumber, for: transfer.to)
                if let link = link(payee: swishNumber) { handOff(to: link) }
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            // Said plainly, because a phone number is the kind of thing people reasonably want to
            // know the fate of before typing it in.
            Text("Sparas bara på den här telefonen, inte i gruppen.")
        }
        .confirmationDialog(
            "Gick betalningen igenom?",
            isPresented: $askingToConfirm,
            titleVisibility: .visible
        ) {
            Button("Ja, betalt") { settle(method: awaitingReturn ?? .cash) }
            Button("Nej, inte än", role: .cancel) { awaitingReturn = nil }
        }
    }

    private var amountSection: some View {
        // The transfer's own bucket — in a mixed group a DKK debt is a DKK payment, and the
        // code is spelled out whenever it strays from the group's primary.
        let currency = transfer.currency
        let explicit = currency != group?.currency
        return VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(MoneyFormat.string(transfer.amountMinor, currency, explicit: explicit))
                    .font(.system(size: 44, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            ZeroLine(amountMinor: -transfer.amountMinor, scaleMinor: transfer.amountMinor * 2)
                .padding(.horizontal, 40)
            Text("Efter betalningen: \(MoneyFormat.string(0, currency, explicit: explicit)) · ni är kvitt i \(currency.code) 🎉")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        }
        .padding(.top, 20)
    }

    private func name(_ memberId: MemberID) -> String {
        if memberId == group?.me(for: userId)?.id { return String(localized: "Du") }
        return group?.members[memberId]?.displayName ?? "?"
    }

    /// The money is coming to you, so there is nothing here for you to pay.
    ///
    /// Opening Swish would be wrong twice: it would have you send money you are owed, and it would
    /// need the other person's number when the one that matters is yours.
    private var theyOweMe: Bool {
        transfer.to == group?.me(for: userId)?.id
    }

    /// The payment-app link for this transfer, if the currency has one and we know a number.
    private var paymentLink: PaymentLink? {
        link(payee: payees.number(for: transfer.to))
    }

    private func link(payee: String?) -> PaymentLink? {
        guard let group else { return nil }
        return PaymentLinkBuilder.preferred(
            for: Money(amountMinor: transfer.amountMinor, currency: transfer.currency),
            payee: payee,
            message: group.name
        )
    }

    /// The link you send someone who owes you: your number, their amount, already filled in.
    ///
    /// This is how your Swish number reaches another person — one message, that you chose to send,
    /// about one debt. It is deliberately not an event: an event is immutable, so a phone number
    /// in a group log would sit on every member's device forever with no way to withdraw it
    /// (CLAUDE.md). `nil` until you have set a number in Jag, and the button says so.
    private var requestLink: URL? {
        guard let group, let number = profile.swishNumberForPayment else { return nil }
        // The `swish://payment?data=` shape, the one a real phone accepts — not the app.swish.nu
        // link, which it rejects as "felaktigt format". No callback: the recipient is not us.
        return PaymentLinkBuilder.swishAppSwitch(
            payee: number,
            amount: Money(amountMinor: transfer.amountMinor, currency: transfer.currency),
            message: group.name,
            callback: nil
        )?.url
    }

    /// A SEK transfer with nobody's number yet: offer to ask for it rather than hiding the button.
    private var needsNumber: Bool {
        transfer.currency == .sek && payees.number(for: transfer.to) == nil
    }

    private func handOff(to link: PaymentLink) {
        if link.method == .mobilePay {
            // MobilePay has no public person-to-person prefill, so the exact amount goes on the
            // clipboard instead — paste beats retyping a number you can mistype.
            UIPasteboard.general.string = PaymentLinkBuilder.decimalString(transfer.amountMinor)
            copiedAmount = true
        }
        awaitingReturn = link.method
        openURL(link.url) { opened in
            guard !opened else { return }
            // The app is not installed. Say so rather than leaving a button that does nothing.
            awaitingReturn = nil
            failure = link.method == .swish
                ? String(localized: "Swish verkar inte finnas på den här telefonen.")
                : String(localized: "MobilePay verkar inte finnas på den här telefonen.")
        }
    }

    /// What you get instead of "Öppna Swish" when the money is owed to you.
    ///
    /// A share sheet rather than a button that does something: only the other person can move the
    /// money, so the most this screen can do is hand you the message to send. "Markera som betald"
    /// stays underneath, for when they have paid you by some other route entirely.
    private struct RequestPaymentButton: View {
        let link: URL?

        var body: some View {
            if let link {
                ShareLink(item: link) {
                    Text("Skicka betallänk")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(hex: 0xEE4A9B), in: .rect(cornerRadius: 22))
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            } else {
                // Said rather than hidden: a missing button looks like a missing feature, and the
                // fix is one field away under Jag.
                Text("Lägg till ditt Swish-nummer under Jag för att kunna skicka en betallänk.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 10)
            }
        }
    }

    private func settle(method: PaymentMethod) {
        awaitingReturn = nil
        guard let group else { return }
        do {
            try ledger.record(
                .paymentRecorded(try PaymentRecordedPayload(
                    fromMemberId: transfer.from,
                    toMemberId: transfer.to,
                    currency: group.currency,
                    amountMinor: transfer.amountMinor,
                    date: CalendarDate(Date()),
                    method: method
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
