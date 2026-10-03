import Charts
import SwiftUI

/// Spending day by day as thin bars with round tops. A finger scrubs across them (or taps one): the
/// picked bar turns graphite and its day and sum ride in a pill above it. The dashed line is the
/// day's budget. The port of Android's `DayBars`.
struct DayBarsChart: View {
    let content: InsightsContent

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 200
    /// The day whose bar is picked: today to begin with, then whatever a finger last touched.
    @State private var pickedId: Int?

    var body: some View {
        let days = content.days
        let picked = days.first { $0.id == pickedId } ?? content.defaultDay
        // The tallest bar or the budget line, so neither leaves the chart.
        let top = max(days.map(\.value).max() ?? 0, content.dailyBudget ?? 0)
        let stub = top * 0.02
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Day", day.key), y: .value("Spent", max(day.value, stub)), width: .ratio(0.62))
                    .foregroundStyle(day.id == picked?.id ? Theme.Color.graphite : Theme.Color.graphite.opacity(0.3))
                    // Round tops, flat bottoms: the bar stands on the baseline.
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                    .accessibilityLabel(Text(verbatim: day.name(in: locale)))
                    .accessibilityValue(Text(verbatim: SpokenAmount.text(day.amount, locale: locale)))
            }
            // The pill rides at the top of the plot over the picked bar, wherever the bar ends, and
            // stays inside the card at either edge.
            if let picked {
                RuleMark(x: .value("Day", picked.key))
                    .foregroundStyle(.clear)
                    // The chart's own value says which day is picked; this line is only its anchor.
                    .accessibilityHidden(true)
                    .annotation(position: .overlay, alignment: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        pill(picked)
                    }
            }
            if let budget = content.dailyBudget {
                RuleMark(y: .value("Budget", budget))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundStyle(Theme.Color.muted.opacity(0.7))
                    .accessibilityLabel(Text(verbatim: InsightsContent.budgetLabel.text(in: locale)))
                    .accessibilityValue(Text(verbatim: SpokenAmount.text(content.dailyBudgetAmount ?? "", locale: locale)))
            }
        }
        .chartXScale(domain: days.map(\.key))
        // Headroom over the tallest bar, where the pill rides.
        .chartYScale(domain: 0...max(top * 1.3, 1))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(preset: .aligned, position: .bottom, values: days.filter { content.axisLabel($0, in: locale) != nil }.map(\.key)) { value in
                if let key = value.as(String.self), let day = days.first(where: { $0.key == key }) {
                    AxisValueLabel(centered: true) {
                        Text(verbatim: content.axisLabel(day, in: locale) ?? "")
                            .font(.caption2)
                            .foregroundStyle(day.id == picked?.id ? Theme.Color.graphite : Theme.Color.muted)
                    }
                }
            }
        }
        // The words in the chart are labels on a drawing: they grow with the type, but not so far that the
        // pill covers the bars; VoiceOver reads them in full whatever their size.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(height: height)
        .chartOverlay { proxy in
            // A bar answers to a plain tap and to a finger sliding across, as on Android.
            GeometryReader { geometry in
                HorizontalTouchLayer { location in
                    guard let plot = proxy.plotFrame else { return }
                    let x = location.x - geometry[plot].origin.x
                    if let key = proxy.value(atX: x, as: String.self), let id = Int(key) { pickedId = id }
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: pickedId)
        // A new period starts on its own default again.
        .onChange(of: content.period) { _, _ in
            pickedId = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: InsightsContent.daysLabel.text(in: locale)))
        // The picked day, the pill's words: the pill itself is a drawing over the chart.
        .accessibilityValue(Text(verbatim: picked?.pillText(in: locale) ?? ""))
        .accessibilityIdentifier("insights.days")
    }

    private func pill(_ day: InsightsDay) -> some View {
        Text(verbatim: day.pillText(in: locale))
            .font(.footnote.weight(.medium))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .tabularDigits()
            .foregroundStyle(Theme.Color.onGraphite)
            .lineLimit(1)
            // The annotation is given the width of a rule, none at all.
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, Theme.Gap.xs)
            .background(Theme.Color.graphite, in: .capsule)
            .accessibilityIdentifier("insights.pill")
    }
}
