import Foundation
import Security
import Testing

@testable import GoldaData

/// The behaviour every secret store promises, run against the in-memory store everywhere and the
/// real Keychain wherever the host process may use it.
private func checkTheStoreContract(_ store: some SecretStore) throws {
    #expect(store.read("k") == nil)

    try store.write("first", for: "k")
    #expect(store.read("k") == "first")

    try store.write("second", for: "k")
    #expect(store.read("k") == "second")

    // Keys are independent.
    try store.write("other", for: "k2")
    #expect(store.read("k") == "second")
    #expect(store.read("k2") == "other")

    try store.delete("k")
    #expect(store.read("k") == nil)
    #expect(store.read("k2") == "other")
    try store.delete("k2")

    // Deleting what is not there is fine.
    try store.delete("never-written")
}

private func checkBlankAndTrimmedValues(_ store: some SecretStore) throws {
    // Android trimmed the key it was given.
    try store.write("  AIza-key \n", for: "k")
    #expect(store.read("k") == "AIza-key")

    // An emptied field clears the key.
    try store.write("   ", for: "k")
    #expect(store.read("k") == nil)

    try store.write("", for: "never-written")
    #expect(store.read("never-written") == nil)
    try store.delete("k")
}

@Suite struct InMemorySecretStoreTests {
    @Test func followsTheContract() throws {
        try checkTheStoreContract(InMemorySecretStore())
    }

    @Test func trimsAndTreatsBlankAsDelete() throws {
        try checkBlankAndTrimmedValues(InMemorySecretStore())
    }

    @Test func startsWithTheGivenValues() {
        let store = InMemorySecretStore([SecretKey.gemini: "abc"])
        #expect(store.read(SecretKey.gemini) == "abc")
    }

    @Test func storesAreIndependentOfEachOther() throws {
        let a = InMemorySecretStore()
        let b = InMemorySecretStore()
        try a.write("x", for: "k")
        #expect(b.read("k") == nil)
    }

    @Test func survivesConcurrentWrites() async throws {
        let store = InMemorySecretStore()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask { try? store.write("v\(i)", for: "key\(i)") }
            }
        }
        for i in 0..<100 { #expect(store.read("key\(i)") == "v\(i)") }
    }
}

/// Whether the host process may use the Keychain at all. An unsigned `swift test` run on macOS
/// often cannot (it answers errSecMissingEntitlement), while an iOS simulator test host can.
private let keychainIsUsable: Bool = {
    let store = KeychainSecretStore(service: "com.f4studio.golda.tests.probe.\(UUID().uuidString)")
    defer { try? store.delete("probe") }
    do {
        try store.write("probe", for: "probe")
        return store.read("probe") == "probe"
    } catch {
        return false
    }
}()

@Suite struct KeychainSecretStoreTests {
    /// A service of its own, so a test never sees (or destroys) the real Gemini key.
    let service = "com.f4studio.golda.tests.\(UUID().uuidString)"

    var store: KeychainSecretStore { KeychainSecretStore(service: service) }

    @Test func usesTheAppsServiceByDefault() {
        #expect(KeychainSecretStore.defaultService == "com.f4studio.golda")
    }

    @Test(.enabled(if: keychainIsUsable, "The Keychain is not available to this process"))
    func followsTheContract() throws {
        defer { cleanUp() }
        try checkTheStoreContract(store)
    }

    @Test(.enabled(if: keychainIsUsable, "The Keychain is not available to this process"))
    func trimsAndTreatsBlankAsDelete() throws {
        defer { cleanUp() }
        try checkBlankAndTrimmedValues(store)
    }

    @Test(.enabled(if: keychainIsUsable, "The Keychain is not available to this process"))
    func servicesDoNotSeeEachOther() throws {
        defer { cleanUp() }
        try store.write("mine", for: "k")
        #expect(KeychainSecretStore(service: service + ".other").read("k") == nil)
    }

    @Test(.enabled(if: keychainIsUsable, "The Keychain is not available to this process"))
    func bytesThatAreNotTextReadAsMissing() throws {
        defer { cleanUp() }
        // 0xFF is never valid UTF-8, the stand-in for data that came back damaged.
        var item = identity(of: "k")
        item[kSecValueData as String] = Data([0xFF, 0xFE, 0xFD])
        let added = SecItemAdd(item as CFDictionary, nil)
        #expect(added == errSecSuccess)
        #expect(store.read("k") == nil)

        // And a fresh write repairs it.
        try store.write("good", for: "k")
        #expect(store.read("k") == "good")
    }

    #if os(iOS)
    // The macOS file-based keychain does not report the accessibility class, so the policy can only
    // be read back on iOS (the simulator or a device).
    @Test(.enabled(if: keychainIsUsable, "The Keychain is not available to this process"))
    func itemsStayOnThisDeviceAndOutOfICloud() throws {
        defer { cleanUp() }
        try store.write("secret", for: "k")
        let attributes = try attributesOfItem("k")
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        // A non-synchronizable item reports 0 (or leaves the attribute out).
        let synchronizable = attributes[kSecAttrSynchronizable as String] as? Int ?? 0
        #expect(synchronizable == 0)
    }

    @Test(.enabled(if: keychainIsUsable, "The Keychain is not available to this process"))
    func rewritingBringsAnOldItemToThePolicy() throws {
        defer { cleanUp() }
        var item = identity(of: "k")
        item[kSecValueData as String] = Data("old".utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let added = SecItemAdd(item as CFDictionary, nil)
        #expect(added == errSecSuccess)

        try store.write("new", for: "k")
        #expect(store.read("k") == "new")
        let attributes = try attributesOfItem("k")
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }
    #endif

    private func identity(of key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    private func attributesOfItem(_ key: String) throws -> [String: Any] {
        var query = identity(of: key)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        try #require(status == errSecSuccess)
        return try #require(result as? [String: Any])
    }

    private func cleanUp() {
        // Deletes every item of the throwaway service, whichever keys the test used.
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}
