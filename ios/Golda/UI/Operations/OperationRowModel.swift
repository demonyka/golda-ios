import Foundation
import GoldaCore

/// What one operation's row says, worked out the way Android's `OperationRow` does and kept free of
/// views so the rules can be tested: the title, the line under it, the amount and the line under
/// that. Amounts are written by `Fmt` (always the Russian way, D13); the few words the row needs
/// come from the String Catalog in `title(in:)`. Home and an account's page share it; the page
/// passes its account, so each row shows that account's own side.
struct OperationRowModel: Identifiable, Equatable, Sendable {
    /// Where the row's title comes from. Only the last three need a translation.
    enum Title: Equatable, Sendable {
        /// The note, or for a transfer the accounts it moves between ("Карта ₽ → Наличные ₾").
        case verbatim(String)
        /// A built-in category by its key; a key the app does not know falls back to the type.
        case category(String)
        case reconciliation
        case transfer
        case noCategory
    }

    /// The colour of the amount. A transfer is neither spent nor earned, so it is quieter.
    enum Tone: Equatable, Sendable {
        case normal
        case neutral
    }

    /// The small amount under the main one: the other side of a transfer, the shop's price, or
    /// the main currency's worth.
    struct Secondary: Equatable, Sendable {
        /// The other end of a transfer: "→ 800 $".
        var arrow = false
        /// Converted or estimated: "≈ 1 849 ₽".
        var approximate = false
        var amount: String

        /// "→ ≈ 265 ₾", as the row writes it.
        var text: String {
            (arrow ? "→ " : "") + (approximate ? "≈ " : "") + amount
        }
    }

    let operation: OperationFull
    let symbol: String
    let title: Title
    /// The note under a transfer's accounts, or the account a purchase was paid from when it is
    /// not the usual one.
    let supporting: String?
    /// Who wrote it, in a shared profile (D67).
    let author: OperationAuthor?
    let main: String
    let secondary: Secondary?
    let tone: Tone

    var id: UUID { operation.op.id }

    /// The row for [full] in [data]. On an account's page pass [accountId]: the amount is then that
    /// account's own side, signed as the account sees it, with its worth or other side underneath.
    /// Nil for an operation without postings, which the ledger never writes.
    init?(_ full: OperationFull, in data: AppData, accountId: UUID? = nil) {
        let op = full.op
        guard let out = full.postings.first(where: { $0.amountMinor < 0 }) ?? full.postings.first else { return nil }
        let into = full.postings.first { $0.amountMinor > 0 && $0.id != out.id }
        let outAccount = data.accountById[out.accountId]
        let intoAccount = into.flatMap { data.accountById[$0.accountId] }
        let category = op.categoryKey.flatMap { key in Category.builtIn.first { $0.key == key } }
        let ownCategory = op.categoryKey.flatMap(data.categories.own)
        let code = outAccount?.currency ?? "RUB"
        let own = accountId.flatMap { id in full.postings.first { $0.accountId == id } }
        let ownCode = own.flatMap { data.accountById[$0.accountId]?.currency } ?? code

        var title: Title
        if !op.note.isBlank {
            title = .verbatim(op.note)
        } else if let ownCategory {
            title = .verbatim(ownCategory.name)
        } else if let category {
            title = .category(category.key)
        } else {
            title = op.type == .adjustment ? .reconciliation : op.type == .transfer ? .transfer : .noCategory
        }

        let main: String
        var secondary: Secondary?
        var supporting: String?
        let usualName = outAccount.flatMap { $0.id == data.usualAccountId ? nil : $0.name }
        if op.type == .transfer, let into, let intoAccount {
            let fromName = outAccount?.name ?? ""
            if let own {
                let incoming = own.amountMinor > 0
                let otherAccount = incoming ? outAccount : intoAccount
                let otherCode = otherAccount?.currency ?? code
                main = Fmt.amount(own.amountMinor, ownCode, signed: true)
                if otherCode != ownCode {
                    secondary = Secondary(amount: Fmt.amount((incoming ? out : into).amountMinor.magnitudeAsInt64, otherCode))
                }
            } else {
                // A transfer is neither spent nor earned: no sign.
                main = Fmt.amount(-out.amountMinor, code)
                if intoAccount.currency != code {
                    secondary = Secondary(arrow: true, approximate: op.isEstimate, amount: Fmt.amount(into.amountMinor, intoAccount.currency))
                }
            }
            // The accounts say what a transfer is; a note, if any, goes underneath.
            title = .verbatim("\(fromName) → \(intoAccount.name)")
            supporting = Self.restatesTransfer(op.note, from: outAccount?.name, to: intoAccount.name) || op.note.isBlank ? nil : op.note
            tone = .neutral
        } else {
            if let own {
                main = Fmt.amount(own.amountMinor, ownCode, signed: true)
                if let purchaseCurrency = op.purchaseCurrency, let purchaseMinor = op.purchaseAmountMinor {
                    secondary = Secondary(amount: Fmt.amount(-purchaseMinor, purchaseCurrency))
                } else if ownCode != data.base.code {
                    // What the account's own amount comes to in the main currency.
                    secondary = Secondary(approximate: true, amount: data.base.approx(own.rubMinor))
                }
            } else if let purchaseCurrency = op.purchaseCurrency, let purchaseMinor = op.purchaseAmountMinor {
                // On Home one amount says it: the price in the currency it was paid in.
                main = Fmt.amount(-purchaseMinor, purchaseCurrency)
                supporting = usualName
            } else {
                main = Fmt.amount(out.amountMinor, code, signed: true)
                supporting = usualName
            }
            tone = .normal
        }

        self.operation = full
        self.symbol = ownCategory.map { data.categories.symbol($0.key) } ?? Symbols.operation(categoryKey: category?.key, type: op.type)
        self.title = title
        self.supporting = supporting
        author = data.authorship?.byOperation[op.id]
        self.main = main
        self.secondary = secondary
    }

