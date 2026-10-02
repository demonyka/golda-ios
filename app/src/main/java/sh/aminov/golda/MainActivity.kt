package sh.aminov.golda

import android.app.Application
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.quicksettings.TileService
import android.widget.RemoteViews
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import sh.aminov.golda.data.Demo
import sh.aminov.golda.data.Repo
import sh.aminov.golda.domain.I18n
import sh.aminov.golda.ui.GoldaRoot
import sh.aminov.golda.ui.GoldaTheme
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit
import sh.aminov.golda.data.DebtReminder
import sh.aminov.golda.data.ReconcileSchedule
import kotlinx.coroutines.flow.first
import androidx.work.OneTimeWorkRequestBuilder
import sh.aminov.golda.data.ReconcileReminder

class GoldaApplication : Application() {
    val repo by lazy { Repo(this) }

    override fun onCreate() {
        super.onCreate()
        I18n.russian = resources.configuration.locales[0].language == "ru"
    }
}

const val ACTION_VOICE = "sh.aminov.golda.VOICE"
const val TAB_ACCOUNTS = 1
const val TAB_GOALS = 2

/** Which tab a notification opens. */
const val EXTRA_TAB = "golda.tab"

fun voicePendingIntent(context: Context): PendingIntent = PendingIntent.getActivity(
    context,
    0,
    Intent(context, MainActivity::class.java)
        .setAction(ACTION_VOICE)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
)

class MainActivity : ComponentActivity() {
    private val repo get() = (application as GoldaApplication).repo

    /** "Start recording" requests from the tile, the widget and the shortcut. */
    private val voiceRequests = Channel<Unit>(Channel.CONFLATED)

    /** Tabs to open, from notifications. */
    private val tabRequests = Channel<Int>(Channel.CONFLATED)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Changing the app's language recreates the activity, so this stays current.
        I18n.russian = resources.configuration.locales[0].language == "ru"
        enableEdgeToEdge()
        if (savedInstanceState == null) handle(intent)
        lifecycleScope.launch {
            repo.ensureSeed()
            debugCommands(intent)
            repo.refreshRates()
            repo.processVoiceQueue()
            ReconcileSchedule.apply(this@MainActivity, repo.settings.flow.first().reconcileReminder)
            repo.wishes.rescheduleReminders()
        }
        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            "debts",
            ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<DebtReminder>(1, TimeUnit.DAYS).build(),
        )
        setContent { GoldaTheme { GoldaRoot(repo, voiceRequests, tabRequests) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
        lifecycleScope.launch { debugCommands(intent) }
    }

    private fun handle(intent: Intent) {
        if (intent.action == ACTION_VOICE) voiceRequests.trySend(Unit)
        intent.getIntExtra(EXTRA_TAB, -1).takeIf { it >= 0 }?.let { tabRequests.trySend(it) }
    }

    /** adb shell am start -n sh.aminov.golda/.MainActivity --ez golda.demo true */
    private suspend fun debugCommands(intent: Intent) {
        if (!BuildConfig.DEBUG) return
        when {
            intent.getBooleanExtra("golda.samples", false) -> Demo.samples(repo)
            intent.getBooleanExtra("golda.demo", false) -> Demo.fill(repo)
            intent.getBooleanExtra("golda.reset", false) -> repo.resetAll()
            // Notes copied into files/voice with run-as, understood as if just recorded.
            intent.getBooleanExtra("golda.voiceQueue", false) -> repo.processVoiceQueue()
            intent.getBooleanExtra("golda.reconcileNow", false) ->
                WorkManager.getInstance(this).enqueue(OneTimeWorkRequestBuilder<ReconcileReminder>().build())
        }
    }
}

/** Quick Settings tile: one tap starts recording. */
class VoiceTileService : TileService() {
    override fun onClick() {
        super.onClick()
        startActivityAndCollapse(voicePendingIntent(this))
    }
}

/** A one-cell home screen button that starts recording. */
class VoiceWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = RemoteViews(context.packageName, R.layout.widget_voice).apply {
            setOnClickPendingIntent(R.id.widget_mic, voicePendingIntent(context))
        }
        ids.forEach { manager.updateAppWidget(it, views) }
    }
}
