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
