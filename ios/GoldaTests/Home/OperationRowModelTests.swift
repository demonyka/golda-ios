import Foundation
import GoldaCore
import Testing

@testable import Golda

/// The rules of Android's `OperationRow`, branch by branch, on rows built by hand.
@MainActor @Suite struct OperationRowModelTests {
    typealias F = HomeFixture
    var books = HomeFixture()

    // MARK: Home (no account page)

    @Test func anExpenseIsTitledByItsNoteAndSigned() throws {
        let coffee = F.operation(.expense, at: F.at(hour: 9), note: "Кофе", category: "eating_out", [(books.rub, -15_000, -15_000)])
        let row = try books.row(coffee)

        #expect(row.title == .verbatim("Кофе"))
        #expect(row.title(in: F.en) == "Кофе")
        #expect(row.main == "−150 ₽")
        #expect(row.secondary == nil)
        #expect(row.tone == .normal)
        #expect(row.symbol == "fork.knife")
        #expect(row.id == coffee.op.id)
    }

    @Test func incomeIsSignedPlusAndNamedByItsCategory() throws {
        let salary = F.operation(.income, at: F.at(hour: 9), category: "salary", [(books.rub, 15_840_000, 15_840_000)])
        let row = try books.row(salary)

        #expect(row.main == "+158\u{202F}400 ₽")
        #expect(row.title == .category("salary"))
        #expect(row.title(in: F.ru) == "Зарплата")
        #expect(row.title(in: F.en) == "Salary")
        #expect(row.symbol == "briefcase")
        #expect(row.tone == .normal)
    }

    @Test func aBlankNoteGivesWayToTheCategory() throws {
        let groceries = F.operation(.expense, at: F.at(hour: 9), note: "  ", category: "groceries", [(books.rub, -50_000, -50_000)])
        let row = try books.row(groceries)

        #expect(row.title == .category("groceries"))
        #expect(row.title(in: F.ru) == "Продукты")
        #expect(row.title(in: F.en) == "Groceries")
    }

    @Test func withNeitherNoteNorCategoryTheTypeNamesTheRow() throws {
        let adjustment = F.operation(.adjustment, at: F.at(hour: 9), [(books.rub, -1_000, -1_000)])
        let bare = F.operation(.expense, at: F.at(hour: 9), [(books.rub, -1_000, -1_000)])
        // A key the app does not know is no category at all, as an unknown `categoryId` is on Android.
        let unknown = F.operation(.expense, at: F.at(hour: 9), category: "made_up", [(books.rub, -1_000, -1_000)])
        let oneSided = F.operation(.transfer, at: F.at(hour: 9), [(books.rub, -1_000, -1_000)])

        #expect(try books.row(adjustment).title(in: F.ru) == "Сверка")
        #expect(try books.row(adjustment).title(in: F.en) == "Reconciliation")
        #expect(try books.row(adjustment).symbol == Symbols.reconcile)
        #expect(try books.row(bare).title(in: F.ru) == "Без категории")
        #expect(try books.row(bare).title(in: F.en) == "No category")
        #expect(try books.row(unknown).title == .noCategory)
        #expect(try books.row(unknown).symbol == Symbols.other)
        // A transfer that lost its other side has no "A → B" to show.
        #expect(try books.row(oneSided).title(in: F.ru) == "Перевод")
        #expect(try books.row(oneSided).title(in: F.en) == "Transfer")
        #expect(try books.row(oneSided).main == "−10 ₽")
    }

    @Test func aTransferReadsFromAToBWithoutASignInAQuietColour() throws {
        let abroad = F.operation(
            .transfer, at: F.at(hour: 9), note: "Перевод за границу",
            [(books.rub, -7_360_000, -7_360_000), (books.usd, 80_000, 7_360_000)]
        )
        let row = try books.row(abroad)

        #expect(row.title == .verbatim("Карта ₽ → Доллары"))
        #expect(row.main == "73\u{202F}600 ₽")
        #expect(row.secondary == OperationRowModel.Secondary(arrow: true, amount: "800 $"))
        #expect(row.secondary?.text == "→ 800 $")
        // "Перевод…" only says what the arrow does.
        #expect(row.supporting == nil)
        #expect(row.tone == .neutral)
        #expect(row.symbol == Symbols.transfer)
    }

    @Test func aTransferNoteThatAddsSomethingGoesUnderneath() throws {
        let cushion = F.operation(
            .transfer, at: F.at(hour: 9), note: "В подушку",
            [(books.rub, -8_000_000, -8_000_000), (books.savings, 8_000_000, 8_000_000)]
        )
        let row = try books.row(cushion)

        #expect(row.title == .verbatim("Карта ₽ → Накопительный"))
        #expect(row.supporting == "В подушку")
        // Same currency on both ends: one amount says it.
        #expect(row.secondary == nil)
        #expect(row.main == "80\u{202F}000 ₽")
    }

    @Test func aNoteNamingBothAccountsRestatesTheTransfer() throws {
        let toCash = F.operation(
            .transfer, at: F.at(hour: 9), note: "С карты на наличные",
            [(books.rub, -300_000, -300_000), (books.cash, 9_000, 300_000)]
        )
        #expect(try books.row(toCash).supporting == nil)

        #expect(OperationRowModel.restatesTransfer("Перевод себе", from: "Карта", to: "Наличные"))
        #expect(OperationRowModel.restatesTransfer("Transfer to cash", from: "Card", to: "Cash"))
        #expect(OperationRowModel.restatesTransfer("ПЕРЕВОД", from: nil, to: nil))
        // The stem is the first word of three letters or more, cut to four, and hyphens split words.
        #expect(OperationRowModel.restatesTransfer("с мультивалютной в наличку", from: "Мульти-валютная USD", to: "Наличные ₾"))
        #expect(OperationRowModel.restatesTransfer("из usd-кошелька в нал", from: "USD-кошелёк", to: "Нал"))
        #expect(!OperationRowModel.restatesTransfer("Банкомат", from: "Доллары", to: "Наличные ₾"))
        #expect(!OperationRowModel.restatesTransfer("с карты", from: "Карта ₽", to: "Наличные ₾"))
        #expect(!OperationRowModel.restatesTransfer("с карты на наличные", from: nil, to: "Наличные ₾"))
        #expect(!OperationRowModel.restatesTransfer("на ₽ и $", from: "₽", to: "$"))
    }

