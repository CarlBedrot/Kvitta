import SwiftUI

/// Provider cards describe the supported handoff, never imply an account is connected.
struct PaymentServicesView: View {
    let profile: UserProfile
    let onProfile: () -> Void
    let onSync: () -> Void
    @State private var paymentsOnly = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            EditorialHeading(title: String(localized: "Betalning & konto"), symbol: "person.crop.circle", action: onProfile)
            HStack(spacing: 8) {
                EditorialPill(title: String(localized: "Alla"), selected: !paymentsOnly) { paymentsOnly = false }
                EditorialPill(title: String(localized: "Betalningar"), selected: paymentsOnly) { paymentsOnly = true }
            }
            VStack(spacing: typeSize.isAccessibilitySize ? 16 : 12) {
                service("Swish", subtitle: String(localized: "Svenska nummer · SEK"),
                        footnote: profile.paymentPhone?.country == .sweden ? (profile.paymentPhone?.international ?? "") : String(localized: "Mottagare med +46"),
                        fill: Editorial.coral, angle: -7, symbol: "arrow.up.right", action: onProfile)
                service("MobilePay", subtitle: String(localized: "Danska nummer · DKK"),
                        footnote: profile.paymentPhone?.country == .denmark ? (profile.paymentPhone?.international ?? "") : String(localized: "Mottagare med +45"),
                        fill: Editorial.yellow, angle: 5, symbol: "arrow.up.right", action: onProfile)
                if !paymentsOnly {
                    service(String(localized: "Ditt konto"), subtitle: String(localized: "Profil & synkronisering"),
                            footnote: String(localized: "Se kontostatus"), fill: Editorial.mint,
                            angle: -4, symbol: "arrow.up.right", action: onSync)
                }
            }.padding(.horizontal, 12).padding(.vertical, 16)
        }
    }

    private func service(_ title: String, subtitle: String, footnote: String, fill: Color,
                         angle: Double, symbol: String, action: @escaping () -> Void) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        return Button(action: action) {
            layout {
                VStack(alignment: .leading, spacing: 10) {
                    Text(subtitle.uppercased()).font(.caption2.weight(.semibold))
                    Text(title).font(Editorial.heading(34)).fixedSize(horizontal: false, vertical: true)
                    Text(footnote).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(Editorial.coal, lineWidth: 1))
            }.foregroundStyle(Editorial.coal).padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill, in: .rect(cornerRadius: 24))
                .rotationEffect(.degrees(typeSize.isAccessibilitySize ? 0 : angle))
        }.buttonStyle(.plain)
         .accessibilityHint(title == "Swish" || title == "MobilePay" ? String(localized: "Redigera ditt telefonnummer") : String(localized: "Se kontostatus"))
    }
}
