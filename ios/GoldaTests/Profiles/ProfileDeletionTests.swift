import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// Deleting a profile takes its books along, so the question says what goes; the last profile
/// cannot go at all, and the screens say why.
@Suite struct ProfileDeletionTests {
    private let ru = Locale(identifier: "ru")
    private let en = Locale(identifier: "en")

    private func contents(accounts: Int = 0, operations: Int = 0, goals: Int = 0, wishes: Int = 0, payments: Int = 0) -> ProfileContents {
        ProfileContents(accounts: accounts, operations: operations, goals: goals, wishes: wishes, payments: payments)
    }

    @Test func theQuestionNamesTheProfile() {
        let deletion = ProfileDeletion(name: "Семья", contents: nil)
        #expect(deletion.title(in: ru) == "Удалить «Семья»?")
        #expect(deletion.title(in: en) == "Delete “Семья”?")
        #expect(ProfileDeletion.confirmTitle.text(in: ru) == "Удалить")
        #expect(ProfileDeletion.confirmTitle.text(in: en) == "Delete")
    }

    @Test func everythingThatGoesIsCounted() {
        let deletion = ProfileDeletion(name: "Личный", contents: contents(accounts: 7, operations: 25, goals: 2, wishes: 2, payments: 2))
        #expect(deletion.message(in: ru) == "Вместе с профилем удалится всё, что в нём есть: 7 счетов, 25 операций, 2 цели, 2 покупки в вишлисте и 2 платежа. Это не отменить.")
        #expect(deletion.message(in: en) == "Everything in it goes too: 7 accounts, 25 operations, 2 goals, 2 wishlist items, and 2 payments. This can’t be undone.")
    }

    @Test func russianCountsTakeTheirForms() {
        let one = ProfileDeletion(name: "Поездка", contents: contents(accounts: 1, operations: 1, goals: 1, wishes: 1, payments: 1))
        #expect(one.message(in: ru) == "Вместе с профилем удалится всё, что в нём есть: 1 счёт, 1 операция, 1 цель, 1 покупка в вишлисте и 1 платёж. Это не отменить.")
        #expect(one.message(in: en) == "Everything in it goes too: 1 account, 1 operation, 1 goal, 1 wishlist item, and 1 payment. This can’t be undone.")
        let few = ProfileDeletion(name: "Поездка", contents: contents(accounts: 3, operations: 22, goals: 4, wishes: 23, payments: 24))
        #expect(few.message(in: ru) == "Вместе с профилем удалится всё, что в нём есть: 3 счёта, 22 операции, 4 цели, 23 покупки в вишлисте и 24 платежа. Это не отменить.")
        let many = ProfileDeletion(name: "Поездка", contents: contents(accounts: 11, operations: 100, goals: 5, wishes: 12, payments: 15))
        #expect(many.message(in: ru) == "Вместе с профилем удалится всё, что в нём есть: 11 счетов, 100 операций, 5 целей, 12 покупок в вишлисте и 15 платежей. Это не отменить.")
    }

    @Test func onlyWhatThereIsIsListed() {
        let deletion = ProfileDeletion(name: "Поездка", contents: contents(accounts: 2, payments: 1))
        #expect(deletion.message(in: ru) == "Вместе с профилем удалится всё, что в нём есть: 2 счёта и 1 платёж. Это не отменить.")
        #expect(deletion.message(in: en) == "Everything in it goes too: 2 accounts and 1 payment. This can’t be undone.")
        let single = ProfileDeletion(name: "Поездка", contents: contents(goals: 1))
        #expect(single.message(in: en) == "Everything in it goes too: 1 goal. This can’t be undone.")
    }

    @Test func anEmptyProfileSaysSo() {
        let deletion = ProfileDeletion(name: "Поездка", contents: contents())
        #expect(deletion.message(in: ru) == "В профиле пока ничего нет.")
        #expect(deletion.message(in: en) == "There is nothing in it yet.")
    }

    /// When the count could not be read, the question still names everything that goes.
    @Test func withoutACountTheKindsAreNamed() {
        let deletion = ProfileDeletion(name: "Поездка", contents: nil)
        #expect(deletion.message(in: ru) == "Вместе с профилем удалятся его счета, операции, цели, вишлист и платежи. Это не отменить.")
        #expect(deletion.message(in: en) == "Its accounts, operations, goals, wishlist and payments go too. This can’t be undone.")
    }

    @Test func theLastProfileStays() {
        #expect(!ProfileDeletion.canDelete(profileCount: 1))
        #expect(!ProfileDeletion.canDelete(profileCount: 0))
        #expect(ProfileDeletion.canDelete(profileCount: 2))
        #expect(ProfileDeletion.lastProfileReason.text(in: ru) == "Последний профиль удалить нельзя — сначала создай другой.")
        #expect(ProfileDeletion.lastProfileReason.text(in: en) == "The last profile can’t be deleted. Create another one first.")
    }

    /// Opening balances are bookkeeping, not operations anyone recorded; they go with the accounts.
    @Test func contentsCountWhatTheScreensShow() {
        let card = Account(name: "Карта", currency: "RUB", type: .card, includeInFree: true)
        let opening = OperationFull(Operation(type: .opening, timestamp: 0), [])
        let coffee = OperationFull(Operation(type: .expense, timestamp: 1), [])
        let salary = OperationFull(Operation(type: .income, timestamp: 2), [])
        let snapshot = ProfileSnapshot(
            profile: Profile(name: "Личный"), accounts: [card], operations: [salary, coffee, opening],
            obligations: [Obligation(name: "Аренда", amountMinor: 1, currency: "RUB", dayOfMonth: 1)],
            goals: [Goal(name: "Велосипед", targetMinor: 1, currency: "RUB")],
            wishes: [
                Wish(title: "Наушники", amountMinor: 1, currency: "USD", createdAt: 0, decideAt: 0),
                Wish(title: "Кроссовки", amountMinor: 1, currency: "GEL", createdAt: 0, decideAt: 0, status: .skipped),
            ]
        )
        #expect(ProfileContents(snapshot) == contents(accounts: 1, operations: 2, goals: 1, wishes: 2, payments: 1))
        #expect(!ProfileContents(snapshot).isEmpty)
        #expect(contents().isEmpty)
    }

    // MARK: The list

    @Test func theListMarksTheActiveProfile() {
        let personal = Profile(name: "Личный", sort: 0), family = Profile(name: "Семья", sort: 1)
        let rows = ProfileRow.rows([personal, family], activeId: family.id)
        #expect(rows.map(\.name) == ["Личный", "Семья"])
        #expect(rows.map(\.isActive) == [false, true])
        #expect(rows[1].accessibilityLabel(in: ru) == "Семья, активный")
        #expect(rows[1].accessibilityLabel(in: en) == "Семья, active")
        #expect(rows[0].accessibilityLabel(in: en) == "Личный")
    }
}
