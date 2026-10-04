import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The Insights tab's display models: what Android's `AnalyticsScreen` writes, as structure and as
/// text in both languages, from fixed books and a fixed clock. The sums are `AnalyticsTests`'s.
@Suite struct InsightsModelTests {
    typealias F = HomeFixture
    typealias I = InsightsFixture

    // MARK: Week

    @Test func theWeekAddsUpAsInTheKotlinTest() {
        let content = I().content()

        #expect(content.period == Period(from: LocalDate(2026, 9, 26), to: LocalDate(2026, 10, 2)))
        // 500 ₽ + 920 ₽ + 300 ₽, the September 20 lunch left out.
        #expect(content.spent == "1\u{202F}720 ₽")
        #expect(content.averagePerDay == "246 ₽")
        #expect(content.income == "1\u{202F}000 ₽")
        #expect(!content.isEmpty)
    }

    @Test func theRingHasASlicePerCategoryBiggestFirst() {
        let content = I().content()

        #expect(content.slices.map(\.title) == [.key("groceries"), .key("eating_out")])
        #expect(content.slices.map(\.rubMinor) == [92_000, 80_000])
        #expect(content.slices.map(\.amount) == ["920 ₽", "800 ₽"])
        #expect(content.slices.map(\.isRest) == [false, false])
        #expect(abs(content.slices[0].share - 92.0 / 172) < 0.000_001)
    }

    @Test func theRowsSayTheShareInWholePercentAndNameTheirSlice() {
        let rows = I().content().rows

        #expect(rows.map(\.title) == [.key("groceries"), .key("eating_out")])
        #expect(rows.map(\.symbol) == ["cart", "fork.knife"])
        #expect(rows.map(\.amount) == ["920 ₽", "800 ₽"])
        #expect(rows.map(\.percent) == ["53\u{00A0}%", "47\u{00A0}%"])
        #expect(rows.map(\.slice) == [0, 1])
        #expect(rows.map(\.title.self).map { $0.text(in: F.ru) } == ["Продукты", "Кафе"])
        #expect(rows.map(\.title.self).map { $0.text(in: F.en) } == ["Groceries", "Eating out"])
    }

    @Test func aRowIsReadAsOneSentenceWithTheAmountInWords() {
        let row = I().content().rows[0]
        #expect(row.accessibilityLabel(in: F.en) == "Groceries, 920 Russian rubles, 53\u{00A0}%")
    }

    // MARK: Folding

    private func content(_ spends: [(String?, Int64)]) -> InsightsContent {
        let home = HomeFixture()
        var fixture = InsightsFixture(operations: [])
        fixture.home.operations = spends.map { I.expense(home, $0.0, rub: $0.1) }
        return fixture.content()
    }

    @Test func onlyTheThreeBiggestGetASliceAndTheRestShareOne() {
        // 100 000 kopecks: 50 %, 30 %, 10 % and three that are under the rest.
        let content = content([("groceries", 50_000), ("eating_out", 30_000), ("transport", 10_000), ("fun", 6_000), ("health", 3_000), ("clothes", 1_000)])

        #expect(content.slices.map(\.title) == [.key("groceries"), .key("eating_out"), .key("transport"), .rest])
        #expect(content.slices.map(\.rubMinor) == [50_000, 30_000, 10_000, 10_000])
        #expect(content.slices.map(\.isRest) == [false, false, false, true])
        // Every category keeps its row; the folded ones wear the dot of the folded slice.
        #expect(content.rows.count == 6)
        #expect(content.rows.map(\.slice) == [0, 1, 2, 3, 3, 3])
        #expect(content.rows.map(\.isRest) == [false, false, false, true, true, true])
        #expect(CategoryTitle.rest.text(in: F.ru) == "Остальное")
        #expect(CategoryTitle.rest.text(in: F.en) == "Everything else")
    }

