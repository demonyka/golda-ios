import Foundation
import GoldaCore

// Everything the Insights tab shows, worked out from one `AppData`, the day it is and the period
// picked, the way Android's `AnalyticsScreen` does it. Plain values: the views only lay them out,
// and tests check them in both languages with a fixed clock. The sums come from `Analytics.report`;
// what is added here is the grouping into ring slices, the rows, the day bars and the words.

/// Who a slice or a row is named after.
enum CategoryTitle: Equatable, Sendable {
    /// A built-in category by its key; a key the app does not know reads "Other".
    case key(String)
    /// An expense without a category.
    case none
    /// The folded slice: what is under the share a ring slice needs.
    case rest

    init(_ key: String?) {
        self = key.map { .key($0) } ?? .none
    }

    func text(in locale: Locale) -> String {
        switch self {
        case .key(let key): CategoryName.resource(key).text(in: locale)
        case .none: LocalizedStringResource("No category", comment: "Row title of an operation with neither a note nor a category.").text(in: locale)
        case .rest: LocalizedStringResource("Everything else", table: "Insights", comment: "Insights: the ring slice that gathers the small categories.").text(in: locale)
        }
    }
}

/// One slice of the ring.
struct InsightsSlice: Identifiable, Equatable, Sendable {
    /// Its place in the ring, from twelve o'clock round.
    let id: Int
    let title: CategoryTitle
    let rubMinor: Int64
    /// 0...1 of the period's spending.
    let share: Double
    /// "6 618 ₽", in the main currency.
    let amount: String
    /// The same in main-currency units, for the digits to roll to.
    let value: Double
    /// The folded slice wears the quietest tone.
    let isRest: Bool
}

/// One category of the list under the ring. Every category keeps its row; the folded ones wear the
/// dot of "Everything else".
struct InsightsRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: CategoryTitle
    let symbol: String
    /// "6 618 ₽"
    let amount: String
    /// "39 %", "<1 %".
    let percent: String
    /// The slice it belongs to: its own, or the folded one.
    let slice: Int
    let isRest: Bool

    func accessibilityLabel(in locale: Locale) -> String {
        [title.text(in: locale), SpokenAmount.text(amount, locale: locale), percent].joined(separator: ", ")
    }
}

/// One day under the bars.
struct InsightsDay: Identifiable, Equatable, Sendable {
    let date: LocalDate
    let rubMinor: Int64
    /// "1 420 ₽"
    let amount: String
    /// In main-currency units, what the bar is drawn from.
    let value: Double
    let isToday: Bool

    var id: Int { date.epochDay }

    /// What the chart places the bar by: a name, so the days are steps of a scale and not numbers on one.
    var key: String { String(date.epochDay) }

    /// "Сегодня", or "Пт 26": the pill over the picked bar and what VoiceOver says for it.
    func name(in locale: Locale) -> String {
        if isToday { return DayLabel.today.text(in: locale) }
        return InsightsDates.weekday(date, in: locale) + " " + String(date.day)
    }

    /// "Пт 26 · 1 420 ₽"
    func pillText(in locale: Locale) -> String {
        name(in: locale) + " · " + amount
    }
}

/// What the center of the ring says: the period's total, or the slice that was tapped.
struct InsightsCenter: Equatable, Sendable {
    /// The slice's name; nil for the total.
    let title: CategoryTitle?
    /// "16 944 ₽"
    let amount: String
    /// The amount in main-currency units, for the digits to roll to.
    let value: Double
    /// "2 421 ₽" a day for the total, the share for a slice.
    let detail: Detail

    enum Detail: Equatable, Sendable {
        case perDay(String)
        case share(String)
        case nothing
    }
}

struct InsightsContent: Equatable, Sendable {
    /// The ring shows this many categories on their own; the rest share one slice.
    static let topSlices = 3
    /// Below this share of the period a category folds into "Everything else".
    static let minimumPercent: Int64 = 4

