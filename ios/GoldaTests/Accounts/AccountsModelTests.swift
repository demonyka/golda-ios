import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// Android's `accountBlocks`: a bank's accounts pulled together, neighbours without one in a plain
/// list, and a group of one is no group.
@Suite struct AccountBlockTests {
    private func account(_ name: String, group: String? = nil, sort: Int = 0) -> Account {
        Account(name: name, currency: "RUB", type: .card, groupName: group, includeInFree: true, sort: sort)
    }

    private func shape(_ blocks: [AccountBlock]) -> [String] {
        blocks.map { ($0.group ?? "-") + ": " + $0.accounts.map(\.name).joined(separator: ", ") }
    }

    @Test func theDemoAccountsMakeAPlainListABankAndAnotherPlainList() {
        let books = AccountsFixture()
        #expect(shape(AccountBlock.blocks(books.accounts)) == [
            "-: Карта ₽, Накопительный",
            "Мультивалютная: Мультивалютная USD, Мультивалютная GEL",
            "-: Наличные ₾, Кредитка, Кредит",
        ])
    }

    @Test func aGroupOfOneIsNotAGroup() {
        let accounts = [account("Карта"), account("Вклад", group: "Тинькофф"), account("Наличные")]
        #expect(shape(AccountBlock.blocks(accounts)) == ["-: Карта, Вклад, Наличные"])
    }

    @Test func aBanksAccountsGatherWhereTheFirstOfThemStands() {
        let accounts = [
            account("USD", group: "Мульти"), account("Карта"), account("GEL", group: "Мульти"), account("Наличные"),
            account("EUR", group: "Мульти"),
        ]
        #expect(shape(AccountBlock.blocks(accounts)) == ["Мульти: USD, GEL, EUR", "-: Карта, Наличные"])
    }

    @Test func plainNeighboursOnEitherSideOfABankStayApart() {
        let accounts = [account("Карта"), account("USD", group: "Мульти"), account("GEL", group: "Мульти"), account("Наличные")]
        #expect(shape(AccountBlock.blocks(accounts)) == ["-: Карта", "Мульти: USD, GEL", "-: Наличные"])
    }

    @Test func twoBanksInARowAndABlankGroupName() {
        let accounts = [
            account("USD", group: "А"), account("GEL", group: "А"), account("RUB", group: "Б"), account("EUR", group: "Б"),
            account("Пустая", group: "  "), account("Ещё пустая", group: "  "),
        ]
        // A blank name is no bank, even when two accounts share it.
        #expect(shape(AccountBlock.blocks(accounts)) == ["А: USD, GEL", "Б: RUB, EUR", "-: Пустая, Ещё пустая"])
    }

    @Test func noAccountsNoBlocks() {
        #expect(AccountBlock.blocks([]).isEmpty)
    }
}

/// The Accounts tab on the demo-shaped books: the hero, the sections and the rows.
@MainActor @Suite struct AccountsContentTests {
    typealias F = HomeFixture
    var books = AccountsFixture()

    @Test func theTotalIsEveryAccountInTheMainCurrencyWithTheOthers() {
        let hero = books.content.hero
        // 1 600 + 250 000 + 9 200 + 8 856,72 + 5 160 − 15 000 − 200 000 ₽.
        #expect(hero.totalMinor == 5_981_672)
        #expect(hero.currency == "RUB")
        // Rounded like the others line (D61), which says 59 817 ₽ in dollars' place.
        #expect(hero.total == "59\u{202F}817 ₽")
        // The local lari first, then dollars, at the rates with the 10 % markup.
        #expect(hero.others == "1\u{202F}813 ₾ · 680 $")
        #expect(AccountsHero.caption.text(in: F.ru) == "Всего")
        #expect(AccountsHero.caption.text(in: F.en) == "Total")
    }

    @Test func anotherMainCurrencyMovesTheTotal() {
        var books = books
        books.device.baseCurrency = "USD"
        let hero = AccountsHero(data: books.data)
        #expect(hero.currency == "USD")
        // 59 816,72 ₽ at 88 ₽ a dollar.
        #expect(hero.totalMinor == 67_974)
        #expect(hero.total == "680 $") // 679,74 $, as the others line elsewhere rounds it (D61)
        #expect(hero.others == "1\u{202F}813 ₾ · 59\u{202F}817 ₽")
        // The bank's label follows the main currency too.
        #expect(AccountsContent(data: books.data, today: F.today).sections[1].label == "Мультивалютная · 205 $")
    }

