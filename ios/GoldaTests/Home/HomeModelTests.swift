import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The hero of Home: Android's `HomeScreen` numbers on books built by hand, on 2026-10-02 with
/// payday on the 10th (8 days left).
@MainActor @Suite struct HomeHeroTests {
    typealias F = HomeFixture
    var books = HomeFixture()

    /// 20 000 ₽ on the card since September 1 (before the last payday, so the pace can be measured)
    /// and [spentToday] kopecks spent this morning.
    private func spending(_ spentToday: Int64, openedOn opening: LocalDate = LocalDate(2026, 9, 1)) -> HomeFixture {
        var books = books
        books.operations = [
            F.operation(.expense, at: F.at(hour: 9), note: "Обед", category: "eating_out", [(books.rub, -spentToday, -spentToday)]),
            F.operation(.opening, at: F.at(opening, hour: 9), [(books.rub, 2_000_000, 2_000_000)]),
        ]
        return books
    }

    @Test func theDayLeftInTheMainCurrencyWithTheOthersAndTheBar() {
        let hero = HomeHero(data: spending(50_000).data, today: F.today)

        // (19 500 + 500) ₽ over 8 days is 2 500 ₽ a day; 500 ₽ of it is gone.
        #expect(hero.budget.perDayRub == 250_000)
        #expect(hero.left == "2\u{202F}000 ₽")
        #expect(hero.leftMinor == 200_000)
        #expect(hero.currency == "RUB")
        // The local lari first, then dollars, at the rates with the 10 % markup.
        #expect(hero.others == "60,6 ₾ · 22,7 $")
        #expect(hero.progress == 0.8)
        #expect(!hero.isOverspent)
        #expect(!hero.isBarFlat)
        #expect(hero.perDay == "2\u{202F}500 ₽")
        #expect(hero.daysLeft == 8)
        #expect(hero.perDayText(in: F.ru) == "2\u{202F}500 ₽ в день")
        #expect(hero.perDayText(in: F.en) == "2\u{202F}500 ₽ a day")
        #expect(hero.paydayText(in: F.ru) == "8 дней до зарплаты")
        #expect(hero.paydayText(in: F.en) == "8 days to payday")
        #expect(hero.setAside == nil)
        #expect(hero.setAsideText(in: F.ru) == nil)
        #expect(hero.graceWarnings.isEmpty)
    }

    @Test func spendingPastTheBudgetTurnsTheHeroRedWithAFullFlatBar() {
        let hero = HomeHero(data: spending(300_000).data, today: F.today)

        #expect(hero.budget.perDayRub == 250_000)
        #expect(hero.left == "−500 ₽")
        #expect(hero.leftMinor == -50_000)
        #expect(hero.isOverspent)
        #expect(hero.progress == 1)
        #expect(hero.isBarFlat)
    }

    @Test func nothingSpentYetIsAFullBarThatHasSettled() {
        var books = spending(0)
        books.operations.removeFirst()
        let hero = HomeHero(data: books.data, today: F.today)

        #expect(hero.progress == 1)
        #expect(hero.isBarFlat)
        #expect(!hero.isOverspent)
    }

    @Test func noBudgetAtAllIsAnEmptyBar() {
        let hero = HomeHero(data: books.data, today: F.today)

        #expect(hero.left == "0 ₽")
        #expect(hero.progress == 0)
        #expect(!hero.isBarFlat)
        #expect(!hero.isOverspent)
        #expect(hero.pace == nil)
    }

    @Test func thePaceComparesTodaysShareWithTheOneThePeriodStartedWith() {
        // The period started on September 10 with 20 000 ₽ for 30 days: 666 ₽ a day. Today it is 2 500 ₽.
        let ahead = HomeHero(data: spending(50_000).data, today: F.today)
        #expect(ahead.pace == HomeHero.Pace(isAhead: true, amount: "1\u{202F}833 ₽"))
        #expect(ahead.paceText == " ▲1\u{202F}833")

        // 25 000 ₽ of a 30 000 ₽ start went on September 20: 625 ₽ a day now against 1 000 ₽.
        var behindBooks = books
        behindBooks.operations = [
            F.operation(.expense, at: F.at(hour: 9), note: "Обед", [(books.rub, -50_000, -50_000)]),
            F.operation(.expense, at: F.at(LocalDate(2026, 9, 20), hour: 9), note: "Ноутбук", [(books.rub, -2_500_000, -2_500_000)]),
            F.operation(.opening, at: F.at(LocalDate(2026, 9, 1), hour: 9), [(books.rub, 3_000_000, 3_000_000)]),
        ]
        let behind = HomeHero(data: behindBooks.data, today: F.today)
        #expect(behind.pace == HomeHero.Pace(isAhead: false, amount: "375 ₽"))
        #expect(behind.paceText == " ▼375")
    }

