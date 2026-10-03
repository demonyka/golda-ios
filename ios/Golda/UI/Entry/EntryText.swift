import Foundation
import GoldaCore
import GoldaData

/// The words of the operation form and of what it reports afterwards, from the "Entry" table. The
/// domain and the repository hand over numbers and values (D18); the sentences are put together
/// here, in the language of the locale passed in, so tests check both languages without changing
/// the simulator. Amounts stay as `Fmt` writes them (D13); `spoken` variants say them in words.
enum EntryText {
    // MARK: The form

    static func typeTitle(_ type: OpType) -> LocalizedStringResource {
        switch type {
        case .income: LocalizedStringResource("Income", table: "Entry", comment: "Operation form: the type switch, money that came in.")
        case .transfer: LocalizedStringResource("Transfer", table: "Entry", comment: "Operation form: the type switch, money moved between own accounts.")
        default: LocalizedStringResource("Expense", table: "Entry", comment: "Operation form: the type switch, money spent.")
        }
    }

    static let newTitle = LocalizedStringResource("New operation", table: "Entry", comment: "Operation form: the title for a new operation.")
    static let editTitle = LocalizedStringResource("Operation", table: "Entry", comment: "Operation form: the title when an operation is open for editing.")
    static let decidingTitle = LocalizedStringResource("Not sure", table: "Entry", comment: "Operation form: the title of “Not sure”, where a purchase is weighed up before buying.")
    static let cancel = LocalizedStringResource("Cancel", table: "Entry", comment: "Closes the operation form without saving.")
    static let back = LocalizedStringResource("Back", table: "Entry", comment: "Operation form, “Not sure”: back to the form.")
    static let close = LocalizedStringResource("Close", table: "Entry", comment: "Closes the read-only sheet of an opening balance or a reconciliation adjustment.")
    /// "Записать": a new operation.
    static let record = LocalizedStringResource("Save.new", defaultValue: "Save", table: "Entry", comment: "Operation form: the confirmation that records a new operation. Russian “Записать”.")
    /// "Сохранить": the changes to an existing one.
    static let save = LocalizedStringResource("Save", table: "Entry", comment: "Operation form: the confirmation that saves the changes to an operation.")
    static let delete = LocalizedStringResource("Delete", table: "Entry", comment: "Operation form: deletes the operation, at once, with an undo afterwards.")
    static let notSure = LocalizedStringResource("Not sure", table: "Entry", comment: "Operation form: the button that turns a new expense into “Not sure”, the facts about the price.")
    static let skip = LocalizedStringResource("Skip", table: "Entry", comment: "“Not sure”: do not buy it; the money goes to the main goal. Russian “Не беру”.")
    static let think = LocalizedStringResource("Think", table: "Entry", comment: "“Not sure”: put it on the wishlist for a while. Russian “Подумаю”.")
    static let buy = LocalizedStringResource("Buy", table: "Entry", comment: "“Not sure”: buy it; the expense is recorded. Russian “Беру”.")

    static let amount = LocalizedStringResource("Amount", table: "Entry", comment: "VoiceOver: the big amount field of the operation form.")
    static let currency = LocalizedStringResource("Currency", table: "Entry", comment: "Operation form: the menu of the currency the price is in.")
    static let account = LocalizedStringResource("Account", table: "Entry", comment: "Operation form: the account pill when no account is picked, and its VoiceOver name.")
    static let date = LocalizedStringResource("Date", table: "Entry", comment: "VoiceOver: the date pill of the operation form.")
    static let from = LocalizedStringResource("From", table: "Entry", comment: "Transfer: the tile of the account the money leaves.")
    static let to = LocalizedStringResource("To", table: "Entry", comment: "Transfer: the tile of the account the money goes to.")
    static let swap = LocalizedStringResource("Swap", table: "Entry", comment: "Transfer: the round button that swaps “From” and “To”.")
    static let category = LocalizedStringResource("Category", table: "Entry", comment: "VoiceOver: the group of category tiles.")
    static let correct = LocalizedStringResource("Correct", table: "Entry", comment: "VoiceOver hint: tap to type the bank's real figure over the estimate.")

    /// The note's placeholder says what the line is for, never the type picked above it.
    static func notePlaceholder(type: OpType, categoryKey: String?, deciding: Bool) -> LocalizedStringResource {
        if deciding { return LocalizedStringResource("What is it", table: "Entry", comment: "“Not sure”: the placeholder of what the purchase is.") }
        if type == .transfer { return LocalizedStringResource("Note", table: "Entry", comment: "Transfer: the placeholder of its note.") }
        if let categoryKey { return CategoryName.resource(categoryKey) }
        return type == .income
            ? LocalizedStringResource("From where", table: "Entry", comment: "Income: the placeholder of where the money came from.")
            : purchase
    }

    /// What a purchase with neither a note nor a category is called.
    static let purchase = LocalizedStringResource("Purchase", table: "Entry", comment: "An expense with neither a note nor a category; also the placeholder of an expense's note.")

