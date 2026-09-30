import SwiftUI
import Charts
import KvittaCore

/// Roles transcribed from the user's seven-screen visual reference.
enum Editorial {
    static let coal = Color(hex: 0x202020)
    static let raised = Color(hex: 0x303030)
    static let paper = Color(hex: 0xFAFAF9)
    static let mint = Color(hex: 0xC8D8CD)
    static let purple = Color(hex: 0x7974F2)
    static let coral = Color(hex: 0xFA806E)
    static let yellow = Color(hex: 0xF4D66D)
    static let muted = Color(hex: 0xBFC2B7)

    static func heading(_ size: CGFloat = 30) -> Font {
        .custom("AvenirNextCondensed-Medium", size: size, relativeTo: .title)
    }
}

struct EditorialHeading: View {
    let title: String
    var dark = false
    var symbol = "arrow.up.right"
    var action: (() -> Void)?
    var onBack: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let onBack {
                EditorialCircleButton(symbol: "arrow.left", label: String(localized: "Tillbaka"), action: onBack)
            } else {
                Image(systemName: "asterisk")
                    .font(.system(size: 12, weight: .black))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Editorial.coal)
                    .background(Editorial.paper, in: .circle)
                    .accessibilityHidden(true)
            }
            Text(title.uppercased())
                .font(Editorial.heading()).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(dark ? Editorial.coal : Editorial.paper)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 2)
            if let action { EditorialCircleButton(symbol: symbol, label: title, action: action) }
        }
    }
}

struct EditorialCircleButton: View {
    let symbol: String
    let label: String
    var fill = Editorial.paper
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .foregroundStyle(Editorial.coal)
                .frame(width: 32, height: 32).background(fill, in: .circle)
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct EditorialPill: View {
    let title: String
    var selected = false
    var fill = Editorial.paper
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.medium))
                .foregroundStyle(Editorial.coal)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(selected ? Editorial.mint : fill, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct EditorialPanel<Content: View>: View {
    var fill: Color
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content
    var body: some View {
        content().padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: .rect(cornerRadius: 28))
    }
}

/// Shared by the category explorer and group cards so their layers stay identical.
struct EditorialCardStack<Top: View, Metadata: View, Content: View>: View {
    @ViewBuilder let top: () -> Top
    @ViewBuilder let metadata: () -> Metadata
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: -16) {
            top()
                .font(Editorial.heading(20)).foregroundStyle(Editorial.coal)
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Editorial.coral, in: .rect(cornerRadius: 26))
            metadata()
                .foregroundStyle(Editorial.paper)
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Editorial.coal, in: .rect(cornerRadius: 26))
            EditorialPanel(fill: Editorial.yellow, content: content)
        }.clipShape(.rect(cornerRadius: 28))
    }
}

struct EditorialCardTitle: View {
    let title: String
    let symbol: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top))
    }

    var body: some View {
        layout {
            Text(title.uppercased()).font(Editorial.heading(38))
                .foregroundStyle(Editorial.coal)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Image(systemName: symbol).font(.system(size: 20))
                .foregroundStyle(Editorial.paper).frame(width: 40, height: 40)
                .background(Editorial.coal, in: .circle).accessibilityHidden(true)
        }
    }
}

struct EditorialMetadataPill: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Editorial.coral).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.medium)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(Editorial.coal)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Editorial.paper.opacity(0.35), in: .capsule)
    }
}

/// The inset statistic panel used by Spending and group payment summaries.
struct EditorialMetric: View {
    let title: String
    let value: String
    let badge: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerLayout {
                Text(title.uppercased()).font(Editorial.heading(17))
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                EditorialBadge(text: badge).fixedSize()
            }
            Text(value).font(Editorial.heading(36)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(Editorial.coal)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Editorial.paper.opacity(0.17), in: .rect(cornerRadius: 20))
    }
}

struct EditorialBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).monospacedDigit()
            .foregroundStyle(Editorial.paper).padding(.horizontal, 8).padding(.vertical, 5)
            .background(Editorial.coal, in: .capsule)
    }
}

struct EditorialExpenseRow: View {
    let item: ExpenseReport.Item
    var dark = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: Categories.symbol(for: item.categoryId))
                    .font(.body).foregroundStyle(Editorial.coal)
                    .frame(width: 40, height: 40).background(Editorial.coral, in: .circle)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.body.weight(.semibold))
                    Text(item.groupName).font(.caption)
                    Text(MoneyFormat.string(item.amountMinor, item.currency, explicit: true))
                        .font(.subheadline).monospacedDigit()
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                    .frame(width: 28, height: 28).background(Editorial.paper, in: .circle)
                    .foregroundStyle(Editorial.coal)
            }
            .foregroundStyle(dark ? Editorial.coal : Editorial.paper)
            .padding(.vertical, 12).contentShape(.rect)
        }.buttonStyle(.plain)
    }
}

struct EditorialWeekChart: View {
    let items: [ExpenseReport.Item]
    let days: ClosedRange<Int>
    let currency: CurrencyCode
    var area = false
    var payments: [Payment]? = nil
    var barHeight: CGFloat = 210
    @Binding var selectedDay: Int?

