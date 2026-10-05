import Foundation
import GoldaCore

/// Everything the goal form knows and decides, the state and rules of Android's `GoalSheet` without
/// the views: the defaults, what makes the form valid, the main-goal star and the `Goal` that saving
/// hands over. The sheet only lays it out.
struct GoalFormModel: Equatable, Sendable {
    /// What the line under the main-goal switch says. The repository keeps exactly one main goal,
    /// so the switch says what saving will do to the others, and stays on where turning it off
    /// would change nothing.
    enum MainNote: Equatable, Sendable {
        /// The goal is the main one: another goal's star is what moves it.
        case staysMain
        /// No other goal: the first goal is the main one, whatever the switch says.
        case onlyGoal
        /// On, and [name] is the main goal now: it stops being one.
        case takesOverFrom(String)
        /// Off: what the main goal is for.
        case explains
    }

    /// An account the goal can be saved on.
    struct AccountChoice: Identifiable, Equatable, Sendable {
        let id: UUID
        let name: String
    }

    /// The goal being changed; nil for a new one.
    let editing: Goal?
    /// The id a new goal gets, fixed for the life of the form so a second tap saves the same goal.
    let goalId: UUID
    /// Offered first, in the app's one order: the local currency, the shown ones, an edited goal's own.
    /// Every other currency follows them in the list (`CurrencySections`).
    let preferredCurrencies: [String]
    let accounts: [AccountChoice]
    /// The profile's main goal when it is another one.
    let otherMainGoal: Goal?
    /// The profile has goals besides this one.
    let hasOtherGoals: Bool

    var name: String
    var currency: String
    /// The target as typed; the big field groups thousands while typing.
    var targetText: String
    /// Put aside by hand (and by refusals) besides the linked account, as typed.
    var savedText: String
    var accountId: UUID?
    /// As the switch shows it; `isMainLocked` keeps it on where it cannot go off.
    var isMain: Bool

    /// The form for [editing], or for a new goal when it is nil, over the open profile's books.
    init(data: AppData, editing: Goal?, goalId: UUID = UUID()) {
        self.init(goals: data.goals, accounts: data.accounts, settings: data.settings, editing: editing, goalId: goalId)
    }

    init(goals: [Goal], accounts: [Account], settings: Settings, editing: Goal?, goalId: UUID = UUID()) {
        self.editing = editing
        self.goalId = editing?.id ?? goalId
        let others = goals.filter { $0.id != editing?.id }
        otherMainGoal = others.first(where: \.isMain)
        hasOtherGoals = !others.isEmpty
        // A new goal starts in the first shown currency that is not the ruble, as on Android: what
        // you save up for abroad is priced there.
        let start = editing?.currency ?? settings.displayCurrencies.first { $0 != "RUB" } ?? "RUB"
        preferredCurrencies = CurrencyDisplay.currencyChoices(settings: settings, extra: [start])
        self.accounts = accounts.map { AccountChoice(id: $0.id, name: $0.name) }

        name = editing?.name ?? ""
        currency = start
        targetText = editing.map { AmountInput.grouped(Fmt.editable($0.targetMinor, $0.currency)) } ?? ""
        // A plain field, as Android's, so no grouping.
        savedText = editing.flatMap { $0.savedMinor > 0 ? Fmt.editable($0.savedMinor, $0.currency) : nil } ?? ""
        accountId = editing?.accountId
        isMain = editing?.isMain ?? (otherMainGoal == nil)
    }

    var isNew: Bool { editing == nil }

    // MARK: The main goal

    /// The switch cannot go off: the goal is the main one now, or the only goal there is. Either
    /// way the repository would make it main again.
    var isMainLocked: Bool { editing?.isMain == true || !hasOtherGoals }

    /// What saving makes of the main goal.
    var willBeMain: Bool { isMain || isMainLocked }

    var mainNote: MainNote {
        if editing?.isMain == true { return .staysMain }
        if !hasOtherGoals { return .onlyGoal }
        if willBeMain, let other = otherMainGoal { return .takesOverFrom(other.name) }
        return .explains
    }

    // MARK: Reading what was typed

