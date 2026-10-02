import Foundation
import Testing

@testable import GoldaData

/// Each test gets its own UserDefaults suite and removes it afterwards.
@Suite final class DeviceSettingsTests {
    let suiteName = "golda.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: Decoding

    @Test func freshSettingsHoldTheDefaults() {
        let s = DeviceSettings()
        #expect(!s.onboarded)
        #expect(s.activeProfileId == nil)
        #expect(s.displayCurrencies == ["RUB", "USD"])
        #expect(s.localCurrency == "RUB")
        #expect(s.baseCurrency == "RUB")
        #expect(s.geminiModel == "gemini-3.5-flash-lite")
        #expect(s.reconcileReminder)
        #expect(!s.voiceConsent)
        #expect(s.lastAccountId.isEmpty)
        #expect(s.celebratedGoalId.isEmpty)
    }

    @Test func anEmptyObjectDecodesToTheDefaults() throws {
        #expect(try decode("{}") == DeviceSettings())
    }

    @Test func missingKeysTakeTheirDefaultsAndPresentOnesSurvive() throws {
        let s = try decode(#"{"onboarded": true, "baseCurrency": "GEL", "voiceConsent": true}"#)
        #expect(s.onboarded)
        #expect(s.baseCurrency == "GEL")
        #expect(s.voiceConsent)
        // Everything else is untouched.
        #expect(s.localCurrency == "RUB")
        #expect(s.displayCurrencies == ["RUB", "USD"])
        #expect(s.geminiModel == "gemini-3.5-flash-lite")
        #expect(s.reconcileReminder)
        #expect(s.activeProfileId == nil)
    }

    @Test func aDamagedValueCostsOnlyItself() throws {
        let s = try decode(#"""
        {"onboarded": "yes", "localCurrency": "THB", "reconcileReminder": false,
         "activeProfileId": "not-a-uuid", "lastAccountId": [1, 2, 3]}
        """#)
        #expect(!s.onboarded)
        #expect(s.localCurrency == "THB")
        #expect(!s.reconcileReminder)
        #expect(s.activeProfileId == nil)
        #expect(s.lastAccountId.isEmpty)
    }

    @Test func blankCurrenciesAreDropped() throws {
        let s = try decode(#"{"displayCurrencies": ["RUB", "", " ", "GEL"]}"#)
        #expect(s.displayCurrencies == ["RUB", "GEL"])
    }

    @Test func anExplicitEmptyListStaysEmpty() throws {
        // The Kotlin store kept an empty list too; only a missing key meant "default".
        let s = try decode(#"{"displayCurrencies": []}"#)
        #expect(s.displayCurrencies.isEmpty)
    }

    @Test func perProfileMapsKeepValidPairsAndDropTheRest() throws {
        let profile = UUID(), account = UUID()
        let s = try decode(#"""
        {"lastAccountId": {"\#(profile.uuidString)": "\#(account.uuidString)", "junk": "\#(account.uuidString)",
                           "\#(UUID().uuidString)": "junk"}}
        """#)
        #expect(s.lastAccountId == [profile: account])
    }

    // MARK: Encoding

    @Test func roundTripsEveryField() throws {
        let (p1, p2) = (UUID(), UUID())
        let original = DeviceSettings(
            onboarded: true, activeProfileId: p2, displayCurrencies: ["RUB", "GEL", "THB"], localCurrency: "GEL",
            baseCurrency: "USD", geminiModel: "gemini-x", reconcileReminder: false, voiceConsent: true,
            lastAccountId: [p1: UUID(), p2: UUID()], celebratedGoalId: [p1: UUID()]
        )
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(DeviceSettings.self, from: data) == original)
    }

    @Test func perProfileMapsAreWrittenAsPlainObjects() throws {
        let profile = UUID(), account = UUID()
        let data = try JSONEncoder().encode(DeviceSettings(lastAccountId: [profile: account]))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let map = try #require(object["lastAccountId"] as? [String: String])
        #expect(map == [profile.uuidString: account.uuidString])
    }

    // MARK: Store

    @Test func aFreshStoreHoldsTheDefaults() {
        #expect(makeStore().current == DeviceSettings())
    }

    @Test func updatesSurviveARestart() {
        let profile = UUID(), account = UUID()
        makeStore().update {
            $0.onboarded = true
            $0.activeProfileId = profile
            $0.displayCurrencies = ["RUB", "THB"]
            $0.lastAccountId[profile] = account
        }
        let again = makeStore().current
        #expect(again.onboarded)
        #expect(again.activeProfileId == profile)
        #expect(again.displayCurrencies == ["RUB", "THB"])
        #expect(again.lastAccountId == [profile: account])
    }

    @Test func updateReturnsTheNewSettings() {
        let store = makeStore()
        let result = store.update { $0.baseCurrency = "USD" }
        #expect(result.baseCurrency == "USD")
        #expect(store.current == result)
    }

    @Test func theMapEntryOfOneProfileCanBeRemoved() {
        let (p1, p2) = (UUID(), UUID())
        let store = makeStore()
        store.update { $0.celebratedGoalId = [p1: UUID(), p2: UUID()] }
        store.update { $0.celebratedGoalId[p1] = nil }
        #expect(makeStore().current.celebratedGoalId.keys.sorted { $0.uuidString < $1.uuidString } == [p2])
    }

    @Test func garbageInDefaultsIsAFreshInstall() {
        defaults.set(Data("not json".utf8), forKey: DeviceSettingsStore.defaultKey)
        #expect(makeStore().current == DeviceSettings())
        defaults.set("a string, not data", forKey: DeviceSettingsStore.defaultKey)
        #expect(makeStore().current == DeviceSettings())
    }

    @Test func resetReturnsToTheDefaultsAndForgetsTheStoredValue() {
        let store = makeStore()
        store.update { $0.onboarded = true }
        store.reset()
        #expect(store.current == DeviceSettings())
        #expect(defaults.data(forKey: DeviceSettingsStore.defaultKey) == nil)
        #expect(makeStore().current == DeviceSettings())
    }

    @Test func storesWithDifferentKeysDoNotMix() {
        makeStore(key: "a").update { $0.onboarded = true }
        #expect(!makeStore(key: "b").current.onboarded)
    }

    @Test func anUpdateThatChangesNothingWritesNothing() {
        let store = makeStore()
        store.update { _ in }
        #expect(defaults.data(forKey: DeviceSettingsStore.defaultKey) == nil)
    }

    // MARK: Changes stream

    @Test func theStreamStartsWithTheCurrentSettingsThenFollowsEveryChange() async {
        let store = makeStore()
        store.update { $0.localCurrency = "GEL" }

        var iterator = store.changes().makeAsyncIterator()
        #expect(await iterator.next()?.localCurrency == "GEL")

        store.update { $0.localCurrency = "THB" }
        #expect(await iterator.next()?.localCurrency == "THB")

        // A no-op is not announced: the next value is the next real change.
        store.update { $0.localCurrency = "THB" }
        store.update { $0.localCurrency = "USD" }
        #expect(await iterator.next()?.localCurrency == "USD")
    }

    @Test func everyObserverSeesTheChange() async {
        let store = makeStore()
        var first = store.changes().makeAsyncIterator()
        var second = store.changes().makeAsyncIterator()
        _ = await (first.next(), second.next())

        store.update { $0.onboarded = true }
        #expect(await first.next()?.onboarded == true)
        #expect(await second.next()?.onboarded == true)
    }

    @Test func aStreamThatWentAwayDoesNotBreakLaterUpdates() async {
        let store = makeStore()
        do {
            var gone = store.changes().makeAsyncIterator()
            _ = await gone.next()
        }
        store.update { $0.onboarded = true }
        #expect(store.current.onboarded)
    }

    @Test func updatesFromManyTasksAreNotLost() async {
        let store = makeStore()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                let profile = UUID()
                group.addTask { store.update { $0.lastAccountId[profile] = UUID() } }
            }
        }
        #expect(store.current.lastAccountId.count == 50)
        #expect(makeStore().current.lastAccountId.count == 50)
    }

    // MARK: Helpers

    private func makeStore(key: String = DeviceSettingsStore.defaultKey) -> DeviceSettingsStore {
        DeviceSettingsStore(defaults: defaults, key: key)
    }

    private func decode(_ json: String) throws -> DeviceSettings {
        try JSONDecoder().decode(DeviceSettings.self, from: Data(json.utf8))
    }
}
