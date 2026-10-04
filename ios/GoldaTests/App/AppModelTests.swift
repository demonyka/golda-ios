import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The active profile, switching, creating and deleting profiles, onboarding and the launch work.
@MainActor @Suite(.timeLimit(.minutes(1))) struct AppModelTests {
    let harness: AppHarness

    init() throws {
        harness = try AppHarness()
    }

    var model: AppModel { harness.model }

    // MARK: Onboarding

    @Test func aFreshInstallOpensOnOnboarding() async throws {
        await model.start()

        #expect(model.isLoaded)
        #expect(model.phase.isOnboarding)
        #expect(model.profiles.isEmpty && model.activeProfileId == nil && model.data == nil)
    }

    @Test func beginningOnboardingCreatesTheFirstProfileAndOpensIt() async throws {
        await model.start()

        try await model.beginOnboarding(profileName: "Личный")

        let profile = try #require(model.profiles.first)
        #expect(model.profiles.map(\.name) == ["Личный"])
        #expect(harness.device.current.activeProfileId == profile.id)
        #expect(model.activeProfileId == profile.id)
        // The steps set the profile up through its books, so they must be there; the app is not
        // open until the last step says so.
        await eventually { model.data?.profile.id == profile.id }
        #expect(!harness.device.current.onboarded)
        #expect(model.phase.isOnboarding)
    }

    @Test func beginningOnboardingKeepsAProfileThatIsAlreadyThere() async throws {
        let family = try await harness.profile("Семья")
        await model.start()
        #expect(model.phase.isOnboarding)

        try await model.beginOnboarding(profileName: "Личный")

        #expect(model.profiles.map(\.id) == [family])
        #expect(model.activeProfileId == family)
        await eventually { model.data?.profile.id == family }
        #expect(!harness.device.current.onboarded)
    }

    /// The screen's task can run again (the view comes back); two profiles would be a bug nobody sees.
    @Test func beginningOnboardingTwiceAtOnceCreatesOneProfile() async throws {
        await model.start()

        async let first: Void = model.beginOnboarding(profileName: "Личный")
        async let second: Void = model.beginOnboarding(profileName: "Личный")
        _ = try await (first, second)

        #expect(model.profiles.map(\.name) == ["Личный"])
        try await model.beginOnboarding(profileName: "Личный")
        #expect(model.profiles.count == 1)
    }

    @Test func finishingOnboardingOpensTheApp() async throws {
        await model.start()
        try await model.beginOnboarding(profileName: "Личный")
        let profile = try #require(model.profiles.first)

        model.finishOnboarding()

        #expect(harness.device.current.onboarded)
        await eventually { model.phase.data?.profile.id == profile.id }
    }

    /// What the steps did to the books before the end stays: income through the profile, an account
    /// through the form's save, currencies through this phone's settings.
    @Test func whatTheStepsSetUpIsThereWhenTheAppOpens() async throws {
        await model.start()
        try await model.beginOnboarding(profileName: "Личный")
        let profile = try #require(model.profiles.first)
        var settings = profile.settings
        settings.incomeHourly = false
        settings.monthlySalary = 150_000
        settings.payday = 5
        try await model.saveProfileSettings(settings, profileId: profile.id)
        model.toggleShownCurrency("GEL")
        model.setLocalCurrency("GEL")
        _ = try await harness.data()
        try await model.saveAccount(
            Account(name: "Card", currency: "RUB", type: .card, includeInFree: true, sort: 0), openingMinor: 1_000_00
        )

        model.finishOnboarding()

        await eventually { model.phase.data?.accounts.count == 1 }
        let data = try #require(model.phase.data)
        #expect(data.profile.settings.monthlySalary == 150_000 && !data.profile.settings.incomeHourly)
        #expect(data.profile.settings.payday == 5)
        #expect(data.settings.localCurrency == "GEL" && data.settings.displayCurrencies.contains("GEL"))
        #expect(data.accounts.map(\.name) == ["Card"])
    }

    // MARK: The active profile

    @Test func theLastUsedProfileOpensAtLaunch() async throws {
        _ = try await harness.profile("Личный")
        let family = try await harness.profile("Семья")
        harness.onboard(active: family)

        await model.start()

        #expect(model.activeProfileId == family)
        #expect(try await harness.data().profile.name == "Семья")
    }

    @Test func aRememberedProfileThatIsGoneFallsBackToTheFirstAndThePhoneFollows() async throws {
        let personal = try await harness.profile("Личный")
        _ = try await harness.profile("Семья")
        harness.onboard(active: UUID())

        await model.start()

        #expect(model.activeProfileId == personal)
        #expect(try await harness.data().profile.id == personal)
        await eventually { harness.device.current.activeProfileId == personal }
    }

    /// The phone's choice can name a profile the observed list has not caught up with yet; that
    /// one must not be forgotten.
    @Test func aProfileChosenBeforeTheListHasItOpensOnceItArrives() async throws {
        let personal = try await harness.profile("Личный")
        harness.onboard(active: personal)
        await model.start()
        _ = try await harness.data()

        let family = try await harness.repository.createProfile(name: "Семья").id
        harness.device.update { $0.activeProfileId = family }

        await eventually { model.data?.profile.id == family }
        #expect(harness.device.current.activeProfileId == family)
    }

    @Test func switchingTheActiveProfileChangesTheSnapshot() async throws {
        let personal = try await harness.profile("Личный", accounts: [.card("Карта ₽")])
        let family = try await harness.profile("Семья", accounts: [.card("Общая карта"), .card("Наличные", sort: 1)])
        harness.onboard(active: personal)
        await model.start()
        #expect(try await harness.data().accounts.map(\.name) == ["Карта ₽"])

        model.switchProfile(to: family)

        #expect(model.activeProfileId == family)
        #expect(harness.device.current.activeProfileId == family)
        await eventually { model.data?.profile.id == family }
        #expect(model.data?.accounts.map(\.name) == ["Общая карта", "Наличные"])
        #expect(model.data?.profile.name == "Семья")
    }

    @Test func switchingToAnUnknownProfileChangesNothing() async throws {
        let personal = try await harness.profile("Личный")
        harness.onboard(active: personal)
        await model.start()

        model.switchProfile(to: UUID())

        #expect(model.activeProfileId == personal)
        #expect(harness.device.current.activeProfileId == personal)
    }

    @Test func aChangeInTheActiveProfileReachesTheData() async throws {
        let personal = try await harness.profile("Личный")
        harness.onboard(active: personal)
        await model.start()
        _ = try await harness.data()

        try await harness.repository.saveAccount(.card("Карта ₽"), profileId: personal, openingMinor: 500_000)

        await eventually { model.data?.accounts.count == 1 }
        let card = try #require(model.data?.accounts.first)
        #expect(model.data?.states[card.id]?.balanceMinor == 500_000)
    }

    // MARK: Creating and deleting profiles

    @Test func creatingAProfileOpensIt() async throws {
        let personal = try await harness.profile("Личный")
        harness.onboard(active: personal)
        await model.start()

        let family = try await model.createProfile(name: "  Семья ")

        #expect(family.name == "Семья")
        #expect(model.profiles.map(\.name) == ["Личный", "Семья"])
        #expect(model.activeProfileId == family.id)
        #expect(harness.device.current.activeProfileId == family.id)
        await eventually { model.data?.profile.id == family.id }
    }

    @Test func renamingAProfileReachesTheList() async throws {
        let personal = try await harness.profile("Личный")
        harness.onboard(active: personal)
        await model.start()

        try await model.renameProfile(personal, to: "Мой")

        await eventually { model.activeProfile?.name == "Мой" && model.data?.profile.name == "Мой" }
    }

    @Test func deletingTheActiveProfileFallsBackAndTheDeviceSettingFollows() async throws {
        let personal = try await harness.profile("Личный")
        let family = try await harness.profile("Семья")
        harness.onboard(active: family)
        await model.start()
        #expect(try await harness.data().profile.id == family)

        try await model.deleteProfile(family)

        #expect(model.profiles.map(\.id) == [personal])
        #expect(model.activeProfileId == personal)
        #expect(harness.device.current.activeProfileId == personal)
        await eventually { model.data?.profile.id == personal }
    }

    @Test func deletingAnotherProfileKeepsTheActiveOne() async throws {
        let personal = try await harness.profile("Личный")
        let family = try await harness.profile("Семья")
        harness.onboard(active: personal)
        await model.start()

        try await model.deleteProfile(family)

        #expect(model.profiles.map(\.id) == [personal])
        #expect(model.activeProfileId == personal)
        #expect(harness.device.current.activeProfileId == personal)
    }

    @Test func theLastProfileCannotBeDeleted() async throws {
        let personal = try await harness.profile("Личный")
        harness.onboard(active: personal)
        await model.start()

        await #expect(throws: RepositoryError.lastProfile) { try await model.deleteProfile(personal) }
        #expect(model.activeProfileId == personal)
    }

    /// What sync will do: the profile's rows vanish without the repository, so nothing moved the
    /// phone's choice. The ended snapshot stream does.
    @Test func aProfileDeletedBehindTheModelsBackFallsBackAndIsRemembered() async throws {
        let personal = try await harness.profile("Личный")
        let family = try await harness.profile("Семья")
        harness.onboard(active: family)
        await model.start()
        _ = try await harness.data()

        try await harness.environment.database.write { try $0.deleteProfile(family) }

        await eventually { model.data?.profile.id == personal }
        #expect(model.activeProfileId == personal)
        #expect(harness.device.current.activeProfileId == personal)
    }

    // MARK: The books of the profile on screen

    @Test func changesGoToTheProfileOnScreenAndDeletingCanBeUndone() async throws {
        let card = Account.card("Карта ₽")
        _ = try await harness.profile("Личный")
        let family = try await harness.profile("Семья", accounts: [card])
        harness.onboard(active: family)
        await model.start()
        _ = try await harness.data()

        let id = try await model.save(
            Draft(type: .expense, timestamp: AppHarness.now, accountId: card.id, amountMinor: 15_000, categoryKey: "eating_out")
        )
        await eventually { model.data?.visibleOperations.map(\.op.id) == [id] }
        #expect(model.data?.usualAccountId == card.id)

        let token = try #require(try await model.deleteOperation(id))
        #expect(token.profileId == family)
        await eventually { model.data?.visibleOperations.isEmpty == true }

        try await model.restoreOperation(token)
        await eventually { model.data?.visibleOperations.map(\.op.id) == [id] }

        let adjustment = try await model.reconcile(accountId: card.id, actualMinor: 0)
        #expect(adjustment != nil)
        await eventually { model.data?.states[card.id]?.balanceMinor == 0 }
    }

    @Test func changesNeedAProfileOnScreen() async throws {
        await model.start()

        await #expect(throws: AppModelError.noProfileOpen) {
            try await model.save(Draft(type: .expense, timestamp: AppHarness.now, accountId: UUID(), amountMinor: 100))
        }
    }

    // MARK: Launch work

    @Test func launchSeedsTheRatesAndAFailedRefreshIsSilent() async throws {
        let personal = try await harness.profile("Личный")
        harness.onboard(active: personal)
        await model.start()

        let data = try await harness.data()
        #expect(data.ratesDate == "2026-10-02")
        #expect(data.rates.official("USD") == 83.2454)
        #expect(await model.refreshRates() == false)
        #expect(model.data?.ratesDate == "2026-10-02")
    }

    @Test func freshRatesReachTheData() async throws {
        let harness = try AppHarness(ratesSource: StubRatesSource {
            [CbrRate(code: "USD", rubPerUnit: 90.5, date: "2026-10-03"), CbrRate(code: "RUB", rubPerUnit: 1, date: "2026-10-03")]
        })
        let personal = try await harness.profile("Личный")
        harness.onboard(active: personal)
        // Launch refreshes in the background; the wait covers it.
        await harness.model.start()

        await eventually { harness.model.data?.ratesDate == "2026-10-03" }
        #expect(harness.model.data?.rates.official("USD") == 90.5)
        #expect(await harness.model.refreshRates())
    }

    @Test func samplesAtLaunchOpenTheMadeUpPerson() async throws {
        _ = try await harness.profile("Старый")

        await model.start(command: .samples, profileName: "Личный")

        #expect(model.profiles.map(\.name) == ["Личный"])
        #expect(harness.device.current.onboarded)
        let data = try await harness.data()
        #expect(data.profile.name == "Личный")
        #expect(data.accounts.count == 7)
        #expect(data.operations.count == 28)
    }

    @Test func demoAtLaunchOpensTheOpeningBalancesOnly() async throws {
        await model.start(command: .demo, profileName: "Личный")

        let data = try await harness.data()
        #expect(data.accounts.count == 7)
        #expect(data.operations.allSatisfy { $0.op.type == .opening })
        #expect(data.visibleOperations.isEmpty)
    }

    @Test func resetAtLaunchGoesBackToTheWelcome() async throws {
        let personal = try await harness.profile("Личный")
        harness.onboard(active: personal)

        await model.start(command: .reset)

        #expect(model.profiles.isEmpty)
        #expect(!harness.device.current.onboarded)
        #expect(model.phase.isOnboarding)
    }

    @Test func launchWorkRunsOnce() async throws {
        await model.start(command: .samples, profileName: "Личный")
        let profiles = model.profiles

        await model.start(command: .reset)

        #expect(model.profiles == profiles)
    }
}