    @Test func aLoneFoldedCategoryKeepsItsOwnName() {
        let content = content([("groceries", 50_000), ("eating_out", 30_000), ("transport", 10_000), ("fun", 6_000)])
        #expect(content.slices.map(\.title) == [.key("groceries"), .key("eating_out"), .key("transport"), .key("fun")])
        #expect(content.slices.last?.isRest == true)
    }

    @Test func aCategoryUnderFourPercentFoldsEvenAmongTheTopThree() {
        // 3 % of the period is below the share a slice needs.
        let content = content([("groceries", 96_000), ("eating_out", 3_000), ("transport", 1_000)])
        #expect(content.slices.map(\.title) == [.key("groceries"), .rest])
        #expect(content.slices.map(\.rubMinor) == [96_000, 4_000])
        #expect(content.rows.map(\.slice) == [0, 1, 1])
    }

    @Test func exactlyFourPercentStillGetsASlice() {
        let content = content([("groceries", 96_000), ("eating_out", 4_000)])
        #expect(content.slices.map(\.title) == [.key("groceries"), .key("eating_out")])
        #expect(content.slices.map(\.isRest) == [false, false])
    }

    @Test func aShareUnderHalfAPercentReadsLessThanOne() {
        let content = content([("groceries", 99_900), ("eating_out", 100)])
        #expect(content.rows.map(\.percent) == ["100\u{00A0}%", "<1\u{00A0}%"])
    }

    @Test func noCategoryAndUnknownKeysHaveNamesToo() {
        let content = content([(nil, 20_000), ("my_own", 10_000)])
        #expect(content.rows.map { $0.title.text(in: F.ru) } == ["Без категории", "Прочее"])
        #expect(content.rows.map { $0.title.text(in: F.en) } == ["No category", "Other"])
        #expect(content.rows.map(\.symbol) == ["shippingbox", "shippingbox"])
    }

    // MARK: Center

    @Test func theMiddleSaysTheTotalAndTheDailyAverageUntilASliceIsPicked() {
        let content = I().content()
        let center = content.center(focus: nil)

        #expect(center.title == nil)
        #expect(center.amount == "1\u{202F}720 ₽")
        #expect(center.value == 1_720)
        #expect(content.centerCaption(center, in: F.ru) == "≈ 246 ₽/день")
        #expect(content.centerCaption(center, in: F.en) == "≈ 246 ₽/day")
        #expect(content.centerAccessibilityLabel(center, in: F.en) == "Spent 1720 Russian rubles, about 246 Russian rubles a day")
    }

    @Test func aPickedSliceSpeaksForItself() {
        let content = I().content()
        let center = content.center(focus: 1)

        #expect(center.title == .key("eating_out"))
        #expect(center.amount == "800 ₽")
        #expect(center.detail == .share("47\u{00A0}%"))
        #expect(content.centerCaption(center, in: F.en) == "47\u{00A0}%")
        #expect(content.centerAccessibilityLabel(center, in: F.en) == "Eating out, 800 Russian rubles, 47\u{00A0}%")
    }

    @Test func aPickPastTheSlicesIsNoPick() {
        let content = I().content()
        #expect(content.focus(1) == 1)
        #expect(content.focus(2) == nil)
        #expect(content.focus(nil) == nil)
        #expect(content.center(focus: 7).title == nil)
    }

    @Test func aTapOnTheRingFindsTheSliceUnderIt() {
        let content = I().content()
        // The chart reports the amounts laid end to end: 92 000, then 80 000.
        #expect(content.slice(atAngle: 0) == 0)
        #expect(content.slice(atAngle: 91_999.5) == 0)
        #expect(content.slice(atAngle: 92_000) == 1)
        #expect(content.slice(atAngle: 171_999) == 1)
        #expect(content.slice(atAngle: 172_000) == nil)
    }

    // MARK: Days

