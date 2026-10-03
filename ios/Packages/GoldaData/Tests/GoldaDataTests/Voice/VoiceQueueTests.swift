import Foundation
import Testing

@testable import GoldaData

/// The queue's files: named by the time and the profile, oldest first, out of backups.
@Suite final class VoiceQueueTests {
    let folder: TemporaryFolder
    let queue: VoiceQueue
    let personal = StoreFixture.id(1)
    let recordedAt: Int64 = 1_759_399_200_000

    init() throws {
        folder = try TemporaryFolder()
        queue = VoiceQueue(directory: folder.url.appending(path: "voice", directoryHint: .isDirectory))
    }

    @Test func aNewNoteIsNamedByItsTimeAndProfile() throws {
        let file = try queue.newFile(profileId: personal, recordedAt: recordedAt)
        #expect(file.lastPathComponent == "1759399200000.00000000-0000-0000-0000-000000000001.wav")
        #expect(file.deletingLastPathComponent().standardizedFileURL == queue.directory.standardizedFileURL)
        #expect(queue.recordedAt(of: file) == recordedAt)
        #expect(queue.profileId(of: file) == personal)
        #expect(try queue.newFile(profileId: personal, recordedAt: recordedAt, fileExtension: "m4a").pathExtension == "m4a")
    }

    @Test func theFolderIsCreatedOnDemandAndKeptOutOfBackups() throws {
        #expect(!FileManager.default.fileExists(atPath: queue.directory.path(percentEncoded: false)))
        #expect(queue.pending().isEmpty)

        _ = try queue.newFile(profileId: personal, recordedAt: recordedAt)
        var isFolder: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: queue.directory.path(percentEncoded: false), isDirectory: &isFolder))
        #expect(isFolder.boolValue)
        // A fresh URL, so the value comes from the disk, not from the one that set it.
        let values = try URL(fileURLWithPath: queue.directory.path(percentEncoded: false)).resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func pendingNotesComeOldestFirstAndOnlyAudio() throws {
        let family = StoreFixture.id(2)
        let names = [
            "1759399300000.\(personal.uuidString).wav",
            "1759399100000.\(family.uuidString).wav",
            "1759399200000.\(personal.uuidString).m4a",
            "1759399150000.ogg",
            "notes.txt",
            ".DS_Store",
        ]
        _ = try queue.newFile(profileId: personal, recordedAt: recordedAt)
        for name in names { try Data([1]).write(to: queue.directory.appending(path: name)) }

        #expect(queue.pending().map(\.lastPathComponent) == [
            "1759399100000.\(family.uuidString).wav",
            "1759399150000.ogg",
            "1759399200000.\(personal.uuidString).m4a",
            "1759399300000.\(personal.uuidString).wav",
        ])
    }

    @Test func aNameWithoutAProfileStillHasItsTime() throws {
        // Android's own naming: the time alone.
        let file = try folder.file("1759399150000.ogg")
        #expect(queue.recordedAt(of: file) == 1_759_399_150_000)
        #expect(queue.profileId(of: file) == nil)
    }

    @Test func aNameWithoutATimeFallsBackToWhenTheFileWasWritten() throws {
        let file = try folder.file("note.wav")
        try setModified(file, 1_759_399_123_000)
        #expect(queue.recordedAt(of: file) == 1_759_399_123_000)
        #expect(queue.modifiedAt(of: file) == 1_759_399_123_000)
        #expect(queue.profileId(of: file) == nil)
        #expect(queue.profileId(of: try folder.file("1759399150000.not-a-uuid.wav")) == nil)
    }

    @Test func deletingANoteRemovesItAndAMissingOneIsFine() throws {
        let file = try queue.newFile(profileId: personal, recordedAt: recordedAt)
        try Data([1]).write(to: file)
        #expect(queue.pending().map(\.lastPathComponent) == [file.lastPathComponent])

        try queue.delete(file)
        #expect(queue.pending().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        try queue.delete(file)
    }

    @Test func theLiveQueueIsInApplicationSupport() {
        #expect(VoiceQueue.live.directory.lastPathComponent == "voice")
        #expect(VoiceQueue.live.directory.deletingLastPathComponent().standardizedFileURL
            == URL.applicationSupportDirectory.standardizedFileURL)
    }
}
