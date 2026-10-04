import Foundation
import GRDB

/// The SQLite database, migrated to the current schema. Reads and writes go through `read` and
/// `write`, each one transaction; screens follow `profiles()`, `snapshots(profileId:)` and `rates()`.
public final class GoldaDatabase: Sendable {
    let writer: any DatabaseWriter
    /// Epoch milliseconds now: when a change to the books is stamped for sync (last writer wins).
    let clock: @Sendable () -> Int64

    /// Internal for the migration tests, which hand it a file written by an older schema.
    init(
        _ writer: any DatabaseWriter, eraseDatabaseOnSchemaChange: Bool = false, clock: (@Sendable () -> Int64)?
    ) throws {
        var migrator = Schema.migrator
        migrator.eraseDatabaseOnSchemaChange = eraseDatabaseOnSchemaChange
        try migrator.migrate(writer)
        self.writer = writer
        self.clock = clock ?? { Int64(Date().timeIntervalSince1970 * 1000) }
    }

    /// The database file at [url], created with its folder when missing. A pool in WAL mode, so
    /// observations read while a write is in progress.
    ///
    /// [eraseDatabaseOnSchemaChange] wipes the file and builds it afresh when the migrations it
    /// recorded now create a different schema. Only for builds where no real data can exist: an
    /// unreleased migration edited in place leaves older files with its old shape, which the
    /// migrator counts as applied, and every read of the changed tables then fails. Off, such a
    /// file is left exactly as it is.
    ///
    /// [clock] stamps each change for sync; nil is the phone's clock.
    public static func open(
        at url: URL, eraseDatabaseOnSchemaChange: Bool = false, clock: (@Sendable () -> Int64)? = nil
    ) throws -> GoldaDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try GoldaDatabase(
            DatabasePool(path: url.path, configuration: configuration),
            eraseDatabaseOnSchemaChange: eraseDatabaseOnSchemaChange, clock: clock
        )
    }

    /// A private database that lives as long as this value: tests and UI test runs.
    public static func inMemory(clock: (@Sendable () -> Int64)? = nil) throws -> GoldaDatabase {
        try GoldaDatabase(DatabaseQueue(configuration: configuration), clock: clock)
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

    /// Runs [body] in one transaction: it all lands, or nothing does when it throws. What it
    /// changed in the books joins the sync queue in the same transaction (`SyncLedger`), so no
    /// change can reach the books without its way to the other phones, nor the other way round.
    @discardableResult
    public func write<T: Sendable>(_ body: @Sendable (Store) throws -> T) async throws -> T {
        let clock = clock
        return try await writer.write { db in
            let result = try body(Store(db: db))
            try SyncLedger.flush(db, now: clock())
            return result
        }
    }

    /// Every profile, again after each change to the table.
    public func profiles() -> AsyncThrowingStream<[Profile], any Error> {
        let observation = ValueObservation
            .tracking { db -> [Profile]? in try Store(db: db).profiles() }
            .removeDuplicates()
        return stream(observation.values(in: writer, bufferingPolicy: .bufferingNewest(1)))
    }

    /// The profile's books, again after each change to them. Writes to other profiles touch the same
    /// tables and refetch, but an unchanged snapshot is not sent twice. The stream ends when the
    /// profile is deleted (here or by sync), so the app can switch to another one.
    public func snapshots(profileId: UUID) -> AsyncThrowingStream<ProfileSnapshot, any Error> {
        let observation = ValueObservation
            .tracking { db in try Store(db: db).snapshot(profileId: profileId) }
            .removeDuplicates()
        return stream(observation.values(in: writer, bufferingPolicy: .bufferingNewest(1)))
    }

    /// Every profile's books, in the profiles' order, again after each change to any of them. What
    /// spans the profiles (the reminders) follows this; the screens follow the profile on screen.
    public func allSnapshots() -> AsyncThrowingStream<[ProfileSnapshot], any Error> {
        let observation = ValueObservation
            .tracking { db -> [ProfileSnapshot]? in
                let store = Store(db: db)
                return try store.profiles().compactMap { try store.snapshot(profileId: $0.id) }
            }
            .removeDuplicates()
        return stream(observation.values(in: writer, bufferingPolicy: .bufferingNewest(1)))
    }

    /// The rate table by code, again after each change to it (a refresh, a reset), so the app
    /// revalues what it shows without rereading after its own refresh. Rates are shared by every
    /// profile; each applies its own markup.
    public func rates() -> AsyncThrowingStream<[RateRecord], any Error> {
        let observation = ValueObservation
            .tracking { db -> [RateRecord]? in try Store(db: db).rates() }
            .removeDuplicates()
        return stream(observation.values(in: writer, bufferingPolicy: .bufferingNewest(1)))
    }

    /// Bridges an observation to a stream that keeps only the latest value for a slow reader, ends
    /// on nil or when the reader stops listening, and throws when the database fails: a stream that
    /// merely ended would look like a deleted profile, and the app would wait for books that never
    /// come.
    private func stream<Element: Sendable>(
        _ values: AsyncValueObservation<Element?>
    ) -> AsyncThrowingStream<Element, any Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    for try await value in values {
                        guard let value else { break }
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