    @Test func noPaceWithoutMoneyFromBeforeTheLastPayday() {
        let hero = HomeHero(data: spending(50_000, openedOn: LocalDate(2026, 9, 20)).data, today: F.today)
        #expect(hero.pace == nil)
        #expect(hero.paceText == nil)
    }

    @Test func paymentsDueBeforePaydayAreSetAside() {
        var books = spending(50_000)
        books.obligations = [
            Obligation(name: "Кредит", amountMinor: 1_000_000, currency: "RUB", dayOfMonth: 5),
            // Due after payday: not this period's worry.
            Obligation(name: "Аренда", amountMinor: 90_000, currency: "GEL", dayOfMonth: 1),
        ]
        let hero = HomeHero(data: books.data, today: F.today)

        #expect(hero.budget.perDayRub == 125_000)
        #expect(hero.setAside == "10\u{202F}000 ₽")
        #expect(hero.setAsideText(in: F.ru) == "Отложено на платежи: 10\u{202F}000 ₽")
        #expect(hero.setAsideText(in: F.en) == "Set aside for payments: 10\u{202F}000 ₽")
    }

    @Test func anotherMainCurrencyMovesTheBigNumber() {
        var books = spending(50_000)
        books.device.baseCurrency = "USD"
        let hero = HomeHero(data: books.data, today: F.today)

        // 2 000 ₽ at 88 ₽ a dollar: 22,73 $, rounded as the toast rounds it (D61).
        #expect(hero.left == "23 $")
        #expect(hero.leftMinor == 2_273)
        #expect(hero.currency == "USD")
        #expect(hero.others == "60,6 ₾ · 2\u{202F}000 ₽")
        #expect(hero.paceText == " ▲20,8")
    }

    @Test func graceWarningsComeInTheOrderOfTheAccounts() {
        var books = spending(50_000)
        let visa = Account(name: "Виза", currency: "RUB", type: .credit, includeInFree: false, sort: 4, graceUntil: Int64(F.today.plusDays(3).epochDay))
        let master = Account(name: "Мастер", currency: "RUB", type: .credit, includeInFree: false, sort: 5, graceUntil: Int64(F.today.epochDay))
        books.extraAccounts = [visa, master]
        books.operations += [
            F.operation(.opening, at: F.at(LocalDate(2026, 9, 1), hour: 9), [(master, -100_000, -100_000)]),
            F.operation(.opening, at: F.at(LocalDate(2026, 9, 1), hour: 9), [(visa, -4_800_000, -4_800_000)]),
        ]
        let hero = HomeHero(data: books.data, today: F.today)

        #expect(hero.graceWarnings.map(\.accountName) == ["Виза", "Мастер"])
        #expect(hero.graceWarnings.map(\.daysLeft) == [3, 0])
        #expect(hero.graceWarnings.map(\.owed) == ["48\u{202F}000 ₽", "1\u{202F}000 ₽"])
    }

