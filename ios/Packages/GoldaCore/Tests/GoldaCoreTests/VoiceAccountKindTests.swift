import Foundation
import Testing

@testable import GoldaCore

/// D65: «с карты», «наличкой», «с кредитки» name a kind of account, not one; the code picks the one
/// of that kind in the money said. A person with a ruble card and a lari card says «шаурма 15 лари с
/// карты» and means the lari one, and «подписка 100 рублей с карты» the ruble one.
@Suite struct VoiceAccountKindTests {
    let rates = Rates(["USD": 83.2454, "GEL": 31.9597, "THB": 2.47438], markup: 0.10)
    let rubCard = Account(id: uid(1), name: "Т-Банк", currency: "RUB", type: .card, includeInFree: true, sort: 0)
    let gelCard = Account(id: uid(2), name: "TBC", currency: "GEL", type: .card, includeInFree: true, sort: 1)
    let multiUsd = Account(id: uid(3), name: "Мультивалютная USD", currency: "USD", type: .card, groupName: "Мультивалютная", includeInFree: true, sort: 2)
    let multiGel = Account(id: uid(4), name: "Мультивалютная GEL", currency: "GEL", type: .card, groupName: "Мультивалютная", includeInFree: true, sort: 3)
    let cash = Account(id: uid(5), name: "Наличные", currency: "GEL", type: .cash, includeInFree: true, sort: 4)
    let credit = Account(id: uid(6), name: "Кредитка", currency: "RUB", type: .credit, includeInFree: true, sort: 5)
    let savings = Account(id: uid(7), name: "Накопительный", currency: "RUB", type: .savings, includeInFree: false, sort: 6)
    let loan = Account(id: uid(8), name: "Кредит", currency: "RUB", type: .loan, includeInFree: true, sort: 7)
    let now = LocalDate(2026, 10, 2).atTimeMillis(hour: 20, in: utc)

    var accounts: [Account] { [rubCard, gelCard, multiUsd, multiGel, cash, credit, savings, loan] }

