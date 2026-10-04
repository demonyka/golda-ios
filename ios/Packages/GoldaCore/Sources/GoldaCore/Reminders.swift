import Foundation

/// One set of books, as the reminders read it.
public struct ReminderBooks: Equatable, Sendable {
    /// Whose books these are. The domain does not look inside it (the app passes a profile id); it
    /// comes back on each reminder, so a tap opens the same books.
    public var id: UUID
    public var accounts: [Account]
    public var states: [UUID: AccountState]
    public var wishes: [Wish]

    public init(id: UUID, accounts: [Account], states: [UUID: AccountState], wishes: [Wish]) {
        self.id = id
        self.accounts = accounts
        self.states = states
        self.wishes = wishes
    }
}

/// A local notification to come. The domain gives the values, not the sentence (D18): the app
/// words it in the reader's language.
public struct Reminder: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        /// The thinking time of a wish is up: "Прошло 3 дня. Ещё хочешь «Наушники» за 120 $?"
        case wish(wishId: UUID, title: String, amountMinor: Int64, currency: String, waitHours: Int64)
        /// A debt's monthly payment, [daysLeft] 3 or 0: "Через 3 дня платёж: 10 000 ₽".
        case payment(accountId: UUID, accountName: String, amountMinor: Int64, currency: String, daysLeft: Int)
        /// A credit card's interest-free period ends, [daysLeft] 7, 1 or 0, with what is owed now.
        case gracePeriod(accountId: UUID, accountName: String, owedMinor: Int64, currency: String, daysLeft: Int)
        /// Sunday evening: compare the balances with the bank.
        case reconcile
    }

    public enum Time: Equatable, Sendable {
        /// A moment, the same wherever the phone is: a wish's time is up when its hours have passed.
        case instant(Int64)
        /// A time of day on a calendar day, wherever the phone is on that day: a payment is due on
        /// a date, not at an instant.
        case day(LocalDate, hour: Int, minute: Int)
        /// Every week at that time, wherever the phone is; it repeats without the app.
        case weekly(DayOfWeek, hour: Int, minute: Int)
    }

    /// The same for the same thing across plans, so a plan replaces what an earlier one scheduled:
    /// one per wish, one per debt, kind and day ("payment.<account>.2026-10-22"), one for reconciling.
    public var id: String
    /// The books it is about; nil for the reconcile reminder, which is one for all of them.
    public var booksId: UUID?
    public var event: Event
    public var time: Time
    /// When it next goes off, epoch milliseconds in the zone of the plan; the plan is in this order.
    public var fireAt: Int64

    public init(id: String, booksId: UUID?, event: Event, time: Time, fireAt: Int64) {
        self.id = id
        self.booksId = booksId
        self.event = event
        self.time = time
        self.fireAt = fireAt
    }
}

/// What to remind of and when, for every set of books at once: the port of Android's `WishReminder`,
/// `DebtReminder` and `ReconcileReminder`. Android's workers run when a reminder is due and decide
/// then; iOS shows a notification without running the app, so the plan is made ahead and made again
/// at launch, after a change and in the background.
public enum Reminders {
    /// iOS keeps the 64 soonest pending notifications of an app and silently drops the rest. The plan
    /// stops a few short, so a request added before the old ones are removed never pushes out one
    /// the plan wanted.
    public static let limit = 60

    /// Debt reminders come in the morning of their day. Android's daily worker had no set hour.
    public static let debtHour = 10
    /// Android's `ReconcileSchedule`: Sundays at 19:00.
    public static let reconcileDay = DayOfWeek.sunday
    public static let reconcileHour = 19

    /// Days before a payment it is reminded of, as in `DebtReminder`.
    static let paymentDays = [3, 0]
    /// Days before the end of an interest-free period.
    static let graceDays = [7, 1, 0]

    /// Everything still to come, soonest first, at most [limit]. Every reminder of a debt's next two
    /// payments and of its interest-free period is planned at once, each a request of its own: iOS
    /// shows them without the app, which may not run again before the day (the background refresh
    /// comes when the system decides, never after a force quit), so a reminder planned only after
    /// the one before it had gone off could never come (D49). That is at most seven places a debt;
    /// past [limit] the furthest wait for a later plan. A moment already passed is left out; its
    /// notification, if any, went off when it came.
    public static func plan(_ books: [ReminderBooks], reconcile: Bool, now: Int64, zone: TimeZone, limit: Int = limit) -> [Reminder] {
        let today = LocalDate(epochMillis: now, in: zone)
        var planned: [Reminder] = []
        for book in books {
            planned += book.wishes.compactMap { wish(of: $0, books: book.id, now: now) }
            for account in book.accounts where account.isDebt {
                // Only a debt still owed is reminded of, as `DebtReminder` checks the balance.
                guard let balance = book.states[account.id]?.balanceMinor, balance < 0 else { continue }
                planned += payments(of: account, books: book.id, today: today, now: now, zone: zone)
                planned += grace(of: account, owedMinor: -balance, books: book.id, now: now, zone: zone)
            }
        }
        if reconcile { planned.append(reconcileReminder(now: now, zone: zone)) }
        let ordered = planned.sorted { ($0.fireAt, $0.id) < ($1.fireAt, $1.id) }
        return Array(ordered.prefix(max(limit, 0)))
    }

