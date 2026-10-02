import Foundation

/// The part of the settings that belongs to this phone (D16): it is neither synced nor shared.
/// The profile part (income, payday, markup) lives in the `profile` table; the app composes both
/// into `GoldaCore.Settings` for the active profile.
///
/// It is stored as one JSON value, and decoding takes the default for every key that is missing or
/// has the wrong type, as the Android store did with `?: default`, so a build that adds a field
/// never loses the others.
public struct DeviceSettings: Codable, Sendable, Equatable {
    public var onboarded: Bool
    /// Nil until the first profile exists; the app falls back to the first profile when it points at a
    /// profile that is gone.
    public var activeProfileId: UUID?
    public var displayCurrencies: [String]
    /// Currency of the country you are in; voice input falls back to it.
    public var localCurrency: String
    /// The currency the big numbers and totals are shown in.
    public var baseCurrency: String
    public var geminiModel: String
    /// Sunday-evening nudge to compare balances with the bank.
    public var reconcileReminder: Bool
    /// The person agreed to send voice notes to the third-party model (App Review 5.1.2(i)); until
    /// then nothing leaves the phone.
    public var voiceConsent: Bool
    /// The account used last, per profile id.
    public var lastAccountId: [UUID: UUID]
    /// The goal whose "reached" badge has already bloomed, per profile id, so it celebrates only once.
    public var celebratedGoalId: [UUID: UUID]

    public init(
        onboarded: Bool = false, activeProfileId: UUID? = nil, displayCurrencies: [String] = ["RUB", "USD"],
        localCurrency: String = "RUB", baseCurrency: String = "RUB", geminiModel: String = "gemini-3.5-flash-lite",
        reconcileReminder: Bool = true, voiceConsent: Bool = false, lastAccountId: [UUID: UUID] = [:],
        celebratedGoalId: [UUID: UUID] = [:]
    ) {
        self.onboarded = onboarded
        self.activeProfileId = activeProfileId
        self.displayCurrencies = displayCurrencies
        self.localCurrency = localCurrency
        self.baseCurrency = baseCurrency
        self.geminiModel = geminiModel
        self.reconcileReminder = reconcileReminder
        self.voiceConsent = voiceConsent
        self.lastAccountId = lastAccountId
        self.celebratedGoalId = celebratedGoalId
    }

    private enum CodingKeys: String, CodingKey {
        case onboarded, activeProfileId, displayCurrencies, localCurrency, baseCurrency, geminiModel
        case reconcileReminder, voiceConsent, lastAccountId, celebratedGoalId
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DeviceSettings()
        // `try?` here is deliberate: one damaged value must cost only itself, not every setting.
        onboarded = (try? c.decodeIfPresent(Bool.self, forKey: .onboarded)) ?? d.onboarded
        activeProfileId = (try? c.decodeIfPresent(UUID.self, forKey: .activeProfileId)) ?? d.activeProfileId
        displayCurrencies = (try? c.decodeIfPresent([String].self, forKey: .displayCurrencies))
            .map { $0.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } } ?? d.displayCurrencies
        localCurrency = (try? c.decodeIfPresent(String.self, forKey: .localCurrency)) ?? d.localCurrency
        baseCurrency = (try? c.decodeIfPresent(String.self, forKey: .baseCurrency)) ?? d.baseCurrency
        geminiModel = (try? c.decodeIfPresent(String.self, forKey: .geminiModel)) ?? d.geminiModel
        reconcileReminder = (try? c.decodeIfPresent(Bool.self, forKey: .reconcileReminder)) ?? d.reconcileReminder
        voiceConsent = (try? c.decodeIfPresent(Bool.self, forKey: .voiceConsent)) ?? d.voiceConsent
        lastAccountId = Self.decodeIdMap(c, .lastAccountId)
        celebratedGoalId = Self.decodeIdMap(c, .celebratedGoalId)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(onboarded, forKey: .onboarded)
        try c.encodeIfPresent(activeProfileId, forKey: .activeProfileId)
        try c.encode(displayCurrencies, forKey: .displayCurrencies)
        try c.encode(localCurrency, forKey: .localCurrency)
        try c.encode(baseCurrency, forKey: .baseCurrency)
        try c.encode(geminiModel, forKey: .geminiModel)
        try c.encode(reconcileReminder, forKey: .reconcileReminder)
        try c.encode(voiceConsent, forKey: .voiceConsent)
        try c.encode(Self.stringMap(lastAccountId), forKey: .lastAccountId)
        try c.encode(Self.stringMap(celebratedGoalId), forKey: .celebratedGoalId)
    }

    // Codable writes a dictionary keyed by anything but String as a flat [key, value, key, value]
    // array. A plain object of UUID strings is readable and survives a hand edit.
    private static func stringMap(_ map: [UUID: UUID]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: map.map { ($0.key.uuidString, $0.value.uuidString) })
    }

    /// Pairs that are not two UUIDs are dropped one by one, like Kotlin's `mapNotNull`.
    private static func decodeIdMap(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [UUID: UUID] {
        guard let raw = try? c.decodeIfPresent([String: String].self, forKey: key) else { return [:] }
        var map: [UUID: UUID] = [:]
        for (k, v) in raw {
            if let k = UUID(uuidString: k), let v = UUID(uuidString: v) { map[k] = v }
        }
        return map
    }
}