    /// "Можно сегодня 1 849 ₽", under the number before an amount is typed.
    static func safeToday(_ amount: String, in locale: Locale) -> String {
        LocalizedStringResource("Safe today \(amount)", table: "Entry", comment: "Operation form, under the empty amount: what can be spent today, “Safe today 1 849 ₽”.").text(in: locale)
    }

    /// "≈ 5,87 $ со счёта": what the card is charged; without "≈" once corrected.
    static func charged(_ amount: String?, isEstimate: Bool, in locale: Locale, spoken: Bool = false) -> String {
        let written = amount.map { spoken ? SpokenAmount.text($0, locale: locale) : $0 } ?? "—"
        let shown = isEstimate ? (spoken ? about(written, in: locale) : "≈ " + written) : written
        return LocalizedStringResource("\(shown) from the account", table: "Entry", comment: "Operation form: what the card is charged for a purchase in another currency, “≈ 5,87 $ from the account”.").text(in: locale)
    }

    /// "→ ≈ 109,21 $": what the other account receives.
    static func received(_ amount: String?, isEstimate: Bool, in locale: Locale, spoken: Bool = false) -> String {
        let written = amount.map { spoken ? SpokenAmount.text($0, locale: locale) : $0 } ?? "—"
        if spoken {
            let shown = isEstimate ? about(written, in: locale) : written
            return LocalizedStringResource("Receives \(shown)", table: "Entry", comment: "VoiceOver, transfer: what the other account receives, “Receives about 109 US dollars”.").text(in: locale)
        }
        return "→ " + (isEstimate ? "≈ " : "") + written
    }

    /// "about 109 US dollars", for VoiceOver.
    static func about(_ spoken: String, in locale: Locale) -> String {
        LocalizedStringResource("about \(spoken)", table: "Entry", comment: "VoiceOver: an approximate amount, “about 1849 Russian rubles”.").text(in: locale)
    }

    // MARK: "Сомневаюсь"

    /// The small line of a fact: "ч работы", "от цели", "дня бюджета".
    static func factLabel(_ fact: EntryFormModel.Fact, in locale: Locale) -> String {
        switch fact.kind {
        case .hoursOfWork:
            LocalizedStringResource("h of work", table: "Entry", comment: "“Not sure”: under the hours of work the price is, “2,6 h of work”.").text(in: locale)
        case .goalShare:
            LocalizedStringResource("of the goal", table: "Entry", comment: "“Not sure”: under the share of the main goal the price is, “12 % of the goal”.").text(in: locale)
        case .daysOfBudget:
            daysOfBudget(fact.value, in: locale)
        }
    }

    /// "дня бюджета" after "3,6", "дней бюджета" after "5": a whole number takes its plural form,
    /// a fraction the form for "a part of" ("дня", "days").
    static func daysOfBudget(_ number: String, in locale: Locale) -> String {
        guard let whole = Int(number) else {
            return LocalizedStringResource("days of budget", table: "Entry", comment: "“Not sure”: under a fractional number of days of the budget the price is, “3,6 days of budget”.").text(in: locale)
        }
        let counted = LocalizedStringResource("\(whole) days of budget", table: "Entry", comment: "“Not sure”: a whole number of days of the budget the price is, “5 days of budget”. The number shows above the words, so it is cut off the front.").text(in: locale)
        // A catalog's plural forms must contain the number; the tile shows it above the words, so
        // it is cut off here, with whatever grouping the locale gave it.
        return String(counted.drop { !$0.isLetter })
    }

    /// The fact as one sentence for VoiceOver: "2,6 h of work".
    static func spokenFact(_ fact: EntryFormModel.Fact, in locale: Locale) -> String {
        fact.value + " " + factLabel(fact, in: locale)
    }

    /// How long "Подумаю" waits: "24 часа", "3 дня".
    static func wait(_ hours: Int64, in locale: Locale) -> String {
        switch Goals.waitSpan(hours) {
        case .hours(let hours):
            LocalizedStringResource("\(Int(hours)) hours", table: "Entry", comment: "How long to think before buying, “24 hours”.").text(in: locale)
        case .days(let days):
            LocalizedStringResource("\(Int(days)) days", table: "Entry", comment: "How long to think before buying, “3 days”.").text(in: locale)
        }
    }

    // MARK: Bookkeeping

    static func bookkeepingTitle(_ type: OpType) -> LocalizedStringResource {
        type == .adjustment
            ? LocalizedStringResource("Reconciliation adjustment", table: "Entry", comment: "Read-only sheet of an operation that brought an account to the bank's balance.")
            : LocalizedStringResource("Opening balance", table: "Entry", comment: "Read-only sheet of an account's opening balance.")
    }

    // MARK: Failures

