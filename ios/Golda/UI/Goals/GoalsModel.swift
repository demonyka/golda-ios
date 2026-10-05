import Foundation
import GoldaCore
import GoldaData

// Everything the Goals tab shows, worked out from one `AppData`, the moment it is and the goal this
// phone has already celebrated, the way Android's `GoalsScreen` does it. Plain values: the views
// only lay them out, and tests check them in both languages with a fixed clock.

/// "13 700 ₽ сэкономлено отказами": what "Не беру" kept from being spent so far, in the main
/// currency. It goes into no goal (D63): money not spent is not money put aside. Shown from the
/// start ("0 ₽"), so the mechanic is visible before it is first used.
struct SkippedTotal: Equatable, Sendable {
    let rubMinor: Int64
    /// "13 700 ₽", or "0 ₽" before the first refusal.
    let amount: String

    init(wishes: [Wish], rates: Rates, base: Base) {
        // Held at Int64.max: refusals too big to add up show a wrong figure, not a crash (D59).
        rubMinor = wishes.filter { $0.status == .skipped }.moneySum { Goals.rubOf($0.amountMinor, $0.currency, rates) }
        amount = base.approx(rubMinor)
    }

    func text(in locale: Locale, spoken: Bool = false) -> String {
        let figure = spoken ? SpokenAmount.text(amount, locale: locale) : amount
        return LocalizedStringResource(
            "\(figure) saved by skipping", table: "Goals",
            comment: "Goals hero: what refusals (“I’ll pass”) kept from being spent, “13 700 ₽ saved by skipping”. Not put into any goal."
        ).text(in: locale)
    }
}

/// The main goal as the hero: what is saved, how far along, and whether it can be bought.
struct MainGoalHero: Equatable, Sendable {
    let goal: Goal
    /// Saved so far in the goal's currency: the linked account plus what refusals put aside.
    let savedMinor: Int64
    /// "30 330,19 ₽", as the big number writes it.
    let saved: String
    /// 0...1 for the bar: full is also the overflow.
    let progress: Double
    /// Whole percent, past 100 when the goal is overshot ("110 %").
    let percent: Int64
    /// "80 000 ₽"
    let target: String
    /// Saved at least the target: the bar is full and "Купить" appears.
    let isReached: Bool
    /// Reached and not yet celebrated on this phone: the wave settles with a tap of haptics, once.
    let celebrates: Bool
    let skipped: SkippedTotal

    init(goal: Goal, data: AppData, skipped: SkippedTotal, celebratedGoalId: UUID?) {
        self.goal = goal
        savedMinor = Goals.progressMinor(goal, data.states, data.rates)
        saved = Fmt.amount(savedMinor, goal.currency)
        progress = Double(Goals.share(savedMinor, goal.targetMinor))
        percent = Goals.percentRounded(savedMinor, goal.targetMinor)
        target = Fmt.amount(goal.targetMinor, goal.currency)
        isReached = savedMinor >= goal.targetMinor
        celebrates = isReached && celebratedGoalId != goal.id
        self.skipped = skipped
    }

    /// "38 % из 80 000 ₽"
    func progressText(in locale: Locale, spoken: Bool = false) -> String {
        let share = GoalPercent.text(percent)
        let whole = spoken ? SpokenAmount.text(target, locale: locale) : target
        return LocalizedStringResource(
            "\(share) of \(whole)", table: "Goals",
            comment: "Goals hero: how far along the main goal is, “38 % of 80 000 ₽”. The percent, then the goal’s amount."
        ).text(in: locale)
    }

    /// "Купить Велосипед · 80 000 ₽", the only buy button of the screen.
    func buyTitle(in locale: Locale) -> String {
        let name = goal.name, amount = target
        return LocalizedStringResource(
            "Buy \(name) · \(amount)", table: "Goals",
            comment: "Goals hero: the button that buys a reached goal, “Buy Bike · 80 000 ₽”. The goal’s name, then its amount."
        ).text(in: locale)
    }