    @Test func voiceOverReadsTheHeroAsOneSentenceInWords() {
        var books = spending(50_000)
        books.obligations = [Obligation(name: "Кредит", amountMinor: 1_000_000, currency: "RUB", dayOfMonth: 5)]
        let hero = HomeHero(data: books.data, today: F.today)

        let russian = hero.accessibilityLabel(in: F.ru)
        #expect(russian.hasPrefix("Можно сегодня. 750 "))
        #expect(russian.contains("в день"))
        #expect(russian.contains("Лучше плана на "))
        #expect(russian.contains("8 дней до зарплаты"))
        #expect(russian.contains("Отложено на платежи: 10000 "))
        // Figures as whole numbers, never split by the narrow spaces or followed by a bare sign.
        #expect(!russian.contains("\u{202F}"))
        #expect(!russian.contains("₽"))
        #expect(!russian.contains("₾"))

        let english = hero.accessibilityLabel(in: F.en)
        #expect(english.hasPrefix("Safe to spend today. 750 "))
        #expect(english.localizedCaseInsensitiveContains("Russian rubles"))
        #expect(english.contains("8 days to payday"))
        #expect(english.contains("Ahead of plan by "))
    }

    /// The made-up person on the day the Android screenshot was taken (`docs/screenshots/home.png`):
    /// the same budget, the same days and the same rows.
    @Test func theSampleLifeMatchesTheAndroidScreenshot() async throws {
        let harness = try AppHarness()
        await harness.model.start(command: .samples, profileName: "Личный")
        let data = try await harness.data()
        let content = HomeContent(data: data, today: harness.environment.today())

        #expect(content.hero.left == "1\u{202F}849 ₽")
        #expect(content.hero.perDayText(in: F.ru) == "2\u{202F}648 ₽ в день")
        #expect(content.hero.paydayText(in: F.ru) == "8 дней до зарплаты")
        #expect(content.hero.setAsideText(in: F.ru) == "Отложено на платежи: 10\u{202F}000 ₽")
        #expect(content.hero.pace == nil)
        #expect(content.hero.graceWarnings.isEmpty)

        #expect(content.days.prefix(3).map { $0.label.text(in: F.ru) } == ["Сегодня", "Вчера", "30 сентября"])
        let today = content.days[0].rows, yesterday = content.days[1].rows
        #expect(today.map { $0.title(in: F.ru) } == ["Кофе", "Шаурма"])
        #expect(today.map(\.main) == ["−8 ₾", "−15 ₾"])
        #expect(today.map(\.supporting) == ["Наличные ₾", "Наличные ₾"])
        #expect(yesterday.map { $0.title(in: F.ru) } == ["Обед", "Аптека", "Рынок"])
        #expect(yesterday.map(\.main) == ["−18 ₾", "−45 ₾", "−48,50 ₾"])
        // The market was paid last, from the dollar card, which made that card the usual one.
        #expect(yesterday.map(\.supporting) == ["Наличные ₾", "Мультивалютная GEL", nil])
    }
}

@Suite struct GraceWarningTests {
    typealias F = HomeFixture

    private func state(owed: Int64, endsIn days: Int?, currency: String = "RUB") -> AccountState {
        let card = Account(
            name: "Кредитка", currency: currency, type: .credit, includeInFree: false,
            graceUntil: days.map { Int64(F.today.plusDays($0).epochDay) }
        )
        return AccountState(account: card, balanceMinor: -owed, rubMinor: -owed)
    }

    @Test func aWeekOrLessBeforeTheEndWhileSomethingIsOwed() {
        #expect(GraceWarning(state(owed: 4_800_000, endsIn: 7), today: F.today)?.daysLeft == 7)
        #expect(GraceWarning(state(owed: 4_800_000, endsIn: 0), today: F.today)?.daysLeft == 0)
        #expect(GraceWarning(state(owed: 4_800_000, endsIn: 8), today: F.today) == nil)
        #expect(GraceWarning(state(owed: 4_800_000, endsIn: -1), today: F.today) == nil)
        #expect(GraceWarning(state(owed: 0, endsIn: 3), today: F.today) == nil)
        #expect(GraceWarning(state(owed: -5_000, endsIn: 3), today: F.today) == nil)
        #expect(GraceWarning(state(owed: 4_800_000, endsIn: nil), today: F.today) == nil)
    }

    @Test func theWarningSaysWhatToPayInTheCardsCurrency() throws {
        let warning = try #require(GraceWarning(state(owed: 15_050, endsIn: 3, currency: "USD"), today: F.today))
        #expect(warning.accountName == "Кредитка")
        #expect(warning.owed == "150,50 $")
    }

