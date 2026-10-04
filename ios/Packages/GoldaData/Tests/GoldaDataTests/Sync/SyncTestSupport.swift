import Foundation
import GoldaCore

@testable import GoldaData

extension Account {
    static func card(_ name: String, currency: String = "RUB", sort: Int = 0) -> Account {
        Account(name: name, currency: currency, type: .card, includeInFree: true, sort: sort)
    }
}

/// Records as another phone would send them.
enum SyncFixture {
    static let device = "zzzzzzzzzzzz"

    static func record(_ payload: SyncPayload, zone: SyncZone, at time: Int64, by device: String = SyncFixture.device) -> SyncRecord {
        SyncRecord(zone: zone, payload: payload, updatedAt: time, authorDevice: device)
    }

    /// A profile with one account in [zone], as its first fetch brings it.
    static func profile(_ name: String, account: Account, zone: SyncZone, at time: Int64) -> [SyncRecord] {
        [
            record(.profile(Profile(id: zone.profileId, name: name)), zone: zone, at: time),
            record(.account(account), zone: zone, at: time),
        ]
    }

    /// A transfer of [amount] from [from] to [to]: the header and both legs.
    static func transfer(
        _ amount: Int64, from: UUID, to: UUID, zone: SyncZone, at time: Int64, id: UUID = UUID()
    ) -> (header: SyncRecord, out: SyncRecord, into: SyncRecord) {
        let operation = GoldaCore.Operation(id: id, type: .transfer, timestamp: time)
        return (
            record(.operation(operation, postingCount: 2), zone: zone, at: time),
            record(.posting(Posting(operationId: id, accountId: from, amountMinor: -amount, rubMinor: -amount)), zone: zone, at: time),
            record(.posting(Posting(operationId: id, accountId: to, amountMinor: amount, rubMinor: amount)), zone: zone, at: time)
        )
    }
}
