import Foundation

/// The backup file format: JSON, `version: 2` for what this app writes, and Android's `version: 1`
/// for reading.
public enum BackupFormat {
    /// The version `encode` writes.
    public static let version = 2

    /// Pretty-printed with sorted keys, so two backups of the same books differ only where the books
    /// do and a file diffs well. UUIDs are written as strings, instants as epoch milliseconds.
    public static func encode(_ backup: Backup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(WireBackup(backup))
    }

    /// Reads a whole file and checks it; nothing is returned for a file that is not completely sound,
    /// so the caller can touch its data only after this succeeds. A file without a `version` is
    /// version 1, as in Kotlin, where 1 is the default.
    ///
    /// [personalProfileName] names the profile an Android file (which has no profiles) is imported
    /// into; version 2 files carry their own names and ignore it.
    public static func decode(_ data: Data, personalProfileName: String) throws -> Backup {
        let decoder = JSONDecoder()
        let backup: Backup
        do {
            switch try decoder.decode(Header.self, from: data).version ?? 1 {
            case 1:
                backup = try decoder.decode(AndroidBackup.self, from: data).backup(personalProfileName: personalProfileName)
            case 2:
                backup = try decoder.decode(WireBackup.self, from: data).backup
            case let other:
                throw BackupError.unsupportedVersion(other)
            }
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.unreadable(describe(error))
        }
        try backup.validate()
        return backup
    }

    private struct Header: Decodable {
        var version: Int?
    }

    private static func describe(_ error: any Error) -> String {
        guard let error = error as? DecodingError else { return String(describing: error) }
        func path(_ keys: [any CodingKey]) -> String {
            keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "missing key at \(path(context.codingPath + [key]))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(path(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }
}
