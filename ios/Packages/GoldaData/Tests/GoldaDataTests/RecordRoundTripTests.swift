import Foundation
import GoldaCore
import Testing

@testable import GoldaData

/// Every model comes back exactly as written: all optionals set, all cleared again, and money at
/// the ends of `Int64`.
@Suite struct RecordRoundTripTests {
    let profileId = StoreFixture.id(1)

    @Test func profile() async throws {
        let database = try GoldaDatabase.inMemory()
        let profile = Profile(
            id: StoreFixture.id(1), name: "Семья", sort: Int.max,
            settings: ProfileSettings(
                incomeHourly: false, hourlyRate: 1_234.5, monthlySalary: 250_000.75, taxPercent: 13,
                hoursPerWeek: 37.5, payday: 31, markup: -0.034
            )
        )
        try await database.write { try $0.save(profile) }
        #expect(try await database.read { try $0.profile(profile.id) } == profile)

        let renamed = Profile(id: profile.id, name: "Компания", sort: 0)
        try await database.write { try $0.save(renamed) }
        #expect(try await database.read { try $0.profiles() } == [renamed])
    }

    @Test func profileSettingsAreTheProfilesPartOfTheDomainSettings() {
        let settings = Settings(
            incomeHourly: false, hourlyRate: 1, monthlySalary: 2, taxPercent: 3, hoursPerWeek: 4, payday: 5,
            displayCurrencies: ["GEL"], localCurrency: "GEL", baseCurrency: "USD", markup: 0.06, lastAccountId: StoreFixture.id(9)
        )
        #expect(ProfileSettings(from: settings) == ProfileSettings(
            incomeHourly: false, hourlyRate: 1, monthlySalary: 2, taxPercent: 3, hoursPerWeek: 4, payday: 5, markup: 0.06
        ))
        #expect(ProfileSettings() == ProfileSettings(from: Settings()))
    }

    @Test func account() async throws {
        let database = try await StoreFixture.database(profiles: 1)
        let full = Account(
            id: StoreFixture.id(10), name: "Кредитка", currency: "RUB", type: .credit, groupName: "Банк",
            includeInFree: false, interestRate: 29.9, sort: -3, paymentDay: 25, paymentMinor: .max,
            graceUntil: .min, reconciledAt: 1_759_400_000_000
        )
        let bare = Account(id: full.id, name: "Наличные ₾", currency: "GEL", type: .cash, includeInFree: true, sort: 7)

        try await database.write { try $0.save(full, profileId: profileId) }
        #expect(try await database.read { try $0.account(full.id, profileId: profileId) } == full)
        try await database.write { try $0.save(bare, profileId: profileId) }
        #expect(try await database.read { try $0.accounts(profileId: profileId) } == [bare])
    }

    @Test func operationWithPostings() async throws {
        let database = try await StoreFixture.database(profiles: 1)
        let full = GoldaCore.Operation(
            id: StoreFixture.id(20), type: .transfer, timestamp: .max, categoryKey: "travel", note: "обмен",
            voiceText: "поменял сто долларов", purchaseAmountMinor: .min, purchaseCurrency: "THB", isEstimate: true,
            cbrFrom: 1, cbrTo: 83.2454
        )
        let bare = GoldaCore.Operation(id: full.id, type: .expense, timestamp: .min)
        let postings = [
            Posting(id: StoreFixture.id(30), operationId: full.id, accountId: StoreFixture.id(10), amountMinor: .min, rubMinor: .min),
            Posting(id: StoreFixture.id(31), operationId: full.id, accountId: StoreFixture.id(11), amountMinor: .max, rubMinor: .max),
        ]

        try await database.write { store in
            try store.save(StoreFixture.account(10), profileId: profileId)
            try store.save(StoreFixture.account(11, currency: "USD"), profileId: profileId)
            try store.book(full, postings, profileId: profileId, updatedAt: 1_759_400_000_123)
        }
        #expect(try await database.read { try $0.operation(full.id, profileId: profileId) } == OperationFull(full, postings))
        let updatedAt = try await database.writer.read { db in try OperationRecord.fetchOne(db, id: full.id)?.updatedAt }
        #expect(updatedAt == 1_759_400_000_123)

        try await database.write { try $0.save(bare, profileId: profileId, updatedAt: .max) }
        #expect(try await database.read { try $0.operations(profileId: profileId) } == [OperationFull(bare, postings)])
    }

    @Test func obligation() async throws {
        let database = try await StoreFixture.database(profiles: 1)
        let obligation = Obligation(id: StoreFixture.id(40), name: "Аренда", amountMinor: .max, currency: "GEL", dayOfMonth: 31)
        try await database.write { try $0.save(obligation, profileId: profileId) }
        #expect(try await database.read { try $0.obligation(obligation.id, profileId: profileId) } == obligation)
    }

    @Test func goal() async throws {
        let database = try await StoreFixture.database(profiles: 1)
        let full = Goal(
            id: StoreFixture.id(50), name: "Машина", targetMinor: .max, currency: "USD", accountId: StoreFixture.id(10),
            savedMinor: .min, isMain: true
        )
        let bare = Goal(id: full.id, name: "Отпуск", targetMinor: 0, currency: "RUB")

        try await database.write { try $0.save(full, profileId: profileId) }
        #expect(try await database.read { try $0.goal(full.id, profileId: profileId) } == full)
        try await database.write { try $0.save(bare, profileId: profileId) }
        #expect(try await database.read { try $0.goals(profileId: profileId) } == [bare])
    }

    @Test func wish() async throws {
        let database = try await StoreFixture.database(profiles: 1)
        let full = Wish(
            id: StoreFixture.id(60), title: "Наушники", amountMinor: .max, currency: "RUB", createdAt: .min, decideAt: .max,
            status: .bought, decidedAt: 1_759_400_000_000
        )
        let bare = Wish(id: full.id, title: "", amountMinor: .min, currency: "THB", createdAt: 0, decideAt: 0)

        try await database.write { try $0.save(full, profileId: profileId) }
        #expect(try await database.read { try $0.wish(full.id, profileId: profileId) } == full)
        try await database.write { try $0.save(bare, profileId: profileId) }
        #expect(try await database.read { try $0.wishes(profileId: profileId) } == [bare])
    }

    @Test func ratesUpsertByCode() async throws {
        let database = try GoldaDatabase.inMemory()
        try await database.write { store in
            try store.save([
                RateRecord(code: "USD", rubPerUnit: 83.2454, date: "2026-10-01"),
                RateRecord(code: "THB", rubPerUnit: 2.47438, date: "2026-10-01"),
            ])
            try store.save([RateRecord(code: "USD", rubPerUnit: 84.0001, date: "2026-10-02")])
        }
        #expect(try await database.read { try $0.rates() } == [
            RateRecord(code: "THB", rubPerUnit: 2.47438, date: "2026-10-01"),
            RateRecord(code: "USD", rubPerUnit: 84.0001, date: "2026-10-02"),
        ])
    }
}