    let kind: PeriodKind
    let period: Period
    /// The day the current pay period began, for the "С 10 сент." choice.
    let paydayStart: LocalDate
    let report: Report
    let slices: [InsightsSlice]
    let rows: [InsightsRow]
    let days: [InsightsDay]
    /// The daily budget in main-currency units; nil when there is none to show.
    let dailyBudget: Double?
    /// "2 648 ₽", the same as written.
    let dailyBudgetAmount: String?
    /// "16 944 ₽"
    let spent: String
    let spentValue: Double
    /// "2 421 ₽"
    let averagePerDay: String
    let income: String
    let exchangeLoss: String
    /// "12 %" of what went through exchanges; nil when nothing did.
    let exchangeLossPercent: String?

    init(data: AppData, today: LocalDate, kind: PeriodKind, custom: Period? = nil) {
        let period = Analytics.period(kind, today: today, settings: data.settings, custom: custom)
        let report = Analytics.report(
            data.operations, accounts: data.accountById, period: period, today: today, zone: data.zone, rates: data.rates
        )
        let base = data.base
        self.kind = kind
        self.period = period
        self.report = report
        paydayStart = Analytics.period(.sincePayday, today: today, settings: data.settings).from

        let own = report.categories.prefix(Self.topSlices).filter {
            report.spentRub > 0 && $0.rubMinor * 100 >= report.spentRub * Self.minimumPercent
        }
        let rest = Array(report.categories.dropFirst(own.count))
        func share(_ rub: Int64) -> Double { report.spentRub > 0 ? Double(rub) / Double(report.spentRub) : 0 }
        var slices = own.enumerated().map { index, spend in
            InsightsSlice(
                id: index, title: CategoryTitle(spend.categoryKey), rubMinor: spend.rubMinor,
                share: share(spend.rubMinor), amount: base.approx(spend.rubMinor), value: base.major(spend.rubMinor), isRest: false
            )
        }
        if !rest.isEmpty {
            let folded = rest.moneySum(\.rubMinor)
            // A lone folded category keeps its own name: "Everything else" would hide what it is.
            slices.append(InsightsSlice(
                id: slices.count, title: rest.count == 1 ? CategoryTitle(rest[0].categoryKey) : .rest, rubMinor: folded,
                share: share(folded), amount: base.approx(folded), value: base.major(folded), isRest: true
            ))
        }
        self.slices = slices
        rows = report.categories.enumerated().map { index, spend in
            let slice = min(index, own.count)
            return InsightsRow(
                id: spend.categoryKey ?? "-", title: CategoryTitle(spend.categoryKey),
                symbol: Symbols.category(spend.categoryKey),
                amount: base.approx(spend.rubMinor), percent: GoalPercent.whole(share(spend.rubMinor)),
                slice: slice, isRest: index >= own.count
            )
        }
        days = report.days.map {
            InsightsDay(date: $0.date, rubMinor: $0.rubMinor, amount: base.approx($0.rubMinor), value: base.major($0.rubMinor), isToday: $0.date == today)
        }
        let perDay = Budget.today(
            states: data.states, operations: data.operations, settings: data.settings, today: today, zone: data.zone,
            obligations: data.allObligations, rates: data.rates
        ).perDayRub
        dailyBudget = perDay > 0 ? base.major(perDay) : nil
        dailyBudgetAmount = perDay > 0 ? base.approx(perDay) : nil
        spent = base.approx(report.spentRub)
        spentValue = base.major(report.spentRub)
        averagePerDay = base.approx(report.averagePerDayRub)
        income = base.approx(report.incomeRub)
        exchangeLoss = base.approx(report.fxLossRub)
        exchangeLossPercent = report.fxVolumeRub > 0 ? GoalPercent.whole(Double(report.fxLossRub) / Double(report.fxVolumeRub)) : nil
    }

    var isEmpty: Bool { report.categories.isEmpty }

