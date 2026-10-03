import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// An account's page, Android's `AccountScreen`: the hero's figures and the operations that touched
/// the account, each with the account's own side.
@MainActor @Suite struct AccountPageModelTests {
    typealias F = HomeFixture
    var books = AccountsFixture()

    @Test func aForeignCardShowsWhatItCostAndTheRateItWasBoughtAt() throws {
        let page = try books.page(books.usd)
        #expect(page.caption(in: F.ru) == "Карта · Мультивалютная")
        #expect(page.caption(in: F.en) == "Card · Мультивалютная")
        #expect(page.balance == "100 $")
        // 9 200 ₽ in the other shown currencies, the local lari first.
        #expect(page.others == "279 ₾ · 9\u{202F}200 ₽")
        // 18 400 ₽ for 200 $, half of them still there: 92 ₽ a dollar.
        #expect(page.purchaseRate == "92 ₽/$")
        #expect(page.purchaseRateText(in: F.ru) == "курс покупки 92 ₽/$")
        #expect(page.purchaseRateText(in: F.en) == "bought at 92 ₽/$")
        #expect(page.interest == nil)
        #expect(try books.page(books.gel).purchaseRate == "34,33 ₽/₾")
    }

    @Test func aRubleAccountHasNoPurchaseRate() throws {
        let page = try books.page(books.card)
        #expect(page.caption(in: F.ru) == "Карта")
        #expect(page.purchaseRate == nil)
        #expect(page.purchaseRateText(in: F.en) == nil)
        #expect(page.others == "48,5 ₾ · 18,2 $")
        #expect(try books.page(books.credit).purchaseRate == nil)
        #expect(try books.page(books.credit).balance == "−15\u{202F}000 ₽")
    }

    @Test func aForeignAccountInTheRedHasNoRateToShow() throws {
        let dollars = Account(name: "Овердрафт $", currency: "USD", type: .card, includeInFree: true, sort: 7)
        let operations = [F.operation(.expense, at: F.at(hour: 9), note: "Кофе", [(dollars, -500, -44_000)])] + books.operations
        let data = books.data(accounts: books.accounts + [dollars], operations: operations)
        let page = try #require(AccountPageModel(data: data, accountId: dollars.id, today: F.today))
        #expect(page.balance == "−5 $")
        #expect(page.purchaseRate == nil)
    }

    @Test func savingsWithARateShowTheMonthsInterest() throws {
        let page = try books.page(books.savings)
        #expect(page.interest?.text(in: F.ru) == "+2\u{202F}548 ₽ за октябрь")
        #expect(page.interest?.text(in: F.en) == "+2\u{202F}548 ₽ for October")
        // Its only operation is the opening balance, which is bookkeeping, not an event.
        #expect(page.days.isEmpty)
    }

    @Test func aTransferInAndOutShowsTheAccountsOwnSideEachTime() throws {
        let page = try books.page(books.usd)
        #expect(page.days.map(\.label) == [.date(LocalDate(2026, 9, 21)), .date(LocalDate(2026, 9, 20))])
        let rows = page.days.flatMap(\.rows)
        #expect(rows.count == 2)

        // Out: dollars changed into lari, the lari underneath.
        #expect(rows[0].title == .verbatim("Мультивалютная USD → Мультивалютная GEL"))
        #expect(rows[0].main == "−100 $")
        #expect(rows[0].secondary == OperationRowModel.Secondary(amount: "268 ₾"))
        #expect(rows[0].supporting == "Обмен")
        #expect(rows[0].tone == .neutral)

        // In: rubles sent abroad, what they were underneath; the note only restated the transfer.
        #expect(rows[1].title == .verbatim("Карта ₽ → Мультивалютная USD"))
        #expect(rows[1].main == "+200 $")
        #expect(rows[1].secondary == OperationRowModel.Secondary(amount: "18\u{202F}400 ₽"))
        #expect(rows[1].supporting == nil)
    }

    @Test func theSameTransferSeenFromTheSendingAccount() throws {
        let page = try books.page(books.card)
        let rows = page.days.flatMap(\.rows)
        #expect(rows.map(\.main) == ["−18\u{202F}400 ₽"])
        #expect(rows.first?.secondary?.text == "200 $")
        // From Home the same transfer has no sign and an arrow.
        let home = try #require(OperationRowModel(books.operations[2], in: books.data))
        #expect(home.main == "18\u{202F}400 ₽")
        #expect(home.secondary?.text == "→ 200 $")
    }

    @Test func anExpenseInAForeignAccountShowsItsWorthInTheMainCurrency() throws {
        let page = try books.page(books.gel)
        #expect(page.days.map(\.label) == [.today, .date(LocalDate(2026, 9, 21))])
        let rows = page.days.flatMap(\.rows)
        #expect(rows[0].main == "−10 ₾")
        #expect(rows[0].secondary == OperationRowModel.Secondary(approximate: true, amount: "−343 ₽"))
        #expect(rows[0].secondary?.text == "≈ −343 ₽")
        #expect(rows[1].main == "+268 ₾")
        #expect(rows[1].secondary?.text == "100 $")
    }

