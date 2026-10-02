package sh.aminov.golda.domain

import java.util.Locale

/**
 * Two languages, kept next to each other in the code: `tr("Сегодня", "Today")`.
 * The activity sets [russian] from the app's language (system per-app
 * language setting, or the switch in Golda's settings).
 */
object I18n {
    @Volatile
    var russian: Boolean = true

    val locale: Locale get() = if (russian) Locale.forLanguageTag("ru") else Locale.ENGLISH
}

fun tr(ru: String, en: String): String = if (I18n.russian) ru else en

/** "1 день / 2 дня / 5 дней" and "1 day / 2 days". */
fun plural(n: Long, one: String, few: String, many: String, enOne: String, enMany: String): String {
    if (!I18n.russian) return if (n == 1L) enOne else enMany
    val mod100 = n % 100
    val mod10 = n % 10
    return when {
        mod100 in 11..14 -> many
        mod10 == 1L -> one
        mod10 in 2..4 -> few
        else -> many
    }
}
