import Foundation
import GoldaCore

// Everything Home shows, worked out from one `AppData` and the day it is, the way Android's
// `HomeScreen` does it. Plain values: the views below only lay them out, and tests check them in
// both languages with a fixed clock.

/// The hero: "Можно сегодня", how much of the day's budget is left, and how long it has to last.
struct HomeHero: Equatable, Sendable {
    /// The day's budget in rubles (kopecks): what is left, the share per day, and so on.
    let budget: Today
    /// The main currency the big number is in.
    let currency: String
    /// What is left today in minor units of [currency]; negative once overspent.
    let leftMinor: Int64
    /// "1 849 ₽", the big number as written.
    let left: String
    /// The other shown currencies: "52,2 ₾ · 20 $"; empty when only the main one is shown.
    let others: String
    /// 0...1: what is left of today's budget; full once it is spent past.
    let progress: Double
    /// Today's spending went past the budget: the whole card turns red.
    let isOverspent: Bool
    /// The wave settles when the bar is full: overspent, or nothing spent yet.
    let isBarFlat: Bool
    /// "2 648 ₽", what the bar is measured against.
    let perDay: String
    /// How today's share compares with the one the pay period started with.
    let pace: Pace?
    let graceWarnings: [GraceWarning]
    /// "10 000 ₽" put aside for payments due before payday; nil when nothing is.
    let setAside: String?

    /// ▲ ahead of plan (spending slower than the period allows) or ▼ behind it.
    struct Pace: Equatable, Sendable {
        let isAhead: Bool
        /// "120 ₽", without a sign.
        let amount: String
    }

    init(data: AppData, today: LocalDate) {
        let budget = Budget.today(
            states: data.states, operations: data.operations, settings: data.settings, today: today, zone: data.zone,
            obligations: data.allObligations, rates: data.rates
        )
        let base = data.base
        self.budget = budget
        currency = base.code
        leftMinor = base.minor(budget.leftTodayRub)
        left = base.whole(budget.leftTodayRub)
        others = data.others(rubMinor: budget.leftTodayRub, exclude: base.code)
        isOverspent = budget.leftTodayRub < 0
        if isOverspent {
            progress = 1
        } else if budget.perDayRub > 0 {
            progress = min(1, max(0, Double(budget.leftTodayRub) / Double(budget.perDayRub)))
        } else {
            progress = 0
        }
        isBarFlat = isOverspent || progress >= 1
        perDay = base.approx(budget.perDayRub)
        pace = Budget.pace(
            today: budget, accounts: data.accounts, operations: data.operations, settings: data.settings, date: today,
            zone: data.zone, obligations: data.allObligations, rates: data.rates
        ).map { Pace(isAhead: $0 >= 0, amount: base.approx(Int64(clamping: $0.magnitude))) }
        // In the order of the accounts, as Android's states map keeps it.
        graceWarnings = data.accounts.compactMap { data.states[$0.id] }.compactMap { GraceWarning($0, today: today) }
        setAside = budget.obligationsRub > 0 ? base.approx(budget.obligationsRub) : nil
    }

    var daysLeft: Int { budget.daysLeft }

    /// " ▲120" after the day's share: the arrow and the figure, the symbol left to the share before it.
    var paceText: String? {
        pace.map { pace in
            let symbol = " " + Currencies.symbol(currency)
            let figure = pace.amount.hasSuffix(symbol) ? String(pace.amount.dropLast(symbol.count)) : pace.amount
            return " " + (pace.isAhead ? "▲" : "▼") + figure
        }
    }

    // MARK: Text

    static let caption = LocalizedStringResource("Safe to spend today", comment: "Home hero caption over the big number: what can be spent today.")

    /// "2 648 ₽ a day".
    func perDayText(in locale: Locale) -> String {
        LocalizedStringResource("\(perDay) a day", comment: "Home hero: today's budget share, “2 648 ₽ a day”.").text(in: locale)
    }

    /// "8 days to payday", with the Russian forms of "day".
    func paydayText(in locale: Locale) -> String {
        Self.paydayText(daysLeft, in: locale)
    }

    static func paydayText(_ days: Int, in locale: Locale) -> String {
        LocalizedStringResource("\(days) days to payday", comment: "Home hero: days until the next salary, “8 days to payday”.").text(in: locale)
    }

    /// "Set aside for payments: 10 000 ₽".
    func setAsideText(in locale: Locale) -> String? {
        setAside.map {
            LocalizedStringResource("Set aside for payments: \($0)", comment: "Home hero: money kept back for payments due before payday.").text(in: locale)
        }
    }

    /// The hero as one sentence for VoiceOver, every amount in words, in the order it is drawn.
    func accessibilityLabel(in locale: Locale) -> String {
        var sentences = [Self.caption.text(in: locale), SpokenAmount.text(left, locale: locale)]
        if !others.isEmpty {
            sentences.append(others.components(separatedBy: " · ").map { SpokenAmount.text($0, locale: locale) }.joined(separator: ", "))
        }
        let spokenPerDay = SpokenAmount.text(perDay, locale: locale)
        sentences.append(LocalizedStringResource("\(spokenPerDay) a day", comment: "Home hero: today's budget share, “2 648 ₽ a day”.").text(in: locale))
        if let pace {
            let amount = SpokenAmount.text(pace.amount, locale: locale)
            sentences.append(
                pace.isAhead
                    ? LocalizedStringResource("Ahead of plan by \(amount)", comment: "VoiceOver, Home hero: today's share is bigger than the pay period started with (▲).").text(in: locale)
                    : LocalizedStringResource("Behind plan by \(amount)", comment: "VoiceOver, Home hero: today's share is smaller than the pay period started with (▼).").text(in: locale)
            )
        }
        sentences.append(paydayText(in: locale))
        sentences += graceWarnings.map { $0.text(in: locale, spoken: true) }
        if let setAside {
            let amount = SpokenAmount.text(setAside, locale: locale)
            sentences.append(LocalizedStringResource("Set aside for payments: \(amount)", comment: "Home hero: money kept back for payments due before payday.").text(in: locale))
        }
        return sentences.joined(separator: ". ")
    }
}

