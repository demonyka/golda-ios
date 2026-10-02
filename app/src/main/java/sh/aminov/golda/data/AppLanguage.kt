package sh.aminov.golda.data

import android.app.Activity
import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import android.os.LocaleList
import androidx.core.content.edit
import java.util.Locale

/**
 * The app's own language, apart from the phone's: "ru", "en", or "" for the system one.
 *
 * Android 13+ keeps it per app (LocaleManager, with res/xml/locales_config), and the system
 * recreates the screen and the app's resources in it. Before 13 there is no such thing, so the
 * choice lives in a small preferences file, the activity wraps its context in that locale
 * ([wrap]) and recreates itself when it changes.
 */
object AppLanguage {
    private const val PREFS = "app_language"
    private const val KEY = "tag"

    fun tag(context: Context): String =
        if (Build.VERSION.SDK_INT >= 33) {
            context.getSystemService(LocaleManager::class.java).applicationLocales.takeIf { !it.isEmpty }?.get(0)?.language.orEmpty()
        } else {
            prefs(context).getString(KEY, "").orEmpty()
        }

    /** Switches the language. On 13+ the system recreates the activity; before, [activity] does it itself. */
    fun set(activity: Activity, tag: String) {
        if (Build.VERSION.SDK_INT >= 33) {
            activity.getSystemService(LocaleManager::class.java).applicationLocales =
                if (tag.isEmpty()) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(tag)
        } else {
            prefs(activity).edit { putString(KEY, tag) }
            activity.recreate()
        }
    }

    /** Whether the app speaks Russian now: the chosen language, or the phone's when none is chosen. */
    fun russian(context: Context): Boolean {
        val chosen = tag(context)
        if (chosen.isNotEmpty()) return chosen == "ru"
        // On 13+ the app's configuration already is the system's when nothing is chosen; before 13 the
        // activity's may be wrapped, so ask the system itself.
        val system = if (Build.VERSION.SDK_INT >= 33) context.resources.configuration.locales[0] else Resources.getSystem().configuration.locales[0]
        return system.language == "ru"
    }

    /** Before Android 13: [base] in the chosen language, so resources and formatting follow it. */
    fun wrap(base: Context): Context {
        if (Build.VERSION.SDK_INT >= 33) return base
        val chosen = tag(base).takeIf { it.isNotEmpty() } ?: return base
        val config = Configuration(base.resources.configuration)
        config.setLocale(Locale.forLanguageTag(chosen))
        return base.createConfigurationContext(config)
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