    /// The title in the language of [locale].
    func title(in locale: Locale) -> String {
        switch title {
        case .verbatim(let text): text
        case .category(let key): CategoryName.resource(key).text(in: locale)
        case .reconciliation: LocalizedStringResource("Reconciliation", comment: "Row title of an operation that brought an account to the bank's balance.").text(in: locale)
        case .transfer: LocalizedStringResource("Transfer", comment: "Row title of a transfer between accounts that has no note.").text(in: locale)
        case .noCategory: LocalizedStringResource("No category", comment: "Row title of an operation with neither a note nor a category.").text(in: locale)
        }
    }

    /// The line under the title: the note or the account, then who wrote it in a shared profile,
    /// "Наличные ₾ · Лекла".
    func supportingText(in locale: Locale) -> String? {
        let parts = [supporting, author?.text(in: locale)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The whole row as VoiceOver reads it: the title, the line under it, then the amounts in words.
    func accessibilityLabel(in locale: Locale) -> String {
        var parts = [title(in: locale)]
        if let supporting = supportingText(in: locale) { parts.append(supporting) }
        parts.append(SpokenAmount.text(main, locale: locale))
        if let secondary {
            let spoken = SpokenAmount.text(secondary.amount, locale: locale)
            parts.append(secondary.approximate ? LocalizedStringResource("about \(spoken)", comment: "VoiceOver: an approximate amount, “about 1849 Russian rubles”.").text(in: locale) : spoken)
        }
        return parts.joined(separator: ", ")
    }

    /// Whether a transfer's note only says what "A → B" already does: it starts with
    /// "перевод"/"transfer", or names both accounts (by the first four letters of their first word
    /// of three letters or more).
    static func restatesTransfer(_ note: String, from: String?, to: String?) -> Bool {
        let text = note.lowercased()
        if text.hasPrefix("перевод") || text.hasPrefix("transfer") { return true }
        func stem(_ name: String?) -> String? {
            name?.lowercased()
                .split(separator: " ", omittingEmptySubsequences: false)
                .flatMap { $0.split(separator: "-", omittingEmptySubsequences: false) }
                .first { $0.count >= 3 }
                .map { String($0.prefix(4)) }
        }
        guard let a = stem(from), let b = stem(to) else { return false }
        return text.contains(a) && text.contains(b)
    }
}

/// The built-in categories' names in the interface language, by key. Android named them in code;
/// here they are catalog entries, one per key (both "other" keys share "Other").
enum CategoryName {
    static func resource(_ key: String) -> LocalizedStringResource {
        switch key {
        case "eating_out": LocalizedStringResource("Eating out", comment: "Category: cafés and restaurants.")
        case "groceries": LocalizedStringResource("Groceries", comment: "Category.")
        case "transport": LocalizedStringResource("Transport", comment: "Category.")
        case "housing": LocalizedStringResource("Housing", comment: "Category: rent and utilities.")
        case "telecom": LocalizedStringResource("Phone", comment: "Category: phone and internet.")
        case "fun": LocalizedStringResource("Fun", comment: "Category: entertainment.")
        case "health": LocalizedStringResource("Health", comment: "Category.")
        case "clothes": LocalizedStringResource("Clothes", comment: "Category.")
        case "subscriptions": LocalizedStringResource("Subscriptions", comment: "Category.")
        case "travel": LocalizedStringResource("Travel", comment: "Category.")
        case "fees": LocalizedStringResource("Fees", comment: "Category: bank and ATM fees.")
        case "salary": LocalizedStringResource("Salary", comment: "Income category.")
        case "interest": LocalizedStringResource("Interest", comment: "Income category: interest earned.")
        case "gift": LocalizedStringResource("Gift", comment: "Income category.")
        default: LocalizedStringResource("Other", comment: "Category: anything else, spent or earned.")
        }
    }
}

private extension String {
    /// Kotlin's `isBlank()`: empty or whitespace only.
    var isBlank: Bool { allSatisfy(\.isWhitespace) }
}

private extension Int64 {
    /// Kotlin's `abs` on a Long; a posting is never `Int64.min`, so the magnitude always fits.
    var magnitudeAsInt64: Int64 { Int64(clamping: magnitude) }
}
