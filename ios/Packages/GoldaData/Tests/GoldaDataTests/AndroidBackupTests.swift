import Foundation
import GoldaCore
import Testing

@testable import GoldaData

/// The Android app's `version: 1` file (`Fixtures/android-backup-v1.json`) imports into one new
/// profile, with the same balances to the kopeck.
@Suite(.timeLimit(.minutes(1))) struct AndroidBackupTests {
    // The fixture's "now": 2026-09-21. Day and hour in milliseconds.
    let now: Int64 = 1_790_000_000_000
    let day: Int64 = 86_400_000
    let hour: Int64 = 3_600_000

    @Test func theFixtureImportsWithTheExpectedCounts() async throws {
        let h = try BackupHarness()
        let summary = try await h.importAndroidFixture()

        let snapshot = try await h.onlySnapshot()
        #expect(snapshot.profile.name == "Личный")
        #expect(summary.sourceVersion == 1)
        #expect(summary.profiles == 1)
        #expect(summary.activeProfileId == snapshot.profile.id)
        #expect(snapshot.accounts.count == 7 && summary.accounts == 7)
        #expect(snapshot.operations.count == 29 && summary.operations == 29)
        #expect(snapshot.postings.count == 33 && summary.postings == 33)
        #expect(snapshot.obligations.count == 3 && summary.obligations == 3)
        #expect(snapshot.goals.count == 3 && summary.goals == 3)
        #expect(snapshot.wishes.count == 3 && summary.wishes == 3)
        let rates = try await h.rates()
        #expect(rates.count == 4 && summary.rates == 4)
    }

    @Test func theProfileIsNamedByTheCaller() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture(name: "Personal")
        #expect(try await h.onlySnapshot().profile.name == "Personal")
    }

    @Test func theImportMakesTheProfileActiveAndOnboards() async throws {
        let h = try BackupHarness()
        #expect(!h.device.current.onboarded)
        let summary = try await h.importAndroidFixture()
        #expect(h.device.current.onboarded)
        #expect(h.device.current.activeProfileId == summary.activeProfileId)
    }

    // MARK: Money

    @Test func everyBalanceAndCostBasisIsTheSumOfItsPostings() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let snapshot = try await h.onlySnapshot()

        // The expectation is computed from the raw file, by Android ids and account names, without
        // going through any of the import's code.
        let file = try BackupFixtures.androidV1Object()
        let fileAccounts = try #require(file["accounts"] as? [[String: Any]])
        let filePostings = try #require(file["postings"] as? [[String: Any]])
        var expected: [String: (amount: Int64, rub: Int64)] = [:]
        for account in fileAccounts {
            let id = try #require(account["id"] as? Int64)
            let mine = filePostings.filter { ($0["accountId"] as? Int64) == id }
            expected[try #require(account["name"] as? String)] = (
                mine.reduce(0) { $0 + (($1["amountMinor"] as? Int64) ?? 0) },
                mine.reduce(0) { $0 + (($1["rubMinor"] as? Int64) ?? 0) }
            )
        }

        let states = Ledger.states(snapshot.accounts, snapshot.postings)
        for account in snapshot.accounts {
            let state = try #require(states[account.id])
            let want = try #require(expected[account.name])
            #expect(state.balanceMinor == want.amount, "balance of \(account.name)")
            #expect(state.rubMinor == want.rub, "cost basis of \(account.name)")
            // And by summing this account's postings directly.
            let own = snapshot.postings.filter { $0.accountId == account.id }
            #expect(own.reduce(0) { $0 + $1.amountMinor } == want.amount)
            #expect(own.reduce(0) { $0 + $1.rubMinor } == want.rub)
        }
        #expect(expected.count == 7)
    }

    @Test func theFixtureBalancesAreWhatTheAndroidLedgerMade() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let snapshot = try await h.onlySnapshot()
        let states = Ledger.states(snapshot.accounts, snapshot.postings)

        // Worked out when the fixture was written, with the ledger's rules (average cost, half up).
        let known: [String: (Int64, Int64)] = [
            "Карта ₽": (910_100, 910_100),
            "Накопительный": (33_000_000, 33_000_000),
            "Мультивалютная USD": (7_801, 717_692),
            "Мультивалютная GEL": (23_690, 813_239),
            "Наличные ₾": (16_900, 586_717),
            "Кредитка": (-1_500_000, -1_500_000),
            "Кредит": (-20_000_000, -20_000_000),
        ]
        for (name, want) in known {
            let state = try #require(states[try snapshot.account(named: name).id])
            #expect(state.balanceMinor == want.0, "balance of \(name)")
            #expect(state.rubMinor == want.1, "cost basis of \(name)")
        }
    }

    @Test func everyPostingSitsOnItsOperationAndOnAnAccountOfTheProfile() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let snapshot = try await h.onlySnapshot()
        let accountIds = Set(snapshot.accounts.map(\.id))

        for full in snapshot.operations {
            #expect(!full.postings.isEmpty)
            for posting in full.postings {
                #expect(posting.operationId == full.op.id)
                #expect(accountIds.contains(posting.accountId))
            }
        }
        // Transfers have two sides, the rest one.
        for full in snapshot.operations {
            #expect(full.postings.count == (full.op.type == .transfer ? 2 : 1), "\(full.op.note)")
        }
        // Every id is its own UUID.
        let ids = snapshot.accounts.map(\.id) + snapshot.operations.map(\.op.id) + snapshot.postings.map(\.id)
            + snapshot.obligations.map(\.id) + snapshot.goals.map(\.id) + snapshot.wishes.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: Fields

    @Test func accountFieldsStayOnTheAccount() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let snapshot = try await h.onlySnapshot()

        let usd = try snapshot.account(named: "Мультивалютная USD")
        let gel = try snapshot.account(named: "Мультивалютная GEL")
        #expect(usd.groupName == "Мультивалютная" && gel.groupName == "Мультивалютная")
        #expect(usd.currency == "USD" && gel.currency == "GEL")
        #expect(usd.type == .card && usd.includeInFree)

        let savings = try snapshot.account(named: "Накопительный")
        #expect(savings.type == .savings && !savings.includeInFree && savings.interestRate == 12.0 && savings.groupName == nil)

        let credit = try snapshot.account(named: "Кредитка")
        #expect(credit.type == .credit && !credit.includeInFree && credit.sort == 5)
        #expect(credit.interestRate == 29.9 && credit.paymentDay == 25 && credit.paymentMinor == 300_000)
        #expect(credit.graceUntil == 20_731)

        let loan = try snapshot.account(named: "Кредит")
        #expect(loan.type == .loan && loan.paymentDay == 5 && loan.paymentMinor == 1_000_000 && loan.graceUntil == nil)

        #expect(snapshot.accounts.map(\.sort) == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test func reconciledAtMovesFromTheSettingsOntoTheAccounts() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let snapshot = try await h.onlySnapshot()

        #expect(try snapshot.account(named: "Карта ₽").reconciledAt == now - day)
        #expect(try snapshot.account(named: "Наличные ₾").reconciledAt == now - 2 * hour)
        for name in ["Накопительный", "Мультивалютная USD", "Мультивалютная GEL", "Кредитка", "Кредит"] {
            #expect(try snapshot.account(named: name).reconciledAt == nil, "\(name)")
        }
    }

    @Test func categoryIdsBecomeKeysThroughTheFilesOwnCategories() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let snapshot = try await h.onlySnapshot()

        #expect(try snapshot.operation(noted: "Аренда").op.categoryKey == "housing")
        #expect(try snapshot.operation(noted: "Комиссия банкомата").op.categoryKey == "fees")
        #expect(try snapshot.operation(noted: "Музыка и облако").op.categoryKey == "subscriptions")
        #expect(snapshot.operations.first { $0.op.type == .income }?.op.categoryKey == "salary")
        // Openings, transfers and adjustments have no category.
        for full in snapshot.operations where [.opening, .transfer, .adjustment].contains(full.op.type) {
            #expect(full.op.categoryKey == nil)
        }
        // Every key is one of the built-in ones.
        let keys = Set(Category.builtIn.map(\.key))
        for full in snapshot.operations { #expect(full.op.categoryKey.map(keys.contains) ?? true) }
    }

    @Test func anOperationInAnotherCurrencyKeepsItsPurchase() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let snapshot = try await h.onlySnapshot()

        let market = try snapshot.operation(noted: "Рынок")
        #expect(market.op.purchaseAmountMinor == 4_850 && market.op.purchaseCurrency == "GEL" && market.op.isEstimate)
        let usd = try snapshot.account(named: "Мультивалютная USD")
        #expect(market.postings.first?.accountId == usd.id)
        #expect(market.postings.first?.amountMinor == -1_899)

        let plain = try snapshot.operation(noted: "Аптека")
        #expect(plain.op.purchaseAmountMinor == nil && plain.op.purchaseCurrency == nil && !plain.op.isEstimate)
    }

    @Test func aTransferKeepsItsOfficialRatesAndBothSides() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let snapshot = try await h.onlySnapshot()

        let abroad = try snapshot.operation(noted: "Перевод за границу")
        #expect(abroad.op.type == .transfer && abroad.op.cbrFrom == 1.0 && abroad.op.cbrTo == 83.25)
        // The source first, then the destination, as the ledger made them.
        let rubles = try snapshot.account(named: "Карта ₽").id
        let dollars = try snapshot.account(named: "Мультивалютная USD").id
        #expect(abroad.postings.map(\.accountId) == [rubles, dollars])
        #expect(abroad.postings.map(\.amountMinor) == [-7_360_000, 80_000])
        #expect(abroad.postings.map(\.rubMinor) == [-7_360_000, 7_360_000])

        let exchange = try snapshot.operation(noted: "Обмен в приложении банка")
        #expect(exchange.op.cbrFrom == 83.25 && exchange.op.cbrTo == 31.96)
    }

    @Test func voiceTextAndAdjustmentsSurvive() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let snapshot = try await h.onlySnapshot()

        let shawarma = try snapshot.operation(noted: "Шаурма")
        #expect(shawarma.op.voiceText == "шаурма пятнадцать лари и кофе восемь лари")
        #expect(snapshot.operations.filter { $0.op.type == .adjustment }.count == 1)
        #expect(snapshot.operations.filter { $0.op.type == .opening }.count == 4)
    }

    @Test func goalsWishesObligationsAndRatesArrive() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let snapshot = try await h.onlySnapshot()

        let bike = try #require(snapshot.goals.first { $0.name == "Велосипед" })
        #expect(bike.isMain && bike.savedMinor == 2_150_000 && bike.targetMinor == 8_000_000 && bike.accountId == nil)
        // Goals point at the new ids of their accounts.
        let cushion = try #require(snapshot.goals.first { $0.name == "Подушка" })
        let savings = try snapshot.account(named: "Накопительный")
        #expect(cushion.accountId == savings.id && !cushion.isMain)
        let trip = try #require(snapshot.goals.first { $0.name == "Отпуск в Грузии" })
        let lari = try snapshot.account(named: "Мультивалютная GEL")
        #expect(trip.accountId == lari.id && trip.currency == "GEL")

        let skipped = try #require(snapshot.wishes.first { $0.status == .skipped })
        #expect(skipped.title == "Кроссовки" && skipped.decidedAt == now - 4 * day && skipped.currency == "GEL")
        let waiting = try #require(snapshot.wishes.first { $0.status == .waiting })
        #expect(waiting.title == "Наушники" && waiting.decidedAt == nil && waiting.decideAt == now + 2 * day)
        #expect(snapshot.wishes.contains { $0.status == .bought && $0.title == "Рюкзак" })

        let rent = try #require(snapshot.obligations.first { $0.name == "Аренда" })
        #expect(rent.amountMinor == 90_000 && rent.currency == "GEL" && rent.dayOfMonth == 1)

        let rates = try await h.rates()
        #expect(rates.map(\.code) == ["EUR", "GEL", "THB", "USD"])
        #expect(rates.first { $0.code == "USD" } == RateRecord(code: "USD", rubPerUnit: 83.25, date: "2026-09-21"))
    }

    // MARK: Orders

    @Test func androidsOrdersSurviveTheNewIds() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let snapshot = try await h.onlySnapshot()

        #expect(snapshot.accounts.map(\.name) == [
            "Карта ₽", "Накопительный", "Мультивалютная USD", "Мультивалютная GEL", "Наличные ₾", "Кредитка", "Кредит",
        ])
        // Two obligations on day 1: the older one first, as Android's `ORDER BY dayOfMonth, id`.
        #expect(snapshot.obligations.map(\.name) == ["Аренда", "Подписки", "Интернет дома"])
        // The main goal first, then by creation (the file lists Android ids 2, 1, 3).
        #expect(snapshot.goals.map(\.name) == ["Велосипед", "Подушка", "Отпуск в Грузии"])
        // BOUGHT, SKIPPED, WAITING.
        #expect(snapshot.wishes.map(\.title) == ["Рюкзак", "Кроссовки", "Наушники"])
        // Newest first.
        let timestamps = snapshot.operations.map(\.op.timestamp)
        #expect(timestamps == timestamps.sorted(by: >))
        // One voice note, two expenses at one moment: the one written last is listed first.
        let coffee = try #require(snapshot.operations.firstIndex { $0.op.note == "Кофе" && $0.op.voiceText != nil })
        let shawarma = try #require(snapshot.operations.firstIndex { $0.op.note == "Шаурма" })
        #expect(coffee < shawarma)
    }

    @Test func mintedIdsKeepTheOrderOfTheNumbers() throws {
        let numbers: [Int64] = [40, 7, 1_000, 3, 12, 99, 1, 500, 8, 2, 64, 33, 21, 5, 18]
        let minted = try IDMint.mint(numbers, "thing")
        #expect(minted.count == numbers.count)
        let ascending = numbers.sorted().map { withUnsafeBytes(of: minted[$0]!.uuid) { Array($0) } }
        #expect(ascending == ascending.sorted { $0.lexicographicallyPrecedes($1) })
        #expect(Set(minted.values).count == numbers.count)
        #expect(throws: BackupError.duplicateId("thing 7")) { try IDMint.mint([7, 8, 7], "thing") }
    }

    @Test func tiesResolveByAndroidIdWhateverOrderTheFileListsThem() async throws {
        // What Android's `ORDER BY ..., id` does with equal keys, shuffled in the file so that only
        // the ids can tell the order: accounts with one `sort`, obligations on one day, operations at
        // one moment.
        let ids: [Int64] = [17, 4, 29, 11, 2, 23, 8, 30, 15, 6, 26, 1, 19, 13, 21, 9, 28, 3, 24, 12]
        let file: [String: Any] = [
            "version": 1, "exportedAt": 0, "settings": [String: Any](),
            "accounts": ids.map { ["id": $0, "name": "a\($0)", "currency": "RUB", "type": "CARD", "includeInFree": true, "sort": 0] as [String: Any] },
            "categories": [Any](),
            "operations": ids.map { ["id": $0, "type": "EXPENSE", "timestamp": 5_000, "note": "o\($0)"] as [String: Any] },
            "postings": ids.map { ["id": $0, "operationId": $0, "accountId": $0, "amountMinor": -1, "rubMinor": -1] as [String: Any] },
            "rates": [Any](),
            "obligations": ids.map { ["id": $0, "name": "p\($0)", "amountMinor": 1, "currency": "RUB", "dayOfMonth": 1] as [String: Any] },
            "goals": [Any](),
            "wishes": ids.map { ["id": $0, "title": "w\($0)", "amountMinor": 1, "currency": "RUB", "createdAt": 1, "decideAt": 2] as [String: Any] },
        ]
        let h = try BackupHarness()
        try await h.backups.import(BackupFixtures.data(file), personalProfileName: "Личный")
        let snapshot = try await h.onlySnapshot()

        let ascending = ids.sorted()
        #expect(snapshot.accounts.map(\.name) == ascending.map { "a\($0)" })
        #expect(snapshot.obligations.map(\.name) == ascending.map { "p\($0)" })
        #expect(snapshot.wishes.map(\.title) == ascending.map { "w\($0)" })
        // The last written comes first.
        #expect(snapshot.operations.map(\.op.note) == ascending.reversed().map { "o\($0)" })
    }

    @Test func reconciliationsOfUnknownAccountsAndBadKeysAreDropped() async throws {
        let file = try BackupFixtures.edit(BackupFixtures.androidV1()) { file in
            var settings = try #require(file["settings"] as? [String: Any])
            var reconciled = try #require(settings["reconciledAt"] as? [String: Any])
            reconciled["999"] = 1_700_000_000_000
            reconciled["not-a-number"] = 1_700_000_000_000
            settings["reconciledAt"] = reconciled
            file["settings"] = settings
        }
        let h = try BackupHarness()
        try await h.backups.import(file, personalProfileName: "Личный")
        let snapshot = try await h.onlySnapshot()
        #expect(snapshot.accounts.filter { $0.reconciledAt != nil }.count == 2)
    }

    @Test func goalsKeepAndroidsIdsAsTheirPlaceInTheCreationOrder() async throws {
        // The file lists the main goal first (Android ids 2, 1, 3), but ids were handed out in
        // creation order: the cushion is the oldest goal, the bike the second, the trip the third.
        let backup = try BackupFormat.decode(BackupFixtures.androidV1(), personalProfileName: "Личный")
        let byName = Dictionary(
            uniqueKeysWithValues: backup.profiles[0].goals.map { ($0.name, backup.goalCreatedAt[$0.id]) }
        )
        #expect(byName == ["Подушка": 1, "Велосипед": 2, "Отпуск в Грузии": 3])

        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let profileId = try await h.onlySnapshot().profile.id
        #expect(try await h.goalNamesByAge(profileId) == ["Подушка", "Велосипед", "Отпуск в Грузии"])
    }

    @Test func whenTheMainGoalGoesTheOldestByCreationBecomesMain() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let snapshot = try await h.onlySnapshot()
        let repository = h.repository()

        // The trip becomes the main goal; then it is deleted. The oldest of the rest is the cushion
        // (Android id 1), not the bike that the file happens to list first.
        var trip = try #require(snapshot.goals.first { $0.name == "Отпуск в Грузии" })
        trip.isMain = true
        try await repository.saveGoal(trip, profileId: snapshot.profile.id)
        try await repository.deleteGoal(trip.id, profileId: snapshot.profile.id)

        let goals = try await h.onlySnapshot().goals
        #expect(goals.map(\.name) == ["Подушка", "Велосипед"])
        #expect(goals.map(\.isMain) == [true, false])
    }

    @Test func goalsAddedAfterTheImportComeAfterTheAndroidOnes() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let profileId = try await h.onlySnapshot().profile.id
        try await h.repository().saveGoal(Goal(name: "Ноутбук", targetMinor: 1, currency: "RUB"), profileId: profileId)
        #expect(try await h.goalNamesByAge(profileId) == ["Подушка", "Велосипед", "Отпуск в Грузии", "Ноутбук"])
    }

    // MARK: Settings

    @Test func theProfileGetsIncomePaydayAndMarkup() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let settings = try await h.onlySnapshot().profile.settings

        #expect(settings == ProfileSettings(
            incomeHourly: true, hourlyRate: 1000, monthlySalary: 0, taxPercent: 10, hoursPerWeek: 40, payday: 10,
            markup: 0.1362
        ))
    }

    @Test func theDeviceGetsCurrenciesModelAndReminder() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let device = h.device.current

        #expect(device.displayCurrencies == ["RUB", "USD", "GEL"])
        #expect(device.localCurrency == "GEL")
        #expect(device.baseCurrency == "GEL")
        #expect(device.geminiModel == "gemini-3.5-flash-lite")
        #expect(device.reconcileReminder)
        // The per-profile maps are not carried: they would point at ids that no longer exist.
        #expect(device.lastAccountId.isEmpty && device.celebratedGoalId.isEmpty)
    }

    @Test func theMainCurrencyTravelsWithABackup() async throws {
        // Ported from Android's BaseCurrencyTest.theMainCurrencyTravelsWithABackup: the setting
        // survives export and import, and a file from before it existed gives rubles.
        let source = try BackupHarness()
        try await source.seedFamilyProfile()
        source.device.update { $0.baseCurrency = "GEL" }

        let text = try await source.backups.export()
        #expect(String(decoding: text, as: UTF8.self).contains(#""baseCurrency" : "GEL""#))
        #expect(try BackupFormat.decode(text, personalProfileName: "Личный").device.baseCurrency == "GEL")

        let target = try BackupHarness()
        try await target.backups.import(text, personalProfileName: "Личный")
        #expect(target.device.current.baseCurrency == "GEL")

        // A version 2 file from before the setting existed.
        let oldV2 = try BackupFixtures.edit(text) { file in
            var device = try #require(file["device"] as? [String: Any])
            #expect(device.removeValue(forKey: "baseCurrency") != nil)
            file["device"] = device
        }
        #expect(try BackupFormat.decode(oldV2, personalProfileName: "Личный").device.baseCurrency == "RUB")

        // And an Android file from before it existed: the fixture says GEL, so take the key out.
        let oldAndroid = try BackupFixtures.edit(BackupFixtures.androidV1()) { file in
            var settings = try #require(file["settings"] as? [String: Any])
            #expect(settings.removeValue(forKey: "baseCurrency") != nil)
            file["settings"] = settings
        }
        #expect(try BackupFormat.decode(oldAndroid, personalProfileName: "Личный").device.baseCurrency == "RUB")
        let legacy = try BackupHarness()
        legacy.device.update { $0.baseCurrency = "GEL" }
        try await legacy.backups.import(oldAndroid, personalProfileName: "Личный")
        #expect(legacy.device.current.baseCurrency == "RUB")
    }

    // MARK: Leniency

    @Test func unknownKeysAreIgnored() async throws {
        // The fixture already has some (top level, settings, an account, an operation); add one more
        // to the profile-like places the version 1 shape has.
        let file = try BackupFixtures.edit(BackupFixtures.androidV1()) { file in
            file["quickEntry"] = ["on": true] as [String: Any]
            var goals = try #require(file["goals"] as? [[String: Any]])
            goals[0]["emoji"] = "🚲"
            file["goals"] = goals
            var wishes = try #require(file["wishes"] as? [[String: Any]])
            wishes[0]["store"] = "Nike"
            file["wishes"] = wishes
        }
        let h = try BackupHarness()
        try await h.backups.import(file, personalProfileName: "Личный")
        let snapshot = try await h.onlySnapshot()
        #expect(snapshot.accounts.count == 7 && snapshot.operations.count == 29 && snapshot.goals.count == 3)
    }

    @Test func missingKeysTakeTheAndroidDefaults() async throws {
        let file: [String: Any] = [
            "version": 1, "exportedAt": 0, "settings": [String: Any](),
            "accounts": [["id": 1, "name": "Карта", "currency": "RUB", "type": "CARD", "includeInFree": true]],
            "categories": [["id": 1, "key": "groceries", "name": "Продукты", "emoji": "🛒", "kind": "EXPENSE"]],
            "operations": [["id": 1, "type": "EXPENSE", "timestamp": 1_000, "categoryId": 1]],
            "postings": [["operationId": 1, "id": 1, "accountId": 1, "amountMinor": -500, "rubMinor": -500]],
            "rates": [Any](),
            "obligations": [Any](),
            "goals": [["id": 1, "name": "Отпуск", "targetMinor": 100_000, "currency": "RUB"]],
            "wishes": [["id": 1, "title": "Кофемашина", "amountMinor": 5_000, "currency": "RUB", "createdAt": 1, "decideAt": 2]],
        ]
        let h = try BackupHarness()
        h.device.update { $0.baseCurrency = "GEL"; $0.localCurrency = "THB"; $0.geminiModel = "other"; $0.reconcileReminder = false }
        try await h.backups.import(BackupFixtures.data(file), personalProfileName: "Личный")
        let snapshot = try await h.onlySnapshot()

        // Settings: the Kotlin defaults.
        #expect(snapshot.profile.settings == ProfileSettings(from: Settings()))
        #expect(snapshot.profile.settings.hoursPerWeek == 40 && snapshot.profile.settings.payday == 15)
        #expect(snapshot.profile.settings.markup == 0.10 && snapshot.profile.settings.incomeHourly)
        let device = h.device.current
        #expect(device.displayCurrencies == ["RUB", "USD"] && device.localCurrency == "RUB" && device.baseCurrency == "RUB")
        #expect(device.geminiModel == "gemini-3.5-flash-lite" && device.reconcileReminder)

        // Rows: sort 0, no group, a plain note, not an estimate, goal not main with nothing saved, a waiting wish.
        let account = try #require(snapshot.accounts.first)
        #expect(account.sort == 0 && account.groupName == nil && account.interestRate == nil && account.reconciledAt == nil)
        let op = try #require(snapshot.operations.first?.op)
        #expect(op.note == "" && !op.isEstimate && op.voiceText == nil && op.categoryKey == "groceries")
        let goal = try #require(snapshot.goals.first)
        #expect(goal.savedMinor == 0 && !goal.isMain && goal.accountId == nil)
        #expect(try #require(snapshot.wishes.first).status == .waiting)
    }

    @Test func aGoalOrCategoryPointingNowhereLosesOnlyTheLink() async throws {
        let file = try BackupFixtures.edit(BackupFixtures.androidV1()) { file in
            var goals = try #require(file["goals"] as? [[String: Any]])
            goals[1]["accountId"] = 999
            file["goals"] = goals
            var operations = try #require(file["operations"] as? [[String: Any]])
            operations[4]["categoryId"] = 999
            file["operations"] = operations
        }
        let h = try BackupHarness()
        try await h.backups.import(file, personalProfileName: "Личный")
        let snapshot = try await h.onlySnapshot()
        #expect(try #require(snapshot.goals.first { $0.name == "Подушка" }).accountId == nil)
        #expect(snapshot.operations.filter { $0.op.type == .income }.allSatisfy { $0.op.categoryKey == nil })
    }

    @Test func requiredKeysAreRequired() throws {
        func rejects(_ change: (inout [String: Any]) throws -> Void) throws {
            let file = try BackupFixtures.edit(BackupFixtures.androidV1(), change)
            #expect(throws: BackupError.self) { try BackupFormat.decode(file, personalProfileName: "Личный") }
        }
        try rejects { $0.removeValue(forKey: "accounts") }
        try rejects { $0.removeValue(forKey: "settings") }
        try rejects { $0.removeValue(forKey: "exportedAt") }
        try rejects {
            var accounts = try #require($0["accounts"] as? [[String: Any]])
            accounts[0].removeValue(forKey: "currency")
            $0["accounts"] = accounts
        }
        try rejects {
            var accounts = try #require($0["accounts"] as? [[String: Any]])
            accounts[0]["type"] = "WALLET"
            $0["accounts"] = accounts
        }
    }

    // MARK: Refusals

    @Test func aPostingOnAnUnknownAccountOrOperationIsRefused() throws {
        let onAccount = try BackupFixtures.edit(BackupFixtures.androidV1()) { file in
            var postings = try #require(file["postings"] as? [[String: Any]])
            postings[3]["accountId"] = 4_242
            file["postings"] = postings
        }
        #expect(throws: BackupError.self) { try BackupFormat.decode(onAccount, personalProfileName: "Личный") }

        let onOperation = try BackupFixtures.edit(BackupFixtures.androidV1()) { file in
            var postings = try #require(file["postings"] as? [[String: Any]])
            postings[3]["operationId"] = 4_242
            file["postings"] = postings
        }
        #expect(throws: BackupError.self) { try BackupFormat.decode(onOperation, personalProfileName: "Личный") }
    }

    @Test func repeatedIdsAreRefused() throws {
        let file = try BackupFixtures.edit(BackupFixtures.androidV1()) { file in
            var accounts = try #require(file["accounts"] as? [[String: Any]])
            accounts[1]["id"] = accounts[0]["id"]
            file["accounts"] = accounts
        }
        #expect(throws: BackupError.self) { try BackupFormat.decode(file, personalProfileName: "Личный") }
    }

    @Test func aFileWithoutAVersionIsVersionOne() throws {
        let file = try BackupFixtures.edit(BackupFixtures.androidV1()) { $0.removeValue(forKey: "version") }
        #expect(try BackupFormat.decode(file, personalProfileName: "Личный").sourceVersion == 1)
    }

    @Test func anEmptyAndroidFileStillGetsAProfile() async throws {
        // Android's own test file: nothing but a base currency.
        let file: [String: Any] = [
            "version": 1, "exportedAt": 0, "settings": ["baseCurrency": "GEL"],
            "accounts": [Any](), "categories": [Any](), "operations": [Any](), "postings": [Any](), "rates": [Any](),
            "obligations": [Any](), "goals": [Any](), "wishes": [Any](),
        ]
        let h = try BackupHarness()
        try await h.backups.import(BackupFixtures.data(file), personalProfileName: "Личный")
        let snapshot = try await h.onlySnapshot()
        #expect(snapshot.profile.name == "Личный" && snapshot.accounts.isEmpty && snapshot.operations.isEmpty)
        #expect(h.device.current.baseCurrency == "GEL")
    }

    @Test func anAndroidImportReplacesWhatWasThere() async throws {
        let h = try BackupHarness()
        try await h.seedFamilyProfile()
        try await h.database.write { try $0.save(StoreFixture.profile(1, name: "Старый")) }
        #expect(try await h.snapshots().count == 2)

        try await h.importAndroidFixture()
        let snapshots = try await h.snapshots()
        #expect(snapshots.map(\.profile.name) == ["Личный"])
        #expect(try await h.rates().count == 4)
    }
}
