import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// What the account form's two intents do to the open profile's books, through `AppModel` and a
/// real in-memory database.
@MainActor @Suite struct AccountFormIntentTests {
    @Test func aNewAccountIsAddedToTheProfileOnScreenWithItsOpeningBalance() async throws {
        let harness = try AppHarness()
        let personal = try await harness.profile("Личный")
        let family = try await harness.profile("Семья")
        harness.onboard(active: family)
        await harness.model.start()
        let data = try await harness.data()

        var form = AccountFormModel(data: data, editing: nil)
        form.name = "Кредит"
        form.type = .loan
        form.pickCurrency("RUB")
        form.openingText = "200000"
        form.rateText = "19,9"
        form.paymentText = "10000"
        form.paymentDay = 5
        let output = try #require(form.output)
        try await harness.model.saveAccount(output.account, openingMinor: output.openingMinor)

        await eventually { harness.model.data?.accounts.count == 1 }
        let books = try #require(harness.model.data)
        #expect(books.profile.id == family)
        #expect(books.accounts == [output.account])
        #expect(books.states[output.account.id]?.balanceMinor == -20_000_000)
        // The opening balance is bookkeeping: it is in the books, not in the list of operations.
        #expect(books.operations.map(\.op.type) == [.opening])
        #expect(books.visibleOperations.isEmpty)
        // The loan's payment is now set aside before payday.
        #expect(books.allObligations.map(\.amountMinor) == [1_000_000])

        let other = try await harness.environment.database.read { try $0.accounts(profileId: personal) }
        #expect(other.isEmpty)
    }

    @Test func editingChangesTheAccountButNeitherItsBalanceNorItsReconcileStamp() async throws {
        let harness = try AppHarness()
        let card = Account.card("Карта")
        let profile = try await harness.profile("Личный")
        harness.onboard(active: profile)
        try await harness.repository.saveAccount(card, profileId: profile, openingMinor: 500_000)
        try await harness.repository.reconcile(accountId: card.id, actualMinor: 450_000, profileId: profile)
        await harness.model.start()
        let data = try await harness.data()
        let stored = try #require(data.accounts.first)
        #expect(stored.reconciledAt == AppHarness.now)

        // A form opened before the reconcile still carries no stamp; saving it keeps the stored one.
        var form = AccountFormModel(data: data, editing: card)
        form.name = "Основная карта"
        form.groupChoice = .new
        form.newGroupName = "Т-Банк"
        form.openingText = "1"
        let output = try #require(form.output)
        #expect(output.account.reconciledAt == nil)
        try await harness.model.saveAccount(output.account, openingMinor: output.openingMinor)

        await eventually { harness.model.data?.accounts.first?.name == "Основная карта" }
        let books = try #require(harness.model.data)
        let edited = try #require(books.accounts.first)
        #expect(edited.groupName == "Т-Банк")
        #expect(edited.reconciledAt == AppHarness.now)
        #expect(books.states[card.id]?.balanceMinor == 450_000)
        #expect(books.operations.count == 2, "the opening and the reconcile, nothing new")
    }

    @Test func deletingAnAccountTakesItsOperationsAndBothSidesOfItsTransfers() async throws {
        let harness = try AppHarness()
        let card = Account.card("Карта")
        let cash = Account(name: "Наличные", currency: "RUB", type: .cash, includeInFree: true, sort: 1)
        let profile = try await harness.profile("Личный", accounts: [card, cash])
        harness.onboard(active: profile)
        try await harness.repository.save(
            Draft(type: .transfer, timestamp: AppHarness.now, accountId: card.id, amountMinor: 10_000, toAccountId: cash.id, toAmountMinor: 10_000),
            profileId: profile
        )
        try await harness.repository.save(
            Draft(type: .expense, timestamp: AppHarness.now, accountId: cash.id, amountMinor: 2_000, categoryKey: "eating_out"),
            profileId: profile
        )
        await harness.model.start()
        _ = try await harness.data()
        await eventually { harness.model.data?.operations.count == 2 }

        try await harness.model.deleteAccount(card.id)

        await eventually { harness.model.data?.accounts.count == 1 }
        let books = try #require(harness.model.data)
        #expect(books.accounts.map(\.id) == [cash.id])
        // The transfer went with the card; the coffee paid in cash stays.
        #expect(books.operations.map(\.op.type) == [.expense])
    }

    @Test func withNoProfileOpenNothingIsWritten() async throws {
        let harness = try AppHarness()
        await harness.model.start()
        await #expect(throws: AppModelError.noProfileOpen) {
            try await harness.model.saveAccount(Account.card("Карта"), openingMinor: 100)
        }
        await #expect(throws: AppModelError.noProfileOpen) {
            try await harness.model.deleteAccount(UUID())
        }
    }
}