    static let saveFailed = LocalizedStringResource("The operation was not saved. Try again.", table: "Entry", comment: "Operation form: saving failed.")
    static let deleteFailed = LocalizedStringResource("The operation was not deleted. Try again.", table: "Entry", comment: "Operation form: deleting failed.")
    static let decideFailed = LocalizedStringResource("That did not work. Try again.", table: "Entry", comment: "“Not sure”: skipping or putting on the wishlist failed.")
    static let ok = LocalizedStringResource("OK", table: "Entry", comment: "Closes a message.")
}

/// What the toast says after the form did something: the port of Android's `announce`,
/// `deleteOperation` and the "Сомневаюсь" snackbars, from the values the repository returns.
enum EntryAnnouncement {
    /// "Шаурма · 15 ₾", then on a second line what it cost in work and what is left for today:
    /// "≈ 2,6 ч работы · на сегодня осталось 503 ₽". The title is the note, else the category,
    /// else "Записано".
    static func saved(_ draft: Draft, impact: Impact?, data: AppData, in locale: Locale) -> String {
        let code = draft.purchaseCurrency ?? data.accountById[draft.accountId]?.currency ?? "RUB"
        let shown = draft.purchaseAmountMinor ?? draft.amountMinor
        let title = title(note: draft.note, categoryKey: draft.categoryKey, fallback: savedTitle, in: locale)
        let first = title + " · " + Fmt.amount(shown, code)
        guard let impact else { return first }
        return first + "\n" + impactLine(impact, base: data.base, in: locale)
    }

    /// "≈ 2,6 ч работы · на сегодня осталось 503 ₽", or "перерасход 120 ₽" once today is spent past.
    static func impactLine(_ impact: Impact, base: Base, in locale: Locale) -> String {
        var parts: [String] = []
        if let hours = impact.hoursOfWork {
            let number = Fmt.number(hours, decimals: 1)
            parts.append(LocalizedStringResource("≈ \(number) h of work", table: "Entry", comment: "After an expense: the hours of work it cost, “≈ 2,6 h of work”.").text(in: locale))
        }
        if impact.leftTodayRub >= 0 {
            let left = base.approx(impact.leftTodayRub)
            parts.append(LocalizedStringResource("left for today \(left)", table: "Entry", comment: "After an expense: what is left of today's budget, “left for today 503 ₽”.").text(in: locale))
        } else {
            let over = base.approx(-impact.leftTodayRub)
            parts.append(LocalizedStringResource("over budget by \(over)", table: "Entry", comment: "After an expense: by how much today's budget is spent past, “over budget by 120 ₽”.").text(in: locale))
        }
        return parts.joined(separator: " · ")
    }

    /// "«Шаурма» удалено".
    static func deleted(_ full: OperationFull, in locale: Locale) -> String {
        let title = title(note: full.op.note, categoryKey: full.op.categoryKey, fallback: entryTitle, in: locale)
        return LocalizedStringResource("“\(title)” deleted", table: "Entry", comment: "Toast after an operation was deleted, with its note or category.").text(in: locale)
    }

    /// "+50 $ к «Велосипед»", or "Сэкономлено 50 $" without a main goal.
    static func skipped(_ outcome: SkipOutcome, in locale: Locale) -> String {
        if let goal = outcome.goal, let added = outcome.addedMinor {
            let amount = Fmt.amount(added, goal.currency)
            let name = goal.name
            return LocalizedStringResource("+\(amount) to “\(name)”", table: "Entry", comment: "Toast after “Skip”: what went to the main goal, “+50 $ to “Bike””.").text(in: locale)
        }
        let saved = Fmt.amount(outcome.wish.amountMinor, outcome.wish.currency)
        return LocalizedStringResource("Saved \(saved)", table: "Entry", comment: "Toast after “Skip” with no main goal: the money not spent, “Saved 50 $”.").text(in: locale)
    }

    /// "«Наушники» — решить через 3 дня".
    static func thinking(_ wish: Wish, in locale: Locale) -> String {
        let wait = EntryText.wait((wish.decideAt - wish.createdAt) / 3_600_000, in: locale)
        let title = wish.title
        return LocalizedStringResource("“\(title)”: decide in \(wait)", table: "Entry", comment: "Toast after “Think”: the purchase waits on the wishlist, ““Headphones”: decide in 3 days”.").text(in: locale)
    }

    static let undo = LocalizedStringResource("Undo", table: "Entry", comment: "Toast action: takes back the operation just recorded. Russian “Отменить”.")
    static let restore = LocalizedStringResource("Undo.delete", defaultValue: "Undo", table: "Entry", comment: "Toast action: brings a deleted operation back. Russian “Вернуть”.")

    private static let savedTitle = LocalizedStringResource("Saved", table: "Entry", comment: "Toast after recording an operation with neither a note nor a category.")
    private static let entryTitle = LocalizedStringResource("Entry", table: "Entry", comment: "What a deleted operation with neither a note nor a category is called in the toast.")

    private static func title(note: String, categoryKey: String?, fallback: LocalizedStringResource, in locale: Locale) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let categoryKey { return CategoryName.resource(categoryKey).text(in: locale) }
        return fallback.text(in: locale)
    }
}
