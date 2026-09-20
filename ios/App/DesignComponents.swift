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
                .font(.system(size: 31, weight: .heavy))
                .tracking(-1.4)
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slice")
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    let profile: UserProfile
    var onProfile: (() -> Void)?
    var showGreeting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                BrandLogo()
                Spacer()
                Button(action: { onProfile?() }) {
                    Avatar(name: profile.nameOrDefault, photo: profile.avatarData, size: 42)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Öppna Profil")
            }
            VStack(alignment: .leading, spacing: 4) {
                if showGreeting {
                    Text(profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Hej där" : "Hej \(profile.nameOrDefault)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.secondary)
                }
                Text(title)
                    .font(.system(size: 39, weight: .heavy))
                    .tracking(-1.3)
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
            }
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
                    Text(status.isBlocked ? "Synk behöver din hjälp" : "Offline – dina ändringar är sparade")
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
    let title: String
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
        case .offline(let detail): return detail.isEmpty ? "Vi försöker igen när anslutningen är tillbaka." : detail
        case .blocked(let detail): return detail
        case .disabled, .idle, .syncing: return ""
        }
    }

    var accessibilityText: String {
        switch self {
        case .offline: return "Offline. Dina ändringar är sparade lokalt."
        case .blocked: return "Synk behöver din hjälp."
        case .disabled, .idle, .syncing: return ""
        }
    }
}

struct BalanceHero: View {
    let summary: BalanceBook.Summary
    let label: String
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Theme.heroSecondary)
                    Text(summary.hasOpenBalances
                         ? (summary.netMinor == 0 ? "0 \(summary.currency.code) netto" : MoneyFormat.string(summary.netMinor, summary.currency, sign: .always))
                         : "Allt är jämnt")
                        .font(.system(size: 42, weight: .heavy))
                        .monospacedDigit()
                        .minimumScaleFactor(0.68)
                        .foregroundStyle(Theme.heroText)
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(Theme.heroSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 12)
                SliceMark(size: 62, usesGradient: true)
                    .opacity(0.9)
            }
            Divider().overlay(Theme.heroSecondary.opacity(0.25))
            HStack(alignment: .top, spacing: 16) {
                HeroTotal(title: "Du ska få", amount: summary.receivableMinor, currency: summary.currency, color: Theme.positive)
                Rectangle().fill(Theme.heroSecondary.opacity(0.25)).frame(width: 1, height: 36)
                HeroTotal(title: "Du ska betala", amount: summary.payableMinor, currency: summary.currency, color: Theme.negative)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.hero, in: .rect(cornerRadius: 24))
    }
}

private struct HeroTotal: View {
    let title: String
    let amount: Int64
    let currency: CurrencyCode
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(Theme.heroSecondary)
            Text(MoneyFormat.string(amount, currency))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(amount == 0 ? Theme.heroSecondary : color)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
