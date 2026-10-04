import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// A tapped reminder opens its profile, and the tabs show the rest once that profile's books are on
/// screen: the wish in «Сомневаюсь», Accounts, or Accounts in reconcile mode.
@MainActor @Suite(.timeLimit(.minutes(1))) struct ReminderRoutingTests {
    let harness: AppHarness

    init() throws {
        harness = try AppHarness()
    }

    var model: AppModel { harness.model }

    private func twoProfiles() async throws -> (personal: UUID, family: UUID) {
        let personal = try await harness.profile("Личный")
        let family = try await harness.profile("Семья")
        harness.onboard(active: personal)
        await model.start()
        #expect(try await harness.data().profile.id == personal)
        return (personal, family)
    }

    @Test func aTapSwitchesToItsProfileAndThenOpensItsTab() async throws {
        let (personal, family) = try await twoProfiles()
        model.openReminder(ReminderTap(profileId: family, destination: .reconcile))

        #expect(model.activeProfileId == family)
        // The old books are still on screen for a moment: the tabs wait for the right ones.
        #expect(model.takeReminderDestination(showing: personal) == nil)
        await eventually { model.data?.profile.id == family }
        #expect(model.takeReminderDestination(showing: family) == .reconcile)
        #expect(model.takeReminderDestination(showing: family) == nil, "shown once")
    }

    @Test func aTapOnTheProfileOnScreenOpensAtOnce() async throws {
        let (personal, _) = try await twoProfiles()
        let wish = UUID()
        model.openReminder(ReminderTap(profileId: personal, destination: .wish(wish)))
        #expect(model.takeReminderDestination(showing: personal) == .wish(wish))
    }

    /// The Sunday reminder is one for every profile: it opens reconciling where the person is.
    @Test func aTapWithoutAProfileStaysOnTheOneOnScreen() async throws {
        let (personal, _) = try await twoProfiles()
        model.openReminder(ReminderTap(profileId: nil, destination: .reconcile))
        #expect(model.activeProfileId == personal)
        #expect(model.takeReminderDestination(showing: personal) == .reconcile)
    }

    /// A reminder of a profile deleted since still opens its tab, on the profile there is.
    @Test func aTapForAProfileThatIsGoneOpensOnTheOneOnScreen() async throws {
        let (personal, _) = try await twoProfiles()
        model.openReminder(ReminderTap(profileId: UUID(), destination: .accounts))
        #expect(model.activeProfileId == personal)
        #expect(model.takeReminderDestination(showing: personal) == .accounts)
    }

    /// Tapped before the app has read its profiles (a cold launch from the notification): the
    /// switch happens once they are there.
    @Test func aTapBeforeTheProfilesAreReadWaitsForThem() async throws {
        let personal = try await harness.profile("Личный")
        let family = try await harness.profile("Семья")
        harness.onboard(active: personal)
        model.openReminder(ReminderTap(profileId: family, destination: .accounts))
        await model.start()
        #expect(try await harness.data().profile.id == personal)
        // The tabs, first on screen, ask for it: the switch happens now.
        #expect(model.takeReminderDestination(showing: personal) == nil)
        #expect(model.activeProfileId == family)
        await eventually { model.data?.profile.id == family }
        #expect(model.takeReminderDestination(showing: family) == .accounts)
    }
}