    func settings(last: Account? = nil) -> Settings {
        Settings(displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL", lastAccountId: last?.id)
    }

    func position(_ account: Account) -> String { String(accounts.firstIndex(of: account)! + 1) }

    func record(
        _ currency: String?, intent: String = "expense", amount: String = "15", kind: String? = nil, named: Account? = nil,
        toKind: String? = nil, to: Account? = nil, accounts: [Account]? = nil, last: Account? = nil
    ) throws -> Draft {
        let list = accounts ?? self.accounts
        func at(_ account: Account?) -> String? { account.flatMap { a in list.firstIndex(of: a).map { String($0 + 1) } } }
        let item = VoiceItem(
            intent: intent, amount: amount, currency: currency, note: "шаурма", accountId: at(named), toAccountId: at(to),
            accountKind: kind, toAccountKind: toKind
        )
        let actions = VoiceMapper.actions(
            VoiceResult(transcript: "…", items: [item]), accounts: list, categories: [], settings: settings(last: last),
            rates: rates, recordedAt: now, zone: utc
        )
        guard case .record(let draft) = actions[0] else { throw Failure() }
        return draft
    }

    struct Failure: Error {}

    @Test func aCardInTheMoneySaid() throws {
        // «шаурма 15 лари с карты» right after paying by the ruble card: the lari card, not cash.
        #expect(try record("GEL", kind: "card", last: rubCard).accountId == gelCard.id)
        // «подписка 100 рублей с карты» right after the lari card: the ruble card.
        #expect(try record("RUB", kind: "card", last: gelCard).accountId == rubCard.id)
        // «такси 20 долларов с карты»: the dollar part of the multi-currency card.
        #expect(try record("USD", kind: "card").accountId == multiUsd.id)
        // No money said: a purchase is in the local money (D44).
        #expect(try record(nil, kind: "card", last: rubCard).accountId == gelCard.id)
    }

    @Test func ofTwoCardsInTheMoneySaidTheLastUsedThenTheFirst() throws {
        #expect(try record("GEL", kind: "card", last: multiGel).accountId == multiGel.id)
        #expect(try record("GEL", kind: "card", last: cash).accountId == gelCard.id)
    }

    @Test func aDebitCardBeforeACreditCardInTheSameMoney() throws {
        #expect(try record("RUB", kind: "card").accountId == rubCard.id)
        // With no debit card in rubles, the credit card is the ruble card there is.
        let noRubCard = accounts.filter { $0 != rubCard }
        #expect(try record("RUB", kind: "card", accounts: noRubCard).accountId == credit.id)
    }

    @Test func cashAndTheCreditCardAndSavingsByTheirWords() throws {
        #expect(try record("GEL", kind: "cash", last: gelCard).accountId == cash.id)
        #expect(try record("RUB", kind: "credit", last: rubCard).accountId == credit.id)
        #expect(try record("RUB", intent: "income", amount: "5000", kind: "savings").accountId == savings.id)
    }

    @Test func noAccountOfTheKindInTheMoneySaidTakesOneOfTheKindAndConverts() throws {
        // «пад тай 80 бат с карты»: no baht card, so the last card used, charged in its money.
        let draft = try record("THB", amount: "80", kind: "card", last: multiUsd)
        #expect(draft.accountId == multiUsd.id)
        #expect(draft.purchaseCurrency == "THB" && draft.isEstimate)
        // Cash in rubles there is not: the lari cash, converted.
        let rubles = try record("RUB", amount: "500", kind: "cash")
        #expect(rubles.accountId == cash.id && rubles.purchaseCurrency == "RUB")
    }

    @Test func aKindWithNoAccountOfItFallsBackToTheUsualPick() throws {
        let noCash = accounts.filter { $0 != cash }
        #expect(try record("GEL", kind: "cash", accounts: noCash, last: rubCard).accountId == gelCard.id)
    }

    @Test func aLoanIsNeverAKindToPayWith() throws {
        // A kind the code does not know is no kind.
        #expect(try record("RUB", kind: "loan", last: gelCard).accountId == rubCard.id)
    }

    @Test func aNamedAccountStaysUnlessItsBankHasThePartInTheMoneySaid() throws {
        // «15 лари с мультивалютной»: the model named the dollar part; the bank's lari part is meant.
        #expect(try record("GEL", named: multiUsd).accountId == multiGel.id)
        // «15 лари с Т-Банка»: a ruble account named by name is paid from, converted.
        let draft = try record("GEL", named: rubCard)
        #expect(draft.accountId == rubCard.id && draft.purchaseCurrency == "GEL")
        // No money said: the named part stays.
        #expect(try record(nil, named: multiUsd).accountId == multiUsd.id)
    }

    @Test func aNamedAccountAndAKindTogetherTrustTheKindsAccountInTheMoneySaid() throws {
        // The model numbered «с карты» as the first card anyway: the lari card is the card in lari.
        #expect(try record("GEL", kind: "card", named: rubCard).accountId == gelCard.id)
        // A named account of the kind in the money said is kept.
        #expect(try record("GEL", kind: "card", named: multiGel).accountId == multiGel.id)
    }

    @Test func aWithdrawalGoesFromTheCardToCashInTheMoneySaid() throws {
        // «снял 100 лари с карты»: from the lari card to the lari cash.
        let draft = try record("GEL", intent: "transfer", amount: "100", kind: "card", toKind: "cash", last: rubCard)
        #expect(draft.accountId == gelCard.id)
        #expect(draft.toAccountId == cash.id)
        #expect(draft.amountMinor == 10_000 && draft.toAmountMinor == 10_000)
        // «положил 500 рублей на накопительный с карты».
        let saved = try record("RUB", intent: "transfer", amount: "500", kind: "card", toKind: "savings")
        #expect(saved.accountId == rubCard.id && saved.toAccountId == savings.id)
    }

    @Test func incomeOnACardInTheMoneySaid() throws {
        #expect(try record("USD", intent: "income", amount: "1000", kind: "card", last: rubCard).accountId == multiUsd.id)
    }
}
