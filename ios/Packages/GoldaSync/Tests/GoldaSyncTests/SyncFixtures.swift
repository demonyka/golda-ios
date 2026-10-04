import Foundation
import GoldaCore
import GoldaData
@testable import GoldaSync

/// A clock the tests move by hand, in ms since 1970.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 1_760_000_000_000

    var now: Int64 { lock.withLock { value } }

    func advance(_ ms: Int64) { lock.withLock { value += ms } }

    var reader: @Sendable () -> Int64 { { [self] in now } }
}

enum Fixtures {
    static let profileId = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
    static let accountId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    static func profile(_ name: String = "Семья", id: UUID = profileId, zone: SyncZone? = nil, at time: Int64 = 1, by device: String = "A") -> SyncRecord {
        SyncRecord(
            zone: zone ?? .own(id),
            payload: .profile(Profile(id: id, name: name, sort: 2, settings: ProfileSettings(
                incomeHourly: true, hourlyRate: 1500.5, monthlySalary: 0, taxPercent: 13, hoursPerWeek: 40, payday: 10, markup: 0.02
            ))),
            updatedAt: time, authorDevice: device
        )
    }

    /// An expense of [amountMinor] with its one posting, as the spike writes it.
    static func expense(
        _ note: String, _ amountMinor: Int64, in zone: SyncZone, id: UUID = UUID(), at time: Int64 = 1, by device: String = "A"
    ) -> (operation: SyncRecord, posting: SyncRecord) {
        let operation = GoldaCore.Operation(id: id, type: .expense, timestamp: time, categoryKey: "food", note: note)
        let posting = Posting(operationId: id, accountId: accountId, amountMinor: -amountMinor, rubMinor: -amountMinor)
        return (
            SyncRecord(zone: zone, payload: .operation(operation, postingCount: 1), updatedAt: time, authorDevice: device),
            SyncRecord(zone: zone, payload: .posting(posting), updatedAt: time, authorDevice: device)
        )
    }

    static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "golda-sync-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "sync.sqlite")
    }
}

extension SyncRecord {
    var note: String? {
        if case .operation(let op, _) = payload { return op.note }
        return nil
    }
}