    @Test func theWeekHasSevenDaysAndTodayIsPickedFirst() throws {
        let content = I().content()

        #expect(content.days.count == 7)
        #expect(content.days.map(\.date.day) == [26, 27, 28, 29, 30, 1, 2])
        #expect(content.days.last?.isToday == true)
        #expect(content.days.filter(\.isToday).count == 1)
        #expect(content.defaultDay?.date == LocalDate(2026, 10, 2))
        // 500 ₽ and the 10 $ that cost 920 ₽.
        #expect(content.days.last?.amount == "1\u{202F}420 ₽")
        #expect(content.days.last?.value == 1_420)
        #expect(content.days[5].amount == "300 ₽")
        #expect(content.days[0].amount == "0 ₽")
    }

    @Test func aDayIsNamedForThePillAndForVoiceOver() throws {
        let content = I().content()
        let yesterday = content.days[5]

        #expect(content.days.last?.pillText(in: F.ru) == "Сегодня · 1\u{202F}420 ₽")
        #expect(content.days.last?.pillText(in: F.en) == "Today · 1\u{202F}420 ₽")
        // 1 October 2026 is a Thursday.
        #expect(yesterday.pillText(in: F.ru) == "Чт 1 · 300 ₽")
        #expect(yesterday.pillText(in: F.en) == "Thu 1 · 300 ₽")
        #expect(content.days[4].name(in: F.ru) == "Ср 30")
    }

    @Test func aWeekNamesItsDaysWithTwoLetters() {
        let content = I().content()
        #expect(content.days.map { content.axisLabel($0, in: F.ru) } == ["Сб", "Вс", "Пн", "Вт", "Ср", "Чт", "Пт"])
        #expect(content.days.map { content.axisLabel($0, in: F.en) } == ["Sa", "Su", "Mo", "Tu", "We", "Th", "Fr"])
    }

    @Test func aMonthMarksTheFirstTenthTwentiethAndToday() {
        let content = I().content(.month)

        #expect(content.period == Period(from: LocalDate(2026, 9, 3), to: LocalDate(2026, 10, 2)))
        #expect(content.days.count == 30)
        let marked = content.days.compactMap { day in content.axisLabel(day, in: F.en).map { (day.date.day, $0) } }
        #expect(marked.map(\.0) == [10, 20, 1, 2])
        #expect(marked.map(\.1) == ["10", "20", "1", "2"])
        // The September 20 lunch is in the month, in its own day.
        #expect(content.days.first { $0.date == LocalDate(2026, 9, 20) }?.amount == "9\u{202F}999 ₽")
        #expect(content.spent == "11\u{202F}719 ₽")
    }

    @Test func aShortCustomRangeNamesItsDaysToo() {
        let content = I().content(.custom, custom: Period(from: LocalDate(2026, 9, 30), to: LocalDate(2026, 10, 2)))
        #expect(content.days.count == 3)
        #expect(content.days.map { content.axisLabel($0, in: F.en) } == ["We", "Th", "Fr"])
    }

    @Test func aPeriodThatIsOverStartsOnItsLastDay() {
        let content = I().content(.custom, custom: Period(from: LocalDate(2026, 9, 18), to: LocalDate(2026, 9, 22)))
        #expect(content.defaultDay?.date == LocalDate(2026, 9, 22))
        #expect(content.days.map(\.isToday) == [false, false, false, false, false])
    }

    @Test func theBudgetLineIsTheDaysShareWhenThereIsOne() {
        // No money in the books: nothing to draw.
        #expect(I().content().dailyBudget == nil)
        #expect(I().content().dailyBudgetAmount == nil)

        var fixture = I()
        let opening = F.operation(.opening, at: F.at(LocalDate(2026, 9, 1), hour: 8), [(fixture.home.rub, 10_000_000, 10_000_000)])
        fixture.home.operations.append(opening)
        let data = fixture.data
        let share = Budget.today(
            states: data.states, operations: data.operations, settings: data.settings, today: F.today, zone: data.zone,
            obligations: data.allObligations, rates: data.rates
        ).perDayRub
        #expect(share > 0)
        #expect(fixture.content().dailyBudget == Double(share) / 100)
        #expect(fixture.content().dailyBudgetAmount == data.base.approx(share))
    }

