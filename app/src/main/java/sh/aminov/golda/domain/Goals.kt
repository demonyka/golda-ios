package sh.aminov.golda.domain

import sh.aminov.golda.data.Category
import sh.aminov.golda.data.Goal
import java.time.YearMonth
import kotlin.math.roundToLong

/** What a purchase means, already formatted for the "хочу купить" card. */
data class Facts(
    val item: String,
    val amount: String,
    val hours: String? = null,
    /** How many days of "можно сегодня" the amount is. */
    val days: String? = null,
    val goal: String? = null,
    val goalPct: String? = null,
    /** The same three as numbers, for the "сомневаюсь" tiles: hours of work, days of budget, share of the main goal. */
    val hoursValue: Double? = null,
    val daysValue: Double? = null,
    val goalShare: Double? = null,
    /** How long "Подумаю" would wait: "3 дня". */
    val wait: String? = null,
)

object Goals {
    /** Saved so far, in the goal's currency: the linked account plus what skipped purchases put aside. */
    fun progressMinor(goal: Goal, states: Map<Long, AccountState>, rates: Rates): Long {
        val account = goal.accountId?.let { states[it] }
        val fromAccount = when {
            account == null -> 0L
            account.currency == goal.currency -> account.balanceMinor
            else -> rates.fromRub(account.rubMinor, goal.currency)?.let { Currencies.toMinor(it, goal.currency) } ?: 0L
        }
        return (fromAccount + goal.savedMinor).coerceAtLeast(0)
    }

    fun targetRub(goal: Goal, rates: Rates): Long? =
        if (goal.currency == "RUB") goal.targetMinor else rates.rubMinor(goal.targetMinor, goal.currency)

    /**
     * How long to think before buying: a day for small things, three days
     * for up to a tenth of a month's pay, a week for anything bigger.
     */
    fun waitHours(rubMinor: Long, settings: Settings, month: YearMonth): Long {
        val income = settings.salaryFor(month.minusMonths(1)) * 100
        return when {
            income <= 0 || rubMinor < income * 0.02 -> 24
            rubMinor < income * 0.10 -> 72
            else -> 168
        }
    }

    fun waitLabel(hours: Long): String = when {
        hours < 48 -> plural(hours, "час", "часа", "часов", "hour", "hours").let { "$hours $it" }
        else -> (hours / 24).let { "$it ${plural(it, "день", "дня", "дней", "day", "days")}" }
    }

    /** Facts about spending [rubMinor] on [item] for the "хочу купить" card. */
    fun facts(
        item: String,
        amount: String,
        rubMinor: Long,
        settings: Settings,
        perDayRub: Long,
        mainGoal: Goal?,
        rates: Rates,
    ): Facts {
        val hours = settings.hourNet.takeIf { it > 0 }?.let { rubMinor / 100.0 / it }
        val goalRub = mainGoal?.let { targetRub(it, rates) }?.takeIf { it > 0 }
        return Facts(
            item = item,
            amount = amount,
            hours = hours?.let { Fmt.number(it, 1) + tr(" ч", " h") },
            days = perDayRub.takeIf { it > 0 }?.let { Fmt.number(rubMinor.toDouble() / it, 1) },
            goal = mainGoal?.name,
            goalPct = goalRub?.let { Fmt.percent(rubMinor.toDouble() / it) },
            hoursValue = hours,
            daysValue = perDayRub.takeIf { it > 0 }?.let { rubMinor.toDouble() / it },
            goalShare = goalRub?.let { rubMinor.toDouble() / it },
        )
    }


    fun rubOf(minor: Long, currency: String, rates: Rates): Long =
        if (currency == "RUB") minor else rates.rubMinor(minor, currency) ?: 0

    fun minorOfRub(rubMinor: Long, currency: String, rates: Rates): Long =
        if (currency == "RUB") rubMinor else rates.fromRub(rubMinor, currency)?.let { Currencies.toMinor(it, currency) } ?: 0

    fun share(part: Long, whole: Long): Float = if (whole > 0) (part.toDouble() / whole).coerceIn(0.0, 1.0).toFloat() else 0f

    fun percentRounded(part: Long, whole: Long): Long = if (whole > 0) (part * 100.0 / whole).roundToLong() else 0
}

private val categoryNames = mapOf(
    "eating_out" to ("Кафе" to "Eating out"),
    "groceries" to ("Продукты" to "Groceries"),
    "transport" to ("Транспорт" to "Transport"),
    "housing" to ("Жильё" to "Housing"),
    "telecom" to ("Связь" to "Phone"),
    "fun" to ("Развлечения" to "Fun"),
    "health" to ("Здоровье" to "Health"),
    "clothes" to ("Одежда" to "Clothes"),
    "subscriptions" to ("Подписки" to "Subscriptions"),
    "travel" to ("Путешествия" to "Travel"),
    "fees" to ("Комиссии" to "Fees"),
    "other" to ("Прочее" to "Other"),
    "salary" to ("Зарплата" to "Salary"),
    "interest" to ("Проценты" to "Interest"),
    "gift" to ("Подарок" to "Gift"),
    "other_income" to ("Прочее" to "Other"),
)

/** Default names that have since been shortened: data saved with them still counts as the default. */
private val formerNames = mapOf("eating_out" to "Еда вне дома")

/** Built-in categories speak the app's language; ones the user renames keep their name. */
fun Category.label(): String =
    categoryNames[key]?.takeIf { it.first == name || formerNames[key] == name }?.let { tr(it.first, it.second) } ?: name
