import Foundation
import GoldaCore
import Testing

@testable import GoldaData

/// The version 2 file: what the app writes, reads back and refuses.
@Suite(.timeLimit(.minutes(1))) struct BackupTests {
    /// Two profiles (the imported Android books and a family), rates and device settings that differ
    /// from the defaults.
    func livedIn() async throws -> BackupHarness {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        try await h.seedFamilyProfile()
        h.device.update {
            $0.displayCurrencies = ["RUB", "GEL", "THB"]
            $0.localCurrency = "THB"
            $0.baseCurrency = "GEL"
            $0.geminiModel = "gemini-3.5-flash"
            $0.reconcileReminder = false
        }
        return h
    }

    func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    // MARK: Round trip

    @Test func exportImportExportIsByteForByteStable() async throws {
        let source = try await livedIn()
        let first = try await source.backups.export()

        let target = try BackupHarness()
        try await target.backups.import(first, personalProfileName: "Не нужен")
        let second = try await target.backups.export()

        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test func aRoundTripLosesNothing() async throws {
        let source = try await livedIn()
        let file = try await source.backups.export()

        let target = try BackupHarness()
        let summary = try await target.backups.import(file, personalProfileName: "Не нужен")

        // Same ids, same rows, in the same orders, for every profile.
        let before = try await source.snapshots()
        let after = try await target.snapshots()
        #expect(before.count == 2)
        #expect(after == before)
        #expect(try await target.rates() == source.rates())
        let counters = try await source.goalCounters()
        #expect(counters.count == 5)
        #expect(try await target.goalCounters() == counters)
        let paymentCounters = try await source.obligationCounters()
        #expect(paymentCounters.count == 4)
        #expect(try await target.obligationCounters() == paymentCounters)

        #expect(summary.sourceVersion == 2)
        #expect(summary.profiles == 2)
        #expect(summary.accounts == 10 && summary.operations == 32 && summary.postings == 37)
        #expect(summary.obligations == 4 && summary.goals == 5 && summary.wishes == 4 && summary.rates == 4)

        // The carried device settings arrive.
        let sent = source.device.current
        let got = target.device.current
        #expect(got.displayCurrencies == sent.displayCurrencies)
        #expect(got.localCurrency == "THB" && got.baseCurrency == "GEL")
        #expect(got.geminiModel == "gemini-3.5-flash" && !got.reconcileReminder)
    }

    @Test func anyCurrencyCodeComesBack() async throws {
        // Pesos from the full catalogue and a code no list knows (a lev from before the euro, a typo
        // from another app): neither is checked against a list, so neither is lost.
        let source = try BackupHarness()
        let family = StoreFixture.id(900)
        try await source.database.write { store in
            try store.save(Profile(id: family, name: "Семья", sort: 0))
            try store.save(Account(id: StoreFixture.id(901), name: "Песо", currency: "ARS", type: .cash, includeInFree: true), profileId: family)
            try store.save(Account(id: StoreFixture.id(902), name: "Левы", currency: "BGN", type: .cash, includeInFree: true), profileId: family)
            try store.save([RateRecord(code: "ARS", rubPerUnit: 0.055, date: "2026-10-03")])
        }
        source.device.update {
            $0.displayCurrencies = ["RUB", "ARS", "ZZZ"]
            $0.localCurrency = "ARS"
            $0.baseCurrency = "ZZZ"
        }
        let file = try await source.backups.export()

        let target = try BackupHarness()
        try await target.backups.import(file, personalProfileName: "Не нужен")
        #expect(try await target.onlySnapshot().accounts.map(\.currency) == ["ARS", "BGN"])
        #expect(try await target.rates().contains(RateRecord(code: "ARS", rubPerUnit: 0.055, date: "2026-10-03")))
        let device = target.device.current
        #expect(device.displayCurrencies == ["RUB", "ARS", "ZZZ"])
        #expect(device.localCurrency == "ARS" && device.baseCurrency == "ZZZ")
    }

    @Test func nothingIsRoundedOnTheWay() async throws {
        let source = try await livedIn()
        let target = try BackupHarness()
        try await target.backups.import(source.backups.export(), personalProfileName: "Не нужен")

        let family = try #require(try await target.snapshots().last)
        #expect(family.profile.settings.markup == 0.1 + 0.2)
        #expect(family.profile.settings.monthlySalary == 250_000.5)
        let transfer = try family.operation(noted: "В копилку")
        #expect(transfer.op.cbrTo == 83.1 + 0.15 && transfer.op.purchaseAmountMinor == 12_345)
        // Posting order inside an operation is the order the ledger made them in, not the id order.
        #expect(transfer.postings.map(\.id) == [StoreFixture.id(916), StoreFixture.id(915)])
    }

    @Test func importingAnExportOfAnAndroidImportGivesTheSameBooks() async throws {
        let h = try BackupHarness()
        try await h.importAndroidFixture()
        let books = try await h.onlySnapshot()

        let again = try BackupHarness()
        try await again.backups.import(h.backups.export(), personalProfileName: "Не нужен")
        #expect(try await again.onlySnapshot() == books)
        #expect(try await again.onlySnapshot().profile.name == "Личный")
    }

    // MARK: Goals' creation order

    @Test func theRoundTripKeepsTheGoalCreationOrderSoTheOldestBecomesMain() async throws {
        let source = try await livedIn()
        let personal = try #require(try await source.snapshots().first).profile.id
        // The store lists the main goal first, so the file's order is not the creation order.
        let file = try await source.backups.export()
        #expect(try await source.snapshots()[0].goals.map(\.name) == ["Велосипед", "Подушка", "Отпуск в Грузии"])
        #expect(try await source.goalNamesByAge(personal) == ["Подушка", "Велосипед", "Отпуск в Грузии"])

        let target = try BackupHarness()
        try await target.backups.import(file, personalProfileName: "Не нужен")
        #expect(try await target.goalNamesByAge(personal) == ["Подушка", "Велосипед", "Отпуск в Грузии"])

        // Election after the import: the trip becomes main and is deleted; the oldest of the rest is
        // the cushion. Had the import taken the file's order, the bike (listed first) would win.
        let repository = target.repository()
        var trip = try #require(try await target.snapshots()[0].goals.first { $0.name == "Отпуск в Грузии" })
        trip.isMain = true
        try await repository.saveGoal(trip, profileId: personal)
        try await repository.deleteGoal(trip.id, profileId: personal)
        let goals = try await target.snapshots()[0].goals
        #expect(goals.map(\.name) == ["Подушка", "Велосипед"] && goals.map(\.isMain) == [true, false])

        // A goal added later goes after all of them.
        try await repository.saveGoal(Goal(name: "Ноутбук", targetMinor: 1, currency: "RUB"), profileId: personal)
        #expect(try await target.goalNamesByAge(personal) == ["Подушка", "Велосипед", "Ноутбук"])
    }

    @Test func theFileHoldsEveryGoalsCounter() async throws {
        let source = try await livedIn()
        let file = try await source.backups.export()
        let object = try #require(try JSONSerialization.jsonObject(with: file) as? [String: Any])
        let profiles = try #require(object["profiles"] as? [[String: Any]])
        let goals = profiles.flatMap { $0["goals"] as? [[String: Any]] ?? [] }
        #expect(goals.count == 5)
        #expect(goals.allSatisfy { $0["createdAt"] is Int })
        // Counters per profile: the family's two goals are 1 and 2 again.
        let family = try #require(profiles.last?["goals"] as? [[String: Any]])
        #expect(Set(family.compactMap { $0["createdAt"] as? Int }) == [1, 2])
    }

    @Test func aFileWithoutCountersCreatesGoalsInTheListedOrder() async throws {
        let source = try await livedIn()
        let file = try await BackupFixtures.edit(source.backups.export()) { file in
            var profiles = try #require(file["profiles"] as? [[String: Any]])
            for index in profiles.indices {
                let goals = profiles[index]["goals"] as? [[String: Any]] ?? []
                profiles[index]["goals"] = goals.map { goal -> [String: Any] in
                    var goal = goal
                    goal.removeValue(forKey: "createdAt")
                    return goal
                }
            }
            file["profiles"] = profiles
        }
        let target = try BackupHarness()
        try await target.backups.import(file, personalProfileName: "Не нужен")

        // Main first, as listed: that is now also the creation order.
        let snapshots = try await target.snapshots()
        #expect(try await target.goalNamesByAge(snapshots[0].profile.id) == ["Велосипед", "Подушка", "Отпуск в Грузии"])
        #expect(try await target.goalNamesByAge(snapshots[1].profile.id) == ["Машина", "Ремонт"])
        #expect(try await target.goalCounters().values.sorted() == [1, 1, 2, 2, 3])
    }

    @Test func counterlessOrClashingGoalsFallBackToTheListedOrderForTheirProfile() async throws {
        let source = try await livedIn()
        let good = try await source.backups.export()

        // One goal of the first profile has no counter: that profile falls back, the family keeps its own.
        let missing = try BackupFixtures.edit(good) { file in
            var profiles = try #require(file["profiles"] as? [[String: Any]])
            var goals = try #require(profiles[0]["goals"] as? [[String: Any]])
            goals[1].removeValue(forKey: "createdAt")
            profiles[0]["goals"] = goals
            file["profiles"] = profiles
        }
        // Two goals of the first profile share a counter.
        let clash = try BackupFixtures.edit(good) { file in
            var profiles = try #require(file["profiles"] as? [[String: Any]])
            var goals = try #require(profiles[0]["goals"] as? [[String: Any]])
            goals[2]["createdAt"] = goals[1]["createdAt"]
            profiles[0]["goals"] = goals
            file["profiles"] = profiles
        }
        for file in [missing, clash] {
            let target = try BackupHarness()
            try await target.backups.import(file, personalProfileName: "Не нужен")
            let snapshots = try await target.snapshots()
            #expect(try await target.goalNamesByAge(snapshots[0].profile.id) == ["Велосипед", "Подушка", "Отпуск в Грузии"])
            #expect(try await target.goalNamesByAge(snapshots[1].profile.id) == ["Ремонт", "Машина"])
        }
    }

    // MARK: Payments' creation order

    @Test func theRoundTripKeepsTheOrderOfOneDaysPayments() async throws {
        let source = try await livedIn()
        let family = StoreFixture.id(900)
        let repository = source.repository()
        // Ids out of creation order, and the first one deleted and undone: its place comes back.
        for n in [925, 921] {
            try await repository.saveObligation(
                Obligation(id: StoreFixture.id(n), name: "Платёж \(n)", amountMinor: 100, currency: "RUB", dayOfMonth: 12),
                profileId: family
            )
        }
        let deleted = try #require(try await repository.deleteObligation(StoreFixture.id(920), profileId: family))
        try await repository.saveObligation(deleted.obligation, profileId: family, createdAt: deleted.createdAt)
        let order = [920, 925, 921].map(StoreFixture.id)
        #expect(try await source.snapshots()[1].obligations.map(\.id) == order)
        let file = try await source.backups.export()

        let target = try BackupHarness()
        try await target.backups.import(file, personalProfileName: "Не нужен")
        #expect(try await target.snapshots()[1].obligations.map(\.id) == order)
        #expect(try await target.obligationCounters() == source.obligationCounters())
        #expect(try await target.backups.export() == file)

        // A payment added later goes after them all.
        try await target.repository().saveObligation(
            Obligation(id: StoreFixture.id(922), name: "Новый", amountMinor: 1, currency: "RUB", dayOfMonth: 12), profileId: family
        )
        #expect(try await target.snapshots()[1].obligations.map(\.id) == order + [StoreFixture.id(922)])
    }

    @Test func theFileHoldsEveryPaymentsCounter() async throws {
        let source = try await livedIn()
        let file = try await source.backups.export()
        let object = try #require(try JSONSerialization.jsonObject(with: file) as? [String: Any])
        let profiles = try #require(object["profiles"] as? [[String: Any]])
        // Android's ids for the imported books, and the family's own count from 1.
        let counters = profiles.map { profile in
            (profile["obligations"] as? [[String: Any]] ?? []).map { "\($0["name"] ?? "") \($0["createdAt"] ?? "-")" }
        }
        #expect(counters == [["Аренда 1", "Подписки 2", "Интернет дома 3"], ["Ипотека 1"]])
    }

    @Test func aFileWithoutPaymentCountersCreatesThemInTheListedOrder() async throws {
        let source = try await livedIn()
        let file = try await BackupFixtures.edit(source.backups.export()) { file in
            var profiles = try #require(file["profiles"] as? [[String: Any]])
            // The first profile's payments listed with the day-1 pair swapped and no counters.
            var payments = try #require(profiles[0]["obligations"] as? [[String: Any]])
            payments.swapAt(0, 1)
            profiles[0]["obligations"] = payments.map { payment -> [String: Any] in
                var payment = payment
                payment.removeValue(forKey: "createdAt")
                return payment
            }
            file["profiles"] = profiles
        }
        let target = try BackupHarness()
        try await target.backups.import(file, personalProfileName: "Не нужен")
        let snapshots = try await target.snapshots()
        #expect(snapshots[0].obligations.map(\.name) == ["Подписки", "Аренда", "Интернет дома"])
        let counters = try await target.obligationCounters()
        #expect(snapshots[0].obligations.map { counters[$0.id] } == [1, 2, 3])
    }

    // MARK: Nothing to export

    @Test func anExportOfNoProfilesIsRefusedWithATypedError() async throws {
        let h = try BackupHarness()
        await #expect(throws: BackupError.nothingToExport) { try await h.backups.export() }

        // Rates alone are not worth a file either.
        try await h.database.write { try $0.save([RateRecord(code: "USD", rubPerUnit: 83.25, date: "2026-09-21")]) }
        await #expect(throws: BackupError.nothingToExport) { try await h.backups.export() }

        // With a profile it works, and what it writes can be imported.
        try await h.database.write { try $0.save(StoreFixture.profile(1)) }
        let file = try await h.backups.export()
        let again = try BackupHarness()
        try await again.backups.import(file, personalProfileName: "Не нужен")
        #expect(try await again.snapshots().count == 1)
    }

    // MARK: The file

    @Test func theFileIsPrettyPrintedWithSortedKeysAndVersionTwo() async throws {
        let source = try await livedIn()
        let data = try await source.backups.export()
        let file = text(data)

        #expect(file.split(separator: "\n").count > 100)
        #expect(file.contains("\n  \"device\" : {"))

        // Top-level keys in alphabetical order, so files diff well.
        let positions = ["device", "exportedAt", "profiles", "rates", "version"].compactMap {
            file.range(of: "\n  \"\($0)\"")?.lowerBound
        }
        #expect(positions.count == 5 && positions == positions.sorted())

        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 2)
        #expect(object["exportedAt"] as? Int64 == 1_790_100_000_000)
        #expect(Set(object.keys) == ["version", "exportedAt", "device", "profiles", "rates"])
    }

    @Test func theFileHoldsTheCarriedDeviceSettingsOnly() async throws {
        let source = try await livedIn()
        let data = try await source.backups.export()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let device = try #require(object["device"] as? [String: Any])
        #expect(Set(device.keys) == ["displayCurrencies", "localCurrency", "baseCurrency", "geminiModel", "reconcileReminder"])
        #expect(device["displayCurrencies"] as? [String] == ["RUB", "GEL", "THB"])
        #expect(device["reconcileReminder"] as? Bool == false)
    }

    @Test func theExportHoldsNoSecretAndNoPrivateSetting() async throws {
        let source = try await livedIn()
        let key = "AIzaSy-this-must-never-leave-the-phone"
        try source.secrets.write(key, for: SecretKey.gemini)
        source.device.update {
            $0.voiceConsent = true
            $0.activeProfileId = StoreFixture.id(900)
            $0.lastAccountId = [StoreFixture.id(900): StoreFixture.id(901)]
            $0.celebratedGoalId = [StoreFixture.id(900): StoreFixture.id(930)]
        }
        let file = text(try await source.backups.export())

        #expect(!file.contains(key))
        #expect(!file.localizedCaseInsensitiveContains("AIza"))
        #expect(!file.localizedCaseInsensitiveContains("apiKey"))
        #expect(!file.contains(SecretKey.gemini))
        for private_ in ["voiceConsent", "activeProfileId", "lastAccountId", "celebratedGoalId", "onboarded", "hasGeminiKey"] {
            #expect(!file.contains(private_), "\(private_) must stay on the phone")
        }
    }

    @Test func exportedAtIsTheClock() async throws {
        let moment = Date(timeIntervalSince1970: 1_234_567.891)
        let h = try BackupHarness(clock: moment)
        try await h.seedFamilyProfile()
        let backup = try await BackupFormat.decode(h.backups.export(), personalProfileName: "Личный")
        #expect(backup.exportedAt == 1_234_567_891)
    }

    // MARK: Import

    @Test func theFirstProfileBecomesActiveAndTheAppOnboarded() async throws {
        let source = try await livedIn()
        let file = try await source.backups.export()
        let personal = try #require(try await source.snapshots().first).profile.id

        let target = try BackupHarness()
        #expect(!target.device.current.onboarded && target.device.current.activeProfileId == nil)
        let summary = try await target.backups.import(file, personalProfileName: "Не нужен")
        #expect(target.device.current.onboarded)
        #expect(target.device.current.activeProfileId == personal)
        #expect(summary.activeProfileId == personal)
    }

    @Test func theFirstProfileBySortIsTheOneThatCountsEvenWhenTheFileListsItLater() async throws {
        let source = try await livedIn()
        let family = StoreFixture.id(900)
        let file = try await BackupFixtures.edit(source.backups.export()) { file in
            var profiles = try #require(file["profiles"] as? [[String: Any]])
            profiles.reverse()
            file["profiles"] = profiles
        }
        let target = try BackupHarness()
        let summary = try await target.backups.import(file, personalProfileName: "Не нужен")
        // "Семья" has sort 1 and "Личный" sort 0, whatever the order in the file.
        #expect(summary.activeProfileId != family)
        #expect(try await target.snapshots().map(\.profile.name) == ["Личный", "Семья"])
    }

    @Test func theImportReplacesEverythingThereWas() async throws {
        let target = try BackupHarness()
        try await target.database.write { store in
            try store.save(StoreFixture.profile(1, name: "Старый"))
            try store.save(StoreFixture.account(2), profileId: StoreFixture.id(1))
            try store.save([RateRecord(code: "XYZ", rubPerUnit: 1, date: "2020-01-01")])
        }
        target.device.update { $0.lastAccountId = [StoreFixture.id(1): StoreFixture.id(2)]; $0.celebratedGoalId = [StoreFixture.id(1): StoreFixture.id(3)] }

        let source = try await livedIn()
        try await target.backups.import(source.backups.export(), personalProfileName: "Не нужен")

        #expect(try await target.snapshots().map(\.profile.name) == ["Личный", "Семья"])
        #expect(try await target.rates().map(\.code) == ["EUR", "GEL", "THB", "USD"])
        // Maps keyed by profiles that are gone are cleared with them.
        #expect(target.device.current.lastAccountId.isEmpty && target.device.current.celebratedGoalId.isEmpty)
    }

    @Test func theImportLeavesTheKeyAndTheConsentAlone() async throws {
        let source = try await livedIn()
        let file = try await source.backups.export()

        let target = try BackupHarness()
        try target.secrets.write("AIzaSy-on-this-phone", for: SecretKey.gemini)
        target.device.update { $0.voiceConsent = true }
        try await target.backups.import(file, personalProfileName: "Не нужен")

        #expect(target.secrets.read(SecretKey.gemini) == "AIzaSy-on-this-phone")
        #expect(target.device.current.voiceConsent)
    }

    @Test func aFileWithoutAnyBaseCurrencyOrDeviceBlockLeavesRublesAndDefaults() async throws {
        let source = try await livedIn()
        let file = try await BackupFixtures.edit(source.backups.export()) { $0.removeValue(forKey: "device") }
        let target = try BackupHarness()
        target.device.update { $0.baseCurrency = "GEL"; $0.geminiModel = "other" }
        try await target.backups.import(file, personalProfileName: "Не нужен")
        #expect(target.device.current.baseCurrency == "RUB")
        #expect(target.device.current.geminiModel == DeviceSettings().geminiModel)
        #expect(target.device.current.displayCurrencies == ["RUB", "USD"])
    }

    // MARK: Leniency

    @Test func unknownKeysAreIgnoredEverywhere() async throws {
        let source = try await livedIn()
        let file = try await BackupFixtures.edit(source.backups.export()) { file in
            file = try #require(BackupFixtures.addingUnknownKeys(file) as? [String: Any])
        }
        #expect(text(file).contains("futureKey"))

        let target = try BackupHarness()
        try await target.backups.import(file, personalProfileName: "Не нужен")
        #expect(try await target.snapshots() == source.snapshots())
        #expect(try await target.rates() == source.rates())
    }

    @Test func missingKeysTakeTheirDefaults() async throws {
        let source = try await livedIn()
        let file = try await BackupFixtures.edit(source.backups.export()) { file in
            file.removeValue(forKey: "device")
            file.removeValue(forKey: "rates")
            file.removeValue(forKey: "exportedAt")
            var profiles = try #require(file["profiles"] as? [[String: Any]])
            func strip(_ list: Any?, _ keys: [String]) -> [[String: Any]] {
                (list as? [[String: Any]] ?? []).map { row in
                    var row = row
                    for key in keys { row.removeValue(forKey: key) }
                    return row
                }
            }
            for index in profiles.indices {
                profiles[index]["accounts"] = strip(profiles[index]["accounts"], ["sort"])
                profiles[index]["operations"] = strip(profiles[index]["operations"], ["note", "isEstimate"])
                profiles[index]["goals"] = strip(profiles[index]["goals"], ["savedMinor", "isMain"])
                profiles[index]["wishes"] = strip(profiles[index]["wishes"], ["status"])
            }
            profiles[1].removeValue(forKey: "settings")
            profiles[1].removeValue(forKey: "obligations")
            profiles[0].removeValue(forKey: "sort")
            file["profiles"] = profiles
        }

        let target = try BackupHarness()
        try await target.backups.import(file, personalProfileName: "Не нужен")
        let snapshots = try await target.snapshots()
        #expect(snapshots.count == 2)
        #expect(try await target.rates().isEmpty)
        #expect(target.device.current.baseCurrency == "RUB")

        for snapshot in snapshots {
            #expect(snapshot.accounts.allSatisfy { $0.sort == 0 })
            #expect(snapshot.operations.allSatisfy { $0.op.note == "" && !$0.op.isEstimate })
            #expect(snapshot.goals.allSatisfy { $0.savedMinor == 0 && !$0.isMain })
            #expect(snapshot.wishes.allSatisfy { $0.status == .waiting })
        }
        let family = try #require(snapshots.first { $0.profile.name == "Семья" })
        #expect(family.profile.settings == ProfileSettings(from: Settings()))
        #expect(family.obligations.isEmpty)
        // Amounts and postings are not defaulted away.
        #expect(family.postings.count == 4)
    }

    // MARK: Refusals

    /// Everything about the books and the device, to compare before and after a refused import.
    struct State: Equatable {
        var snapshots: [ProfileSnapshot]
        var rates: [RateRecord]
        var device: DeviceSettings
    }

    func state(_ h: BackupHarness) async throws -> State {
        State(snapshots: try await h.snapshots(), rates: try await h.rates(), device: h.device.current)
    }

    @Test func aBrokenFileChangesNothing() async throws {
        let h = try await livedIn()
        h.device.update { $0.onboarded = true; $0.activeProfileId = StoreFixture.id(900); $0.voiceConsent = true }
        let before = try await state(h)
        let good = try await h.backups.export()
        let android = try BackupFixtures.androidV1()

        func tampered(_ change: (inout [String: Any]) throws -> Void) throws -> Data {
            try BackupFixtures.edit(good, change)
        }
        func profile(_ file: inout [String: Any], _ index: Int, _ change: (inout [String: Any]) -> Void) throws {
            var profiles = try #require(file["profiles"] as? [[String: Any]])
            change(&profiles[index])
            file["profiles"] = profiles
        }

        let broken: [(String, Data)] = [
            ("not JSON", Data("this is not a backup".utf8)),
            ("empty", Data()),
            ("an array", Data("[]".utf8)),
            ("an empty object", Data("{}".utf8)),
            ("cut off v2", good.prefix(good.count / 2)),
            ("cut off at the last byte", good.dropLast()),
            ("cut off v1", android.prefix(android.count * 2 / 3)),
            ("newer version", try tampered { $0["version"] = 3 }),
            ("version zero", try tampered { $0["version"] = 0 }),
            ("version as text", try tampered { $0["version"] = "2" }),
            ("no profiles", try tampered { $0["profiles"] = [Any]() }),
            ("no profiles key", try tampered { $0.removeValue(forKey: "profiles") }),
            ("amount as text", try tampered {
                try profile(&$0, 0) { p in
                    var operations = p["operations"] as? [[String: Any]] ?? []
                    var postings = operations[0]["postings"] as? [[String: Any]] ?? []
                    postings[0]["amountMinor"] = "ten"
                    operations[0]["postings"] = postings
                    p["operations"] = operations
                }
            }),
            // Past `Money.maxMinor`: Swift traps where Kotlin wraps, so such a row would crash every launch (D59).
            ("amount past the cap", try tampered {
                try profile(&$0, 0) { p in
                    var operations = p["operations"] as? [[String: Any]] ?? []
                    var postings = operations[0]["postings"] as? [[String: Any]] ?? []
                    postings[0]["amountMinor"] = Int64.max
                    operations[0]["postings"] = postings
                    p["operations"] = operations
                }
            }),
            ("negative amount past the cap", try tampered {
                try profile(&$0, 0) { p in
                    var operations = p["operations"] as? [[String: Any]] ?? []
                    var postings = operations[0]["postings"] as? [[String: Any]] ?? []
                    postings[0]["amountMinor"] = -Money.maxMinor - 1
                    operations[0]["postings"] = postings
                    p["operations"] = operations
                }
            }),
            ("goal savings past the cap", try tampered {
                try profile(&$0, 0) { p in
                    var goals = p["goals"] as? [[String: Any]] ?? []
                    goals[0]["savedMinor"] = Money.maxMinor + 1
                    p["goals"] = goals
                }
            }),
            ("v1 amount past the cap", try BackupFixtures.edit(android) { file in
                var postings = try #require(file["postings"] as? [[String: Any]])
                postings[0]["amountMinor"] = Int64.max
                file["postings"] = postings
            }),
            ("profile without a name", try tampered { try profile(&$0, 1) { $0.removeValue(forKey: "name") } }),
            ("id that is not a UUID", try tampered {
                try profile(&$0, 0) { p in
                    var accounts = p["accounts"] as? [[String: Any]] ?? []
                    accounts[0]["id"] = "12"
                    p["accounts"] = accounts
                }
            }),
            ("unknown account type", try tampered {
                try profile(&$0, 1) { p in
                    var accounts = p["accounts"] as? [[String: Any]] ?? []
                    accounts[0]["type"] = "WALLET"
                    p["accounts"] = accounts
                }
            }),
            ("posting on a missing account", try tampered {
                try profile(&$0, 0) { p in
                    var operations = p["operations"] as? [[String: Any]] ?? []
                    var postings = operations[0]["postings"] as? [[String: Any]] ?? []
                    postings[0]["accountId"] = UUID().uuidString
                    operations[0]["postings"] = postings
                    p["operations"] = operations
                }
            }),
            ("posting on another profile's account", try tampered { file in
                var profiles = try #require(file["profiles"] as? [[String: Any]])
                let familyAccounts = try #require(profiles[1]["accounts"] as? [[String: Any]])
                var operations = try #require(profiles[0]["operations"] as? [[String: Any]])
                var postings = try #require(operations[0]["postings"] as? [[String: Any]])
                postings[0]["accountId"] = familyAccounts[0]["id"]
                operations[0]["postings"] = postings
                profiles[0]["operations"] = operations
                file["profiles"] = profiles
            }),
            ("an account id shared by two profiles", try tampered { file in
                var profiles = try #require(file["profiles"] as? [[String: Any]])
                var personal = try #require(profiles[0]["accounts"] as? [[String: Any]])
                let family = try #require(profiles[1]["accounts"] as? [[String: Any]])
                personal[0]["id"] = family[0]["id"]
                profiles[0]["accounts"] = personal
                file["profiles"] = profiles
            }),
            ("the same profile twice", try tampered { file in
                var profiles = try #require(file["profiles"] as? [[String: Any]])
                profiles[1]["id"] = profiles[0]["id"]
                file["profiles"] = profiles
            }),
            ("v1 without its accounts", try BackupFixtures.edit(android) { $0.removeValue(forKey: "accounts") }),
            ("v1 with a posting on nothing", try BackupFixtures.edit(android) { file in
                var postings = try #require(file["postings"] as? [[String: Any]])
                postings[0]["accountId"] = 9_999
                file["postings"] = postings
            }),
        ]

        for (label, data) in broken {
            await #expect(throws: BackupError.self, Comment(rawValue: label)) {
                try await h.backups.import(data, personalProfileName: "Личный")
            }
            #expect(try await state(h) == before, Comment(rawValue: "\(label) changed something"))
        }
    }

    @Test func theRefusalSaysWhy() async throws {
        let h = try await livedIn()
        let good = try await h.backups.export()

        let newer = try BackupFixtures.edit(good) { $0["version"] = 3 }
        await #expect(throws: BackupError.unsupportedVersion(3)) {
            try await h.backups.import(newer, personalProfileName: "Личный")
        }
        let none = try BackupFixtures.edit(good) { $0["profiles"] = [Any]() }
        await #expect(throws: BackupError.noProfiles) {
            try await h.backups.import(none, personalProfileName: "Личный")
        }
        do {
            _ = try BackupFormat.decode(Data("{\"version\": 2,".utf8), personalProfileName: "Личный")
            Issue.record("a cut-off file was accepted")
        } catch let BackupError.unreadable(reason) {
            #expect(!reason.isEmpty)
        }
        do {
            _ = try BackupFormat.decode(
                BackupFixtures.edit(good) { $0.removeValue(forKey: "profiles") }, personalProfileName: "Личный"
            )
            Issue.record("a file without profiles was accepted")
        } catch let BackupError.unreadable(reason) {
            #expect(reason.contains("profiles"))
        }
    }

    @Test func aFailureInsideTheTransactionRollsTheWipeBack() async throws {
        let h = try await livedIn()
        let before = try await state(h)

        // A backup that got past validation but that the database refuses (a posting on an account
        // that is not there): it fails after the old books were deleted, in the same transaction.
        var broken = try BackupFormat.decode(BackupFixtures.androidV1(), personalProfileName: "Личный")
        broken.profiles[0].operations[0].postings[0].accountId = UUID()
        await #expect(throws: (any Error).self) { try await h.backups.apply(broken) }

        #expect(try await state(h) == before)
    }
}
