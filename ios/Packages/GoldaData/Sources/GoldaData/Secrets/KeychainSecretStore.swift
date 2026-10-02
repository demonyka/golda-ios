import Foundation
import Security

/// Secrets as generic-password Keychain items.
///
/// `AfterFirstUnlockThisDeviceOnly` keeps the items out of iCloud Keychain and out of device
/// backups (a restored phone asks for the key again, like Android's undecryptable `KeyVault` data),
/// while still letting a voice note that was recorded with the screen locked reach the key once
/// the phone has been unlocked after boot. Items are explicitly non-synchronizable for the same reason.
public struct KeychainSecretStore: SecretStore {
    public static let defaultService = "com.f4studio.golda"

    private let service: String

    /// [service] is injectable so tests can work in a namespace of their own and never touch the
    /// real key.
    public init(service: String = KeychainSecretStore.defaultService) {
        self.service = service
    }

    public func read(_ key: String) -> String? {
        var query = identity(of: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        // Bytes that are not UTF-8 are as good as missing.
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String, for key: String) throws {
        guard let secret = normalizedSecret(value) else {
            try delete(key)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(secret.utf8),
            // Set on update too, so an item written by an earlier build is brought to the same policy.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let identity = identity(of: key)
        var status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(identity.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(identity(of: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status)
        }
    }

    /// The attributes that pick out one item.
    private func identity(of key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}