    /// The tile as one sentence for VoiceOver, amounts in words.
    func accessibilityLabel(in locale: Locale) -> String {
        [goal.name, SpokenAmount.text(saved, locale: locale), progressText(in: locale, spoken: true), skipped.text(in: locale, spoken: true)]
            .joined(separator: ". ")
    }
}

/// The hero of Goals: the main goal, or what to do when there is none.
enum GoalsHero: Equatable, Sendable {
    /// No goal at all: "Поставь цель".
    case noGoals(SkippedTotal)
    /// Goals, none of them main: "Выбери главную цель". The repository keeps one main goal, so this
    /// is only a moment between two reads, or books from elsewhere.
    case noMainGoal(SkippedTotal)
    case main(MainGoalHero)

    static let caption = LocalizedStringResource(
        "Savings", table: "Goals", comment: "Goals hero caption when there is no main goal: the savings pot."
    )
    static let setGoalTitle = LocalizedStringResource("Set a goal", table: "Goals", comment: "Goals hero with no goals yet: the call to make one.")
    static let setGoalText = LocalizedStringResource(
        "A bike, a trip, a cushion. Every purchase is held up against it.", table: "Goals",
        comment: "Goals hero with no goals yet: what a goal is for."
    )
    static let pickMainTitle = LocalizedStringResource("Pick the main goal", table: "Goals", comment: "Goals hero when goals exist but none is the main one.")
    static let pickMainText = LocalizedStringResource(
        "The star in a goal makes it the main one", table: "Goals", comment: "Goals hero when no goal is main: how to make one main."
    )

    /// The tile as one sentence for VoiceOver.
    func accessibilityLabel(in locale: Locale) -> String {
        switch self {
        case .noGoals(let skipped):
            [Self.caption, Self.setGoalTitle, Self.setGoalText].map { $0.text(in: locale) }.joined(separator: ". ")
                + ". " + skipped.text(in: locale, spoken: true)
        case .noMainGoal(let skipped):
            [Self.caption, Self.pickMainTitle, Self.pickMainText].map { $0.text(in: locale) }.joined(separator: ". ")
                + ". " + skipped.text(in: locale, spoken: true)
        case .main(let hero):
            hero.accessibilityLabel(in: locale)
        }
    }
}

/// Another goal as a row: the name, "62 % · из 1 500 $" over a thin wavy bar, and what is saved.
struct GoalRowModel: Identifiable, Equatable, Sendable {
    let goal: Goal
    let savedMinor: Int64
    /// "330 000 ₽"; the view quiets the cents.
    let saved: String
    let progress: Double
    let percent: Int64
    let target: String

    var id: UUID { goal.id }

    init(goal: Goal, data: AppData) {
        self.goal = goal
        savedMinor = Goals.progressMinor(goal, data.states, data.rates)
        saved = Fmt.amount(savedMinor, goal.currency)
        progress = Double(Goals.share(savedMinor, goal.targetMinor))
        percent = Goals.percentRounded(savedMinor, goal.targetMinor)
        target = Fmt.amount(goal.targetMinor, goal.currency)
    }

    /// "110 % · из 300 000 ₽"
    func detailText(in locale: Locale, spoken: Bool = false) -> String {
        let whole = spoken ? SpokenAmount.text(target, locale: locale) : target
        let of = LocalizedStringResource(
            "of \(whole)", table: "Goals", comment: "A goal’s row: the goal’s amount after its percent, “110 % · of 300 000 ₽”."
        ).text(in: locale)
        return GoalPercent.text(percent) + " · " + of
    }

    func accessibilityLabel(in locale: Locale) -> String {
        [goal.name, detailText(in: locale, spoken: true), SpokenAmount.text(saved, locale: locale)].joined(separator: ", ")
    }
}

/// How long a waiting wish still has, from the moment the screen is drawn.
enum WishWait: Equatable, Sendable {
    /// "через 2 дня", "через 5 часов".
    case left(WaitSpan)
    /// The time is up: "пора решать".
    case due

