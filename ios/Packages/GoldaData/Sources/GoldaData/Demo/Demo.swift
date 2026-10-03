import Foundation
import GoldaCore

/// Debug-only shortcuts so the app can be tried without tapping through onboarding, the port of
/// Android's `Demo`. All names and numbers here are made up.
///
/// BOTH ENTRY POINTS ERASE EVERYTHING FIRST (`Repository.resetAll`: every profile, the rates, the
/// API keys and this phone's settings) and then build one new profile, named by the caller, that
/// holds all of the demo's books. Never call them from a release path. The launch-argument hook
/// (`-golda.demo`, `-golda.samples`, `-golda.reset`) is added in stage 2a, when the app has a
/// composition root to run it from.
///
/// Time is the repository's own clock and time zone, so a test that fixes them gets the same data
/// every run: operations are laid out backwards from "now", and the opening balances, wishes and
/// the credit card's grace period use the same instant.
public enum Demo {
    /// The profile every entry point creates unless told otherwise; onboarding's name too.
    public static let defaultProfileName = "Личный"

    /// A made-up person: paid by the hour, a ruble card, savings, a multi-currency card abroad, cash
    /// and two debts. Accounts have their opening balances and nothing else is recorded. Returns
    /// the new profile, which is also the active one on this phone.
    @discardableResult
    public static func fill(_ repo: Repository, profileName: String = defaultProfileName) async throws -> UUID {
        try await seed(repo, profileName: profileName).profileId
    }

    /// [fill] plus a couple of weeks of made-up life abroad, obligations, goals and a wishlist, so
    /// the screens look lived in. Returns the new profile.
    @discardableResult
    public static func samples(_ repo: Repository, profileName: String = defaultProfileName) async throws -> UUID {
        let books = try await seed(repo, profileName: profileName)
        let profile = books.profileId
        let now = repo.clock()
        let hour: Int64 = 3_600_000
        let day = 24 * hour

        let rub = books.account("Карта ₽")
        let savings = books.account("Накопительный")
        let usd = books.account("Мультивалютная USD")
        let gel = books.account("Мультивалютная GEL")
        let cash = books.account("Наличные ₾")

        func expense(_ at: Int64, _ from: Account, _ minor: Int64, _ key: String, _ note: String = "") -> Draft {
            Draft(type: .expense, timestamp: at, accountId: from.id, amountMinor: minor, categoryKey: key, note: note)
        }

        // Pay arrives in rubles: half goes to savings, 800 $ go abroad for 73 600 ₽, and part of
        // that into lari and cash.
        let start: [Draft] = [
            Draft(type: .income, timestamp: now - 12 * day, accountId: rub.id, amountMinor: 15_840_000, categoryKey: "salary"),
            Draft(
                type: .transfer, timestamp: now - 12 * day + hour, accountId: rub.id, amountMinor: 8_000_000,
                toAccountId: savings.id, toAmountMinor: 8_000_000, note: "В подушку"
            ),
            Draft(
                type: .transfer, timestamp: now - 12 * day + 2 * hour, accountId: rub.id, amountMinor: 7_360_000,
                toAccountId: usd.id, toAmountMinor: 80_000, note: "Перевод за границу"
            ),
            Draft(
                type: .transfer, timestamp: now - 11 * day, accountId: usd.id, amountMinor: 60_000,
                toAccountId: gel.id, toAmountMinor: 160_800, note: "Обмен в приложении банка"
            ),
            Draft(
                type: .transfer, timestamp: now - 10 * day, accountId: usd.id, amountMinor: 10_000,
                toAccountId: cash.id, toAmountMinor: 26_500, note: "Банкомат"
            ),
            expense(now - 10 * day, usd, 300, "fees", "Комиссия банкомата"),
        ]
        for draft in start { try await repo.save(draft, profileId: profile) }

        let days: [Draft] = [
            expense(now - 9 * day, gel, 90_000, "housing", "Аренда"),
            expense(now - 9 * day, rub, 69_900, "subscriptions", "Музыка и облако"),
            expense(now - 8 * day, gel, 6_420, "groceries", "Продукты"),
            expense(now - 8 * day, cash, 1_500, "eating_out", "Хачапури"),
            expense(now - 7 * day, gel, 3_500, "telecom", "Мобильный интернет"),
            expense(now - 7 * day, cash, 800, "transport", "Метро"),
            expense(now - 6 * day, gel, 4_800, "eating_out", "Ужин"),
            expense(now - 5 * day, gel, 8_960, "groceries", "Продукты"),
            expense(now - 5 * day, cash, 2_000, "fun", "Музей"),
            expense(now - 4 * day, gel, 1_200, "transport", "Такси"),
            expense(now - 3 * day, gel, 12_500, "clothes", "Куртка"),
            expense(now - 3 * day, cash, 900, "eating_out", "Кофе"),
            expense(now - 2 * day, gel, 5_230, "groceries", "Продукты"),
            expense(now - 1 * day, gel, 4_500, "health", "Аптека"),
            expense(now - 1 * day, cash, 1_800, "eating_out", "Обед"),
            expense(now - 3 * hour, cash, 1_500, "eating_out", "Шаурма"),
            expense(now - 1 * hour, cash, 800, "eating_out", "Кофе"),
        ]
        for draft in days { try await repo.save(draft, profileId: profile) }
        // A purchase in lari charged to the dollar card: the charge is the app's estimate.
        try await repo.save(
            Draft(
                type: .expense, timestamp: now - day - 4 * hour, accountId: usd.id, amountMinor: 1_899,
                categoryKey: "groceries", note: "Рынок", purchaseAmountMinor: 4_850, purchaseCurrency: "GEL",
                isEstimate: true
            ),
            profileId: profile
        )

        try await repo.saveObligation(Obligation(name: "Аренда", amountMinor: 90_000, currency: "GEL", dayOfMonth: 1), profileId: profile)
        try await repo.saveObligation(Obligation(name: "Подписки", amountMinor: 69_900, currency: "RUB", dayOfMonth: 1), profileId: profile)

        try await repo.saveGoal(
            Goal(name: "Велосипед", targetMinor: 8_000_000, currency: "RUB", savedMinor: 2_150_000, isMain: true),
            profileId: profile
        )
        try await repo.saveGoal(
            Goal(name: "Подушка", targetMinor: 30_000_000, currency: "RUB", accountId: savings.id),
            profileId: profile
        )
        try await repo.skip(Consider(title: "Кроссовки", amountMinor: 25_000, currency: "GEL"), profileId: profile)
        try await repo.think(Consider(title: "Наушники", amountMinor: 12_000, currency: "USD"), profileId: profile)
        return profile
    }

