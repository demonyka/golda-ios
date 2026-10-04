import GoldaCore
import SwiftUI

/// The period's spending on one screen, in Accounts' grammar: the period picker, the ring with the
/// total, the categories under it, the days as bars, and income and exchange losses to close. The
/// port of Android's `AnalyticsScreen`.
///
/// A category row picks its slice in the ring; the bars can be scrubbed with a finger.
struct InsightsScreen: View {
    let data: AppData
    let today: LocalDate

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var kind: PeriodKind = .week
    @State private var custom: Period?
    /// The ring's picked slice; a new period starts without one.
    @State private var picked: Int?
    @State private var rangeRequest: RangeRequest?

    /// The calendar sheet over the screen. [revertTo] is the choice to go back to when it is
    /// cancelled: the segmented control has already moved by then.
    private struct RangeRequest: Identifiable {
        let revertTo: PeriodKind
        let id = UUID()
    }

    var body: some View {
        let content = InsightsContent(data: data, today: today, kind: kind, custom: custom)
        List {
            headerSection(content)
            if !content.isEmpty {
                categoriesSection(content)
                daysSection(content)
            }
            totalsRow(content)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(Theme.Gap.m))
        .scrollContentBackground(.hidden)
        .background(Theme.Color.page)
        .animation(.snappy, value: content.rows)
        .sheet(item: $rangeRequest) { request in
            PeriodRangeSheet(
                period: content.period, zone: data.zone,
                onCancel: {
                    kind = request.revertTo
                    rangeRequest = nil
                },
                onDone: { period in
                    custom = period
                    kind = .custom
                    picked = nil
                    rangeRequest = nil
                }
            )
        }
    }

    // MARK: Period