    @Test func inBothLanguagesWithRussianPlurals() throws {
        func text(_ days: Int, _ locale: Locale) throws -> String {
            try #require(GraceWarning(state(owed: 4_800_000, endsIn: days), today: F.today)).text(in: locale)
        }
        #expect(try text(0, F.ru) == "«Кредитка»: льготный период кончается сегодня — погаси 48\u{202F}000 ₽")
        #expect(try text(1, F.ru) == "«Кредитка»: льготный период кончается через 1 день — погаси 48\u{202F}000 ₽")
        #expect(try text(3, F.ru) == "«Кредитка»: льготный период кончается через 3 дня — погаси 48\u{202F}000 ₽")
        #expect(try text(5, F.ru) == "«Кредитка»: льготный период кончается через 5 дней — погаси 48\u{202F}000 ₽")
        #expect(try text(0, F.en) == "“Кредитка”: the interest-free period ends today; pay 48\u{202F}000 ₽")
        #expect(try text(1, F.en) == "“Кредитка”: the interest-free period ends in 1 day; pay 48\u{202F}000 ₽")
        #expect(try text(7, F.en) == "“Кредитка”: the interest-free period ends in 7 days; pay 48\u{202F}000 ₽")
    }

    @Test func spokenTheAmountIsInWords() throws {
        let warning = try #require(GraceWarning(state(owed: 4_800_000, endsIn: 3), today: F.today))
        let spoken = warning.text(in: F.en, spoken: true)
        #expect(spoken.contains("48000 Russian rubles"))
    }
}

@Suite struct PluralTests {
    typealias F = HomeFixture

    @Test func daysToPaydayTakeTheRussianFormsOfDay() {
        let russian = [
            1: "1 день", 2: "2 дня", 4: "4 дня", 5: "5 дней", 11: "11 дней", 12: "12 дней", 14: "14 дней",
            21: "21 день", 22: "22 дня", 25: "25 дней", 31: "31 день",
        ]
        for (days, words) in russian {
            #expect(HomeHero.paydayText(days, in: F.ru) == words + " до зарплаты")
        }
    }

    @Test func daysToPaydayInEnglish() {
        #expect(HomeHero.paydayText(1, in: F.en) == "1 day to payday")
        #expect(HomeHero.paydayText(2, in: F.en) == "2 days to payday")
        #expect(HomeHero.paydayText(21, in: F.en) == "21 days to payday")
    }
}

@Suite struct DayLabelTests {
    typealias F = HomeFixture

    @Test func todayAndYesterdayByName() {
        #expect(DayLabel(F.today, today: F.today) == .today)
        #expect(DayLabel(F.today.minusDays(1), today: F.today) == .yesterday)
        #expect(DayLabel(F.today.minusDays(2), today: F.today) == .date(LocalDate(2026, 9, 30)))
        #expect(DayLabel.today.text(in: F.ru) == "Сегодня")
        #expect(DayLabel.today.text(in: F.en) == "Today")
        #expect(DayLabel.yesterday.text(in: F.ru) == "Вчера")
        #expect(DayLabel.yesterday.text(in: F.en) == "Yesterday")
    }

    @Test func olderDaysAreTheDayAndTheMonthTheWayEachLanguageWritesThem() {
        // "d MMMM" with the month in the genitive in Russian, "MMMM d" in English.
        #expect(DayLabel.date(LocalDate(2026, 9, 30)).text(in: F.ru) == "30 сентября")
        #expect(DayLabel.date(LocalDate(2026, 9, 30)).text(in: F.en) == "September 30")
        #expect(DayLabel.date(LocalDate(2026, 5, 1)).text(in: F.ru) == "1 мая")
        #expect(DayLabel.date(LocalDate(2026, 5, 1)).text(in: F.en) == "May 1")
        #expect(DayLabel.date(LocalDate(2025, 12, 31)).text(in: Locale(identifier: "ru_RU")) == "31 декабря")
    }
}

@MainActor @Suite struct OperationDayTests {
    typealias F = HomeFixture
    var books = HomeFixture()