    /// What the two entry points share: erase, create the profile, set the phone up and open the
    /// accounts. Returns the profile and its accounts by name.
    private static func seed(_ repo: Repository, profileName: String) async throws -> Books {
        try await repo.resetAll()
        // The profile's part of the settings comes from the domain's defaults plus what is made up here.
        let income = Settings(incomeHourly: true, hourlyRate: 1000, taxPercent: 10, hoursPerWeek: 40, payday: 10)
        let profile = try await repo.createProfile(name: profileName, settings: ProfileSettings(from: income)).id
        repo.deviceSettings.update {
            $0.onboarded = true
            $0.activeProfileId = profile
            $0.displayCurrencies = ["RUB", "USD", "GEL"]
            $0.localCurrency = "GEL"
        }

        let now = repo.clock()
        let today = LocalDate(epochMillis: now, in: repo.zone())
        let accounts: [(account: Account, openingMinor: Int64?)] = [
            (Account(name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true, sort: 0), 500_000),
            (
                Account(name: "Накопительный", currency: "RUB", type: .savings, includeInFree: false, interestRate: 12.0, sort: 1),
                25_000_000
            ),
            (
                Account(
                    name: "Мультивалютная USD", currency: "USD", type: .card, groupName: "Мультивалютная", includeInFree: true,
                    sort: 2
                ),
                nil
            ),
            (
                Account(
                    name: "Мультивалютная GEL", currency: "GEL", type: .card, groupName: "Мультивалютная", includeInFree: true,
                    sort: 3
                ),
                nil
            ),
            (Account(name: "Наличные ₾", currency: "GEL", type: .cash, includeInFree: true, sort: 4), nil),
            (
                Account(
                    name: "Кредитка", currency: "RUB", type: .credit, includeInFree: false, interestRate: 29.9, sort: 5,
                    paymentDay: 25, paymentMinor: 300_000, graceUntil: Int64(today.plusDays(40).epochDay)
                ),
                -1_500_000
            ),
            (
                Account(
                    name: "Кредит", currency: "RUB", type: .loan, includeInFree: false, interestRate: 19.9, sort: 6,
                    paymentDay: 5, paymentMinor: 1_000_000
                ),
                -20_000_000
            ),
        ]
        for (account, openingMinor) in accounts {
            try await repo.saveAccount(account, profileId: profile, openingMinor: openingMinor)
        }
        return Books(profileId: profile, accounts: Dictionary(uniqueKeysWithValues: accounts.map { ($0.account.name, $0.account) }))
    }

    private struct Books {
        let profileId: UUID
        let accounts: [String: Account]

        /// The demo's account by its Russian name; a name that is not there is a bug in `Demo`.
        func account(_ name: String) -> Account {
            guard let account = accounts[name] else { preconditionFailure("The demo has no account \(name)") }
            return account
        }
    }
}
