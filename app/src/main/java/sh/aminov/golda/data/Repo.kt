package sh.aminov.golda.data

import android.content.Context
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import sh.aminov.golda.domain.VoiceAction
import sh.aminov.golda.domain.VoiceMapper
import sh.aminov.golda.domain.VoicePrompt
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import sh.aminov.golda.domain.AccountState
import sh.aminov.golda.domain.Draft
import sh.aminov.golda.domain.Ledger
import sh.aminov.golda.domain.Rates
import sh.aminov.golda.domain.tr

sealed interface VoiceOutcome {
    /** [recorded] pairs each saved operation id with what was saved. */
    data class Done(
        val transcript: String,
        val recorded: List<Pair<Long, Draft>>,
        val considering: List<VoiceAction.Consider>,
        val misunderstood: Boolean,
        val late: Boolean,
        /** What the last expense cost in work and what is left for today. */
        val comment: String? = null,
    ) : VoiceOutcome

    /** Kept for later: no network, or no key yet. */
    data class Waiting(val reason: String) : VoiceOutcome

    data class Failed(val reason: String) : VoiceOutcome
}

class Repo(private val context: Context) {
    private val db = GoldaDb.open(context)
    private val dao = db.dao()
    val settings = SettingsStore(context)

    val accounts = dao.accounts()
    val operations = dao.operations()
    val categories = dao.categories()
    val rates = dao.rates()
    val obligations = dao.obligations()
    val wishes = Wishes(context, this, dao)
    val backups = Backups(db, settings)

    suspend fun saveObligation(obligation: Obligation) = write { dao.upsertObligation(obligation) }

    suspend fun deleteObligation(id: Long) = write { dao.deleteObligation(id) }

    /**
     * Writes finish even when the screen that started them goes away (wiping
     * the data swaps the whole UI for onboarding mid-way, for instance).
     */
    private suspend fun <T> write(block: suspend () -> T): T = withContext(NonCancellable) { block() }

    suspend fun ensureSeed() = write {
        if (dao.categoryCount() == 0) dao.insertCategories(DefaultCategories.all)
        if (dao.ratesNow().isEmpty()) dao.upsertRates(Cbr.fallback)
        repairValuations()
    }

    /** True when fresh rates arrived. */
    suspend fun refreshRates(): Boolean {
        val fresh = runCatching { Cbr.fetch() }.getOrNull() ?: return false
        write {
            dao.upsertRates(fresh)
            repairValuations()
        }
        return true
    }

    /**
     * A posting written while its currency had no rate got valued at 0 ₽;
     * once a rate exists it is valued at today's rate instead.
     */
    private suspend fun repairValuations() {
        val rates = ratesNow()
        val accounts = dao.accountsNow().associateBy { it.id }
        for (posting in dao.postingsNow()) {
            val currency = accounts[posting.accountId]?.currency ?: continue
            if (currency == "RUB" || posting.rubMinor != 0L || posting.amountMinor == 0L) continue
            rates.rubMinor(posting.amountMinor, currency)?.let { dao.updatePosting(posting.copy(rubMinor = it)) }
        }
    }

    private suspend fun ratesNow(): Rates =
        Rates(dao.ratesNow().associate { it.code to it.rubPerUnit }, settings.flow.first().markup)

    suspend fun saveAccount(account: Account, openingMinor: Long?): Long = write {
        if (account.id != 0L) {
            dao.updateAccount(account)
            return@write account.id
        }
        val id = dao.insertAccount(account)
        if (openingMinor != null && openingMinor != 0L) {
            save(Draft(OpType.OPENING, System.currentTimeMillis(), id, openingMinor))
        }
        id
    }

    suspend fun deleteAccount(id: Long) = write {
        dao.deleteOperationsOf(id)
        dao.deleteAccount(id)
    }

    /** Records [draft] (or replaces the operation with its id) and returns the operation id. */
    suspend fun save(draft: Draft): Long = write {
        val states = Ledger.states(dao.accountsNow(), dao.postingsNow(except = draft.id))
        val rates = ratesNow()
        val postings = Ledger.postings(draft, states, rates)
        val cbr = exchangeRates(draft, states, rates)
        val op = Operation(
            id = draft.id,
            type = draft.type,
            timestamp = draft.timestamp,
            categoryId = draft.categoryId,
            note = draft.note.trim(),
            voiceText = draft.voiceText,
            purchaseAmountMinor = draft.purchaseAmountMinor,
            purchaseCurrency = draft.purchaseCurrency,
            isEstimate = draft.isEstimate,
            cbrFrom = cbr?.first,
            cbrTo = cbr?.second,
        )
        val id = dao.saveOperation(op, postings)
        val learned = Ledger.learnedMarkup(draft, states, rates)
        settings.update { s ->
            val withMarkup = if (learned != null) s.copy(markup = learned) else s
            if (draft.type == OpType.EXPENSE) withMarkup.copy(lastAccountId = draft.accountId) else withMarkup
        }
        id
    }

    /** Official rates of both currencies of a transfer that changes currency. */
    private fun exchangeRates(draft: Draft, states: Map<Long, AccountState>, rates: Rates): Pair<Double, Double>? {
        if (draft.type != OpType.TRANSFER) return null
        val from = states[draft.accountId]?.currency ?: return null
        val to = states[draft.toAccountId ?: return null]?.currency ?: return null
        if (from == to) return null
        return (rates.official(from) ?: return null) to (rates.official(to) ?: return null)
    }

    /** Debts with their balances, for reminders. */
    suspend fun debtStates(): List<AccountState> =
        Ledger.states(dao.accountsNow(), dao.postingsNow()).values.filter { it.account.type == AccountType.CREDIT || it.account.type == AccountType.LOAN }

