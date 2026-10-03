import Foundation
import GoldaCore
import GoldaData

/// What a profile holds, counted: what deleting it takes along.
struct ProfileContents: Equatable, Sendable {
    var accounts: Int
    /// The ones the screens list: opening balances are bookkeeping and go with their accounts.
    var operations: Int
    var goals: Int
    /// The whole wishlist, decided purchases included.
    var wishes: Int
    /// The payments typed in; those of debts go with their accounts.
    var payments: Int

    init(accounts: Int = 0, operations: Int = 0, goals: Int = 0, wishes: Int = 0, payments: Int = 0) {
        self.accounts = accounts
        self.operations = operations
        self.goals = goals
        self.wishes = wishes
        self.payments = payments
    }

    init(_ snapshot: ProfileSnapshot) {
        self.init(
            accounts: snapshot.accounts.count,
            operations: snapshot.operations.count(where: { $0.op.type != .opening }),
            goals: snapshot.goals.count,
            wishes: snapshot.wishes.count,
            payments: snapshot.obligations.count
        )
    }

    var isEmpty: Bool { self == ProfileContents() }
}

/// The question before a profile goes with everything in it. Nothing can bring it back, so the
/// question counts what goes; and the last profile cannot go at all.
struct ProfileDeletion: Equatable, Sendable {
    let name: String
    /// Nil when the count could not be read; the question then names the kinds of things that go.
    let contents: ProfileContents?

    /// The app always has a profile to show.
    static func canDelete(profileCount: Int) -> Bool { profileCount > 1 }

    /// "Удалить «Семья»?"
    func title(in locale: Locale) -> String {
        LocalizedStringResource("Delete “\(name)”?", table: "Profiles", comment: "Title of the question before a profile is deleted, with its name.").text(in: locale)
    }

    /// What goes too: "7 счетов, 25 операций и 2 платежа", or that there is nothing in it yet.
    func message(in locale: Locale) -> String {
        guard let contents else { return Self.generalWarning.text(in: locale) }
        let parts = Self.parts(contents).map { $0.text(in: locale) }
        if parts.isEmpty { return Self.emptyNote.text(in: locale) }
        let list = parts.formatted(.list(type: .and).locale(locale))
        return LocalizedStringResource(
            "Everything in it goes too: \(list). This can’t be undone.", table: "Profiles",
            comment: "Question before a profile is deleted: what goes with it, “7 accounts, 25 operations and 2 payments”."
        ).text(in: locale)
    }

    /// The counts that are not zero, in the order the app shows them.
    private static func parts(_ contents: ProfileContents) -> [LocalizedStringResource] {
        var parts: [LocalizedStringResource] = []
        if contents.accounts > 0 {
            parts.append(LocalizedStringResource("\(contents.accounts) accounts", table: "Profiles", comment: "A number of accounts, inside the question before a profile is deleted."))
        }
        if contents.operations > 0 {
            parts.append(LocalizedStringResource("\(contents.operations) operations", table: "Profiles", comment: "A number of operations, inside the question before a profile is deleted."))
        }
        if contents.goals > 0 {
            parts.append(LocalizedStringResource("\(contents.goals) goals", table: "Profiles", comment: "A number of goals, inside the question before a profile is deleted."))
        }
        if contents.wishes > 0 {
            parts.append(LocalizedStringResource("\(contents.wishes) wishlist items", table: "Profiles", comment: "A number of purchases in the wishlist, inside the question before a profile is deleted."))
        }
        if contents.payments > 0 {
            parts.append(LocalizedStringResource("\(contents.payments) payments", table: "Profiles", comment: "A number of monthly payments, inside the question before a profile is deleted."))
        }
        return parts
    }

    static let confirmTitle = LocalizedStringResource("Delete", table: "Profiles", comment: "Confirms deleting a profile with everything in it.")
    static let actionTitle = LocalizedStringResource("Delete profile", table: "Profiles", comment: "Profile screen and list: the action that deletes a profile.")
    static let emptyNote = LocalizedStringResource("There is nothing in it yet.", table: "Profiles", comment: "Question before an empty profile is deleted.")
    static let generalWarning = LocalizedStringResource(
        "Its accounts, operations, goals, wishlist and payments go too. This can’t be undone.", table: "Profiles",
        comment: "Question before a profile is deleted, when its contents could not be counted."
    )
    static let lastProfileReason = LocalizedStringResource(
        "The last profile can’t be deleted. Create another one first.", table: "Profiles",
        comment: "Why the only profile has no delete action."
    )
}

/// A profile in the list of profiles.
struct ProfileRow: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    /// The one the whole app shows on this phone.
    let isActive: Bool

    /// In the profiles' own order.
    static func rows(_ profiles: [Profile], activeId: UUID?) -> [ProfileRow] {
        profiles.map { ProfileRow(id: $0.id, name: $0.name, isActive: $0.id == activeId) }
    }

    /// "Семья, активный": the check mark said in words.
    func accessibilityLabel(in locale: Locale) -> String {
        guard isActive else { return name }
        return LocalizedStringResource("\(name), active", table: "Profiles", comment: "VoiceOver: a profile in the list that is the active one.").text(in: locale)
    }
}