    private var points: [(day: Int, total: Int64?)] {
        days.map { day in
            if let payments {
                return (day, GroupPaymentReport.total(payments.filter { $0.date.dayNumber == day }))
            }
            return (day, ExpenseReport.total(items.filter { $0.date.dayNumber == day }))
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            if area {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(days), id: \.self) { day in
                            let count = items.filter { $0.date.dayNumber == day }.count
                            Button { selectedDay = selectedDay == day ? nil : day } label: {
                                VStack(spacing: 6) {
                                    Text(ExpenseReport.dayLabel(day)).font(.caption2)
                                    Text("\(count)").font(.caption2.weight(.semibold))
                                        .frame(width: 32, height: 32)
                                        .background(selectedDay == day ? Editorial.coal : Editorial.paper.opacity(0.7), in: .circle)
                                        .foregroundStyle(selectedDay == day ? Editorial.paper : Editorial.coal)
                                }.foregroundStyle(Editorial.coal).frame(minWidth: 44, minHeight: 60)
                            }.buttonStyle(.plain)
                             .accessibilityLabel(ExpenseReport.label(for: day))
                             .accessibilityValue(String(localized: "\(count) utgifter"))
                             .accessibilityAddTraits(selectedDay == day ? .isSelected : [])
                        }
                    }
                }
            }
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    if let total = point.total {
                        if area {
                            AreaMark(x: .value("Day", point.day), y: .value("Minor units", total))
                                .foregroundStyle(Editorial.coral)
                            LineMark(x: .value("Day", point.day), y: .value("Minor units", total))
                                .foregroundStyle(Editorial.coal).lineStyle(StrokeStyle(lineWidth: 1.5))
                        } else {
                            BarMark(x: .value("Day", point.day), y: .value("Minor units", total), width: .fixed(24))
                                .foregroundStyle(selectedDay == point.day ? Editorial.paper : Editorial.mint)
                                .cornerRadius(8)
                                .annotation(position: .top) {
                                    if selectedDay == point.day {
                                        EditorialBadge(text: MoneyFormat.string(total, currency, explicit: true))
                                    }
                                }
                        }
                    }
                }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartXScale(domain: (days.lowerBound - 1)...(days.upperBound + 1))
            .chartYScale(domain: 0...max(points.compactMap(\.total).max() ?? 0, 1))
            .frame(height: area ? 130 : barHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(payments == nil ? String(localized: "Utgifter per dag, \(currency.code)") : String(localized: "Återbetalningar per dag, \(currency.code)"))
            .accessibilityValue(points.map { "\(ExpenseReport.label(for: $0.day)): \(amount($0.total))" }.joined(separator: "; "))
            if !area {
                HStack(spacing: 4) {
                    ForEach(Array(days), id: \.self) { day in
                        Button { selectedDay = selectedDay == day ? nil : day } label: {
                            Text(ExpenseReport.dayLabel(day))
                                .font(.caption2).foregroundStyle(Editorial.coal)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Circle().fill(Editorial.coal).frame(width: 5, height: 5)
                Text(payments == nil ? String(localized: "Gemensamma utgifter") : String(localized: "Återbetalningar")).font(.caption)
                Spacer()
                Text(currency.code).font(.caption.weight(.semibold))
            }.foregroundStyle(Editorial.coal)
            if payments?.isEmpty ?? items.isEmpty {
                Text(payments == nil ? String(localized: "Inga utgifter under perioden") : String(localized: "Inga avräknade återbetalningar under perioden"))
                    .font(.caption).foregroundStyle(Editorial.coal)
            }
            if points.contains(where: { $0.total == nil }) {
                Text("Beloppet är för stort för att visas.").font(.caption).foregroundStyle(Editorial.coal)
            }
        }
    }
    private func amount(_ minor: Int64?) -> String {
        minor.map { MoneyFormat.string($0, currency, explicit: true) } ?? "—"
    }
}

struct EditorialActivityRow: View {
    let entry: FeedEntry
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.categoryId.map { Categories.symbol(for: $0) } ?? "arrow.left.arrow.right")
                    .foregroundStyle(Editorial.coal).frame(width: 40, height: 40)
                    .background(entry.paymentStatus == nil ? Editorial.coral : Editorial.mint, in: .circle)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title).font(.body.weight(.semibold))
                    Text(entry.subtitle).font(.caption).foregroundStyle(Editorial.muted)
                    Text(MoneyFormat.string(entry.amountMinor, entry.currency, explicit: true)).font(.subheadline).monospacedDigit()
                    if entry.wasEdited { Text("redigerad").font(.caption2) }
                    if entry.paymentStatus == .pending { Text("väntar").font(.caption2) }
                    if entry.paymentStatus == .disputed { Text("bestriden").font(.caption2) }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                    .foregroundStyle(Editorial.coal).frame(width: 28, height: 28)
                    .background(Editorial.paper, in: .circle)
            }.foregroundStyle(Editorial.paper).padding(.vertical, 12).contentShape(.rect)
        }.buttonStyle(.plain)
            .accessibilityElement(children: .combine)
    }
}
