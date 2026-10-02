package sh.aminov.golda

import org.junit.Assert.assertEquals
import org.junit.Test
import sh.aminov.golda.data.Account
import sh.aminov.golda.data.AccountType
import sh.aminov.golda.data.Rate
import sh.aminov.golda.domain.Budget
import sh.aminov.golda.domain.Ledger
import sh.aminov.golda.domain.Settings
import sh.aminov.golda.domain.VoiceMapper
import sh.aminov.golda.ui.AppData
import sh.aminov.golda.ui.toggleDisplayCurrency
import java.time.LocalDate
import java.time.ZoneOffset

/** Where each setting reaches the logic: a change in Settings has to change what these return. */
class SettingsEffectsTest {
    private val rubCard = Account(1, "Карта ₽", "RUB", AccountType.CARD, includeInFree = true, sort = 0)
    private val usdCard = Account(2, "Доллары", "USD", AccountType.CARD, includeInFree = true, sort = 1)
    private val gelCash = Account(3, "Лари", "GEL", AccountType.CASH, includeInFree = true, sort = 2)
    private val accounts = listOf(rubCard, usdCard, gelCash)
    private val rates = listOf(Rate("USD", 83.25, "2026-10-02"), Rate("GEL", 31.96, "2026-10-02"))

    private fun data(s: Settings) = AppData(s, accounts, emptyList(), emptyList(), rates)

    @Test
    fun theLocalCurrencyLeadsTheCurrencyChoicesAndTheOthersLine() {
        val shown = listOf("RUB", "USD", "GEL")
        assertEquals(listOf("RUB", "USD", "GEL"), data(Settings(displayCurrencies = shown, localCurrency = "RUB")).currencyChoices())
        assertEquals(listOf("GEL", "RUB", "USD"), data(Settings(displayCurrencies = shown, localCurrency = "GEL")).currencyChoices())
        val others = data(Settings(displayCurrencies = shown, localCurrency = "GEL")).others(100_000, "RUB")
        assertEquals(listOf("₾", "$"), others.split(" · ").map { it.substringAfterLast(' ') })
    }

    @Test
    fun theOthersLineShowsExactlyTheShownCurrencies() {
        val line = data(Settings(displayCurrencies = listOf("RUB", "USD"), localCurrency = "RUB")).others(100_000, "RUB")
        assertEquals(listOf("$"), line.split(" · ").map { it.substringAfterLast(' ') })
    }

    @Test
    fun aNewPurchaseIsPaidFromAnAccountInTheLocalCurrency() {
        // The entry form asks the same question as voice: who pays in this currency?
        val usedLast = Settings(lastAccountId = rubCard.id)
        assertEquals(gelCash.id, VoiceMapper.pick(accounts, usedLast.copy(localCurrency = "GEL").localCurrency, usedLast)?.id)
        assertEquals(usdCard.id, VoiceMapper.pick(accounts, "USD", usedLast)?.id)
        assertEquals(rubCard.id, VoiceMapper.pick(accounts, "RUB", usedLast)?.id)
        // No account in the local currency: the last one used, converted.
        assertEquals(rubCard.id, VoiceMapper.pick(accounts, "THB", usedLast)?.id)
    }

    @Test
    fun hidingTheLocalCurrencyFallsBackToRubles() {
        val s = Settings(displayCurrencies = listOf("RUB", "USD", "GEL"), localCurrency = "GEL")
        val hidden = toggleDisplayCurrency(s, "GEL")
        assertEquals(listOf("RUB", "USD"), hidden.displayCurrencies)
        assertEquals("RUB", hidden.localCurrency)
        // Rubles can't be hidden: they are the base.
        assertEquals(s, toggleDisplayCurrency(s, "RUB"))
    }

    @Test
    fun paydaySetsTheDaysLeft() {
        val today = LocalDate.of(2026, 10, 2)
        assertEquals(LocalDate.of(2026, 10, 15), Settings(payday = 15).nextPayday(today))
        // On payday itself the next one is a month away.
        assertEquals(LocalDate.of(2026, 11, 2), Settings(payday = 2).nextPayday(today))
        assertEquals(LocalDate.of(2026, 11, 1), Settings(payday = 1).nextPayday(today))
        // The 31st in a 30-day month is its last day.
        assertEquals(LocalDate.of(2026, 11, 30), Settings(payday = 31).nextPayday(LocalDate.of(2026, 11, 2)))

        val states = Ledger.states(accounts, emptyList())
        fun daysLeft(payday: Int) = Budget.today(states, emptyList(), Settings(payday = payday), today, ZoneOffset.UTC).daysLeft
        assertEquals(13, daysLeft(15))
        assertEquals(8, daysLeft(10))
        assertEquals(31, daysLeft(2))
    }

    @Test
    fun rateAndTaxSetTheHourOnHand() {
        assertEquals(2_400.0, Settings(incomeHourly = true, hourlyRate = 3_000.0, taxPercent = 20.0).hourNet, 1e-9)
        // A salary of 173 333 ₽ over 40 h a week (173.33 h a month), 13 % tax: about 870 ₽ an hour.
        assertEquals(870.0, Settings(incomeHourly = false, monthlySalary = 173_333.0, taxPercent = 13.0, hoursPerWeek = 40.0).hourNet, 0.5)
    }
}
