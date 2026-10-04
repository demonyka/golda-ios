import Foundation
import GoldaCore

/// The «Можно сегодня» widgets seen from the model: they show the hero of the profile on screen,
/// written after every change to its books, to the profiles and to this phone's settings, and
/// once more as the app leaves the screen.
extension AppModel {
    /// The hero for the day it is now; nothing before onboarding is over, as the app shows no books
    /// then either. While the books are still being read, the widgets keep what they had.
    func publishWidgets() {
        guard isLoaded, failureReason == nil else { return }
        guard device.onboarded, !profiles.isEmpty else {
            widgets.publish(nil)
            return
        }
        guard let data else { return }
        widgets.publish(data, profileCount: profiles.count)
    }

    /// The app leaves the screen: the widgets get this moment's figures (the day may have turned
    /// while it was open), and a background refresh is asked for after midnight, unless the
    /// reminders asked for one already, so the figures reach past tomorrow without a launch.
    func publishWidgetsOnLeaving() {
        publishWidgets()
        let tomorrow = environment.today().plusDays(1)
        ReminderBackground.submitUnlessPending(at: tomorrow.startOfDayMillis(in: environment.zone()))
    }
}