    /// "Неделя · Месяц · С 10 сент. · 📅", and under it, for a range of your own, its dates.
    private func periodRow(_ content: InsightsContent) -> some View {
        VStack(spacing: Theme.Gap.s) {
            Picker(selection: kindBinding) {
                ForEach(PeriodKind.allCases, id: \.self) { option in
                    if option == .custom {
                        Image(systemName: "calendar")
                            .accessibilityLabel(Text(verbatim: InsightsContent.customTitle.text(in: locale)))
                            .tag(option)
                    } else {
                        Text(verbatim: content.title(of: option, in: locale)).tag(option)
                    }
                }
            } label: {
                Text(verbatim: InsightsContent.customTitle.text(in: locale))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("insights.period")
            if kind == .custom {
                Button {
                    rangeRequest = RangeRequest(revertTo: .custom)
                } label: {
                    Text(verbatim: content.rangeText(in: locale))
                        .font(.subheadline.weight(.medium))
                        .tabularDigits()
                        .frame(maxWidth: .infinity, minHeight: Theme.minimumTarget)
                        .contentShape(.rect)
                }
                // The system blue: it is an action, it opens the dates (D34).
                .foregroundStyle(.tint)
                .accessibilityHint(Text(verbatim: InsightsContent.rangeHint.text(in: locale)))
                .accessibilityIdentifier("insights.range")
            }
        }
        // The picker stays where it is when the dates appear under it.
        .frame(minHeight: Theme.minimumTarget, alignment: .top)
    }

    /// Choosing the calendar opens the dates and changes nothing until they are taken, as on Android.
    private var kindBinding: Binding<PeriodKind> {
        Binding(
            get: { kind },
            set: { choice in
                if choice == .custom {
                    rangeRequest = RangeRequest(revertTo: kind)
                } else {
                    kind = choice
                    picked = nil
                }
            }
        )
    }

    // MARK: Sections

    /// The picker, and under it the ring, or the word that there is nothing to show.
    private func headerSection(_ content: InsightsContent) -> some View {
        Section {
            periodRow(content)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if content.isEmpty {
                Text(verbatim: InsightsContent.emptyText.text(in: locale))
                    .font(.body)
                    .foregroundStyle(Theme.Color.muted)
                    .listRowInsets(EdgeInsets(top: Theme.Gap.s, leading: Theme.Gap.l, bottom: Theme.Gap.s, trailing: Theme.Gap.l))
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("insights.empty")
            } else {
                CategoryRing(content: content, picked: $picked)
                    .listRowInsets(EdgeInsets(top: Theme.Gap.m, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    private func categoriesSection(_ content: InsightsContent) -> some View {
        let focus = content.focus(picked)
        return Section {
            ForEach(content.rows) { row in
                Button {
                    picked = picked == row.slice ? nil : row.slice
                } label: {
                    CategoryRowView(row: row)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.Color.card)
                .listRowInsets(EdgeInsets(top: 0, leading: Theme.Gap.m, bottom: 0, trailing: Theme.Gap.m))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: row.accessibilityLabel(in: locale)))
                .accessibilityHint(Text(verbatim: InsightsContent.rowHint.text(in: locale)))
                .accessibilityAddTraits(focus == row.slice ? .isSelected : [])
                .accessibilityIdentifier("insights.category")
            }
        }
    }

    private func daysSection(_ content: InsightsContent) -> some View {
        Section {
            DayBarsChart(content: content)
                .padding(.vertical, Theme.Gap.s)
                .listRowBackground(Theme.Color.card)
        }
    }

    /// Income and exchange losses side by side; stacked once the type is too big for two columns.
    private func totalsRow(_ content: InsightsContent) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Theme.Gap.s)) : AnyLayout(HStackLayout(spacing: Theme.Gap.s))
        return Section {
            layout {
                InsightsTile(title: InsightsContent.incomeTitle, value: content.income, detail: nil)
                    .accessibilityIdentifier("insights.income")
                InsightsTile(title: InsightsContent.exchangeTitle, value: content.exchangeLoss, detail: content.exchangeDetail(in: locale))
                    .accessibilityIdentifier("insights.exchange")
            }
            .fixedSize(horizontal: false, vertical: true)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

/// A category under the ring: its dot (the slice's tone), its symbol, name, amount and share. At the
/// accessibility sizes the amount goes under the name: side by side they cut each other off.
private struct CategoryRowView: View {
    let row: InsightsRow

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The symbols' column grows with the text: a fixed 24 pt let the larger sizes' cart and shirt
    /// spill into the names.
    @ScaledMetric(relativeTo: .body) private var symbolWidth: CGFloat = 24

    var body: some View {
        HStack(spacing: Theme.Gap.m) {
            Circle()
                .fill(RingTone.color(slice: row.slice, isRest: row.isRest))
                .frame(width: 12, height: 12)
                // "The rest" is the card's own tone in the dark theme: a hairline keeps its dot there.
                .overlay { if row.isRest { Circle().strokeBorder(Theme.Color.line, lineWidth: 1) } }
            Image(systemName: row.symbol)
                .foregroundStyle(Theme.Color.muted)
                .frame(width: symbolWidth)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                    name
                    figures
                }
                Spacer(minLength: 0)
            } else {
                name
                Spacer(minLength: Theme.Gap.s)
                figures
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? Theme.Gap.s : 0)
        .frame(minHeight: Theme.minimumTarget)
        .contentShape(.rect)
    }

    private var name: some View {
        Text(verbatim: row.title.text(in: locale))
            .foregroundStyle(Theme.Color.text)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    /// One text, so at the accessibility sizes the share wraps under the amount instead of
    /// cutting it to "661…"; it breaks only after the dot.
    private var figures: some View {
        var amount = AttributedString(row.amount.keepingMarksOnTheLine)
        amount.font = Font.body.weight(.semibold).tabularDigits()
        amount.foregroundColor = Theme.Color.text
        var share = AttributedString("\u{00A0}· " + row.percent.keepingMarksOnTheLine)
        share.font = Font.subheadline.tabularDigits()
        share.foregroundColor = Theme.Color.muted
        return Text(amount + share)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    }
}

/// A figure on a card of its own: "Доходы", "Потери на обмене".
private struct InsightsTile: View {
    let title: LocalizedStringResource
    let value: String
    let detail: String?

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.xs) {
            Text(verbatim: title.text(in: locale))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Color.muted)
            Text(verbatim: value)
                .font(.title2.weight(.semibold))
                .tabularDigits()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(verbatim: detail)
                    .font(.subheadline)
                    .tabularDigits()
                    .foregroundStyle(Theme.Color.muted)
            }
        }
        .padding(Theme.Gap.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Samples") {
    @Previewable @State var model = AppModel.preview()
    NavigationStack {
        if let data = model.data {
            InsightsScreen(data: data, today: model.environment.today())
                .navigationTitle(Text(AppTab.insights.title))
        }
    }
    .environment(model)
    .task { await model.start(command: .samples) }
}

#Preview("Samples, dark, Russian") {
    @Previewable @State var model = AppModel.preview()
    NavigationStack {
        if let data = model.data {
            InsightsScreen(data: data, today: model.environment.today())
                .navigationTitle(Text(AppTab.insights.title))
        }
    }
    .environment(model)
    .environment(\.locale, Locale(identifier: "ru"))
    .preferredColorScheme(.dark)
    .task { await model.start(command: .samples) }
}
