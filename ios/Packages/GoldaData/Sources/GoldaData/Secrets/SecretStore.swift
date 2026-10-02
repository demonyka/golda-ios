import Foundation

/// Where secrets (today only the Gemini API key) live. Android kept them AES-encrypted inside the
/// settings store; iOS keeps them out of every database, defaults file and backup instead.
///
/// The calls are synchronous: a Keychain lookup is a local, millisecond call, and a sync API lets
/// the voice queue and the settings screen read the key without hopping onto an actor first.
public protocol SecretStore: Sendable {
    /// The stored string, or nil when there is none or it cannot be read. Android's `KeyVault`
    /// returned nil for data it could not decrypt, and callers treat "no key" and "unusable key"
    /// the same way (the note waits, the settings screen asks for a key), so no error is thrown.
    func read(_ key: String) -> String?

    /// Stores [value] under [key], replacing what was there. The value is trimmed, and a blank one
    /// removes the entry, as Android's `setGeminiKey` did, so an emptied text field clears the key.
    func write(_ value: String, for key: String) throws

    /// Removes [key]; deleting a key that does not exist is not an error.
    func delete(_ key: String) throws
}

/// Names of the secrets the app keeps.
public enum SecretKey {
    public static let gemini = "geminiKey"
}

public enum SecretStoreError: Error, Equatable, Sendable {
    /// The Keychain refused the change; the payload is the `OSStatus` it answered with.
    case keychain(OSStatus)
}

/// The trimmed secret, or nil when nothing is left of it. One rule for every store.
func normalizedSecret(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