    /// Whole hours left, rounded up, as Android counts them: a wish due in ten minutes still waits
    /// "1 час", and one due a moment ago is due.
    init(decideAt: Int64, now: Int64) {
        let hoursLeft = (decideAt - now + 3_599_999) / 3_600_000
        self = hoursLeft > 0 ? .left(Goals.waitSpan(hoursLeft)) : .due
    }

    func text(in locale: Locale) -> String {
        switch self {
        case .left(.hours(let hours)):
            LocalizedStringResource("in \(hours) hours", table: "Goals", comment: "A waiting wish: the hours left to think, “in 5 hours”.").text(in: locale)
        case .left(.days(let days)):
            LocalizedStringResource("in \(days) days", table: "Goals", comment: "A waiting wish: the days left to think, “in 2 days”.").text(in: locale)
        case .due:
            LocalizedStringResource("time to decide", table: "Goals", comment: "A waiting wish whose thinking time is up.").text(in: locale)
        }
    }
}

/// "14 %", "<1 %": a share in whole percent, as Android's `wholePercent` writes it.
enum GoalPercent {
    /// Kotlin's `round` goes to the even neighbour on a tie (14.5 → 14), and so does this. The
    /// space before the sign does not break, so "%" never starts a line.
    static func whole(_ share: Double) -> String {
        if share > 0, share < 0.005 { return "<1\u{00A0}%" }
        return text(Int64((share * 100).rounded(.toNearestOrEven)))
    }

    /// "62 %" for a percent that is already whole.
    static func text(_ percent: Int64) -> String { "\(percent)\u{00A0}%" }
}

/// A wish that waits for its decision: the name, the wait and its share of the main goal, the price.
struct WaitingWishRowModel: Identifiable, Equatable, Sendable {
    let wish: Wish
    let wait: WishWait
    /// What the wish would take of the main goal, 0...1 and beyond; nil without a main goal.
    let goalShare: Double?
    /// "120 $"
    let amount: String

    var id: UUID { wish.id }

    init(wish: Wish, mainGoal: Goal?, rates: Rates, now: Int64) {
        self.wish = wish
        wait = WishWait(decideAt: wish.decideAt, now: now)
        goalShare = mainGoal.map { goal in
            let target = Goals.rubOf(goal.targetMinor, goal.currency, rates)
            return target > 0 ? Double(Goals.rubOf(wish.amountMinor, wish.currency, rates)) / Double(target) : 0
        }
        amount = Fmt.amount(wish.amountMinor, wish.currency)
    }

    /// "через 2 дня · 14 % цели", or "пора решать".
    func detailText(in locale: Locale) -> String {
        var parts = [wait.text(in: locale)]
        if let goalShare {
            let share = GoalPercent.whole(goalShare)
            parts.append(LocalizedStringResource(
                "\(share) of the goal", table: "Goals", comment: "A waiting wish: its price as a share of the main goal, “14 % of the goal”."
            ).text(in: locale))
        }
        return parts.joined(separator: " · ")
    }

    /// The purchase this wish is, to weigh up again in "Сомневаюсь".
    var consider: Consider { Consider(title: wish.title, amountMinor: wish.amountMinor, currency: wish.currency) }

    func accessibilityLabel(in locale: Locale) -> String {
        [wish.title, detailText(in: locale), SpokenAmount.text(amount, locale: locale)].joined(separator: ", ")
    }
}

/// A wish already decided on: bought or skipped.
struct DecidedWishRowModel: Identifiable, Equatable, Sendable {
    let wish: Wish
    let amount: String

    var id: UUID { wish.id }

    init(wish: Wish) {
        self.wish = wish
        amount = Fmt.amount(wish.amountMinor, wish.currency)
    }

    func detailText(in locale: Locale) -> String {
        wish.status == .bought
            ? LocalizedStringResource("bought", table: "Goals", comment: "A decided wish that was bought.").text(in: locale)
            : LocalizedStringResource("skipped", table: "Goals", comment: "A decided wish that was not bought (“I’ll pass”).").text(in: locale)
    }

