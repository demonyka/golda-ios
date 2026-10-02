package sh.aminov.golda

import org.junit.Assert.assertEquals
import org.junit.Test
import sh.aminov.golda.domain.Goals
import sh.aminov.golda.domain.Settings
import java.time.YearMonth

class GoalsTest {
    @Test
    fun thinkingTimeGrowsWithThePrice() {
        val s = Settings(incomeHourly = true, hourlyRate = 1000.0, taxPercent = 10.0, hoursPerWeek = 40.0)
        val october = YearMonth.of(2026, 10) // September pay: 158 400 ₽
        assertEquals(24L, Goals.waitHours(300_000, s, october)) // 3 000 ₽
        assertEquals(72L, Goals.waitHours(1_500_000, s, october)) // 15 000 ₽
        assertEquals(168L, Goals.waitHours(12_000_000, s, october)) // 120 000 ₽
        assertEquals(24L, Goals.waitHours(12_000_000, Settings(), october)) // no income known
    }
}