    @Test func aDeletedAccountHasNoPage() {
        #expect(AccountPageModel(data: books.data, accountId: UUID(), today: F.today) == nil)
    }

    @Test func voiceOverReadsTheHeroWithAmountsInWords() throws {
        let label = try books.page(books.usd).accessibilityLabel(in: F.en)
        #expect(label.hasPrefix("Card · Мультивалютная. 100 US dollars. "))
        #expect(label.localizedCaseInsensitiveContains("9200 Russian rubles"))
        #expect(label.hasSuffix("bought at 92 ₽/$"))
        let savings = try books.page(books.savings).accessibilityLabel(in: F.ru)
        #expect(savings.contains("за октябрь"))
        #expect(!savings.contains("\u{202F}"))
    }
}

/// The reconcile sheet's arithmetic: Android's `ReconcileSheet`, plus the sign switch the decimal
/// pad needs.
@Suite struct ReconcileEntryTests {
    typealias F = HomeFixture

    @Test func nothingTypedIsTheBalanceAndItMatches() {
        let entry = ReconcileEntry(balanceMinor: 160_000, currency: "RUB")
        #expect(entry.actualMinor == 160_000)
        #expect(entry.differenceMinor == 0)
        #expect(entry.matches)
        #expect(entry.canSave)
        #expect(entry.actionTitle(in: F.ru) == "Сходится")
        #expect(entry.actionTitle(in: F.en) == "It matches")
        #expect(entry.differenceText(in: F.ru) == nil)
        #expect(entry.placeholder == "1\u{202F}600,00")
        #expect(!entry.isNegative)
    }

    @Test func aDifferentBalanceSaysWhatWillBeRecorded() {
        var entry = ReconcileEntry(balanceMinor: 160_000, currency: "RUB")
        entry.text = "1550"
        #expect(entry.actualMinor == 155_000)
        #expect(entry.differenceMinor == -5_000)
        #expect(!entry.matches)
        #expect(entry.canSave)
        #expect(entry.actionTitle(in: F.ru) == "Записать −50 ₽")
        #expect(entry.actionTitle(in: F.en) == "Record −50 ₽")
        #expect(entry.actionTitle(in: F.en, spoken: true).hasSuffix("50 Russian rubles"))
        #expect(entry.differenceText(in: F.ru) == "Разница −50 ₽ запишется корректировкой")
        #expect(entry.differenceText(in: F.en) == "Difference −50 ₽ goes in as an adjustment")
        let spoken = entry.differenceText(in: F.en, spoken: true) ?? ""
        #expect(spoken.hasPrefix("Difference ") && spoken.hasSuffix("50 Russian rubles goes in as an adjustment"), "\(spoken)")
        #expect(!spoken.contains("₽"))

        entry.text = "1 600,25"
        #expect(entry.differenceMinor == 25)
        #expect(entry.actionTitle(in: F.en) == "Record +0,25 ₽")

        // Typing the same number is a match too.
        entry.text = "1600"
        #expect(entry.matches)
        #expect(entry.actionTitle(in: F.ru) == "Сходится")
    }

    @Test func textThatIsNotAnAmountCannotBeSaved() {
        var entry = ReconcileEntry(balanceMinor: 160_000, currency: "RUB")
        entry.text = "12,3,4"
        #expect(entry.actualMinor == nil)
        #expect(!entry.canSave)
        #expect(entry.actionTitle(in: F.en) == "It matches")
        #expect(entry.differenceText(in: F.en) == nil)
    }

    @Test func aDebtIsTypedAsTheBankShowsItAndStaysADebt() {
        var entry = ReconcileEntry(balanceMinor: -1_500_000, currency: "RUB")
        #expect(entry.isNegative)
        #expect(entry.placeholder == "−15\u{202F}000,00")
        entry.text = "14500"
        #expect(entry.actualMinor == -1_450_000)
        #expect(entry.actionTitle(in: F.ru) == "Записать +500 ₽")

        // Paid off past zero: the sign flips.
        entry.isNegative.toggle()
        #expect(entry.actualMinor == 1_450_000)
    }

    @Test func aTypedMinusMakesItNegativeAsOnAndroid() {
        var entry = ReconcileEntry(balanceMinor: 10_000, currency: "USD")
        entry.text = "-25"
        #expect(entry.actualMinor == -2_500)
        entry.text = "−25,5"
        #expect(entry.actualMinor == -2_550)
        #expect(entry.actionTitle(in: F.en) == "Record −125,50 $")
    }

    @Test func currenciesWithoutCentsAndThePageState() {
        var entry = ReconcileEntry(AccountState(account: Account(name: "Вьетнам", currency: "VND", type: .cash, includeInFree: true), balanceMinor: 250_000, rubMinor: 900_000))
        #expect(entry.placeholder == "250\u{202F}000")
        entry.text = "200000"
        #expect(entry.actionTitle(in: F.ru) == "Записать −50\u{202F}000 ₫")
    }
}
