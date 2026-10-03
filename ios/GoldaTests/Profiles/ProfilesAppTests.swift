import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The profiles screens' intents over the real app model: a change to a profile's income, payday
/// or payments reaches Home of that profile at once, and leaves the other profiles alone.
@MainActor @Suite(.timeLimit(.minutes(1))) struct ProfilesAppTests {
    private func samples() async throws -> (AppHarness, AppData) {
        let harness = try AppHarness()
        await harness.model.start(command: .samples, profileName: "Личный")
        return (harness, try await harness.data())
    }

    private func hero(_ harness: AppHarness) -> HomeHero? {
        harness.model.data.map { HomeHero(data: $0, today: harness.environment.today()) }
    }

    @Test func aProfileAddedOnTheScreenLeavesTheActiveOneOpen() async throws {
        let (harness, data) = try await samples()
        let trip = try await harness.model.addProfile(name: "  Поездка ")
        #expect(trip.name == "Поездка")
        await eventually { harness.model.profiles.count == 2 }
        #expect(harness.model.profiles.map(\.name) == ["Личный", "Поездка"])
        #expect(harness.model.activeProfileId == data.profile.id)
        #expect(harness.device.current.activeProfileId == data.profile.id)
    }

    /// The samples are paid on the 10th; on 2 October that is 8 days away. The 20th is 18.
    @Test func aNewPaydayMovesTheDaysToPaydayOnHome() async throws {
        let (harness, data) = try await samples()
        #expect(hero(harness)?.daysLeft == 8)
        var settings = data.profile.settings
        settings.payday = 20
        try await harness.model.saveProfileSettings(settings, profileId: data.profile.id)
        await eventually { harness.model.data?.settings.payday == 20 }
        #expect(hero(harness)?.daysLeft == 18)
    }

    /// The price of a purchase in hours of work comes from the profile's rate after tax.
    @Test func aNewRateChangesTheHourOfWork() async throws {
        let (harness, data) = try await samples()
        #expect(data.settings.hourNet == 900)
        var form = IncomeRateForm(data.profile.settings)
        form.text = "2\u{202F}000"
        let settings = try #require(form.applied(to: data.profile.settings))
        try await harness.model.saveProfileSettings(settings, profileId: data.profile.id)
        await eventually { harness.model.data?.settings.hourNet == 1800 }
    }

    /// The loan's 10 000 ₽ on the 5th is already set aside before the 10th; 500 ₽ more on the 3rd
    /// joins it, goes with a delete and comes back with "Отменить", under the same id.
    @Test func aPaymentIsSetAsideAndItsDeleteCanBeUndone() async throws {
        let (harness, data) = try await samples()
        let profileId = data.profile.id
        #expect(hero(harness)?.setAside == "10\u{202F}000 ₽")

        let water = Obligation(name: "Вода", amountMinor: 50_000, currency: "RUB", dayOfMonth: 3)
        try await harness.model.saveObligation(water, profileId: profileId)
        await eventually { harness.model.data?.obligations.contains(water) == true }
        #expect(hero(harness)?.setAside == "10\u{202F}500 ₽")

        let token = try await harness.model.deleteObligation(water, profileId: profileId)
        // The samples' two payments came first.
        #expect(token == ObligationUndoToken(profileId: profileId, obligation: water, createdAt: 3))
        await eventually { harness.model.data?.obligations.contains(water) == false }
        #expect(hero(harness)?.setAside == "10\u{202F}000 ₽")

        try await harness.model.restoreObligation(token)
        await eventually { harness.model.data?.obligations.contains(water) == true }
        #expect(hero(harness)?.setAside == "10\u{202F}500 ₽")
    }

    /// Payments of one day are listed in the order they were created, as on Android; "Отменить"
    /// puts a deleted one back in its place, not after the others.
    @Test func anUndonePaymentComesBackToItsPlaceInItsDay() async throws {
        let (harness, data) = try await samples()
        let profileId = data.profile.id
        #expect(data.obligations.map(\.name) == ["Аренда", "Подписки"])
        let rent = try #require(data.obligations.first)

        let token = try await harness.model.deleteObligation(rent, profileId: profileId)
        await eventually { harness.model.data?.obligations.map(\.name) == ["Подписки"] }
        try await harness.model.restoreObligation(token)
        await eventually { harness.model.data?.obligations.count == 2 }
        #expect(harness.model.data?.obligations.map(\.name) == ["Аренда", "Подписки"])
        #expect(harness.model.data?.obligations.first == rent)
    }

    /// A profile that is not open is set up without touching the open one; its own books follow.
    @Test func anotherProfileIsSetUpOnItsOwn() async throws {
        let (harness, data) = try await samples()
        let trip = try await harness.model.addProfile(name: "Поездка")
        var first: ProfileSnapshot?
        var latest: ProfileSnapshot?
        for await snapshot in harness.model.profileSnapshots(trip.id) {
            if first == nil {
                first = snapshot
                var settings = trip.settings
                settings.payday = 1
                try await harness.model.saveProfileSettings(settings, profileId: trip.id)
                let hotel = Obligation(name: "Отель", amountMinor: 100, currency: "GEL", dayOfMonth: 2)
                try await harness.model.saveObligation(hotel, profileId: trip.id)
            }
            if snapshot.profile.settings.payday == 1, !snapshot.obligations.isEmpty {
                latest = snapshot
                break
            }
        }
        #expect(first?.profile.settings.payday == 15)
        #expect(latest?.obligations.map(\.name) == ["Отель"])

        #expect(harness.model.data?.profile.id == data.profile.id)
        #expect(harness.model.data?.settings.payday == 10)
        #expect(harness.model.data?.obligations.map(\.name) == data.obligations.map(\.name))
    }

    @Test func whatDeletingAProfileTakesIsCounted() async throws {
        let (harness, data) = try await samples()
        let contents = try #require(try await harness.model.profileContents(data.profile.id))
        #expect(contents.accounts == 7)
        #expect(contents.operations == data.visibleOperations.count)
        #expect(contents.goals == 2)
        #expect(contents.wishes == 2)
        #expect(contents.payments == 2)
        #expect(try await harness.model.profileContents(UUID()) == nil)
    }

    /// The profile's screen follows its snapshots; they end when the profile goes, so it can close.
    @Test func aDeletedProfilesBooksStopComing() async throws {
        let (harness, _) = try await samples()
        let trip = try await harness.model.addProfile(name: "Поездка")
        var received = 0
        // The loop ends only when the stream does; the suite's time limit catches one that never ends.
        for await _ in harness.model.profileSnapshots(trip.id) {
            received += 1
            if received == 1 { try await harness.model.deleteProfile(trip.id) }
        }
        #expect(received >= 1)
        #expect(harness.model.profiles.map(\.name) == ["Личный"])
    }
}