    // MARK: Ring

    /// The slice that is still there: a pick outlives the data it was made on, and may point past it.
    func focus(_ picked: Int?) -> Int? {
        picked.flatMap { slices.indices.contains($0) ? $0 : nil }
    }

    func center(focus: Int?) -> InsightsCenter {
        guard let focus = self.focus(focus) else {
            return InsightsCenter(title: nil, amount: spent, value: spentValue, detail: .perDay(averagePerDay))
        }
        let slice = slices[focus]
        return InsightsCenter(
            title: slice.title, amount: slice.amount, value: slice.value,
            detail: report.spentRub > 0 ? .share(GoalPercent.whole(slice.share)) : .nothing
        )
    }

    /// The slice a tap on the ring lands on, from how far round the ring it is measured in the
    /// slices' own amounts laid end to end from twelve o'clock.
    func slice(atAngle value: Double) -> Int? {
        var end = 0.0
        for slice in slices {
            end += Double(slice.rubMinor)
            if value < end { return slice.id }
        }
        return nil
    }

    // MARK: Day bars

    /// The bar the chart starts on: today, or the last day of a period that is over.
    var defaultDay: InsightsDay? { days.first(where: \.isToday) ?? days.last }

    /// What stands under a bar, if anything: a week names its days, a month marks the 1st, 10th and
    /// 20th and today, as Android does.
    func axisLabel(_ day: InsightsDay, in locale: Locale) -> String? {
        if kind == .week || days.count <= 7 {
            // Two letters: "Пн Вт Ср", never the ambiguous single "В".
            return InsightsDates.weekday(day.date, in: locale, letters: 2)
        }
        return day.isToday || [1, 10, 20].contains(day.date.day) ? String(day.date.day) : nil
    }

    // MARK: Text

    /// The choice's name in the picker.
    func title(of kind: PeriodKind, in locale: Locale) -> String {
        Self.title(of: kind, paydayStart: paydayStart, in: locale)
    }

    static func title(of kind: PeriodKind, paydayStart: LocalDate, in locale: Locale) -> String {
        switch kind {
        case .week:
            return LocalizedStringResource("Week", table: "Insights", comment: "Insights: the last seven days.").text(in: locale)
        case .month:
            return LocalizedStringResource("Month", table: "Insights", comment: "Insights: the last thirty days.").text(in: locale)
        case .sincePayday:
            let date = InsightsDates.short(paydayStart, in: locale)
            return LocalizedStringResource("Since \(date)", table: "Insights", comment: "Insights: from the last payday on, “Since Sep 10”. The date.").text(in: locale)
        case .custom:
            return customTitle.text(in: locale)
        }
    }

    static let customTitle = LocalizedStringResource("Custom range", table: "Insights", comment: "Insights: pick the dates of the period yourself; the picker’s calendar button.")

    /// "26 сент. – 2 окт.": the dates of the period.
    func rangeText(in locale: Locale) -> String {
        InsightsDates.short(period.from, in: locale) + " – " + InsightsDates.short(period.to, in: locale)
    }

    static let emptyText = LocalizedStringResource("No spending in these days.", table: "Insights", comment: "Insights: the period has no expenses.")

    func centerCaption(_ center: InsightsCenter, in locale: Locale) -> String {
        switch center.detail {
        case .perDay(let amount):
            LocalizedStringResource("≈ \(amount)/day", table: "Insights", comment: "Insights, the ring’s center: the average spending per day of the period, “≈ 2 421 ₽/day”.").text(in: locale)
        case .share(let percent): percent
        case .nothing: ""
        }
    }