    suspend fun deleteOperation(id: Long) = write { dao.deleteOperation(id) }

    suspend fun restoreOperation(full: OperationFull) = write { dao.restoreOperation(full.op, full.postings) }

    private val voiceLock = Mutex()
    private val _voice = MutableSharedFlow<VoiceOutcome>(extraBufferCapacity = 16)

    /** Every understood (or postponed) voice note, for the UI to report. */
    val voice: SharedFlow<VoiceOutcome> = _voice

    /** Understands one recorded note and books what it says. The file is removed once understood. */
    suspend fun understand(file: File, late: Boolean = false): VoiceOutcome = voiceLock.withLock { understandLocked(file, late) }

    /** Notes recorded offline or before the key was set. */
    suspend fun processVoiceQueue() = voiceLock.withLock {
        for (file in VoiceQueue.pending(context)) {
            if (System.currentTimeMillis() - file.lastModified() < 2_000) continue // still being recorded
            if (understandLocked(file, late = true) is VoiceOutcome.Waiting) break
        }
    }

    private suspend fun understandLocked(file: File, late: Boolean): VoiceOutcome {
        if (!file.exists()) return VoiceOutcome.Failed(tr("запись потерялась", "the note got lost"))
        val outcome = write<VoiceOutcome> {
            val key = settings.geminiKey() ?: return@write VoiceOutcome.Waiting(tr("Добавь ключ Gemini в настройках — запись сохранена", "Add a Gemini key in settings; the note is kept"))
            val s = settings.flow.first()
            val accounts = dao.accountsNow().sortedBy { it.sort }
            val categories = dao.categoriesNow()
            val zone = ZoneId.systemDefault()
            val system = VoicePrompt.system(accounts, categories, s, LocalDate.now(zone))
            val result = try {
                Gemini.parse(file, system, key, s.geminiModel)
            } catch (e: GeminiException) {
                return@write if (e.offline) VoiceOutcome.Waiting(tr("Нет связи — запись разберётся позже", "No connection; the note will be worked out later")) else VoiceOutcome.Failed("Gemini: ${e.message}")
            }
            val actions = VoiceMapper.actions(result, accounts, categories, s, ratesNow(), VoiceQueue.recordedAt(file), zone)
            val recorded = actions.filterIsInstance<VoiceAction.Record>().map { save(it.draft) to it.draft }
            file.delete()
            val comment = recorded.lastOrNull { it.second.type == OpType.EXPENSE }?.let { wishes.impact(it.first) }
            VoiceOutcome.Done(
                comment = comment,
                transcript = result.transcript,
                recorded = recorded,
                considering = actions.filterIsInstance<VoiceAction.Consider>(),
                misunderstood = actions.any { it is VoiceAction.NotUnderstood },
                late = late,
            )
        }
        _voice.emit(outcome)
        return outcome
    }

    /** "На самом деле на счёте X": books the difference as an adjustment. */
    /** Brings [accountId] to what the bank shows; a match records nothing but the time it was checked. */
    suspend fun reconcile(accountId: Long, actualMinor: Long) = write {
        val state = Ledger.states(dao.accountsNow(), dao.postingsNow()).getValue(accountId)
        val delta = actualMinor - state.balanceMinor
        val now = System.currentTimeMillis()
        if (delta != 0L) save(Draft(OpType.ADJUSTMENT, now, accountId, delta))
        settings.update { it.copy(reconciledAt = it.reconciledAt + (accountId to now)) }
    }

    suspend fun resetAll() = write {
        withContext(Dispatchers.IO) { db.clearAllTables() }
        ensureSeed()
        // Last: clearing settings is what sends the UI back to onboarding.
        settings.clear()
    }
}

object DefaultCategories {
    val all = listOf(
        Category(key = "eating_out", name = "Кафе", emoji = "🍔", kind = CategoryKind.EXPENSE, sort = 0),
        Category(key = "groceries", name = "Продукты", emoji = "🛒", kind = CategoryKind.EXPENSE, sort = 1),
        Category(key = "transport", name = "Транспорт", emoji = "🚕", kind = CategoryKind.EXPENSE, sort = 2),
        Category(key = "housing", name = "Жильё", emoji = "🏠", kind = CategoryKind.EXPENSE, sort = 3),
        Category(key = "telecom", name = "Связь", emoji = "📱", kind = CategoryKind.EXPENSE, sort = 4),
        Category(key = "fun", name = "Развлечения", emoji = "🎉", kind = CategoryKind.EXPENSE, sort = 5),
        Category(key = "health", name = "Здоровье", emoji = "💊", kind = CategoryKind.EXPENSE, sort = 6),
        Category(key = "clothes", name = "Одежда", emoji = "👕", kind = CategoryKind.EXPENSE, sort = 7),
        Category(key = "subscriptions", name = "Подписки", emoji = "🔁", kind = CategoryKind.EXPENSE, sort = 8),
        Category(key = "travel", name = "Путешествия", emoji = "✈️", kind = CategoryKind.EXPENSE, sort = 9),
        Category(key = "fees", name = "Комиссии", emoji = "💸", kind = CategoryKind.EXPENSE, sort = 10),
        Category(key = "other", name = "Прочее", emoji = "📦", kind = CategoryKind.EXPENSE, sort = 11),
        Category(key = "salary", name = "Зарплата", emoji = "💼", kind = CategoryKind.INCOME, sort = 0),
        Category(key = "interest", name = "Проценты", emoji = "🏦", kind = CategoryKind.INCOME, sort = 1),
        Category(key = "gift", name = "Подарок", emoji = "🎁", kind = CategoryKind.INCOME, sort = 2),
        Category(key = "other_income", name = "Прочее", emoji = "📦", kind = CategoryKind.INCOME, sort = 3),
    )
}
