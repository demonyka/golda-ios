import Foundation
import GoldaCore

/// The reminders seen from the model: they start with the app, a tap opens its profile and then its
/// place (the tabs ask for it once that profile's books are on screen), and the intents that create
/// the first need for one ask for permission (D36).
extension AppModel {
    /// After the launch work: the plan follows the books from here on.
    func startReminders() {
        reminders.start()
        #if DEBUG
        if let kind = reminders.debug.tap {
            Task { if let tap = await reminders.debugTap(kind) { openReminder(tap) } }
        }
        #endif
    }

    /// A tapped reminder: its profile opens now, when it is known; the tabs show the rest.
    func openReminder(_ tap: ReminderTap) {
        reminders.pendingTap = tap
        if let id = tap.profileId, id != activeProfileId { switchProfile(to: id) }
    }

    /// Where the tapped reminder leads, once the tabs show its profile's books ([shown]); taken, it
    /// is not shown again. Nil while the switch is on its way. A profile that is not there (deleted
    /// since, or none) opens the place on the profile on screen.
    func takeReminderDestination(showing shown: UUID) -> ReminderTap.Destination? {
        guard let tap = reminders.pendingTap else { return nil }
        if let wanted = tap.profileId, wanted != shown, profiles.contains(where: { $0.id == wanted }) {
            // A tap that came before the profiles were read switches now.
            if activeProfileId != wanted { switchProfile(to: wanted) }
            return nil
        }
        reminders.pendingTap = nil
        return tap.destination
    }

    /// Asks for notifications, if never asked, without holding the caller up.
    func askForNotifications() {
        Task { await reminders.askPermission() }
    }

    /// A debt with a payment day or an interest-free period has something to remind of.
    func askForNotifications(after account: Account) {
        if account.isDebt, account.paymentDay != nil || account.graceUntil != nil { askForNotifications() }
    }
}