    @Test func operationsGoUnderTheirDayNewestDayFirst() {
        var books = self.books
        let a = F.operation(.expense, at: F.at(hour: 10), note: "a", [(books.rub, -100, -100)])
        let b = F.operation(.expense, at: F.at(hour: 8), note: "b", [(books.rub, -100, -100)])
        let c = F.operation(.expense, at: F.at(F.today.minusDays(1), hour: 20), note: "c", [(books.rub, -100, -100)])
        let d = F.operation(.expense, at: F.at(LocalDate(2026, 9, 30), hour: 12), note: "d", [(books.rub, -100, -100)])
        let opening = F.operation(.opening, at: F.at(LocalDate(2026, 9, 1), hour: 9), [(books.rub, 100_000, 100_000)])
        books.operations = [a, b, c, d, opening]

        let days = HomeContent(data: books.data, today: F.today).days

        #expect(days.map(\.date) == [F.today, F.today.minusDays(1), LocalDate(2026, 9, 30)])
        #expect(days.map(\.label) == [.today, .yesterday, .date(LocalDate(2026, 9, 30))])
        // Opening balances are bookkeeping, not events: they never get a day.
        #expect(days.map { $0.rows.map(\.id) } == [[a.op.id, b.op.id], [c.op.id], [d.op.id]])
    }

    @Test func theDayIsTheOneInTheProfilesTimeZone() {
        var books = self.books
        // 21:00 UTC on October 1 is already 01:00 on October 2 in Tbilisi.
        let late = F.operation(.expense, at: F.at(F.today.minusDays(1), hour: 21), note: "late", [(books.rub, -100, -100)])
        books.operations = [late]
        books.zone = TimeZone(secondsFromGMT: 4 * 3_600)!

        let days = HomeContent(data: books.data, today: F.today).days
        #expect(days.map(\.label) == [.today])
    }

    @Test func noOperationsNoDays() {
        #expect(HomeContent(data: books.data, today: F.today).days.isEmpty)
        #expect(HomeContent.emptyText.text(in: F.ru).hasPrefix("Пока пусто. Нажми микрофон"))
        #expect(HomeContent.emptyText.text(in: F.en).hasPrefix("Nothing yet. Tap the mic"))
    }
}

@Suite struct SpokenAmountTests {
    typealias F = HomeFixture

    @Test func amountsAreReadAsWholeNumbersWithTheCurrencyInWords() {
        let english = SpokenAmount.text("1\u{202F}849 ₽", locale: F.en)
        #expect(english.hasPrefix("1849 "))
        #expect(english.localizedCaseInsensitiveContains("Russian rubles"))

        let russian = SpokenAmount.text("1\u{202F}849 ₽", locale: F.ru)
        #expect(russian.hasPrefix("1849 "))
        #expect(russian.contains("руб"))

        #expect(SpokenAmount.text("52,2 ₾", locale: F.en).hasPrefix("52.2 "))
        #expect(SpokenAmount.text("52,2 ₾", locale: F.ru).hasPrefix("52,2 "))
        #expect(SpokenAmount.text("−48,50 ₾", locale: F.en).contains("48.50"))
        #expect(SpokenAmount.text("+150 AED", locale: F.en).localizedCaseInsensitiveContains("dirham"))
    }

    @Test func negativeAmountsStayNegative() {
        let spoken = SpokenAmount.text("−320 ₽", locale: F.en)
        #expect(spoken.contains("320"))
        #expect(spoken.hasPrefix("-") || spoken.hasPrefix("−"))
    }

    @Test func symbolsMapBackToTheirCodes() {
        #expect(SpokenAmount.code(forSymbol: "$") == "USD")
        #expect(SpokenAmount.code(forSymbol: "₾") == "GEL")
        #expect(SpokenAmount.code(forSymbol: "₽") == "RUB")
        #expect(SpokenAmount.code(forSymbol: "AED") == "AED")
        #expect(SpokenAmount.code(forSymbol: "x") == nil)
        #expect(SpokenAmount.code(forSymbol: "") == nil)
    }

    @Test func textThatIsNotAnAmountComesBackReadable() {
        #expect(SpokenAmount.text("Кофе", locale: F.ru) == "Кофе")
        #expect(SpokenAmount.text("1\u{202F}000", locale: F.ru) == "1000")
    }
}
