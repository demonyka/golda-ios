import Foundation
import GoldaCore

@testable import GoldaData

/// Rows for the store tests. Namespaced, because other suites share this test target.
enum StoreFixture {
    /// A stable id for fixture number [n], as GoldaCore's tests make them.
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    static func profile(_ n: Int, name: String = "Личный", sort: Int = 0) -> Profile {
        Profile(id: id(n), name: name, sort: sort)
    }

    static func account(_ n: Int, currency: String = "RUB", sort: Int = 0) -> Account {
        Account(id: id(n), name: "Счёт \(n)", currency: currency, type: .card, includeInFree: true, sort: sort)
    }

    static func operation(_ n: Int, type: OpType = .expense, timestamp: Int64 = 1_000) -> GoldaCore.Operation {
        GoldaCore.Operation(id: id(n), type: type, timestamp: timestamp)
    }

    static func posting(_ n: Int, operation: Int, account: Int, amount: Int64) -> Posting {
        Posting(id: id(n), operationId: id(operation), accountId: id(account), amountMinor: amount, rubMinor: amount)
    }

    /// A database with profiles [profiles] and nothing else.
    static func database(profiles: Int...) async throws -> GoldaDatabase {
        let database = try GoldaDatabase.inMemory()
        try await database.write { store in
            for n in profiles { try store.save(profile(n, name: "Профиль \(n)", sort: n)) }
        }
        return database
    }
}

extension Store {
    /// Writes an operation with its postings, the way the repository will.
    func book(_ operation: GoldaCore.Operation, _ postings: [Posting], profileId: UUID, updatedAt: Int64 = 0) throws {
        try save(operation, profileId: profileId, updatedAt: updatedAt)
        for posting in postings { try save(posting, profileId: profileId) }
    }
}