    func accessibilityLabel(in locale: Locale) -> String {
        [wish.title, detailText(in: locale), SpokenAmount.text(amount, locale: locale)].joined(separator: ", ")
    }
}

/// The Goals tab for the open profile: the hero, the other goals, what waits and what is decided.
struct GoalsContent: Equatable, Sendable {
    /// How many decided wishes the folded list shows at most, the newest first.
    static let decidedShown = 30

    let hero: GoalsHero
    /// Every goal but the main one: the main one first, then by creation (D27), as `AppData` has them.
    let goals: [GoalRowModel]
    /// The profile has a main goal; the other goals are then "Другие цели".
    let hasMainGoal: Bool
    /// The soonest decision first.
    let waiting: [WaitingWishRowModel]
    /// The newest decision first, the first `decidedShown` of them.
    let decided: [DecidedWishRowModel]
    /// All decided wishes, also the ones past `decidedShown`.
    let decidedCount: Int

    /// [now] is epoch milliseconds; [celebratedGoalId] is the goal this phone already celebrated in
    /// the profile.
    init(data: AppData, now: Int64, celebratedGoalId: UUID?) {
        let main = data.goals.first(where: \.isMain)
        let skipped = SkippedTotal(wishes: data.wishes, rates: data.rates, base: data.base)
        if let main {
            hero = .main(MainGoalHero(goal: main, data: data, skipped: skipped, celebratedGoalId: celebratedGoalId))
        } else {
            hero = data.goals.isEmpty ? .noGoals(skipped) : .noMainGoal(skipped)
        }
        hasMainGoal = main != nil
        goals = data.goals.filter { !$0.isMain }.map { GoalRowModel(goal: $0, data: data) }
        // Kotlin's `sortedBy` keeps ties in their order; the offset does the same here.
        waiting = data.wishes.filter { $0.status == .waiting }
            .enumerated()
            .sorted { ($0.element.decideAt, $0.offset) < ($1.element.decideAt, $1.offset) }
            .map { WaitingWishRowModel(wish: $0.element, mainGoal: main, rates: data.rates, now: now) }
        // `sortedByDescending` puts a missing time last, as the smallest.
        let decidedWishes = data.wishes.filter { $0.status != .waiting }
            .enumerated()
            .sorted { ($1.element.decidedAt ?? .min, $0.offset) < ($0.element.decidedAt ?? .min, $1.offset) }
            .map(\.element)
        decided = decidedWishes.prefix(Self.decidedShown).map(DecidedWishRowModel.init)
        decidedCount = decidedWishes.count
    }

    /// The header over the other goals; nil when there are none (only "+ Цель" is left).
    var goalsHeader: LocalizedStringResource? {
        guard !goals.isEmpty else { return nil }
        return hasMainGoal ? Self.otherGoalsTitle : Self.goalsTitle
    }

    /// "Решено · 3"
    func decidedTitle(in locale: Locale) -> String {
        let count = decidedCount
        return LocalizedStringResource(
            "Decided · \(count)", table: "Goals", comment: "Goals: the folded list of wishes bought or skipped, with how many."
        ).text(in: locale)
    }

    static let goalsTitle = LocalizedStringResource("Goals", table: "Goals", comment: "Goals: the header over the goals when none of them is the main one.")
    static let otherGoalsTitle = LocalizedStringResource("Other goals", table: "Goals", comment: "Goals: the header over the goals other than the main one.")
    static let waitingTitle = LocalizedStringResource("Waiting for a decision", table: "Goals", comment: "Goals: the header over the wishes put off with “Let me think”.")
    static let addTitle = LocalizedStringResource("Goal", table: "Goals", comment: "Goals: the row “+ Goal” that opens the form for a new goal; also the title of the form for an existing goal.")
    static let addLabel = LocalizedStringResource("Add goal", table: "Goals", comment: "VoiceOver: the “+ Goal” row.")
    static let removeTitle = LocalizedStringResource("Remove", table: "Goals", comment: "Swipe action and menu item that takes a wish off the list.")
    static let heroHint = LocalizedStringResource("Opens the goal", table: "Goals", comment: "VoiceOver hint of the Goals hero: tapping it opens the goal’s form.")
    static let newGoalHint = LocalizedStringResource("Opens a new goal", table: "Goals", comment: "VoiceOver hint of the empty Goals hero: tapping it opens the form for a new goal.")
    static let wishHint = LocalizedStringResource("Opens the purchase to decide on it", table: "Goals", comment: "VoiceOver hint of a waiting wish: tapping it opens “Not sure” for it.")
    static let decidedHint = LocalizedStringResource("Shows or hides what was decided", table: "Goals", comment: "VoiceOver hint of the “Decided · 3” header.")

