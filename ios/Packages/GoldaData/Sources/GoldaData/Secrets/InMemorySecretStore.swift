import Foundation

/// A secret store that forgets everything on exit. Tests and previews use it, so they run without
/// a Keychain, a signed host or a device.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    // Reads and writes arrive from any task, so every access takes the lock.
    private let lock = NSLock()
    private var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public func read(_ key: String) -> String? {
        lock.withLock { values[key] }
    }

    public func write(_ value: String, for key: String) throws {
        let normalized = normalizedSecret(value)
        lock.withLock { values[key] = normalized }
    }

    public func delete(_ key: String) throws {
        lock.withLock { values[key] = nil }
    }
}
