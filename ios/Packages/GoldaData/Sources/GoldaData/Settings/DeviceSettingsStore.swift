import Foundation

/// [DeviceSettings] in UserDefaults, the iOS counterpart of Android's `SettingsStore` for the
/// device part of the settings.
///
/// The store is the only writer of its key, so it keeps the decoded value in memory and every read
/// is a plain property access: the launch path and SwiftUI can read without awaiting. `UserDefaults`
/// is injectable so tests and UI scenarios work in a throwaway suite.
public final class DeviceSettingsStore: @unchecked Sendable {
    public static let defaultKey = "deviceSettings"

    private let defaults: UserDefaults
    private let key: String
    // Guards `value` and `observers`; updates can race from the voice queue and from the UI.
    private let lock = NSLock()
    private var value: DeviceSettings
    private var observers: [UUID: AsyncStream<DeviceSettings>.Continuation] = [:]

    public init(defaults: UserDefaults = .standard, key: String = DeviceSettingsStore.defaultKey) {
        self.defaults = defaults
        self.key = key
        // Missing or unreadable data is a fresh install, not an error: take the defaults.
        value = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(DeviceSettings.self, from: $0) }
            ?? DeviceSettings()
    }

    public var current: DeviceSettings {
        lock.withLock { value }
    }

    /// Applies [change], saves the result and tells the observers; returns the new settings. A change
    /// that leaves everything as it was neither writes nor notifies.
    @discardableResult
    public func update(_ change: (inout DeviceSettings) -> Void) -> DeviceSettings {
        lock.withLock {
            var next = value
            change(&next)
            apply(next)
            return next
        }
    }

    /// Back to the defaults, as after a fresh install ("reset all data").
    public func reset() {
        lock.withLock {
            apply(DeviceSettings())
            defaults.removeObject(forKey: key)
        }
    }

    /// The current settings first, then every later change, like collecting Android's `Flow`. A
    /// slow reader skips to the newest value instead of queueing the old ones.
    public func changes() -> AsyncStream<DeviceSettings> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            lock.withLock {
                observers[id] = continuation
                continuation.yield(value)
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.observers[id] = nil }
            }
        }
    }

    /// Must be called with the lock held. Yielding inside the lock keeps the order of two racing
    /// updates the same for every observer; `yield` never blocks or calls back into the store.
    private func apply(_ next: DeviceSettings) {
        guard next != value else { return }
        value = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: key) }
        for continuation in observers.values { continuation.yield(next) }
    }
}
