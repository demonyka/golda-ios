import Foundation
import GoldaCore
import Testing

@testable import Golda

/// The notifications' words in both languages: the texts Android's `WishReminder`, `DebtReminder`
/// and `ReconcileReminder` post, from the planner's values.
@MainActor @Suite struct ReminderTextTests {
    let ru = Locale(identifier: "ru_RU")
    let en = Locale(identifier: "en_US")
    let books = UUID()
    let account = UUID()
    let wishId = UUID()
    let nbsp = "\u{202F}"

    func reminder(_ event: Reminder.Event, time: Reminder.Time = .instant(1_000), booksId: UUID? = nil) -> Reminder {
        Reminder(id: "x", booksId: booksId ?? books, event: event, time: time, fireAt: 1_000)
    }

    func payment(_ daysLeft: Int) -> Reminder {
        reminder(.payment(accountId: account, accountName: "Кредит", amountMinor: 1_000_000, currency: "RUB", daysLeft: daysLeft), time: .day(LocalDate(2026, 10, 22), hour: 10, minute: 0))
    }

    func grace(_ daysLeft: Int) -> Reminder {
        reminder(.gracePeriod(accountId: account, accountName: "Кредитка", owedMinor: 4_210_050, currency: "RUB", daysLeft: daysLeft), time: .day(LocalDate(2026, 10, 13), hour: 10, minute: 0))
    }

    @Test func aWishAsksWhetherItIsStillWanted() {
        let wish = reminder(.wish(wishId: wishId, title: "Наушники", amountMinor: 12_000, currency: "USD", waitHours: 72), time: .instant(5_000))
        let russian = ReminderText.request(for: wish, profileName: nil, locale: ru)
        #expect(russian.title == "Наушники")
        #expect(russian.body == "Прошло 3 дня. Ещё хочешь «Наушники» за 120 $?")
        #expect(russian.subtitle.isEmpty)
        #expect(russian.thread == "wishes")
        #expect(russian.trigger == .instant(5_000))
        #expect(russian.tap == ReminderTap(profileId: books, destination: .wish(wishId)))
        #expect(ReminderText.request(for: wish, profileName: nil, locale: en).body == "It’s been 3 days. Still want “Наушники” for 120 $?")

        let day = reminder(.wish(wishId: wishId, title: "Кофе", amountMinor: 50_000, currency: "RUB", waitHours: 24))
        #expect(ReminderText.request(for: day, profileName: nil, locale: ru).body == "Прошло 24 часа. Ещё хочешь «Кофе» за 500 ₽?")
        #expect(ReminderText.request(for: day, profileName: nil, locale: en).body == "It’s been 24 hours. Still want “Кофе” for 500 ₽?")
    }

    @Test func aPaymentSaysWhenAndHowMuch() {
        let soon = ReminderText.request(for: payment(3), profileName: nil, locale: ru)
        #expect(soon.title == "Кредит")
        #expect(soon.body == "Через 3 дня платёж: 10\(nbsp)000 ₽")
        #expect(soon.thread == "debts")
        #expect(soon.trigger == .day(LocalDate(2026, 10, 22), hour: 10, minute: 0))
        #expect(soon.tap == ReminderTap(profileId: books, destination: .accounts))
        #expect(ReminderText.request(for: payment(3), profileName: nil, locale: en).body == "Payment due in 3 days: 10\(nbsp)000 ₽")
        #expect(ReminderText.request(for: payment(0), profileName: nil, locale: ru).body == "Сегодня платёж: 10\(nbsp)000 ₽")
        #expect(ReminderText.request(for: payment(0), profileName: nil, locale: en).body == "Payment due today: 10\(nbsp)000 ₽")
    }

    @Test func theGracePeriodSaysHowLongIsLeftAndWhatToPay() {
        let owed = "42\(nbsp)100,50 ₽"
        #expect(ReminderText.request(for: grace(7), profileName: nil, locale: ru).body == "Льготный период кончается через 7 дней. Погаси \(owed).")
        #expect(ReminderText.request(for: grace(1), profileName: nil, locale: ru).body == "Льготный период кончается через 1 день. Погаси \(owed).")
        #expect(ReminderText.request(for: grace(0), profileName: nil, locale: ru).body == "Льготный период кончается сегодня. Погаси \(owed).")
        #expect(ReminderText.request(for: grace(7), profileName: nil, locale: en).body == "The interest-free period ends in 7 days. Pay \(owed).")
        #expect(ReminderText.request(for: grace(1), profileName: nil, locale: en).body == "The interest-free period ends in 1 day. Pay \(owed).")
        #expect(ReminderText.request(for: grace(0), profileName: nil, locale: en).body == "The interest-free period ends today. Pay \(owed).")
        let request = ReminderText.request(for: grace(7), profileName: nil, locale: ru)
        #expect(request.title == "Кредитка")
        #expect(request.thread == "debts")
        #expect(request.tap == ReminderTap(profileId: books, destination: .accounts))
    }

