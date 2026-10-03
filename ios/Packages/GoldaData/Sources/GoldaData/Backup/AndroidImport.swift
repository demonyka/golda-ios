import Foundation
import GoldaCore

extension AndroidBackup {
    /// The Android file as a version 2 backup. All the content lands in one new profile named
    /// [personalProfileName]; its income, payday and markup come from the file's `settings`, the
    /// currencies, Gemini model and reminder go to the device block.
    ///
    /// Android orders its lists by `id`, which is the order things were created in. UUIDs have no
    /// such order, so ids are minted in ascending byte order (`IDMint`), and rows are listed and
    /// inserted by Android id: ties on `sort`, `dayOfMonth` or an operation's timestamp then resolve
    /// the way they did on Android.
    func backup(personalProfileName: String) throws -> Backup {
        let accountIds = try IDMint.mint(accounts.map(\.id), "account")
        let operationIds = try IDMint.mint(operations.map(\.id), "operation")
        let postingIds = try IDMint.mint(postings.map(\.id), "posting")
        let obligationIds = try IDMint.mint(obligations.map(\.id), "obligation")
        let goalIds = try IDMint.mint(goals.map(\.id), "goal")
        let wishIds = try IDMint.mint(wishes.map(\.id), "wish")

        // The file's own categories say which key a `categoryId` means; an id they do not hold (the
        // category was deleted, Android's SET_NULL) leaves the operation uncategorized.
        var categoryKeys: [Int64: String] = [:]
        for category in categories {
            guard categoryKeys.updateValue(category.key, forKey: category.id) == nil else {
                throw BackupError.duplicateId("category \(category.id)")
            }
        }

        // `reconciledAt` moves from the settings onto the accounts. Entries of accounts that are gone
        // are dropped, and so are keys that are not numbers.
        var reconciled: [Int64: Int64] = [:]
        for (key, at) in settings.reconciledAt {
            if let id = Int64(key) { reconciled[id] = at }
        }

        let accountList = accounts.sorted { ($0.sort, $0.id) < ($1.sort, $1.id) }.map { a in
            Account(
                id: accountIds[a.id]!, name: a.name, currency: a.currency, type: a.type, groupName: a.groupName,
                includeInFree: a.includeInFree, interestRate: a.interestRate, sort: a.sort, paymentDay: a.paymentDay,
                paymentMinor: a.paymentMinor, graceUntil: a.graceUntil, reconciledAt: reconciled[a.id]
            )
        }

        // Postings in the order Android wrote them: a transfer's source first, then its destination.
        var postingsByOperation: [Int64: [Posting]] = [:]
        for p in postings.sorted(by: { $0.id < $1.id }) {
            guard let operationId = operationIds[p.operationId] else {
                throw BackupError.danglingReference("posting \(p.id) is on operation \(p.operationId), which is not in the file")
            }
            guard let accountId = accountIds[p.accountId] else {
                throw BackupError.danglingReference("posting \(p.id) is on account \(p.accountId), which is not in the file")
            }
            postingsByOperation[p.operationId, default: []].append(
                Posting(
                    id: postingIds[p.id]!, operationId: operationId, accountId: accountId, amountMinor: p.amountMinor,
                    rubMinor: p.rubMinor
                )
            )
        }

        // Newest first; of equal timestamps the one written last (the higher id) comes first.
        let operationList = operations.sorted { ($0.timestamp, $0.id) > ($1.timestamp, $1.id) }.map { o in
            OperationFull(
                GoldaCore.Operation(
                    id: operationIds[o.id]!, type: o.type, timestamp: o.timestamp,
                    categoryKey: o.categoryId.flatMap { categoryKeys[$0] }, note: o.note, voiceText: o.voiceText,
                    purchaseAmountMinor: o.purchaseAmountMinor, purchaseCurrency: o.purchaseCurrency,
                    isEstimate: o.isEstimate, cbrFrom: o.cbrFrom, cbrTo: o.cbrTo
                ),
                postingsByOperation[o.id] ?? []
            )
        }

        let obligationList = obligations.sorted { ($0.dayOfMonth, $0.id) < ($1.dayOfMonth, $1.id) }.map { o in
            Obligation(
                id: obligationIds[o.id]!, name: o.name, amountMinor: o.amountMinor, currency: o.currency,
                dayOfMonth: o.dayOfMonth
            )
        }

        // In creation order, not in the file's "main first" order: the store lists the main goal first
        // by itself, and it must not look like the oldest goal just because Android's query put it there.
        // A goal whose account is gone keeps no link, as Android's goals do when their account is deleted.
        let goalList = goals.sorted { $0.id < $1.id }.map { g in
            Goal(
                id: goalIds[g.id]!, name: g.name, targetMinor: g.targetMinor, currency: g.currency,
                accountId: g.accountId.flatMap { accountIds[$0] }, savedMinor: g.savedMinor, isMain: g.isMain
            )
        }

        let wishList = wishes.sorted { $0.id < $1.id }.map { w in
            Wish(
                id: wishIds[w.id]!, title: w.title, amountMinor: w.amountMinor, currency: w.currency,
                createdAt: w.createdAt, decideAt: w.decideAt, status: w.status, decidedAt: w.decidedAt
            )
        }

        let profile = Profile(
            id: UUID(), name: personalProfileName, sort: 0,
            settings: ProfileSettings(
                incomeHourly: settings.incomeHourly, hourlyRate: settings.hourlyRate,
                monthlySalary: settings.monthlySalary, taxPercent: settings.taxPercent,
                hoursPerWeek: settings.hoursPerWeek, payday: settings.payday, markup: settings.markup
            )
        )
        return Backup(
            sourceVersion: 1, exportedAt: exportedAt,
            device: BackupDevice(
                displayCurrencies: settings.displayCurrencies, localCurrency: settings.localCurrency,
                baseCurrency: settings.baseCurrency, geminiModel: settings.geminiModel,
                reconcileReminder: settings.reconcileReminder
            ),
            profiles: [
                ProfileSnapshot(
                    profile: profile, accounts: accountList, operations: operationList, obligations: obligationList,
                    goals: goalList, wishes: wishList
                )
            ],
            rates: rates
        )
    }
}

/// Fresh UUIDs for Android's numeric ids.
enum IDMint {
    /// One new random UUID per id, handed out in ascending byte order: the lower the number, the
    /// lower the UUID. SQLite compares UUID blobs bytewise, so every "order by ..., id" tie-break in
    /// the store then gives the same order Android's numeric ids did.
    static func mint(_ androidIds: [Int64], _ kind: String) throws -> [Int64: UUID] {
        let ascending = androidIds.sorted()
        for (previous, next) in zip(ascending, ascending.dropFirst()) where previous == next {
            throw BackupError.duplicateId("\(kind) \(next)")
        }
        let fresh = ascending
            .map { _ in UUID() }
            .map { (id: $0, bytes: withUnsafeBytes(of: $0.uuid) { Array($0) }) }
            .sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }
        return Dictionary(uniqueKeysWithValues: zip(ascending, fresh.map(\.id)))
    }
}