/// A credit card whose interest-free period ends within a week while something is owed: the port
/// of Android's `graceWarning`.
struct GraceWarning: Equatable, Sendable {
    let accountName: String
    /// 0 is today.
    let daysLeft: Int
    /// What to pay, in the card's currency: "48 000 ₽".
    let owed: String

    /// Nil while there is time, when nothing is owed, or once the period is over.
    init?(_ state: AccountState, today: LocalDate) {
        guard let until = state.account.graceUntil else { return nil }
        let owedMinor = -state.balanceMinor
        guard owedMinor > 0 else { return nil }
        let days = LocalDate.daysBetween(today, LocalDate(epochDay: Int(until)))
        guard (0...7).contains(days) else { return nil }
        accountName = state.account.name
        daysLeft = days
        owed = Fmt.amount(owedMinor, state.account.currency)
    }

    /// "«Кредитка»: льготный период кончается через 3 дня — погаси 48 000 ₽". [spoken] says the
    /// amount in words, for VoiceOver.
    func text(in locale: Locale, spoken: Bool = false) -> String {
        let amount = spoken ? SpokenAmount.text(owed, locale: locale) : owed
        if daysLeft == 0 {
            return LocalizedStringResource(
                "“\(accountName)”: the interest-free period ends today; pay \(amount)",
                comment: "Home hero: a credit card's grace period ends today. The card's name, then what is owed."
            ).text(in: locale)
        }
        let days = LocalizedStringResource("\(daysLeft) days", comment: "A number of days, “3 days”; used inside longer sentences.").text(in: locale)
        return LocalizedStringResource(
            "“\(accountName)”: the interest-free period ends in \(days); pay \(amount)",
            comment: "Home hero: a credit card's grace period ends soon. The card's name, “3 days”, then what is owed."
        ).text(in: locale)
    }
}

/// A day's heading over its operations: "Today", "Yesterday", "30 September".
enum DayLabel: Equatable, Sendable {
    case today
    case yesterday
    case date(LocalDate)

    init(_ date: LocalDate, today: LocalDate) {
        switch date {
        case today: self = .today
        case today.minusDays(1): self = .yesterday
        default: self = .date(date)
        }
    }

    /// "Сегодня", "Вчера", "30 сентября" in Russian; "Today", "Yesterday", "September 30" in English.
    func text(in locale: Locale) -> String {
        switch self {
        case .today: LocalizedStringResource("Today", comment: "Heading of today's operations.").text(in: locale)
        case .yesterday: LocalizedStringResource("Yesterday", comment: "Heading of yesterday's operations.").text(in: locale)
        case .date(let date): Self.dayAndMonth(date, locale: locale)
        }
    }

    /// The day and the month's name the way [locale] writes them together: "d MMMM" in Russian (the
    /// month in the genitive), "MMMM d" in English, as Android's patterns.
    private static func dayAndMonth(_ date: LocalDate, locale: Locale) -> String {
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let instant = Date(timeIntervalSince1970: Double(date.epochDay) * 86_400 + 12 * 3_600)
        return instant.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: utc).day().month(.wide))
    }
}

/// One day of operations, newest first, under its heading.
struct OperationDay: Identifiable, Equatable, Sendable {
    let date: LocalDate
    let label: DayLabel
    let rows: [OperationRowModel]

    var id: LocalDate { date }

    /// [operations] (newest first) by the day they happened in [zone], in the order the days first
    /// appear, as Kotlin's `groupBy` keeps them.
    static func group(_ operations: [OperationFull], in data: AppData, today: LocalDate, accountId: UUID? = nil) -> [OperationDay] {
        var order: [LocalDate] = []
        var byDay: [LocalDate: [OperationRowModel]] = [:]
        for full in operations {
            guard let row = OperationRowModel(full, in: data, accountId: accountId) else { continue }
            let day = Ledger.localDate(full.op.timestamp, data.zone)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(row)
        }
        return order.map { OperationDay(date: $0, label: DayLabel($0, today: today), rows: byDay[$0] ?? []) }
    }
}

/// Home for the open profile: the hero, then the operations by day.
struct HomeContent: Equatable, Sendable {
    let hero: HomeHero
    let days: [OperationDay]

    init(data: AppData, today: LocalDate) {
        hero = HomeHero(data: data, today: today)
        days = OperationDay.group(data.visibleOperations, in: data, today: today)
    }

    static let emptyText = LocalizedStringResource(
        "Nothing yet. Tap the mic and name a purchase, like “shawarma 15 lari”. Or “+” to type it.",
        comment: "Home with no operations yet: how to record the first one."
    )
}