    @Test func theReconcileReminderOpensReconciling() {
        let weekly = Reminder(id: "reconcile", booksId: nil, event: .reconcile, time: .weekly(.sunday, hour: 19, minute: 0), fireAt: 1)
        let russian = ReminderText.request(for: weekly, profileName: nil, locale: ru)
        #expect(russian.title == "Сверь балансы")
        #expect(russian.body == "Неделя прошла. Открой банк и сравни счета в Golda — забытые траты найдутся сами.")
        #expect(russian.thread == "reconcile")
        #expect(russian.trigger == .weekly(.sunday, hour: 19, minute: 0))
        #expect(russian.tap == ReminderTap(profileId: nil, destination: .reconcile))
        let english = ReminderText.request(for: weekly, profileName: nil, locale: en)
        #expect(english.title == "Check your balances")
        #expect(english.body == "A week has passed. Open your bank and compare the accounts in Golda; forgotten purchases will show up.")
    }

    /// With more than one profile, the line under the title says whose books it is about.
    @Test func theProfileIsNamedWhenThereAreSeveral() {
        #expect(ReminderText.request(for: payment(3), profileName: "Семья", locale: ru).subtitle == "Семья")
        #expect(ReminderText.request(for: payment(3), profileName: nil, locale: ru).subtitle.isEmpty)
    }

    /// The signature changes with anything a person would see, so a changed reminder is replaced.
    @Test func theSignatureFollowsWhatIsShown() {
        let base = ReminderText.request(for: payment(3), profileName: nil, locale: ru)
        #expect(base.signature == ReminderText.request(for: payment(3), profileName: nil, locale: ru).signature)
        #expect(base.signature != ReminderText.request(for: payment(0), profileName: nil, locale: ru).signature)
        #expect(base.signature != ReminderText.request(for: payment(3), profileName: "Семья", locale: ru).signature)
        #expect(base.signature != ReminderText.request(for: payment(3), profileName: nil, locale: en).signature)
    }
}

/// The debug flags a UI test launches with, each one on its own.
@Suite struct ReminderDebugOptionsTests {
    @Test func theFlagsAreRead() {
        #expect(ReminderDebugOptions(arguments: []).tap == nil)
        #expect(ReminderDebugOptions(arguments: ["-golda.tapReminder.reconcile"]).tap == .reconcile)
        #expect(ReminderDebugOptions(arguments: ["-golda.tapReminder.wish"]).tap == .wish)
        let soon = ReminderDebugOptions(arguments: ["-golda.inMemory", "-golda.remindSoon"])
        #expect(soon.remindsSoon && soon.usesLiveNotifications, "a delivery needs the system's notifications")
        #expect(ReminderDebugOptions(arguments: ["-golda.liveNotifications"]).usesLiveNotifications)
        #expect(!ReminderDebugOptions(arguments: ["-golda.inMemory"]).usesLiveNotifications)
    }
}

/// What a tap opens survives the trip through a notification's `userInfo`.
@Suite struct ReminderTapTests {
    @Test func aTapComesBackFromItsNotification() {
        let profile = UUID(), wish = UUID()
        let taps = [
            ReminderTap(profileId: profile, destination: .wish(wish)),
            ReminderTap(profileId: profile, destination: .accounts),
            ReminderTap(profileId: nil, destination: .reconcile),
        ]
        for tap in taps {
            let userInfo: [AnyHashable: Any] = tap.userInfo.reduce(into: [:]) { $0[$1.key] = $1.value }
            #expect(ReminderTap(userInfo: userInfo) == tap)
        }
    }

    @Test func aForeignNotificationOpensNothing() {
        #expect(ReminderTap(userInfo: [:]) == nil)
        #expect(ReminderTap(userInfo: ["golda.open": "somewhere"]) == nil)
        #expect(ReminderTap(userInfo: ["golda.open": "wish"]) == nil, "a wish without its id")
        // A profile id that does not parse is no profile: the tab still opens.
        #expect(ReminderTap(userInfo: ["golda.open": "accounts", "golda.profile": "x"]) == ReminderTap(profileId: nil, destination: .accounts))
    }
}