    /// The center as VoiceOver reads it: the total with its daily average, or the slice with its share.
    func centerAccessibilityLabel(_ center: InsightsCenter, in locale: Locale) -> String {
        let amount = SpokenAmount.text(center.amount, locale: locale)
        if let title = center.title {
            return [title.text(in: locale), amount, centerCaption(center, in: locale)].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        let perDay = SpokenAmount.text(averagePerDay, locale: locale)
        return LocalizedStringResource("Spent \(amount), about \(perDay) a day", table: "Insights", comment: "VoiceOver, Insights: the period’s spending and its daily average.").text(in: locale)
    }

    static let incomeTitle = LocalizedStringResource("Income", table: "Insights", comment: "Insights: the tile with what came in during the period.")
    static let exchangeTitle = LocalizedStringResource("Lost on exchange", table: "Insights", comment: "Insights: the tile with what currency exchanges cost against the CBR rate.")

    /// "12 % против ЦБ", or "обменов не было".
    func exchangeDetail(in locale: Locale) -> String {
        if let percent = exchangeLossPercent {
            return LocalizedStringResource("\(percent) against the CBR", table: "Insights", comment: "Insights: the exchange loss as a share of what was exchanged, “3 % against the CBR”.").text(in: locale)
        }
        return LocalizedStringResource("no exchanges", table: "Insights", comment: "Insights: no currency exchange in the period.").text(in: locale)
    }

    static let budgetLabel = LocalizedStringResource("Daily budget", table: "Insights", comment: "VoiceOver: the dashed line over the day bars, the share of the budget that falls on one day.")
    static let daysLabel = LocalizedStringResource("Spending by day", table: "Insights", comment: "VoiceOver: the bars of the period’s spending day by day.")
    static let rowHint = LocalizedStringResource("Shows this category in the ring", table: "Insights", comment: "VoiceOver hint of a category row: it picks the slice in the ring.")
    static let rangeHint = LocalizedStringResource("Changes the dates", table: "Insights", comment: "VoiceOver hint of the line with the custom period’s dates.")
}

/// The period of your own, as the sheet edits it: two days, the end never before the start.
struct PeriodRangeDraft: Equatable, Sendable {
    private(set) var from: LocalDate
    private(set) var to: LocalDate

    init(_ period: Period) {
        from = period.from
        to = max(period.from, period.to)
    }

    /// A start past the end drags the end along, so the range cannot be backwards.
    mutating func setFrom(_ day: LocalDate) {
        from = day
        if to < day { to = day }
    }

    /// An end before the start drags the start along.
    mutating func setTo(_ day: LocalDate) {
        to = day
        if from > day { from = day }
    }

    var period: Period { Period(from: from, to: to) }
}

/// Dates the way the interface language writes them.
enum InsightsDates {
    /// "10 сент.", "Sep 10": the day and the abbreviated month, in the order [locale] puts them.
    static func short(_ date: LocalDate, in locale: Locale) -> String {
        noon(date).formatted(style(in: locale).day().month(.abbreviated))
    }

    /// "27 сент. 2026 г.", "Sep 27, 2026": a day with its year, as the system's date pickers write it.
    static func full(_ date: LocalDate, in locale: Locale) -> String {
        noon(date).formatted(style(in: locale).day().month(.abbreviated).year())
    }

    /// The day's noon in UTC, read back in UTC: no zone can move it to the day before or after.
    private static func noon(_ date: LocalDate) -> Date {
        Date(timeIntervalSince1970: Double(date.epochDay) * 86_400 + 12 * 3_600)
    }

    private static func style(in locale: Locale) -> Date.FormatStyle {
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return Date.FormatStyle(locale: locale, calendar: calendar, timeZone: utc)
    }

    /// "Пт", "Fri"; with [letters] only that many, still capitalised: "Fr".
    static func weekday(_ date: LocalDate, in locale: Locale, letters: Int? = nil) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        // Sunday first in the symbols, Monday is 1 in `DayOfWeek`.
        let name = calendar.shortStandaloneWeekdaySymbols[date.dayOfWeek.rawValue % 7]
        let cut = letters.map { String(name.prefix($0)) } ?? name
        return cut.prefix(1).uppercased() + String(cut.dropFirst())
    }
}
