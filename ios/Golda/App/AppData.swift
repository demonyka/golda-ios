import Foundation
import GoldaCore
import GoldaData

/// One consistent snapshot of everything the screens show for the active profile, the port of
/// Android's `AppData`. Built from one `ProfileSnapshot` (a single read transaction), this phone's
/// settings and the rate table, so every number on screen comes from the same moment.
struct AppData: Sendable {
    let profile: Profile
    /// `GoldaCore.Settings` of this profile on this phone (D16, D21).
    let settings: Settings
    /// By `sort`, then id.
    let accounts: [Account]
    /// Newest first.
    let operations: [OperationFull]
    /// The payments typed in by hand; `allObligations` adds the ones debts carry.
    let obligations: [Obligation]
    /// The main goal first, then the oldest.
    let goals: [Goal]
    let wishes: [Wish]
    /// The built-in categories and the profile's own (D68).
    let categories: CategoryCatalog
    /// Official rates with the profile's markup.
    let rates: Rates
    /// The day of the newest rate in the table, `yyyy-MM-dd`.
    let ratesDate: String?
    /// The main currency the big numbers and totals are shown in.
    let base: Base
    let states: [UUID: AccountState]
    let accountById: [UUID: Account]
    let zone: TimeZone

    /// Monthly payments typed in settings plus the ones debts carry.
    let allObligations: [Obligation]
    /// Operations worth listing: opening balances are bookkeeping, not events.
    let visibleOperations: [OperationFull]
    /// The account things are usually paid from; lists name an account only when it is a different one.
    let usualAccountId: UUID?
    /// Who wrote each operation, in a profile shared with someone (D67); nil otherwise, or until
    /// it is worked out. Set after the snapshot: it needs the server's fields and the share.
    var authorship: Authorship?

    init(snapshot: ProfileSnapshot, device: DeviceSettings, rates rateTable: [RateRecord], zone: TimeZone) {
        profile = snapshot.profile
        settings = Settings(profile: snapshot.profile.settings, device: device, profileId: snapshot.profile.id)
        accounts = snapshot.accounts
        operations = snapshot.operations
        obligations = snapshot.obligations
        goals = snapshot.goals
        wishes = snapshot.wishes
        categories = CategoryCatalog(snapshot.categories)
        rates = Rates(
            Dictionary(rateTable.map { ($0.code, $0.rubPerUnit) }, uniquingKeysWith: { _, last in last }),
            markup: snapshot.profile.settings.markup
        )
        ratesDate = rateTable.map(\.date).max()
        base = Base.of(settings, rates)
        states = Ledger.states(accounts, operations.flatMap(\.postings))
        accountById = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.zone = zone
        allObligations = obligations + Debts.obligations(accounts, states)
        visibleOperations = operations.filter { $0.op.type != .opening }
        usualAccountId = settings.lastAccountId ?? accounts.first(where: Budget.isFree)?.id
    }

    /// "45,8 $ · 124 ₾ · 1 498 ฿": [rubMinor] in every display currency but [exclude], the local one first.
    func others(rubMinor: Int64, exclude: String) -> String {
        CurrencyDisplay.others(rubMinor: rubMinor, exclude: exclude, settings: settings, rates: rates)
    }

    /// Currencies to pick from, in one order everywhere: the local one, the display ones, then [extra].
    func currencyChoices(extra: [String] = []) -> [String] {
        CurrencyDisplay.currencyChoices(settings: settings, extra: extra)
    }
}
