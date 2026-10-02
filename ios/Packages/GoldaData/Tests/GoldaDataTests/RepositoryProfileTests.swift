import Foundation
import GoldaCore
import GRDB
import Testing

@testable import GoldaData

/// Profiles, what never leaks from one into another, and wiping everything.
@Suite final class RepositoryProfileTests {
    let harness: RepositoryHarness
    var repository: Repository { harness.repository }

    init() throws {
        harness = try RepositoryHarness()
    }

    @Test func profilesComeAfterOneAnotherWithTheirSettings() async throws {
        var family = ProfileSettings()
        family.payday = 5
        family.monthlySalary = 200_000
        let personal = try await repository.createProfile(name: " Личный ")
        let second = try await repository.createProfile(name: "Семья", settings: family)
        #expect(personal.name == "Личный" && personal.sort == 0)
        #expect(second.sort == 1 && second.settings == family)
        #expect(try await harness.database.read { try $0.profiles() } == [personal, second])

        try await repository.renameProfile(second.id, to: "Дом")
        #expect(try await harness.database.read { try $0.profile(second.id) }?.name == "Дом")
        await #expect(throws: RepositoryError.unknownProfile(StoreFixture.id(99))) {
            try await self.repository.renameProfile(StoreFixture.id(99), to: "Нет")
        }
    }

    @Test func theLastProfileCannotBeDeleted() async throws {
        let only = try await harness.profile()
        await #expect(throws: RepositoryError.lastProfile) { try await self.repository.deleteProfile(only) }
        #expect(try await harness.database.read { try $0.profile(only) } != nil)
    }

    @Test func deletingAProfileErasesItsBooksAndWhatThisPhoneKeptAboutIt() async throws {
        let personal = try await harness.profile(accounts: [RepositoryLedgerTests.rubCard])
        let family = try await harness.profile("Семья", accounts: [Account(id: StoreFixture.id(20), name: "Общая", currency: "RUB", type: .card, includeInFree: true)])
        try await repository.save(Draft(type: .expense, timestamp: 1, accountId: RepositoryLedgerTests.rubCard.id, amountMinor: 100), profileId: personal)
        try await repository.save(Draft(type: .expense, timestamp: 1, accountId: StoreFixture.id(20), amountMinor: 100), profileId: family)
        harness.device.update {
            $0.activeProfileId = family
            $0.celebratedGoalId[family] = StoreFixture.id(30)
        }

        try await repository.deleteProfile(family)
        #expect(try await harness.database.read { try $0.profiles() }.map(\.id) == [personal])
        #expect(try await harness.database.read { try $0.snapshot(profileId: family) } == nil)
        #expect(try await harness.snapshot(personal).operations.count == 1)
        let device = harness.device.current
        #expect(device.activeProfileId == personal)
        #expect(device.lastAccountId == [personal: RepositoryLedgerTests.rubCard.id])
        #expect(device.celebratedGoalId.isEmpty)

        // Gone already (deleted on another device): nothing to do.
        try await repository.deleteProfile(family)
    }

    @Test func nothingCrossesFromOneProfileIntoAnother() async throws {
        let personal = try await harness.profile(accounts: [RepositoryLedgerTests.rubCard, RepositoryLedgerTests.multiUsd])
        let familyCard = Account(id: StoreFixture.id(20), name: "Общая", currency: "RUB", type: .card, includeInFree: true)
        let family = try await harness.profile("Семья", accounts: [familyCard])
        let rub = RepositoryLedgerTests.rubCard.id
        let usd = RepositoryLedgerTests.multiUsd.id

        try await repository.save(Draft(type: .opening, timestamp: 0, accountId: rub, amountMinor: 13_000_000), profileId: personal)
        try await repository.save(Draft(type: .opening, timestamp: 0, accountId: familyCard.id, amountMinor: 2_600_000), profileId: family)
        let personalLunch = try await repository.save(Draft(type: .expense, timestamp: RepositoryHarness.start, accountId: rub, amountMinor: 300_000), profileId: personal)
        let familyLunch = try await repository.save(Draft(type: .expense, timestamp: RepositoryHarness.start, accountId: familyCard.id, amountMinor: 100_000), profileId: family)

        // "Можно сегодня" of each profile comes from its own books: 130 000 and 26 000 ₽ over 13 days.
        #expect(try await repository.impact(operationId: personalLunch, profileId: personal)?.leftTodayRub == 700_000)
        #expect(try await repository.impact(operationId: familyLunch, profileId: family)?.leftTodayRub == 100_000)
        #expect(try await repository.impact(operationId: personalLunch, profileId: family) == nil)

        // A transfer into another profile's account is not a thing (D22).
        await #expect(throws: LedgerError.unknownAccount(familyCard.id)) {
            try await self.repository.save(Draft(type: .transfer, timestamp: 1, accountId: rub, amountMinor: 100, toAccountId: familyCard.id), profileId: personal)
        }
        // Another profile's operation can be neither edited nor deleted from here.
        await #expect(throws: StoreError.belongsToAnotherProfile(personalLunch)) {
            try await self.repository.save(Draft(type: .expense, timestamp: 1, accountId: familyCard.id, amountMinor: 1, id: personalLunch), profileId: family)
        }
        #expect(try await repository.deleteOperation(personalLunch, profileId: family) == nil)
        #expect(try await harness.operation(personalLunch, personal)?.postings.map(\.amountMinor) == [-300_000])
        await #expect(throws: RepositoryError.unknownAccount(rub)) {
            try await self.repository.reconcile(accountId: rub, actualMinor: 0, profileId: family)
        }
        try await repository.deleteAccount(rub, profileId: family)
        #expect(try await harness.snapshot(personal).accounts.count == 2)

        // The markup an exchange teaches belongs to its profile, and so does the last account used.
        try await repository.save(Draft(type: .transfer, timestamp: 2, accountId: rub, amountMinor: 4_600_000, toAccountId: usd, toAmountMinor: 50_000), profileId: personal)
        expectClose(try await harness.profileSettings(personal).markup, 0.1051, 0.0001)
        #expect(try await harness.profileSettings(family).markup == 0.10)
        #expect(try await repository.settings(profileId: personal).lastAccountId == rub)
        #expect(try await repository.settings(profileId: family).lastAccountId == familyCard.id)
    }

    @Test func settingsAreTheProfilesPartPlusThisPhonesPart() {
        let personal = StoreFixture.id(1)
        let profile = ProfileSettings(incomeHourly: false, hourlyRate: 1, monthlySalary: 2, taxPercent: 3, hoursPerWeek: 4, payday: 5, markup: 0.06)
        let device = DeviceSettings(
            displayCurrencies: ["RUB", "GEL"], localCurrency: "GEL", baseCurrency: "USD",
            lastAccountId: [personal: StoreFixture.id(10), StoreFixture.id(2): StoreFixture.id(20)]
        )
        #expect(Settings(profile: profile, device: device, profileId: personal) == Settings(
            incomeHourly: false, hourlyRate: 1, monthlySalary: 2, taxPercent: 3, hoursPerWeek: 4, payday: 5,
            displayCurrencies: ["RUB", "GEL"], localCurrency: "GEL", baseCurrency: "USD", markup: 0.06,
            lastAccountId: StoreFixture.id(10)
        ))
        #expect(Settings(profile: profile, device: device, profileId: StoreFixture.id(3)).lastAccountId == nil)
        #expect(Settings(profile: ProfileSettings(), device: DeviceSettings(), profileId: personal) == Settings())
    }

    @Test func resetAllLeavesAFreshInstall() async throws {
        let personal = try await harness.profile(accounts: [RepositoryLedgerTests.rubCard])
        _ = try await harness.profile("Семья")
        try await repository.save(Draft(type: .expense, timestamp: 1, accountId: RepositoryLedgerTests.rubCard.id, amountMinor: 100), profileId: personal)
        try await repository.refreshRates(from: StubRatesSource { [CbrRate(code: "EUR", rubPerUnit: 90, date: "2026-10-03")] })
        harness.device.update {
            $0.onboarded = true
            $0.activeProfileId = personal
        }

        try await repository.resetAll()
        #expect(try await harness.database.read { try $0.profiles() }.isEmpty)
        #expect(try await harness.database.read { try $0.rates() } == CbrRatesSource.fallback.map(RateRecord.init).sorted { $0.code < $1.code })
        #expect(harness.device.current == DeviceSettings())
        let leftovers = try await harness.database.writer.read { db in
            try ["account", "operation", "posting", "obligation", "goal", "wish"].map { table in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)")
            }
        }
        #expect(leftovers == [0, 0, 0, 0, 0, 0])
    }
}