    /// "«Наушники» убрано", the toast after a wish is removed.
    static func wishRemoved(_ title: String, in locale: Locale) -> String {
        LocalizedStringResource("“\(title)” removed", table: "Goals", comment: "Toast after a wish was taken off the list, with its name.").text(in: locale)
    }

    /// "Цель «Велосипед» удалена", the toast after a goal is deleted.
    static func goalDeleted(_ name: String, in locale: Locale) -> String {
        LocalizedStringResource("Goal “\(name)” deleted", table: "Goals", comment: "Toast after a goal was deleted, with its name.").text(in: locale)
    }
}

/// What "Купить" on a reached goal will do, said before it is done: the expense and the account it
/// comes from, picked as `VoiceMapper.buy` picks it (the repository books it the same way).
struct GoalPurchasePlan: Equatable, Sendable {
    let goal: Goal
    /// "80 000 ₽"
    let amount: String
    /// The account the expense comes from; nil when no account can pay.
    let accountName: String?

    init(goal: Goal, data: AppData, now: Int64) {
        self.goal = goal
        amount = Fmt.amount(goal.targetMinor, goal.currency)
        let consider = Consider(title: goal.name, amountMinor: goal.targetMinor, currency: goal.currency)
        let draft = VoiceMapper.buy(consider, accounts: data.accounts, settings: data.settings, rates: data.rates, now: now)
        accountName = draft.flatMap { data.accountById[$0.accountId]?.name }
    }

    var canBuy: Bool { accountName != nil }

    /// "Купить «Велосипед»?"
    func title(in locale: Locale) -> String {
        let name = goal.name
        return LocalizedStringResource("Buy “\(name)”?", table: "Goals", comment: "Title of the question before a reached goal is bought, with its name.").text(in: locale)
    }

    /// "Расход 80 000 ₽ с «Карта ₽». Цель закроется."
    func message(in locale: Locale) -> String {
        guard let accountName else { return Self.noAccount.text(in: locale) }
        let amount = amount
        return LocalizedStringResource(
            "\(amount) spent from “\(accountName)”. The goal closes.", table: "Goals",
            comment: "The question before a goal is bought: the expense and the account it comes from. The amount, then the account’s name."
        ).text(in: locale)
    }

    static let noAccount = LocalizedStringResource("No suitable account.", table: "Goals", comment: "A goal cannot be bought: no account to pay from.")
    static let buyTitle = LocalizedStringResource("Buy", table: "Goals", comment: "Confirms buying a reached goal.")
}

/// What buying a goal did, for the toast: "Велосипед · 80 000 ₽" and, under it, the hours of work
/// and what is left for today. The words are the operation form's (`EntryAnnouncement.spent`):
/// "Купить" and "Беру" both spend, and Android announces them the same way.
struct GoalPurchaseReport: Sendable {
    let name: String
    let amount: String
    let impact: Impact?
    let base: Base

    init(goal: Goal, impact: Impact?, base: Base) {
        name = goal.name
        amount = Fmt.amount(goal.targetMinor, goal.currency)
        self.impact = impact
        self.base = base
    }

    func text(in locale: Locale) -> String {
        EntryAnnouncement.spent(title: name, amount: amount, impact: impact, base: base, in: locale)
    }
}
