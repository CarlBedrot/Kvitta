import SwiftUI
import KvittaCore
import KvittaSync

struct SliceMark: View {
    var size: CGFloat = 32
    var usesGradient = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(usesGradient
                  ? AnyShapeStyle(LinearGradient(colors: [Theme.brandBlue, Theme.heroHighlight], startPoint: .topLeading, endPoint: .bottomTrailing))
                  : AnyShapeStyle(Theme.brandBlue))
            .frame(width: size, height: size)
            .overlay {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.07)
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct BrandLogo: View {
    var body: some View {
        HStack(spacing: 8) {
            SliceMark(size: 30)
            Text("slice")
                .font(.title2.weight(.bold))
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slice")
    }
}

struct PageHeader: View {
    let title: LocalizedStringKey
    let profile: UserProfile
    var onProfile: (() -> Void)?
    var showsBrand = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Group {
                if showsBrand { BrandLogo() }
                else { Text(title).font(.title.weight(.semibold)).foregroundStyle(Theme.ink) }
            }
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(action: { onProfile?() }) {
                Avatar(name: profile.nameOrDefault, photo: profile.avatarData, size: 40)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Öppna Profil")
        }
    }
}

struct SyncStatusBanner: View {
    let status: SyncStatus
    let onRetry: () -> Void

    private var isVisible: Bool {
        switch status {
        case .offline, .blocked: true
        case .disabled, .idle, .syncing: false
        }
    }

    var body: some View {
        if isVisible {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: status.isBlocked ? "exclamationmark.triangle.fill" : "icloud.slash.fill")
                    .foregroundStyle(status.isBlocked ? Theme.clay : Theme.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.isBlocked ? String(localized: "Synk behöver din hjälp") : String(localized: "Offline – dina ändringar är sparade"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(status.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button("Försök igen", action: onRetry)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(status.accessibilityText)
        }
    }
}

struct SettingsRow<Content: View>: View {
    let systemImage: String
    let fill: Color
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(fill)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 12)
            content()
        }
        .frame(minHeight: 44)
    }
}

private extension SyncStatus {
    var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }

    var detail: String {
        switch self {
        case .offline(let detail): return detail.isEmpty ? String(localized: "Vi försöker igen när anslutningen är tillbaka.") : detail
        case .blocked(let detail): return detail
        case .disabled, .idle, .syncing: return ""
        }
    }

    var accessibilityText: String {
        switch self {
        case .offline: return String(localized: "Offline. Dina ändringar är sparade lokalt.")
        case .blocked: return String(localized: "Synk behöver din hjälp.")
        case .disabled, .idle, .syncing: return ""
        }
    }
}

struct BalanceHero: View {
    let summary: BalanceBook.Summary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var bothDirections: Bool { summary.receivableMinor > 0 && summary.payableMinor > 0 }
    private var direction: LocalizedStringKey {
        bothDirections ? "Netto" : summary.receivableMinor > 0 ? "Du ska få" : "Du ska betala"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if summary.hasOpenBalances {
                Text(direction).font(.subheadline.weight(.medium)).foregroundStyle(Theme.heroSecondary)
                Text(MoneyFormat.string(bothDirections ? summary.netMinor : abs(summary.netMinor),
                                        summary.currency, sign: bothDirections ? .always : .none, explicit: true))
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.heroText)
                    .fixedSize(horizontal: false, vertical: true)
                if bothDirections {
                    Divider().overlay(Theme.heroSecondary.opacity(0.25))
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                    layout {
                        HeroTotal(title: "Du ska få", amount: summary.receivableMinor, currency: summary.currency)
                        HeroTotal(title: "Du ska betala", amount: summary.payableMinor, currency: summary.currency)
                    }
                }
            } else {
                Label("Kvitt i \(summary.currency.code)", systemImage: "checkmark.circle")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.heroText)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.hero, in: .rect(cornerRadius: 20))
    }
}

private struct HeroTotal: View {
    let title: LocalizedStringKey
    let amount: Int64
    let currency: CurrencyCode

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(Theme.heroSecondary)
            Text(MoneyFormat.string(amount, currency, explicit: true))
                .font(.headline).monospacedDigit().foregroundStyle(Theme.heroText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
