package sh.aminov.golda.data

import sh.aminov.golda.domain.AppLanguage
import android.content.Context
import androidx.room.withTransaction
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.flow.first
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import sh.aminov.golda.GoldaApplication
import sh.aminov.golda.TAB_ACCOUNTS
import sh.aminov.golda.domain.I18n
import sh.aminov.golda.domain.Settings
import sh.aminov.golda.domain.tr
import java.time.DayOfWeek
import java.time.Duration
import java.time.LocalDateTime
import java.time.temporal.TemporalAdjusters
import java.util.concurrent.TimeUnit

/** Everything Golda knows, in one file. The Gemini key is not part of it. */
@Serializable
data class Backup(
    val version: Int = 1,
    val exportedAt: Long,
    val settings: Settings,
    val accounts: List<Account>,
    val categories: List<Category>,
    val operations: List<Operation>,
    val postings: List<Posting>,
    val rates: List<Rate>,
    val obligations: List<Obligation>,
    val goals: List<Goal>,
    val wishes: List<Wish>,
)

private val json = Json {
    prettyPrint = true
    encodeDefaults = true
    ignoreUnknownKeys = true
}

class Backups(private val db: GoldaDb, private val settings: SettingsStore) {
    private val dao = db.dao()

    suspend fun export(): String {
        val backup = Backup(
            exportedAt = System.currentTimeMillis(),
            settings = settings.flow.first().copy(hasGeminiKey = false),
            accounts = dao.accountsNow(),
            categories = dao.categoriesNow(),
            operations = dao.operationsAll(),
            postings = dao.postingsAll(),
            rates = dao.ratesNow(),
            obligations = dao.obligationsNow(),
            goals = dao.goalsNow(),
            wishes = dao.wishesAll(),
        )
        return json.encodeToString(Backup.serializer(), backup)
    }

    /**
     * Replaces everything with the file's contents. The file is read in full
     * first, so a broken file changes nothing. The Gemini key stays.
     */
    suspend fun import(text: String): Backup {
        val backup = json.decodeFromString(Backup.serializer(), text)
        db.clearAllTablesSafely()
        db.withTransaction {
            dao.insertCategories(backup.categories)
            dao.insertAccounts(backup.accounts)
            dao.insertOperations(backup.operations)
            dao.insertPostings(backup.postings)
            dao.upsertRates(backup.rates)
            dao.insertObligations(backup.obligations)
            dao.insertGoals(backup.goals)
            dao.insertWishes(backup.wishes)
        }
        settings.update { current -> backup.settings.copy(hasGeminiKey = current.hasGeminiKey, onboarded = true) }
        return backup
    }

    private suspend fun GoldaDb.clearAllTablesSafely() =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { clearAllTables() }
}

/** Sunday at 19:00, a nudge to compare balances with the bank. */
object ReconcileSchedule {
    private const val WORK = "reconcile"

    fun apply(context: Context, on: Boolean) {
        val work = WorkManager.getInstance(context)
        if (!on) {
            work.cancelUniqueWork(WORK)
            return
        }
        val now = LocalDateTime.now()
        var next = now.with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY)).withHour(19).withMinute(0).withSecond(0).withNano(0)
        if (!next.isAfter(now)) next = next.plusWeeks(1)
        work.enqueueUniquePeriodicWork(
            WORK,
            ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<ReconcileReminder>(7, TimeUnit.DAYS)
                .setInitialDelay(Duration.between(now, next).toMinutes(), TimeUnit.MINUTES)
                .build(),
        )
    }
}

class ReconcileReminder(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val app = applicationContext as GoldaApplication
        I18n.russian = AppLanguage.russian(app)
        notify(
            app, "reconcile", tr("Сверка", "Reconciling"), 300_000,
            tr("Сверь балансы", "Check your balances"),
            tr("Неделя прошла. Открой банк и сравни счета в Golda — забытые траты найдутся сами.",
                "A week has passed. Open your bank and compare the accounts in Golda; forgotten purchases will show up."),
            tab = TAB_ACCOUNTS,
        )
        return Result.success()
    }
}
