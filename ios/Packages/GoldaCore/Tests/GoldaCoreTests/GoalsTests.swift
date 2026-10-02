import Foundation
import Testing

@testable import GoldaCore

/// Port of GoalsTest.kt.
@Suite struct GoalsTests {
    @Test func thinkingTimeGrowsWithThePrice() {
        let s = Settings(incomeHourly: true, hourlyRate: 1000, taxPercent: 10, hoursPerWeek: 40)
        let october = YearMonth(2026, 10) // September pay: 158 400 ₽
        #expect(Goals.waitHours(300_000, s, october) == 24) // 3 000 ₽
        #expect(Goals.waitHours(1_500_000, s, october) == 72) // 15 000 ₽
        #expect(Goals.waitHours(12_000_000, s, october) == 168) // 120 000 ₽
        #expect(Goals.waitHours(12_000_000, Settings(), october) == 24) // no income known
    }
}