    @Test func theDearestDebtAgainstTheBestSavingsInBothLanguages() {
        let hero = books.content.hero
        #expect(hero.advice == .payOffInsteadOfSaving(debt: "Кредитка", debtRate: 29.9, savings: "Накопительный", savingsRate: 12))
        // The percent sign keeps to its number with a no-break space.
        #expect(hero.adviceText(in: F.ru) == "«Кредитка» стоит 29,9\u{00A0}% — дороже, чем приносит «Накопительный» (12\u{00A0}%). Лишние деньги выгоднее пустить на него.")
        #expect(hero.adviceText(in: F.en) == "“Кредитка” costs 29,9\u{00A0}%, more than “Накопительный” earns (12\u{00A0}%). Spare money does more paying it off.")
    }

    @Test func savingsThatEarnMoreThanTheDebtsCost() {
        var books = books
        books.savings.interestRate = 35.27
        let hero = AccountsHero(data: books.data)
        // One decimal at most, as Android's `Fmt.number(rate, 1)`.
        #expect(hero.adviceText(in: F.ru) == "«Накопительный» приносит 35,3\u{00A0}%, больше ставки по долгам. Досрочно гасить невыгодно.")
        #expect(hero.adviceText(in: F.en) == "“Накопительный” earns 35,3\u{00A0}%, more than your debts cost. Paying early does not pay.")
    }

    @Test func severalDebtsAndNoSavingsPayTheDearestFirst() {
        var books = books
        books.savings.interestRate = nil
        let hero = AccountsHero(data: books.data)
        #expect(hero.adviceText(in: F.ru) == "Сначала гаси «Кредитка»: у него самая высокая ставка, 29,9\u{00A0}%.")
        #expect(hero.adviceText(in: F.en) == "Pay off “Кредитка” first: it has the highest rate, 29,9\u{00A0}%.")
    }

    @Test func oneDebtAndNoSavingsIsNothingToSay() {
        var books = books
        books.savings.interestRate = nil
        let accounts = books.accounts.filter { $0.id != books.loan.id }
        #expect(AccountsHero(data: books.data(accounts: accounts)).adviceText(in: F.ru) == nil)
    }

