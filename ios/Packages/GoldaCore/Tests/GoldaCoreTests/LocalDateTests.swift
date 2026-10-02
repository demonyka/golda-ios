import Foundation
import Testing

@testable import GoldaCore

/// `LocalDate` and `YearMonth` mirror java.time; the expected values were taken from the JVM.
@Suite struct LocalDateTests {
    @Test func epochDaysMatchJavaTime() {
        #expect(LocalDate(1970, 1, 1).epochDay == 0)
        #expect(LocalDate(1969, 12, 31).epochDay == -1)
        #expect(LocalDate(2026, 10, 2).epochDay == 20_728)
        #expect(LocalDate(1900, 3, 1).epochDay == -25_508)
        for day in stride(from: -40_000, through: 60_000, by: 997) {
            let date = LocalDate(epochDay: day)
            #expect(LocalDate(date.year, date.month, date.day) == date)
        }
    }

    @Test func weekdaysAreRight() {
        #expect(LocalDate(2026, 10, 2).dayOfWeek == .friday)
        #expect(LocalDate(1970, 1, 1).dayOfWeek == .thursday)
        #expect(LocalDate(1969, 12, 31).dayOfWeek == .wednesday)
        #expect(DayOfWeek.friday.russianName == "пятница")
        #expect(!LocalDate(2026, 10, 2).dayOfWeek.isWeekend)
        #expect(LocalDate(2026, 10, 3).dayOfWeek.isWeekend)
    }

    @Test func monthMathClampsTheDay() {
        #expect(LocalDate(2027, 1, 31).plusMonths(1) == LocalDate(2027, 2, 28))
        #expect(LocalDate(2027, 1, 31).minusMonths(2) == LocalDate(2026, 11, 30))
        #expect(LocalDate(2028, 2, 29).plusMonths(12) == LocalDate(2029, 2, 28))
        #expect(LocalDate(2026, 3, 31).minusMonths(1) == LocalDate(2026, 2, 28))
        #expect(LocalDate(2026, 1, 15).minusMonths(1) == LocalDate(2025, 12, 15))
        #expect(LocalDate(2026, 10, 2).plusDays(30) == LocalDate(2026, 11, 1))
        #expect(LocalDate(2026, 10, 2).lengthOfMonth == 31)
        #expect(LocalDate(2028, 2, 1).lengthOfMonth == 29)
        #expect(LocalDate.daysBetween(LocalDate(2026, 10, 2), LocalDate(2026, 10, 15)) == 13)
    }

    @Test func yearMonthsMoveAcrossYears() {
        #expect(YearMonth(2026, 1).minusMonths(1) == YearMonth(2025, 12))
        #expect(YearMonth(2026, 12).plusMonths(2) == YearMonth(2027, 2))
        #expect(YearMonth(2026, 10) > YearMonth(2026, 9))
        #expect(YearMonth(2026, 2).atDay(28) == LocalDate(2026, 2, 28))
        #expect(YearMonth(from: LocalDate(2026, 10, 2)) == YearMonth(2026, 10))
    }

    @Test func isoTextIsStrict() {
        #expect(LocalDate(iso: "2026-10-02") == LocalDate(2026, 10, 2))
        #expect(LocalDate(iso: "2026-02-30") == nil)
        #expect(LocalDate(iso: "2026-1-1") == nil)
        #expect(LocalDate(iso: "26-10-02") == nil)
        #expect(LocalDate(iso: "2026-10-02T00:00") == nil)
        #expect(LocalDate(iso: "") == nil)
        #expect(LocalDate(2026, 10, 2).description == "2026-10-02")
    }

    @Test func instantsFallOnTheRightDayInAZone() {
        let moscowish = TimeZone(secondsFromGMT: 4 * 3_600)!
        let brazilish = TimeZone(secondsFromGMT: -3 * 3_600)!
        let evening = LocalDate(2026, 10, 1).atTimeMillis(hour: 21, in: utc) // 2026-10-01T21:00Z
        #expect(LocalDate(epochMillis: evening, in: moscowish) == LocalDate(2026, 10, 2))
        #expect(LocalDate(epochMillis: evening, in: utc) == LocalDate(2026, 10, 1))
        let night = LocalDate(2026, 10, 2).atTimeMillis(hour: 1, in: utc)
        #expect(LocalDate(epochMillis: night, in: brazilish) == LocalDate(2026, 10, 1))
        // Before 1970 the day still rounds down.
        #expect(LocalDate(epochMillis: -1, in: utc) == LocalDate(1969, 12, 31))
    }

    @Test func startOfDayRoundTrips() {
        let zone = TimeZone(secondsFromGMT: 4 * 3_600)!
        let day = LocalDate(2026, 10, 2)
        let start = day.startOfDayMillis(in: zone)
        #expect(LocalDate(epochMillis: start, in: zone) == day)
        #expect(LocalDate(epochMillis: start - 1, in: zone) == day.minusDays(1))
        #expect(day.atTimeMillis(hour: 12, in: zone) - start == 12 * 3_600_000)
    }
}
