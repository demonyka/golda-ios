import Foundation

/// Voice notes waiting to be understood, one file each, the port of Android's `VoiceQueue`.
///
/// A note is named `<epochMillis>.<profileUUID>.<ext>`: the time it was recorded, which the
/// operations it becomes are dated with however late they are understood, and the profile that was
/// active then, which they are booked into (ARCHITECTURE, "Голос"). Names sort by time, as long as
/// epoch milliseconds have 13 digits (until the year 2286).
public struct VoiceQueue: Sendable {
    /// What a note can be: WAV from the iOS recorder; Opus, AAC and M4A as Android knew them.
    public static let audioExtensions: Set<String> = ["ogg", "aac", "m4a", "wav"]

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/voice/`.
    public static var live: VoiceQueue {
        VoiceQueue(directory: URL.applicationSupportDirectory.appending(path: "voice", directoryHint: .isDirectory))
    }

    /// Where the recorder writes a note recorded at [recordedAt] (epoch milliseconds) while
    /// [profileId] is active. The folder is created when missing and kept out of device backups:
    /// the recorder creates the file itself, so the mark goes on the folder, which covers whatever
    /// lands in it.
    public func newFile(profileId: UUID, recordedAt: Int64, fileExtension: String = "wav") throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        return directory.appending(path: "\(recordedAt).\(profileId.uuidString).\(fileExtension)", directoryHint: .notDirectory)
    }

    /// Notes waiting, oldest first (by name). None when the folder does not exist yet or cannot be
    /// read, as Android's `listFiles().orEmpty()`.
    public func pending() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { Self.audioExtensions.contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// When the note was recorded, epoch milliseconds: from its name, or, for a file not named by
    /// this queue, when it was last written (Android's fallback).
    public func recordedAt(of file: URL) -> Int64 {
        Int64(nameParts(file).first ?? "") ?? modifiedAt(of: file) ?? 0
    }

    /// The profile that was active when the note was recorded; nil for a name without one.
    public func profileId(of file: URL) -> UUID? {
        let parts = nameParts(file)
        return parts.count == 2 ? UUID(uuidString: parts[1]) : nil
    }

    /// Removes the note; one that is already gone is not an error.
    public func delete(_ file: URL) throws {
        do {
            try FileManager.default.removeItem(at: file)
        } catch CocoaError.fileNoSuchFile {
            // Gone already: that is what was asked.
        }
    }

    /// When the file was last written, epoch milliseconds; nil when it cannot be read. A note
    /// written within the last moments may still be recording.
    public func modifiedAt(of file: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
        return (attributes?[.modificationDate] as? Date).map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
    }

    private func nameParts(_ file: URL) -> [String] {
        file.deletingPathExtension().lastPathComponent.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    }
}