    /// When the app should be woken to plan again: once the soonest debt reminder has gone off, so
    /// the plan reaches a payment further and the amount owed stays current. Nothing is lost if it
    /// never runs: what was planned goes off anyway. Wishes and the weekly reminder need nothing after them.
    /// Not before an hour from [now], so the system is not asked over and over, and not later than
    /// a day, so the plan never grows stale.
    public static func nextRefresh(after plan: [Reminder], now: Int64) -> Int64 {
        let hour: Int64 = 3_600_000
        let soonestDebt = plan.lazy.filter { if case .day = $0.time { true } else { false } }.map(\.fireAt).min()
        return min(max(soonestDebt ?? .max, now + hour), now + 24 * hour)
    }

    // MARK: Each kind

    private static func wish(of wish: Wish, books: UUID, now: Int64) -> Reminder? {
        guard wish.status == .waiting, wish.decideAt > now else { return nil }
        // The wait it was given, as `Wishes.reminderLine` words it.
        let event = Reminder.Event.wish(
            wishId: wish.id, title: wish.title, amountMinor: wish.amountMinor, currency: wish.currency,
            waitHours: (wish.decideAt - wish.createdAt) / 3_600_000
        )
        return Reminder(id: "wish.\(wish.id.uuidString)", booksId: books, event: event, time: .instant(wish.decideAt), fireAt: wish.decideAt)
    }

    /// "In three days" and "today" for the next payment and the one after it, those still to come.
    /// Two payments, so the next month's first reminder is there even if the app does not run
    /// between them.
    private static func payments(of account: Account, books: UUID, today: LocalDate, now: Int64, zone: TimeZone) -> [Reminder] {
        guard let day = account.paymentDay, let amount = account.paymentMinor else { return [] }
        let due = Budget.nextDue(day, today)
        let following = Budget.nextDue(day, due.plusDays(1))
        let third = Budget.nextDue(day, following.plusDays(1))
        // Today's payment counts only while its reminder is still to come.
        let upcoming = [due, following, third].filter { $0.atTimeMillis(hour: debtHour, in: zone) > now }.prefix(2)
        return upcoming.flatMap { date in
            paymentDays.compactMap { daysLeft in
                let event = Reminder.Event.payment(
                    accountId: account.id, accountName: account.name, amountMinor: amount, currency: account.currency, daysLeft: daysLeft
                )
                return onDay(date.minusDays(daysLeft), kind: "payment", account: account, books: books, event: event, now: now, zone: zone)
            }
        }
    }

    /// A week, a day and the last day of the interest-free period, those still to come.
    private static func grace(of account: Account, owedMinor: Int64, books: UUID, now: Int64, zone: TimeZone) -> [Reminder] {
        guard let until = account.graceUntil.map({ LocalDate(epochDay: Int($0)) }) else { return [] }
        return graceDays.compactMap { daysLeft in
            let event = Reminder.Event.gracePeriod(
                accountId: account.id, accountName: account.name, owedMinor: owedMinor, currency: account.currency, daysLeft: daysLeft
            )
            return onDay(until.minusDays(daysLeft), kind: "grace", account: account, books: books, event: event, now: now, zone: zone)
        }
    }

    /// The day is in the id: each reminder of a debt is a request of its own.
    private static func onDay(
        _ date: LocalDate, kind: String, account: Account, books: UUID, event: Reminder.Event, now: Int64, zone: TimeZone
    ) -> Reminder? {
        let fireAt = date.atTimeMillis(hour: debtHour, in: zone)
        guard fireAt > now else { return nil }
        return Reminder(
            id: "\(kind).\(account.id.uuidString).\(date)", booksId: books, event: event, time: .day(date, hour: debtHour, minute: 0),
            fireAt: fireAt
        )
    }

    /// The next Sunday at seven, later than [now]: today's while it is still before seven.
    private static func reconcileReminder(now: Int64, zone: TimeZone) -> Reminder {
        let today = LocalDate(epochMillis: now, in: zone)
        let daysAhead = (reconcileDay.rawValue - today.dayOfWeek.rawValue + 7) % 7
        var fireAt = today.plusDays(daysAhead).atTimeMillis(hour: reconcileHour, in: zone)
        if fireAt <= now { fireAt = today.plusDays(daysAhead + 7).atTimeMillis(hour: reconcileHour, in: zone) }
        return Reminder(
            id: "reconcile", booksId: nil, event: .reconcile, time: .weekly(reconcileDay, hour: reconcileHour, minute: 0), fireAt: fireAt
        )
    }
}