    @Test func theSectionsCarryABanksLabelWithWhatItIsWorth() {
        let sections = books.content.sections
        #expect(sections.map(\.label) == [nil, "Мультивалютная · 18\u{202F}057 ₽", nil])
        #expect(sections.map { $0.rows.map(\.name) } == [
            ["Карта ₽", "Накопительный"],
            ["Мультивалютная USD", "Мультивалютная GEL"],
            ["Наличные ₾", "Кредитка", "Кредит"],
        ])
        #expect(Set(sections.map(\.id)).count == 3)
        // "+ Счёт" closes the last plain list.
        #expect(books.content.addRowJoinsLastSection)
    }

    @Test func afterABankTheAddRowStandsAlone() {
        let accounts = [books.card, books.usd, books.gel]
        let content = AccountsContent(data: books.data(accounts: accounts), today: F.today)
        #expect(content.sections.map(\.label) == [nil, "Мультивалютная · 18\u{202F}057 ₽"])
        #expect(!content.addRowJoinsLastSection)
        // And with no accounts at all.
        #expect(!AccountsContent(data: books.data(accounts: [], operations: []), today: F.today).addRowJoinsLastSection)
    }

    @Test func aGroupOfOneShowsNoLabel() {
        let accounts = [books.card, books.usd, books.cash]
        let content = AccountsContent(data: books.data(accounts: accounts), today: F.today)
        #expect(content.sections.count == 1)
        #expect(content.sections[0].label == nil)
        #expect(content.sections[0].rows.map(\.name) == ["Карта ₽", "Мультивалютная USD", "Наличные ₾"])
    }

    // MARK: Rows and sublines

    @Test func aPlainAccountInTheMainCurrencySaysItsType() throws {
        let row = try books.row(books.card)
        #expect(row.subline.lead == .type(.card))
        #expect(row.subline.approxBase == nil)
        #expect(row.subline.text(in: F.ru) == "Карта")
        #expect(row.subline.text(in: F.en) == "Card")
        #expect(row.balance == "1\u{202F}600 ₽")
        #expect(row.isInBudget)
        #expect(try books.row(books.credit).subline.text(in: F.ru) == "Кредитка")
        #expect(try books.row(books.credit).subline.text(in: F.en) == "Credit card")
        #expect(try books.row(books.credit).balance == "−15\u{202F}000 ₽")
        #expect(try !books.row(books.credit).isInBudget)
        #expect(try books.row(books.loan).subline.text(in: F.ru) == "Кредит")
        #expect(try books.row(books.loan).subline.text(in: F.en) == "Loan")
    }

    /// D62: a credit card with a limit says what is left to spend on it, or how far past it it is.
    @Test func aCreditCardWithALimitSaysWhatIsAvailable() throws {
        var books = books
        books.credit.creditLimitMinor = 15_000_000
        let row = try books.row(books.credit)
        #expect(row.subline.credit == CreditLine(limitMinor: 15_000_000, availableMinor: 13_500_000))
        #expect(row.subline.text(in: F.ru) == "Кредитка · доступно 135\u{202F}000 ₽")
        #expect(row.subline.text(in: F.en) == "Credit card · 135\u{202F}000 ₽ available")
        #expect(row.accessibilityLabel(in: F.en).contains("135000 Russian rubles available"))

        books.credit.creditLimitMinor = 1_000_000
        let over = try books.row(books.credit)
        #expect(over.subline.text(in: F.ru) == "Кредитка · сверх лимита 5\u{202F}000 ₽")
        #expect(over.subline.text(in: F.en) == "Credit card · 5\u{202F}000 ₽ over the limit")
        // The balance is still the debt; the limit is not money.
        #expect(over.balance == "−15\u{202F}000 ₽")
    }

    @Test func aForeignAccountAddsItsWorthInTheMainCurrency() throws {
        let usd = try books.row(books.usd)
        #expect(usd.subline.approxBase == "9\u{202F}200 ₽")
        #expect(usd.subline.text(in: F.ru) == "Карта · ≈ 9\u{202F}200 ₽")
        #expect(usd.subline.text(in: F.en) == "Card · ≈ 9\u{202F}200 ₽")
        #expect(usd.balance == "100 $")
        #expect(try books.row(books.gel).subline.text(in: F.ru) == "Карта · ≈ 8\u{202F}857 ₽")
        #expect(try books.row(books.cash).subline.text(in: F.ru) == "Наличные · ≈ 5\u{202F}160 ₽")
        #expect(try books.row(books.cash).subline.text(in: F.en) == "Cash · ≈ 5\u{202F}160 ₽")
        #expect(try books.row(books.cash).balance == "172 ₾")
    }

    @Test func savingsWithARateSayWhatTheyEarnThisMonth() throws {
        let row = try books.row(books.savings)
        // 250 000 ₽ at 12 % for October's 31 days: 2 547,95 ₽.
        guard case .interest(let forecast) = row.subline.lead else {
            Issue.record("no forecast: \(row.subline)")
            return
        }
        #expect(forecast.amount == "2\u{202F}548 ₽")
        #expect(row.subline.text(in: F.ru) == "+2\u{202F}548 ₽ за октябрь")
        #expect(row.subline.text(in: F.en) == "+2\u{202F}548 ₽ for October")
        #expect(!row.isInBudget)
    }

    @Test func savingsWithoutARateSayTheirType() throws {
        var books = books
        books.savings.interestRate = nil
        let row = try books.row(books.savings)
        #expect(row.subline.lead == .type(.savings))
        #expect(row.subline.text(in: F.ru) == "Накопительный")
        #expect(row.subline.text(in: F.en) == "Savings")
    }

    @Test func foreignSavingsEarnInTheirOwnCurrencyAndShowTheMainOnesWorth() throws {
        let dollars = Account(name: "Вклад $", currency: "USD", type: .savings, includeInFree: false, interestRate: 5, sort: 7)
        let operations = books.operations + [
            HomeFixture.operation(.opening, at: HomeFixture.at(books.september1, hour: 8), [(dollars, 100_000, 8_000_000)]),
        ]
        let data = books.data(accounts: books.accounts + [dollars], operations: operations)
        let row = try books.row(dollars, in: data)
        // 1 000 $ at 5 % for 31 days: 4,25 $, written with one decimal and the tie to even.
        #expect(row.subline.text(in: F.ru) == "+4,2 $ за октябрь · ≈ 80\u{202F}000 ₽")
        #expect(row.subline.text(in: F.en) == "+4,2 $ for October · ≈ 80\u{202F}000 ₽")
    }

    @Test func aRubleAccountShowsItsWorthWhenTheMainCurrencyIsAnother() throws {
        var books = books
        books.device.baseCurrency = "USD"
        let data = books.data
        #expect(try books.row(books.card, in: data).subline.text(in: F.ru) == "Карта · ≈ 18,2 $")
        #expect(try books.row(books.usd, in: data).subline.approxBase == nil)
    }

    @Test func theCentsGoQuiet() {
        let balance = AccountRowView.quietCents("78,01 $")
        let runs = balance.runs.map { String(balance[$0.range].characters) }
        #expect(runs == ["78", ",01", " $"])
        #expect(String(AccountRowView.quietCents("9\u{202F}101 ₽").characters) == "9\u{202F}101 ₽")
    }

    @Test func voiceOverReadsTheRowWithAmountsInWords() throws {
        let english = try books.row(books.usd).accessibilityLabel(in: F.en)
        #expect(english.hasPrefix("Мультивалютная USD, Counts in “Safe to spend today”, Card, about 9200 Russian rubles, "))
        #expect(english.localizedCaseInsensitiveContains("100 US dollars"))
        #expect(!english.contains("\u{202F}"))

        let russian = try books.row(books.savings).accessibilityLabel(in: F.ru)
        #expect(russian.hasPrefix("Накопительный, +"))
        #expect(russian.contains("за октябрь"))
        #expect(!russian.contains("Входит"))
        #expect(!russian.contains("₽"))
    }

    @Test func voiceOverReadsTheHeroAsSentences() {
        let label = books.content.hero.accessibilityLabel(in: F.en)
        #expect(label.hasPrefix("Total. 59817 Russian rubles. "))
        #expect(label.localizedCaseInsensitiveContains("lari"))
        #expect(label.hasSuffix("Spare money does more paying it off."))
    }

    // MARK: Interest month

    @Test func theMonthStandsAlone() {
        #expect(InterestForecast.monthName(LocalDate(2026, 10, 2), locale: F.ru) == "октябрь")
        #expect(InterestForecast.monthName(LocalDate(2026, 5, 31), locale: F.ru) == "май")
        #expect(InterestForecast.monthName(LocalDate(2026, 10, 2), locale: F.en) == "October")
    }
}

/// Reconcile mode's round: each account ticked once, and done when all are.
@Suite struct ReconcileRoundTests {
    @Test func theRoundEndsWhenEveryAccountIsChecked() {
        let books = AccountsFixture()
        var round = ReconcileRound()
        #expect(!round.isComplete(books.accounts))
        #expect(!round.isChecked(books.card.id))

        round.check(books.card.id, matched: true)
        #expect(round.isChecked(books.card.id))
        #expect(round.checked[books.card.id] == true)
        #expect(!round.isComplete(books.accounts))

        for account in books.accounts.dropFirst() { round.check(account.id, matched: account.id != books.cash.id) }
        #expect(round.isComplete(books.accounts))
        // A balance typed in that differed is checked all the same.
        #expect(round.checked[books.cash.id] == false)
        #expect(round.isChecked(books.cash.id))
    }

    @Test func checkingAgainKeepsTheLastAnswer() {
        let id = UUID()
        var round = ReconcileRound()
        round.check(id, matched: false)
        round.check(id, matched: true)
        #expect(round.checked == [id: true])
    }

    @Test func nothingToCheckIsNoRound() {
        #expect(!ReconcileRound().isComplete([]))
    }
}