    // MARK: Income and exchange

    @Test func exchangeLossesAreCountedAgainstTheCBRRate() {
        let content = I().content()

        // 46 000 ₽ became 500 $ at the CBR's 83,2454: 4 377,30 ₽ lost, a tenth of what went through.
        #expect(content.report.fxLossRub == 437_730)
        #expect(content.exchangeLoss == "4\u{202F}377 ₽")
        #expect(content.exchangeLossPercent == "10\u{00A0}%")
        #expect(content.exchangeDetail(in: F.ru) == "10\u{00A0}% против ЦБ")
        #expect(content.exchangeDetail(in: F.en) == "10\u{00A0}% against the CBR")
        #expect(InsightsContent.incomeTitle.text(in: F.ru) == "Доходы")
        #expect(InsightsContent.exchangeTitle.text(in: F.en) == "Lost on exchange")
    }

    @Test func withoutExchangesTheTileSaysSo() {
        let content = content([("groceries", 10_000)])
        #expect(content.exchangeLossPercent == nil)
        #expect(content.exchangeDetail(in: F.ru) == "обменов не было")
        #expect(content.exchangeDetail(in: F.en) == "no exchanges")
        #expect(content.exchangeLoss == "0 ₽")
    }

    // MARK: Empty

    @Test func aPeriodWithoutSpendingHasNoRingButStillShowsIncome() {
        var fixture = InsightsFixture(operations: [])
        fixture.home.operations = [F.operation(.income, at: I.at(1), [(fixture.home.rub, 100_000, 100_000)])]
        let content = fixture.content()

        #expect(content.isEmpty)
        #expect(content.slices.isEmpty)
        #expect(content.rows.isEmpty)
        #expect(content.income == "1\u{202F}000 ₽")
        #expect(content.center(focus: 0).title == nil)
        #expect(content.center(focus: nil).amount == "0 ₽")
        #expect(InsightsContent.emptyText.text(in: F.ru) == "За эти дни трат нет.")
        #expect(InsightsContent.emptyText.text(in: F.en) == "No spending in these days.")
    }

    // MARK: Periods

    @Test func theChoicesAreNamedInBothLanguages() {
        let content = I().content()

        #expect(content.paydayStart == LocalDate(2026, 9, 10))
        #expect(PeriodKind.allCases.map { content.title(of: $0, in: F.ru) } == ["Неделя", "Месяц", "С 10 сент.", "Свой период"])
        #expect(PeriodKind.allCases.map { content.title(of: $0, in: F.en) } == ["Week", "Month", "Since Sep 10", "Custom range"])
    }

    @Test func sincePaydayStartsTheDayTheLastOneWas() {
        let content = I().content(.sincePayday)
        #expect(content.period == Period(from: LocalDate(2026, 9, 10), to: LocalDate(2026, 10, 2)))
        #expect(content.spent == "11\u{202F}719 ₽")
    }

    @Test func aRangeOfYourOwnIsWrittenWithItsDates() {
        let content = I().content(.custom, custom: Period(from: LocalDate(2026, 9, 26), to: LocalDate(2026, 10, 2)))
        #expect(content.rangeText(in: F.ru) == "26 сент. – 2 окт.")
        #expect(content.rangeText(in: F.en) == "Sep 26 – Oct 2")
    }

    @Test func aRangeStillToComeCountsTheAverageOnlyOverDaysThatHappened() {
        let content = I().content(.custom, custom: Period(from: LocalDate(2026, 10, 1), to: LocalDate(2026, 10, 31)))
        #expect(content.days.count == 31)
        #expect(content.report.averagePerDayRub == 172_000 / 2)
    }

    // MARK: Main currency

