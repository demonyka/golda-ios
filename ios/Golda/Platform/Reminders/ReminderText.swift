import Foundation
import GoldaCore

/// The words of the notifications, from the "Reminders" table: the texts Android's `WishReminder`,
/// `DebtReminder` and `ReconcileReminder` post, put together from the planner's values in the
/// language of the locale passed in. Amounts stay as `Fmt` writes them (D13).
enum ReminderText {
    private static let table = "Reminders"

    /// [reminder] as a notification; [profileName] goes under the title when the person has more
    /// than one profile, so a payment says whose books it is about.
    static func request(for reminder: Reminder, profileName: String?, locale: Locale) -> NotificationRequest {
        let title: String, body: String, thread: String, destination: ReminderTap.Destination
        switch reminder.event {
        case .wish(let wishId, let item, let amountMinor, let currency, let waitHours):
            let wait = EntryText.wait(waitHours, in: locale)
            let amount = Fmt.amount(amountMinor, currency)
            title = item
            body = LocalizedStringResource("It’s been \(wait). Still want “\(item)” for \(amount)?", table: table, comment: "Notification when the time to think about a purchase is up: “It’s been 3 days. Still want “Headphones” for 120 $?”").text(in: locale)
            thread = "wishes"
            destination = .wish(wishId)
        case .payment(_, let account, let amountMinor, let currency, let daysLeft):
            let amount = Fmt.amount(amountMinor, currency)
            title = account
            body = daysLeft == 0
                ? LocalizedStringResource("Payment due today: \(amount)", table: table, comment: "Notification on the day a debt's monthly payment is due, under the debt's name.").text(in: locale)
                : LocalizedStringResource("Payment due in \(days(daysLeft, in: locale)): \(amount)", table: table, comment: "Notification three days before a debt's monthly payment, under the debt's name: “Payment due in 3 days: 10 000 ₽”.").text(in: locale)
            thread = "debts"
            destination = .accounts
        case .gracePeriod(_, let account, let owedMinor, let currency, let daysLeft):
            let owed = Fmt.amount(owedMinor, currency)
            title = account
            body = daysLeft == 0
                ? LocalizedStringResource("The interest-free period ends today. Pay \(owed).", table: table, comment: "Notification on the last day of a credit card's interest-free period, with what is owed on it.").text(in: locale)
                : LocalizedStringResource("The interest-free period ends in \(days(daysLeft, in: locale)). Pay \(owed).", table: table, comment: "Notification a week or a day before a credit card's interest-free period ends: “The interest-free period ends in 7 days. Pay 42 100,50 ₽.”").text(in: locale)
            thread = "debts"
            destination = .accounts
        case .reconcile:
            title = LocalizedStringResource("Check your balances", table: table, comment: "Title of the Sunday notification that asks to compare the balances with the bank.").text(in: locale)
            body = LocalizedStringResource("A week has passed. Open your bank and compare the accounts in Golda; forgotten purchases will show up.", table: table, comment: "The Sunday notification that asks to compare the balances with the bank; a tap opens Accounts in reconcile mode.").text(in: locale)
            thread = "reconcile"
            destination = .reconcile
        }
        return NotificationRequest(
            id: reminder.id, title: title, subtitle: profileName ?? "", body: body, thread: thread, trigger: reminder.time,
            tap: ReminderTap(profileId: reminder.booksId, destination: destination)
        )
    }

    /// "3 дня", "1 день", "7 days".
    private static func days(_ count: Int, in locale: Locale) -> String {
        LocalizedStringResource("\(count) days", table: table, comment: "How many days are left in a notification, “in 3 days”.").text(in: locale)
    }
}