    @Test func anEstimatedTransferIntoAnotherCurrencyIsMarked() throws {
        let atm = F.operation(
            .transfer, at: F.at(hour: 9), note: "Банкомат", estimate: true,
            [(books.usd, -10_000, -880_000), (books.cash, 26_500, 880_000)]
        )
        let row = try books.row(atm)

        #expect(row.main == "100 $")
        #expect(row.secondary?.text == "→ ≈ 265 ₾")
        #expect(row.supporting == "Банкомат")
    }

    @Test func aPurchaseInAnotherCurrencyShowsTheShopsPriceAndTheCard() throws {
        let market = F.operation(
            .expense, at: F.at(hour: 9), note: "Рынок", category: "groceries", purchase: (4_850, "GEL"), estimate: true,
            [(books.usd, -1_899, -167_112)]
        )
        let row = try books.row(market)

        #expect(row.main == "−48,50 ₾")
        #expect(row.secondary == nil)
        // Paid from the dollar card, not the usual ruble one.
        #expect(row.supporting == "Доллары")
        #expect(row.tone == .normal)
    }

    @Test func theAccountIsNamedOnlyWhenItIsNotTheUsualOne() throws {
        var books = self.books
        let fromCard = F.operation(.expense, at: F.at(hour: 9), note: "Такси", [(books.rub, -40_000, -40_000)])
        let fromCash = F.operation(.expense, at: F.at(hour: 9), note: "Кофе", [(books.cash, -800, -26_400)])

        // With nothing used yet, the first account that counts towards today is the usual one.
        #expect(try books.row(fromCard).supporting == nil)
        #expect(try books.row(fromCash).supporting == "Наличные ₾")
        #expect(try books.row(fromCash).main == "−8 ₾")

        books.lastUsed(books.cash)
        #expect(try books.row(fromCard).supporting == "Карта ₽")
        #expect(try books.row(fromCash).supporting == nil)
    }

    @Test func anOperationWithoutPostingsHasNoRow() {
        let empty = OperationFull(Operation(type: .expense, timestamp: F.at(hour: 9)), [])
        #expect(OperationRowModel(empty, in: books.data) == nil)
    }

    // MARK: An account's page

    @Test func onAnAccountsPageTheAmountIsThatAccountsOwnSide() throws {
        let market = F.operation(
            .expense, at: F.at(hour: 9), note: "Рынок", purchase: (4_850, "GEL"), estimate: true,
            [(books.usd, -1_899, -167_112)]
        )
        let lunch = F.operation(.expense, at: F.at(hour: 9), note: "Обед", [(books.usd, -1_000, -88_000)])
        let abroad = F.operation(
            .transfer, at: F.at(hour: 9), note: "Перевод за границу",
            [(books.rub, -7_360_000, -7_360_000), (books.usd, 80_000, 7_360_000)]
        )

        let marketRow = try books.row(market, accountId: books.usd.id)
        #expect(marketRow.main == "−18,99 $")
        #expect(marketRow.secondary == OperationRowModel.Secondary(amount: "−48,50 ₾"))
        #expect(marketRow.supporting == nil)

        // Not in the main currency: what it came to in rubles, approximately.
        let lunchRow = try books.row(lunch, accountId: books.usd.id)
        #expect(lunchRow.secondary == OperationRowModel.Secondary(approximate: true, amount: "−880 ₽"))
        #expect(lunchRow.secondary?.text == "≈ −880 ₽")

        let incoming = try books.row(abroad, accountId: books.usd.id)
        #expect(incoming.main == "+800 $")
        #expect(incoming.secondary == OperationRowModel.Secondary(amount: "73\u{202F}600 ₽"))
        #expect(incoming.title == .verbatim("Карта ₽ → Доллары"))
        #expect(incoming.tone == .neutral)

        let outgoing = try books.row(abroad, accountId: books.rub.id)
        #expect(outgoing.main == "−73\u{202F}600 ₽")
        #expect(outgoing.secondary == OperationRowModel.Secondary(amount: "800 $"))
    }

    // MARK: VoiceOver

    @Test func voiceOverReadsTheRowWithAmountsInWords() throws {
        let market = F.operation(
            .expense, at: F.at(hour: 9), note: "Рынок", purchase: (4_850, "GEL"), [(books.usd, -1_899, -167_112)]
        )
        let label = try books.row(market).accessibilityLabel(in: F.en)

        #expect(label.hasPrefix("Рынок, Доллары, "))
        #expect(label.contains("48.50"))
        #expect(label.localizedCaseInsensitiveContains("lari"))
        #expect(!label.contains("₾"))

        let lunch = F.operation(.expense, at: F.at(hour: 9), note: "Обед", [(books.usd, -1_000, -88_000)])
        let russian = try books.row(lunch, accountId: books.usd.id).accessibilityLabel(in: F.ru)
        #expect(russian.contains("около "))
        #expect(!russian.contains("\u{202F}"))
    }
}
