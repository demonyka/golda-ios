import Foundation
import GRDB

/// The SQLite database, migrated to the current schema. Reads and writes go through `read` and
/// `write`, each one transaction; screens follow `profiles()` and `snapshots(profileId:)`.
public final class GoldaDatabase: Sendable {
    let writer: any DatabaseWriter

    private init(_ writer: any DatabaseWriter) throws {
        try Schema.migrator.migrate(writer)
        self.writer = writer
    }

    /// The database file at [url], created with its folder when missing. A pool in WAL mode, so
    /// observations read while a write is in progress.
    public static func open(at url: URL) throws -> GoldaDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try GoldaDatabase(DatabasePool(path: url.path, configuration: configuration))
    }

    /// A private database that lives as long as this value: tests and UI test runs.
    public static func inMemory() throws -> GoldaDatabase {
        try GoldaDatabase(DatabaseQueue(configuration: configuration))
    }

    private static var configuration: Configuration {
        var configuration = Configuration()
        // Cascades from profile, operation and account depend on it (GRDB's default, made explicit).
        configuration.foreignKeysEnabled = true
        return configuration
    }

    public func read<T: Sendable>(_ body: @Sendable (Store) throws -> T) async throws -> T {
        try await writer.read { db in try body(Store(db: db)) }
    }

    /// Runs [body] in one transaction: it all lands, or nothing does when it throws.
    @discardableResult
    public func write<T: Sendable>(_ body: @Sendable (Store) throws -> T) async throws -> T {
        try await writer.write { db in try body(Store(db: db)) }
    }

    /// Every profile, again after each change to the table.
    public func profiles() -> AsyncStream<[Profile]> {
        let observation = ValueObservation
            .tracking { db -> [Profile]? in try Store(db: db).profiles() }
            .removeDuplicates()
        return stream(observation.values(in: writer, bufferingPolicy: .bufferingNewest(1)))
    }

    /// The profile's books, again after each change to them. Writes to other profiles touch the same
    /// tables and refetch, but an unchanged snapshot is not sent twice. The stream ends when the
    /// profile is deleted (here or by sync), so the app can switch to another one.
    public func snapshots(profileId: UUID) -> AsyncStream<ProfileSnapshot> {
        let observation = ValueObservation
            .tracking { db in try Store(db: db).snapshot(profileId: profileId) }
            .removeDuplicates()
        return stream(observation.values(in: writer, bufferingPolicy: .bufferingNewest(1)))
    }

    /// Bridges an observation to a stream that keeps only the latest value for a slow reader, and
    /// ends on nil, on a database error, or when the reader stops listening.
    private func stream<Element: Sendable>(_ values: AsyncValueObservation<Element?>) -> AsyncStream<Element> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    for try await value in values {
                        guard let value else { break }
                        continuation.yield(value)
                    }
                } catch {
                    // The observation only fails when the database does; ending the stream is all a
                    // screen could do about it.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
