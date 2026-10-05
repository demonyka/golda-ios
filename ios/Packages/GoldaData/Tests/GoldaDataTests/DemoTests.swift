import Foundation
import GoldaCore
import Testing

@testable import GoldaData

/// The debug fill and the sample life, laid out on the harness clock (2026-10-02 10:00 UTC).
@Suite(.timeLimit(.minutes(1))) struct DemoTests {
    let harness: RepositoryHarness
    let now = RepositoryHarness.start
    let day: Int64 = 24 * 3_600_000
    let hour: Int64 = 3_600_000

    init() throws {
        harness = try RepositoryHarness()
    }

    var repository: Repository { harness.repository }

    // MARK: fill

    @Test func fillBuildsTheMadePersonWithOpeningBalancesOnly() async throws {
        let profileId = try await Demo.fill(repository)
        let books = try await harness.snapshot(profileId)
        let states = try await harness.states(profileId)

        #expect(books.profile.name == "Личный")
        #expect(books.accounts.map(\.name) == [
            "Карта ₽", "Накопительный", "Мультивалютная USD", "Мультивалютная GEL", "Наличные ₾", "Кредитка", "Кредит",
        ])
        #expect(books.accounts.map(\.type) == [.card, .savings, .card, .card, .cash, .credit, .loan])
        #expect(books.accounts.map(\.currency) == ["RUB", "RUB", "USD", "GEL", "GEL", "RUB", "RUB"])
        // The debts are on: their payments are set aside, their balances never count (D64).
        #expect(books.accounts.map(\.includeInFree) == [true, false, true, true, true, true, true])
        #expect(books.accounts.map(\.groupName) == [nil, nil, "Мультивалютная", "Мультивалютная", nil, nil, nil])
        #expect(books.accounts.map { states[$0.id]?.balanceMinor } == [500_000, 25_000_000, 0, 0, 0, -1_500_000, -20_000_000])

        // The only things recorded are the four opening balances; the zero ones are not booked.
        #expect(books.operations.count == 4)
        #expect(books.operations.allSatisfy { $0.op.type == .opening })
        #expect(books.obligations.isEmpty && books.goals.isEmpty && books.wishes.isEmpty)

        let savings = try #require(books.accounts.first { $0.type == .savings })
        #expect(savings.interestRate == 12.0)
        let credit = try #require(books.accounts.first { $0.type == .credit })
        #expect(credit.interestRate == 29.9 && credit.paymentDay == 25 && credit.paymentMinor == 300_000)
        #expect(credit.graceUntil == Int64(RepositoryHarness.today.plusDays(40).epochDay))
        let loan = try #require(books.accounts.first { $0.type == .loan })
        #expect(loan.interestRate == 19.9 && loan.paymentDay == 5 && loan.paymentMinor == 1_000_000)
    }

    @Test func fillSetsTheProfileAndThePhoneUp() async throws {
        let profileId = try await Demo.fill(repository)
        let settings = try await harness.profileSettings(profileId)

        #expect(settings.incomeHourly)
        #expect(settings.hourlyRate == 1000 && settings.taxPercent == 10 && settings.hoursPerWeek == 40)
        #expect(settings.payday == 10)
        // What the demo does not name keeps the domain's default.
        #expect(settings.markup == Settings().markup && settings.monthlySalary == Settings().monthlySalary)

        let device = harness.device.current
        #expect(device.onboarded)
        #expect(device.activeProfileId == profileId)
        #expect(device.displayCurrencies == ["RUB", "USD", "GEL"])
        #expect(device.localCurrency == "GEL")

        let composed = try await repository.settings(profileId: profileId)
        #expect(composed.payday == 10 && composed.localCurrency == "GEL" && composed.hourNet == 900)
    }

    @Test func theProfileNameIsTheCallers() async throws {
        let profileId = try await Demo.fill(repository, profileName: "Семья")
        #expect(try await harness.snapshot(profileId).profile.name == "Семья")
        let samples = try await Demo.samples(repository, profileName: "Компания")
        #expect(try await harness.snapshot(samples).profile.name == "Компания")
    }

    @Test func fillErasesWhatWasThereFirst() async throws {
        let old = try await harness.profile("Старый", accounts: [RepositoryLedgerTests.rubCard])
        _ = try await harness.profile("Ещё один")
        try await repository.save(
            Draft(type: .expense, timestamp: 1, accountId: RepositoryLedgerTests.rubCard.id, amountMinor: 100), profileId: old
        )
        try harness.secrets.write("AIza-test-key", for: SecretKey.gemini)
        harness.device.update { $0.voiceConsent = true }

        let profileId = try await Demo.fill(repository)

        let profiles = try await harness.database.read { try $0.profiles() }
        #expect(profiles.map(\.id) == [profileId])
        #expect(try await harness.database.read { try $0.snapshot(profileId: old) } == nil)
        #expect(harness.secrets.read(SecretKey.gemini) == nil)
        #expect(!harness.device.current.voiceConsent)
    }

    // MARK: samples

    @Test func samplesLayOutAFortnightAbroad() async throws {
        let profileId = try await Demo.samples(repository)
        let books = try await harness.snapshot(profileId)
        let states = try await harness.states(profileId)

        func count(_ type: OpType) -> Int { books.operations.filter { $0.op.type == type }.count }
        #expect(count(.opening) == 4)
        #expect(count(.income) == 1)
        #expect(count(.transfer) == 4)
        #expect(count(.expense) == 19)
        #expect(books.operations.count == 28)

        let balances = Dictionary(uniqueKeysWithValues: books.accounts.map { ($0.name, states[$0.id]?.balanceMinor) })
        #expect(balances["Карта ₽"] == 910_100)
        #expect(balances["Накопительный"] == 33_000_000)
        #expect(balances["Мультивалютная USD"] == 7_801)
        #expect(balances["Мультивалютная GEL"] == 23_690)
        #expect(balances["Наличные ₾"] == 17_200)
        #expect(balances["Кредитка"] == -1_500_000)
        #expect(balances["Кредит"] == -20_000_000)

        // Newest first: the last coffee an hour ago, then the shawarma, and so on back to the pay. The
        // opening balances were booked at "now", ahead of all of them.
        let lived = books.operations.filter { $0.op.type != .opening }
        #expect(Array(lived.map(\.op.note).prefix(2)) == ["Кофе", "Шаурма"])
        let oldest = try #require(lived.last)
        #expect(oldest.op.type == .income && oldest.op.timestamp == now - 12 * day)
        #expect(oldest.op.categoryKey == "salary")
        // Every category is a key, never an id.
        let keys = Set(Category.builtIn.map(\.key))
        #expect(books.operations.compactMap(\.op.categoryKey).allSatisfy(keys.contains))

        // Both fall on the 1st, so the snapshot's tiebreak (the random id) decides their order.
        let obligations = Dictionary(uniqueKeysWithValues: books.obligations.map { ($0.name, $0) })
        #expect(Set(obligations.keys) == ["Аренда", "Подписки"])
        #expect(obligations["Аренда"].map { [$0.amountMinor, Int64($0.dayOfMonth)] } == [90_000, 1])
        #expect(obligations["Аренда"]?.currency == "GEL")
        #expect(obligations["Подписки"].map { [$0.amountMinor, Int64($0.dayOfMonth)] } == [69_900, 1])
        #expect(obligations["Подписки"]?.currency == "RUB")
    }

    @Test func theDollarCardCarriesWhatItCost() async throws {
        let profileId = try await Demo.samples(repository)
        let books = try await harness.snapshot(profileId)
        let usd = try #require(books.accounts.first { $0.name == "Мультивалютная USD" })
        let rubCard = try #require(books.accounts.first { $0.name == "Карта ₽" })

        // "800 $ go abroad for 73 600 ₽": 92 ₽ a dollar, whatever the CBR rate says.
        let abroad = try #require(books.operations.first { $0.op.note == "Перевод за границу" })
        #expect(abroad.postings.map(\.accountId) == [rubCard.id, usd.id])
        #expect(abroad.postings.map(\.amountMinor) == [-7_360_000, 80_000])
        #expect(abroad.postings.map(\.rubMinor) == [-7_360_000, 7_360_000])

        // Every later dollar leaves at that average, so the last 78.01 $ still cost 92 ₽ each.
        let state = try await harness.state(usd.id, profileId)
        #expect(state.balanceMinor == 7_801)
        #expect(state.rubMinor == 717_692)
        expectClose(try #require(state.costBasis), 92, 0.0001)
    }

    @Test func theCashCarriesTheCostOfTheAtmDollars() async throws {
        let profileId = try await Demo.samples(repository)
        let books = try await harness.snapshot(profileId)
        let usd = try #require(books.accounts.first { $0.name == "Мультивалютная USD" })
        let cash = try #require(books.accounts.first { $0.name == "Наличные ₾" })

        // 100 $ at 92 ₽ (9 200 ₽) became 265 ₾.
        let atm = try #require(books.operations.first { $0.op.note == "Банкомат" })
        #expect(atm.postings.map(\.accountId) == [usd.id, cash.id])
        #expect(atm.postings.map(\.amountMinor) == [-10_000, 26_500])
        #expect(atm.postings.map(\.rubMinor) == [-920_000, 920_000])
        // A lari from the machine cost 34.72 ₽, and it still does after the spending.
        expectClose(try #require(try await harness.state(cash.id, profileId).costBasis), 34.716, 0.01)
    }

    @Test func theExchangeRemembersBothOfficialRates() async throws {
        let profileId = try await Demo.samples(repository)
        let books = try await harness.snapshot(profileId)
        let gel = try #require(books.accounts.first { $0.name == "Мультивалютная GEL" })

        let exchange = try #require(books.operations.first { $0.op.note == "Обмен в приложении банка" })
        // 600 $ at 92 ₽ became 1 608 ₾.
        #expect(exchange.postings.map(\.rubMinor) == [-5_520_000, 5_520_000])
        #expect(exchange.postings.last?.accountId == gel.id)
        #expect(exchange.op.cbrFrom == 83.2454 && exchange.op.cbrTo == 31.9597)
        // Paying 73 600 ₽ for 800 $ at a CBR rate of 83.2454 taught the profile its markup.
        let markup = try await harness.profileSettings(profileId).markup
        expectClose(markup, 92 / 83.2454 - 1, 0.000_001)
    }

    @Test func aLariPurchaseOnTheDollarCardIsAnEstimate() async throws {
        let profileId = try await Demo.samples(repository)
        let books = try await harness.snapshot(profileId)

        let market = try #require(books.operations.first { $0.op.note == "Рынок" })
        #expect(market.op.purchaseAmountMinor == 4_850 && market.op.purchaseCurrency == "GEL")
        #expect(market.op.isEstimate)
        #expect(market.op.timestamp == now - day - 4 * hour)
        #expect(market.postings.map(\.amountMinor) == [-1_899])
        #expect(market.postings.map(\.rubMinor) == [-174_708])
    }

    @Test func samplesHaveGoalsAndAWishlist() async throws {
        let profileId = try await Demo.samples(repository)
        let books = try await harness.snapshot(profileId)
        let savings = try #require(books.accounts.first { $0.name == "Накопительный" })

        #expect(books.goals.map(\.name) == ["Велосипед", "Подушка"])
        let bike = books.goals[0]
        #expect(bike.isMain && bike.targetMinor == 8_000_000 && bike.currency == "RUB")
        // The skipped sneakers stay out of it (D63).
        #expect(bike.savedMinor == 2_150_000)
        let pillow = books.goals[1]
        #expect(!pillow.isMain && pillow.accountId == savings.id && pillow.targetMinor == 30_000_000 && pillow.savedMinor == 0)

        #expect(books.wishes.count == 2)
        let sneakers = try #require(books.wishes.first { $0.title == "Кроссовки" })
        #expect(sneakers.status == .skipped && sneakers.amountMinor == 25_000 && sneakers.currency == "GEL")
        #expect(sneakers.decidedAt == now)
        let headphones = try #require(books.wishes.first { $0.title == "Наушники" })
        #expect(headphones.status == .waiting && headphones.amountMinor == 12_000 && headphones.currency == "USD")
        #expect(headphones.decidedAt == nil && headphones.decideAt > now)
    }

    // MARK: Twice, and ownership

    @Test func samplesTwiceInARowGiveTheSameResult() async throws {
        let first = try await Demo.samples(repository)
        let firstShape = Self.shape(try await harness.snapshot(first))
        let firstDevice = harness.device.current

        let second = try await Demo.samples(repository)
        let secondShape = Self.shape(try await harness.snapshot(second))

        // Same books, new rows: the first run was erased, not added to.
        #expect(first != second)
        #expect(firstShape == secondShape)
        let profiles = try await harness.database.read { try $0.profiles() }
        #expect(profiles.map(\.id) == [second])
        #expect(try await harness.database.read { try $0.snapshot(profileId: first) } == nil)
        #expect(try await harness.database.read { try $0.operations(profileId: first) }.isEmpty)
        #expect(harness.device.current.activeProfileId == second)
        #expect(harness.device.current.displayCurrencies == firstDevice.displayCurrencies)
    }

    @Test func fillAfterSamplesLeavesNoOperationsBehind() async throws {
        try await Demo.samples(repository)
        let profileId = try await Demo.fill(repository)
        let books = try await harness.snapshot(profileId)
        #expect(books.operations.count == 4 && books.operations.allSatisfy { $0.op.type == .opening })
        #expect(books.obligations.isEmpty && books.goals.isEmpty && books.wishes.isEmpty)
    }

    @Test func everyRowBelongsToTheDemoProfile() async throws {
        try await Demo.samples(repository)
        let profileId = try await Demo.samples(repository)
        let books = try await harness.snapshot(profileId)

        let rows = try await harness.database.writer.read { db in
            (
                profiles: try ProfileRecord.fetchAll(db).map(\.id),
                accounts: try AccountRecord.fetchAll(db).map(\.profileId),
                operations: try OperationRecord.fetchAll(db).map(\.profileId),
                postings: try PostingRecord.fetchAll(db).map(\.profileId),
                obligations: try ObligationRecord.fetchAll(db).map(\.profileId),
                goals: try GoalRecord.fetchAll(db).map(\.profileId),
                wishes: try WishRecord.fetchAll(db).map(\.profileId)
            )
        }
        #expect(rows.profiles == [profileId])
        // The counts match the snapshot's, so nothing of the first run is left, and no row is anyone else's.
        #expect(rows.accounts.count == books.accounts.count && rows.accounts.allSatisfy { $0 == profileId })
        #expect(rows.operations.count == books.operations.count && rows.operations.allSatisfy { $0 == profileId })
        let postingCount = books.operations.reduce(0) { $0 + $1.postings.count }
        #expect(rows.postings.count == postingCount && rows.postings.allSatisfy { $0 == profileId })
        #expect(rows.obligations.count == 2 && rows.obligations.allSatisfy { $0 == profileId })
        #expect(rows.goals.count == 2 && rows.goals.allSatisfy { $0 == profileId })
        #expect(rows.wishes.count == 2 && rows.wishes.allSatisfy { $0 == profileId })
        // Every posting is on an account of the profile.
        let accountIds = Set(books.accounts.map(\.id))
        #expect(books.operations.flatMap(\.postings).allSatisfy { accountIds.contains($0.accountId) })
    }

    /// The books without their random ids, line by line, so two runs compare and a difference reads.
    static func shape(_ books: ProfileSnapshot) -> [String] {
        let names = Dictionary(uniqueKeysWithValues: books.accounts.map { ($0.id, $0.name) })
        var lines = ["profile \(books.profile.name) sort=\(books.profile.sort) \(books.profile.settings)"]
        for account in books.accounts {
            var account = account
            account.id = .zero
            lines.append("account \(account)")
        }
        for full in books.operations {
            var op = full.op
            op.id = .zero
            let postings = full.postings.map { "\(names[$0.accountId] ?? "?") \($0.amountMinor) \($0.rubMinor)" }
            lines.append("operation \(op) \(postings)")
        }
        // Same-day obligations come in the order they were created, whatever their random ids.
        for obligation in books.obligations {
            var obligation = obligation
            obligation.id = .zero
            lines.append("obligation \(obligation)")
        }
        for goal in books.goals {
            var goal = goal
            let account = goal.accountId.flatMap { names[$0] } ?? "-"
            goal.id = .zero
            goal.accountId = nil
            lines.append("goal \(goal) account=\(account)")
        }
        for wish in books.wishes {
            var wish = wish
            wish.id = .zero
            lines.append("wish \(wish)")
        }
        return lines
    }
}