    /// The target, more than nothing; nil while it cannot be read.
    var target: Int64? {
        Fmt.parseMinor(targetText, currency).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Put aside: nothing typed is 0; nil when the text cannot be read.
    var saved: Int64? {
        savedText.allSatisfy(\.isWhitespace) ? 0 : Fmt.parseMinor(savedText, currency)
    }

    /// The target field holds text the form cannot read; empty is not wrong, only unfinished.
    var isTargetInvalid: Bool { !targetText.allSatisfy(\.isWhitespace) && target == nil }

    var isSavedInvalid: Bool { saved == nil }

    var canSave: Bool { output != nil }

    /// What saving writes; nil while the name is empty or an amount cannot be read. Without an
    /// account the progress is what was put aside; with one, what was put aside stays too (the
    /// refusals added it), as on Android.
    var output: Goal? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let target, let saved else { return nil }
        return Goal(
            id: goalId, name: trimmed, targetMinor: target, currency: currency, accountId: accountId,
            savedMinor: saved, isMain: willBeMain
        )
    }

    var accountName: String? { accountId.flatMap { id in accounts.first { $0.id == id }?.name } }

    // MARK: Text

    var title: LocalizedStringResource {
        isNew
            ? LocalizedStringResource("New goal", table: "Goals", comment: "Title of the goal form when creating one.")
            : GoalsContent.addTitle
    }

    var saveTitle: LocalizedStringResource {
        isNew
            ? LocalizedStringResource("Add", table: "Goals", comment: "Goal form: the main action that creates the goal.")
            : LocalizedStringResource("Save", table: "Goals", comment: "Goal form: the main action that saves the changes.")
    }

    func mainNoteText(in locale: Locale) -> String {
        switch mainNote {
        case .staysMain:
            LocalizedStringResource(
                "To change the main goal, star another one.", table: "Goals",
                comment: "Goal form, under the main-goal switch of the main goal: how the main goal changes."
            ).text(in: locale)
        case .onlyGoal:
            LocalizedStringResource("The first goal is the main one.", table: "Goals", comment: "Goal form, under the main-goal switch when there is no other goal.").text(in: locale)
        case .takesOverFrom(let name):
            LocalizedStringResource(
                "“\(name)” will no longer be the main goal.", table: "Goals",
                comment: "Goal form, under the main-goal switch turned on: the goal that is main now stops being it. Its name."
            ).text(in: locale)
        case .explains:
            LocalizedStringResource(
                "Every purchase is held up against the main goal.", table: "Goals",
                comment: "Goal form, under the main-goal switch turned off: what the main goal is for."
            ).text(in: locale)
        }
    }

    static let namePrompt = LocalizedStringResource("What it is for", table: "Goals", comment: "Goal form: the placeholder of the goal’s name.")
    static let targetCaption = LocalizedStringResource("How much it takes", table: "Goals", comment: "Goal form: the header over the goal’s amount.")
    static let currencyTitle = LocalizedStringResource("Currency", table: "Goals", comment: "Goal form: the goal’s currency.")
    static let accountTitle = LocalizedStringResource("Saved on", table: "Goals", comment: "Goal form: the account the money for the goal is kept on.")
    static let noAccount = LocalizedStringResource("No account", table: "Goals", comment: "Goal form: the goal is not tied to an account.")
    static let accountFooter = LocalizedStringResource(
        "Progress is the account’s balance plus what is already put aside.", table: "Goals",
        comment: "Goal form: how progress is counted for a goal saved on an account."
    )
    static let savedTitle = LocalizedStringResource("Already put aside", table: "Goals", comment: "Goal form: what has been saved for the goal without an account.")
    static let mainTitle = LocalizedStringResource("Main goal", table: "Goals", comment: "Goal form: the switch that makes the goal the main one.")
    static let cancelTitle = LocalizedStringResource("Cancel", table: "Goals", comment: "Closes a form or a question without changes.")
    static let deleteTitle = LocalizedStringResource("Delete goal", table: "Goals", comment: "Goal form: the trash button.")
    static let okTitle = LocalizedStringResource("OK", table: "Goals", comment: "Closes a message.")
    static let saveFailed = LocalizedStringResource("The goal was not saved. Try again.", table: "Goals", comment: "Goal form: saving failed.")
    static let somethingFailed = LocalizedStringResource("That did not work. Try again.", table: "Goals", comment: "Goals: deleting, buying or bringing something back failed.")
}