    @Test func everythingIsShownInTheMainCurrency() {
        var fixture = I()
        fixture.home.device.baseCurrency = "USD"
        let content = fixture.content()

        // 1 720 ₽ at 88 ₽ a dollar.
        #expect(content.spent == "19,5 $")
        #expect(content.rows.map(\.amount) == ["10,5 $", "9,1 $"])
        #expect(abs((content.days.last?.value ?? 0) - 1_420.0 / 88) < 0.000_001)
    }
}

/// The period of your own, as the sheet edits it.
@Suite struct PeriodRangeDraftTests {
    @Test func aStartPastTheEndDragsTheEndAlong() {
        var draft = PeriodRangeDraft(Period(from: LocalDate(2026, 9, 26), to: LocalDate(2026, 10, 2)))
        draft.setFrom(LocalDate(2026, 10, 5))
        #expect(draft.period == Period(from: LocalDate(2026, 10, 5), to: LocalDate(2026, 10, 5)))
    }

    @Test func anEndBeforeTheStartDragsTheStartAlong() {
        var draft = PeriodRangeDraft(Period(from: LocalDate(2026, 9, 26), to: LocalDate(2026, 10, 2)))
        draft.setTo(LocalDate(2026, 9, 1))
        #expect(draft.period == Period(from: LocalDate(2026, 9, 1), to: LocalDate(2026, 9, 1)))
    }

    @Test func daysInsideTheRangeMoveOnlyTheirOwnEnd() {
        var draft = PeriodRangeDraft(Period(from: LocalDate(2026, 9, 26), to: LocalDate(2026, 10, 2)))
        draft.setFrom(LocalDate(2026, 9, 28))
        draft.setTo(LocalDate(2026, 10, 1))
        #expect(draft.period == Period(from: LocalDate(2026, 9, 28), to: LocalDate(2026, 10, 1)))
    }

    @Test func aBackwardsRangeStartsOutRepaired() {
        let draft = PeriodRangeDraft(Period(from: LocalDate(2026, 10, 2), to: LocalDate(2026, 9, 26)))
        #expect(draft.period == Period(from: LocalDate(2026, 10, 2), to: LocalDate(2026, 10, 2)))
    }
}

/// Dates the way each language writes them.
@Suite struct InsightsDatesTests {
    typealias F = HomeFixture

    @Test func theMonthIsAbbreviatedAndOrderedByLanguage() {
        #expect(InsightsDates.short(LocalDate(2026, 9, 10), in: F.ru) == "10 сент.")
        #expect(InsightsDates.short(LocalDate(2026, 9, 10), in: F.en) == "Sep 10")
        #expect(InsightsDates.short(LocalDate(2026, 1, 3), in: F.ru) == "3 янв.")
    }

    /// The ends of a period of your own carry the year, as the system's date pickers write a day.
    @Test func aFullDayCarriesTheYear() {
        // A narrow no-break space keeps "г." with its year.
        #expect(InsightsDates.full(LocalDate(2026, 9, 27), in: F.ru) == "27 сент. 2026\u{202F}г.")
        #expect(InsightsDates.full(LocalDate(2026, 9, 27), in: F.en) == "Sep 27, 2026")
        #expect(InsightsDates.full(LocalDate(2027, 1, 3), in: F.en) == "Jan 3, 2027")
    }

    @Test func weekdaysAreCapitalisedAndCanBeCutToTwoLetters() {
        // 2026-10-02 is a Friday.
        let friday = LocalDate(2026, 10, 2)
        #expect(InsightsDates.weekday(friday, in: F.ru) == "Пт")
        #expect(InsightsDates.weekday(friday, in: F.en) == "Fri")
        #expect(InsightsDates.weekday(friday, in: F.en, letters: 2) == "Fr")
        #expect(InsightsDates.weekday(LocalDate(2026, 10, 4), in: F.ru) == "Вс")
        #expect(InsightsDates.weekday(LocalDate(2026, 10, 5), in: F.ru) == "Пн")
    }
}
