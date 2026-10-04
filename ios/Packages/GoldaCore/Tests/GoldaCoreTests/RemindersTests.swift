import Foundation
import Testing

@testable import GoldaCore

/// The local notifications, planned. Android posts them from workers (`WishReminder`, the daily
/// `DebtReminder`, the weekly `ReconcileReminder`); iOS cannot run code when one is due, so the
/// planner says ahead of time what fires when, and the app hands that to the system. There is no
/// Kotlin test to port: the expectations are the Android workers' conditions and texts' values.
@Suite struct RemindersTests {
    let moscow = TimeZone(identifier: "Europe/Moscow")!
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let newYork = TimeZone(identifier: "America/New_York")!

    /// Epoch milliseconds of a wall-clock time in [zone].
    func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, in zone: TimeZone) -> Int64 {
        LocalDate(year, month, day).atTimeMillis(hour: hour, minute: minute, in: zone)
    }

    func loan(_ n: Int = 1, paymentDay: Int? = 25, paymentMinor: Int64? = 1_000_000) -> Account {
        Account(id: uid(n), name: "Кредит", currency: "RUB", type: .loan, includeInFree: false, interestRate: 19.9, paymentDay: paymentDay, paymentMinor: paymentMinor)
    }

    func card(_ n: Int = 2, paymentDay: Int? = nil, graceUntil: LocalDate?) -> Account {
        Account(
            id: uid(n), name: "Кредитка", currency: "RUB", type: .credit, includeInFree: false, interestRate: 29.9,
            paymentDay: paymentDay, paymentMinor: paymentDay == nil ? nil : 300_000, graceUntil: graceUntil.map { Int64($0.epochDay) }
        )
    }

    /// Books with each account owing [owed] (a debt's balance is below zero).
    func books(_ accounts: [Account], owed: Int64 = 5_000_000, wishes: [Wish] = [], id: Int = 100) -> ReminderBooks {
        let postings = accounts.map { Posting(accountId: $0.id, amountMinor: -owed, rubMinor: -owed) }
        return ReminderBooks(id: uid(id), accounts: accounts, states: Ledger.states(accounts, postings), wishes: wishes)
    }

    func plan(_ books: [ReminderBooks], reconcile: Bool = false, now: Int64, zone: TimeZone = utc, limit: Int = Reminders.limit) -> [Reminder] {
        Reminders.plan(books, reconcile: reconcile, now: now, zone: zone, limit: limit)
    }

    // MARK: Wishlist

    @Test func aWaitingWishRemindsWhenItsTimeIsUp() {
        let created = at(2026, 10, 3, 12, in: utc)
        let wish = Wish(id: uid(7), title: "Наушники", amountMinor: 12_000, currency: "USD", createdAt: created, decideAt: created + 72 * 3_600_000)
        let planned = plan([books([], wishes: [wish])], now: created + 60_000)
        #expect(planned == [Reminder(
            id: "wish.\(uid(7).uuidString)", booksId: uid(100),
            event: .wish(wishId: uid(7), title: "Наушники", amountMinor: 12_000, currency: "USD", waitHours: 72),
            time: .instant(wish.decideAt), fireAt: wish.decideAt
        )])
    }

    @Test func decidedAndOverdueWishesAreLeftOut() {
        let now = at(2026, 10, 3, 12, in: utc)
        let bought = Wish(id: uid(1), title: "a", amountMinor: 1, currency: "RUB", createdAt: now - 1, decideAt: now + 3_600_000, status: .bought)
        let skipped = Wish(id: uid(2), title: "b", amountMinor: 1, currency: "RUB", createdAt: now - 1, decideAt: now + 3_600_000, status: .skipped)
        // Its notification went off already; a past moment cannot be planned again.
        let overdue = Wish(id: uid(3), title: "c", amountMinor: 1, currency: "RUB", createdAt: now - 25 * 3_600_000, decideAt: now - 3_600_000)
        let dueNow = Wish(id: uid(4), title: "d", amountMinor: 1, currency: "RUB", createdAt: now - 24 * 3_600_000, decideAt: now)
        #expect(plan([books([], wishes: [bought, skipped, overdue, dueNow])], now: now).isEmpty)
    }

    // MARK: Debt payments

    @Test func aPaymentRemindsThreeDaysBeforeAndOnTheDay() {
        let book = books([loan()])
        let early = plan([book], now: at(2026, 10, 3, 12, in: utc))
        #expect(early.map(\.event) == [.payment(accountId: uid(1), accountName: "Кредит", amountMinor: 1_000_000, currency: "RUB", daysLeft: 3)])
        #expect(early.map(\.time) == [.day(LocalDate(2026, 10, 22), hour: 10, minute: 0)])
        #expect(early.map(\.fireAt) == [at(2026, 10, 22, 10, in: utc)])
        #expect(early.map(\.id) == ["payment.\(uid(1).uuidString)"])

        // Past the three-day one, the day itself is next.
        let threeDaysBefore = plan([book], now: at(2026, 10, 22, 10, 30, in: utc))
        #expect(threeDaysBefore.map(\.time) == [.day(LocalDate(2026, 10, 25), hour: 10, minute: 0)])
        #expect(threeDaysBefore.map(\.event) == [.payment(accountId: uid(1), accountName: "Кредит", amountMinor: 1_000_000, currency: "RUB", daysLeft: 0)])

        // On the day before ten it still comes; after it, next month's payment is the nearest.
        #expect(plan([book], now: at(2026, 10, 25, 9, in: utc)).map(\.fireAt) == [at(2026, 10, 25, 10, in: utc)])
        let afterwards = plan([book], now: at(2026, 10, 25, 10, 1, in: utc))
        #expect(afterwards.map(\.time) == [.day(LocalDate(2026, 11, 22), hour: 10, minute: 0)])
    }

    @Test func aPaymentDayPastTheMonthsEndFallsOnItsLastDay() {
        let book = books([loan(paymentDay: 31)])
        #expect(plan([book], now: at(2027, 2, 1, 12, in: utc)).map(\.time) == [.day(LocalDate(2027, 2, 25), hour: 10, minute: 0)])
        #expect(plan([book], now: at(2027, 2, 26, 12, in: utc)).map(\.time) == [.day(LocalDate(2027, 2, 28), hour: 10, minute: 0)])
        // March has the 31st again: three days before it is the 28th.
        #expect(plan([book], now: at(2027, 2, 28, 12, in: utc)).map(\.time) == [.day(LocalDate(2027, 3, 28), hour: 10, minute: 0)])
    }

    @Test func onlyADebtStillOwedWithAPaymentIsReminded() {
        let now = at(2026, 10, 3, 12, in: utc)
        #expect(plan([books([loan()], owed: 0)], now: now).isEmpty, "paid off")
        #expect(plan([books([loan()], owed: -100)], now: now).isEmpty, "overpaid")
        #expect(plan([books([loan(paymentDay: nil)])], now: now).isEmpty, "no payment day")
        #expect(plan([books([loan(paymentMinor: nil)])], now: now).isEmpty, "no payment")
        // A day and a payment on an account that is not a debt remind of nothing, as on Android.
        let overdraft = Account(id: uid(3), name: "Карта", currency: "RUB", type: .card, includeInFree: true, paymentDay: 25, paymentMinor: 100)
        #expect(plan([books([overdraft])], now: now).isEmpty)
    }

    @Test func debtRemindersFallAtTenWhereverThePhoneIs() {
        let planned = plan([books([loan()])], now: at(2026, 10, 3, 12, in: moscow), zone: moscow)
        #expect(planned.map(\.time) == [.day(LocalDate(2026, 10, 22), hour: 10, minute: 0)])
        // Ten in Moscow is seven in UTC.
        #expect(planned.map(\.fireAt) == [at(2026, 10, 22, 7, in: utc)])
    }

    // MARK: Interest-free period

    @Test func theGracePeriodRemindsAWeekADayAndOnItsLastDay() {
        let book = books([card(graceUntil: LocalDate(2026, 10, 20))], owed: 4_210_050)
        func next(_ now: Int64) -> [Reminder] { plan([book], now: now) }

        let week = next(at(2026, 10, 3, 12, in: utc))
        #expect(week.map(\.event) == [.gracePeriod(accountId: uid(2), accountName: "Кредитка", owedMinor: 4_210_050, currency: "RUB", daysLeft: 7)])
        #expect(week.map(\.time) == [.day(LocalDate(2026, 10, 13), hour: 10, minute: 0)])
        #expect(week.map(\.id) == ["grace.\(uid(2).uuidString)"])

        let day = next(at(2026, 10, 13, 11, in: utc))
        #expect(day.map(\.time) == [.day(LocalDate(2026, 10, 19), hour: 10, minute: 0)])
        #expect(day.map(\.event) == [.gracePeriod(accountId: uid(2), accountName: "Кредитка", owedMinor: 4_210_050, currency: "RUB", daysLeft: 1)])

        let last = next(at(2026, 10, 19, 10, 30, in: utc))
        #expect(last.map(\.time) == [.day(LocalDate(2026, 10, 20), hour: 10, minute: 0)])
        #expect(last.map(\.event) == [.gracePeriod(accountId: uid(2), accountName: "Кредитка", owedMinor: 4_210_050, currency: "RUB", daysLeft: 0)])

        // Once the last reminder has gone off, the period is over and nothing is left.
        #expect(next(at(2026, 10, 20, 10, in: utc)).isEmpty)
        #expect(next(at(2026, 11, 1, 10, in: utc)).isEmpty)
    }

    @Test func aGracePeriodWithNothingOwedIsNotReminded() {
        #expect(plan([books([card(graceUntil: LocalDate(2026, 10, 20))], owed: 0)], now: at(2026, 10, 3, 12, in: utc)).isEmpty)
    }

    // MARK: Nearest only

    /// A card both pays monthly and has an interest-free period: Android posts both under two ids
    /// of its own (100 000 + id and 200 000 + id). Each keeps only its next reminder, so a debt
    /// takes two of the 64 places at most, never a month of them.
    @Test func eachDebtPlansOnlyTheNearestReminderOfEachKind() {
        let both = card(paymentDay: 25, graceUntil: LocalDate(2026, 10, 25))
        let planned = plan([books([both, loan(3)])], now: at(2026, 10, 3, 12, in: utc))
        #expect(planned.map(\.id) == [
            "grace.\(uid(2).uuidString)", "payment.\(uid(2).uuidString)", "payment.\(uid(3).uuidString)",
        ])
        #expect(planned.map(\.fireAt) == [at(2026, 10, 18, 10, in: utc), at(2026, 10, 22, 10, in: utc), at(2026, 10, 22, 10, in: utc)])
    }

    // MARK: Reconcile

    @Test func theReconcileReminderComesOnSundayAtSeven() {
        // Saturday noon in Moscow: tomorrow at 19:00 there, 16:00 UTC.
        let planned = plan([], reconcile: true, now: at(2026, 10, 3, 12, in: moscow), zone: moscow)
        #expect(planned == [Reminder(
            id: "reconcile", booksId: nil, event: .reconcile, time: .weekly(.sunday, hour: 19, minute: 0),
            fireAt: at(2026, 10, 4, 16, in: utc)
        )])
        // On Sunday before seven it is still today; at seven or later, next Sunday.
        #expect(plan([], reconcile: true, now: at(2026, 10, 4, 18, 59, in: moscow), zone: moscow).map(\.fireAt) == [at(2026, 10, 4, 19, in: moscow)])
        #expect(plan([], reconcile: true, now: at(2026, 10, 4, 19, in: moscow), zone: moscow).map(\.fireAt) == [at(2026, 10, 11, 19, in: moscow)])
        #expect(plan([], reconcile: false, now: at(2026, 10, 3, 12, in: moscow), zone: moscow).isEmpty)
    }

    @Test func theReconcileReminderFollowsTheZone() {
        // Sunday 17:00 UTC is 20:00 in Moscow, past seven, and 13:00 in New York, before it.
        let instant = at(2026, 10, 4, 17, in: utc)
        #expect(plan([], reconcile: true, now: instant, zone: moscow).map(\.fireAt) == [at(2026, 10, 11, 16, in: utc)])
        #expect(plan([], reconcile: true, now: instant, zone: newYork).map(\.fireAt) == [at(2026, 10, 4, 23, in: utc)])
    }

    @Test func theReconcileReminderKeepsSevenAcrossDaylightSaving() {
        // Berlin moves to summer time on 29 March 2026 and back on 25 October: seven stays seven.
        #expect(plan([], reconcile: true, now: at(2026, 3, 23, 9, in: berlin), zone: berlin).map(\.fireAt) == [at(2026, 3, 29, 17, in: utc)])
        #expect(plan([], reconcile: true, now: at(2026, 3, 22, 20, in: berlin), zone: berlin).map(\.fireAt) == [at(2026, 3, 29, 17, in: utc)])
        #expect(plan([], reconcile: true, now: at(2026, 10, 20, 9, in: berlin), zone: berlin).map(\.fireAt) == [at(2026, 10, 25, 18, in: utc)])
    }

    // MARK: Profiles, order and the limit

    /// The reminders of every set of books, each carrying whose it is; the reconcile reminder is one
    /// for all of them.
    @Test func remindersOfEveryBooksCarryTheirIdAndReconcileIsOne() {
        let now = at(2026, 10, 3, 12, in: utc)
        let wish = Wish(id: uid(9), title: "Велосипед", amountMinor: 8_000_000, currency: "RUB", createdAt: now, decideAt: now + 24 * 3_600_000)
        let planned = plan([books([loan(1)], id: 100), books([], wishes: [wish], id: 200)], reconcile: true, now: now)
        #expect(planned.map(\.id) == ["wish.\(uid(9).uuidString)", "reconcile", "payment.\(uid(1).uuidString)"])
        #expect(planned.map(\.booksId) == [uid(200), nil, uid(100)])
    }

    /// iOS keeps 64 pending notifications and drops the rest without a word, so the plan stops
    /// short of it, keeping the soonest.
    @Test func thePlanKeepsTheSoonestBelowTheSystemLimit() {
        #expect(Reminders.limit < 64)
        // A Monday: the reconcile reminder is six days away.
        let now = at(2026, 10, 5, 12, in: utc)
        let wishes = (1...100).map { n in
            Wish(id: uid(n), title: "\(n)", amountMinor: 100, currency: "RUB", createdAt: now, decideAt: now + Int64(101 - n) * 3_600_000)
        }
        let planned = plan([books([], wishes: wishes)], reconcile: true, now: now)
        #expect(planned.count == Reminders.limit)
        #expect(planned.map(\.fireAt) == planned.map(\.fireAt).sorted())
        // The hundredth wish is due in an hour, the first in a hundred: the latest ones fall off.
        #expect(planned.first?.id == "wish.\(uid(100).uuidString)")
        #expect(!planned.contains { $0.id == "wish.\(uid(1).uuidString)" })
        #expect(!planned.contains { $0.event == .reconcile }, "Sunday is further away than sixty hours")
    }

    @Test func equalMomentsKeepAStableOrder() {
        let now = at(2026, 10, 3, 12, in: utc)
        let due = now + 3_600_000
        let wishes = [uid(3), uid(1), uid(2)].map { Wish(id: $0, title: "x", amountMinor: 1, currency: "RUB", createdAt: now, decideAt: due) }
        #expect(plan([books([], wishes: wishes)], now: now).map(\.id) == [uid(1), uid(2), uid(3)].map { "wish.\($0.uuidString)" })
    }

    // MARK: Background refresh

    /// The app is woken to plan the next reminder of a debt once the one planned has gone off;
    /// never sooner than in an hour and never later than in a day.
    @Test func theNextRefreshFollowsTheSoonestDebtReminder() {
        let now = at(2026, 10, 3, 12, in: utc)
        let hour: Int64 = 3_600_000
        #expect(Reminders.nextRefresh(after: plan([books([loan()])], now: now), now: now) == now + 24 * hour)
        // Due tomorrow (the three-day reminder has gone off): woken when tomorrow's goes off.
        let soon = plan([books([loan(paymentDay: 4)])], now: now)
        #expect(Reminders.nextRefresh(after: soon, now: now) == at(2026, 10, 4, 10, in: utc))
        let wish = Wish(id: uid(9), title: "x", amountMinor: 1, currency: "RUB", createdAt: now, decideAt: now + 60_000)
        let minutesAway = plan([books([loan(paymentDay: 3)], wishes: [wish])], now: at(2026, 10, 3, 9, 50, in: utc))
        #expect(Reminders.nextRefresh(after: minutesAway, now: at(2026, 10, 3, 9, 50, in: utc)) == at(2026, 10, 3, 10, 50, in: utc))
        #expect(Reminders.nextRefresh(after: [], now: now) == now + 24 * hour)
    }
}
