import Foundation
import GoldaCore
import Testing

@testable import GoldaData

/// Categories of the profile's own (D68): made, renamed and deleted; a deleted one leaves its
/// operations in "Прочее" of its kind.
@Suite final class RepositoryCategoryTests {
    let harness: RepositoryHarness
    let profileId: UUID
    let rub = RepositoryLedgerTests.rubCard
    var repository: Repository { harness.repository }

    init() async throws {
        harness = try RepositoryHarness()
        profileId = try await harness.profile(accounts: [rub])
    }

    func spend(_ key: String?, note: String = "корм") async throws -> UUID {
        try await repository.save(
            Draft(type: .expense, timestamp: 1, accountId: rub.id, amountMinor: 10_000, categoryKey: key, note: note), profileId: profileId
        )
    }

    @Test func categoriesAreListedInTheOrderTheyWereMade() async throws {
        let cat = CustomCategory(name: "Кот", kind: .expense, hint: "корм", symbol: "cat")
        let rent = CustomCategory(name: "Аренда", kind: .income)
        try await repository.saveCategory(cat, profileId: profileId)
        try await repository.saveCategory(rent, profileId: profileId)
        var renamed = cat
        renamed.name = "Кошка"
        try await repository.saveCategory(renamed, profileId: profileId)
        #expect(try await harness.snapshot(profileId).categories == [renamed, rent])
    }

    @Test func aDeletedCategoryLeavesItsOperationsInOther() async throws {
        let cat = CustomCategory(name: "Кот", kind: .expense)
        let salary = CustomCategory(name: "Подработка", kind: .income)
        try await repository.saveCategory(cat, profileId: profileId)
        try await repository.saveCategory(salary, profileId: profileId)
        let fed = try await spend(cat.key)
        let lunch = try await spend("eating_out", note: "обед")
        let paid = try await repository.save(
            Draft(type: .income, timestamp: 2, accountId: rub.id, amountMinor: 50_000, categoryKey: salary.key), profileId: profileId
        )

        #expect(try await repository.operationCount(categoryKey: cat.key, profileId: profileId) == 1)
        try await repository.deleteCategory(cat, profileId: profileId)
        try await repository.deleteCategory(salary, profileId: profileId)

        #expect(try await harness.snapshot(profileId).categories.isEmpty)
        #expect(try await harness.operation(fed, profileId)?.op.categoryKey == "other")
        #expect(try await harness.operation(lunch, profileId)?.op.categoryKey == "eating_out")
        #expect(try await harness.operation(paid, profileId)?.op.categoryKey == "other_income")
    }

    @Test func anotherProfilesOperationsKeepTheirCategory() async throws {
        let other = try await harness.profile("Семья", accounts: [Account(name: "Карта", currency: "RUB", type: .card, includeInFree: true)])
        let cat = CustomCategory(name: "Кот", kind: .expense)
        try await repository.saveCategory(cat, profileId: profileId)
        let account = try await harness.snapshot(other).accounts[0]
        // A key is a key: an operation of another profile that happens to hold it is not this one's.
        let theirs = try await repository.save(
            Draft(type: .expense, timestamp: 1, accountId: account.id, amountMinor: 100, categoryKey: cat.key), profileId: other
        )
        try await repository.deleteCategory(cat, profileId: profileId)
        #expect(try await harness.operation(theirs, other)?.op.categoryKey == cat.key)
    }

    @Test func voiceGetsTheCategoriesAndHowThingsWereFiled() async throws {
        let cat = CustomCategory(name: "Кот", kind: .expense, hint: "корм, ветеринар")
        try await repository.saveCategory(cat, profileId: profileId)
        _ = try await spend(cat.key)
        _ = try await spend(nil, note: "такси")
        let books = try await repository.voiceCategories(profileId: profileId)
        #expect(books.categories == Category.all(custom: [cat]))
        #expect(books.examples == [CategoryExample(note: "корм", categoryKey: cat.key)])
    }
}
