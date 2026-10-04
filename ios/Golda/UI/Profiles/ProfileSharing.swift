import Foundation
import GoldaData
import GoldaSync

/// Who a profile is shared with and what this person may do about it, as the profile's screen
/// shows it (stage 5c): the owner invites and stops sharing, a participant leaves. Without iCloud
/// nothing is offered but a word on why.
struct ProfileSharing: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        /// The profile lives in this person's iCloud.
        case owner
        /// Someone else's profile, shared with this person.
        case participant
    }

    let role: Role
    let availability: AppSync.Availability
    /// Everyone in the profile but this person: the owner first, then the others by name, then
    /// those iCloud names no one for (invitations not yet accepted).
    let people: [SyncParticipant]
    /// What went wrong with iCloud last, to say under the section.
    let problem: SyncProblem?

    init(role: Role, availability: AppSync.Availability, participants: [SyncParticipant], problem: SyncProblem? = nil) {
        self.role = role
        self.availability = availability
        people = participants
            .filter { !$0.isCurrentUser && $0.status != .removed }
            .sorted { a, b in
                if a.isOwner != b.isOwner { return a.isOwner }
                if (a.name == nil) != (b.name == nil) { return a.name != nil }
                return (a.name ?? a.id) < (b.name ?? b.id)
            }
        self.problem = problem
    }

    /// Whether anyone but this person is in the profile.
    var isShared: Bool { role == .participant || people.contains { !$0.isOwner } }

    /// "Пригласить…": the owner, with iCloud.
    var canInvite: Bool { role == .owner && availability == .on }
    /// "Закрыть доступ": the owner of a profile someone was invited to.
    var canStopSharing: Bool { role == .owner && availability == .on && people.contains { !$0.isOwner } }
    /// "Выйти из профиля": a participant, with or without a network; the server hears later.
    var canLeave: Bool { role == .participant }
    /// A participant does not delete the owner's profile; they leave it.
    var canDelete: Bool { role == .owner }

    /// What `ProfileDeletion` says for this profile.
    var deletionKind: ProfileDeletion.Sharing {
        switch role {
        case .participant: .sharedWithMe
        case .owner: isShared ? .sharedByMe : .notShared
        }
    }

    /// The line under the section: why there is no invite, what inviting does, who owns it.
    func note(in locale: Locale) -> String {
        if let problem { return SyncProblemText.text(problem, in: locale) }
        switch role {
        case .participant:
            let owner = people.first(where: \.isOwner)?.name
            guard let owner else { return Self.participantNote.text(in: locale) }
            return LocalizedStringResource(
                "Shared with you by its owner, \(owner). Everyone in it sees the same accounts and “Safe to spend today”.",
                table: "Profiles", comment: "Profile screen, sharing: a profile someone shared with this person, with the owner's name."
            ).text(in: locale)
        case .owner:
            switch availability {
            case .off, .noICloud: return Self.noICloudNote.text(in: locale)
            case .on: return (isShared ? Self.sharedNote : Self.inviteNote).text(in: locale)
            }
        }
    }

    /// A person's name, or how to call them when iCloud does not say.
    static func name(of person: SyncParticipant, in locale: Locale) -> String {
        person.name ?? invitedPerson.text(in: locale)
    }

    /// "Владелец", "Ждёт приглашения", "Только просмотр"; nil for a member who reads and writes.
    static func detail(of person: SyncParticipant, in locale: Locale) -> String? {
        if person.isOwner { return ownerTitle.text(in: locale) }
        if person.status == .invited { return invitedTitle.text(in: locale) }
        if !person.canWrite { return readOnlyTitle.text(in: locale) }
        return nil
    }

    // MARK: Text

    static let title = LocalizedStringResource("Sharing", table: "Profiles", comment: "Profile screen: the header over inviting people to the profile.")
    static let inviteTitle = LocalizedStringResource("Invite…", table: "Profiles", comment: "Profile screen, sharing: opens the share sheet to invite someone by AirDrop, Messages or Mail.")
    static let stopTitle = LocalizedStringResource("Stop sharing", table: "Profiles", comment: "Profile screen, sharing: the owner takes the profile away from everyone invited.")
    static let leaveTitle = LocalizedStringResource("Leave profile", table: "Profiles", comment: "Profile screen and list: a participant leaves a profile someone shared with them.")
    static let ownerTitle = LocalizedStringResource("Owner", table: "Profiles", comment: "Profile screen, sharing: beside the name of the person whose profile it is.")
    static let invitedTitle = LocalizedStringResource("Hasn’t joined yet", table: "Profiles", comment: "Profile screen, sharing: beside a person who was invited and has not accepted.")
    static let readOnlyTitle = LocalizedStringResource("Can only view", table: "Profiles", comment: "Profile screen, sharing: beside a person who may not change the profile.")
    static let invitedPerson = LocalizedStringResource("Invited person", table: "Profiles", comment: "Profile screen, sharing: a person iCloud gives no name for.")
    static let inviteNote = LocalizedStringResource(
        "Invite your partner or friends by AirDrop, Messages or Mail: they’ll see and change this profile’s accounts, operations, goals and payments. Your other profiles stay yours.",
        table: "Profiles", comment: "Profile screen, sharing: what inviting does, before anyone is invited."
    )
    static let sharedNote = LocalizedStringResource(
        "Everyone here sees and changes this profile, and gets the same “Safe to spend today”. It’s kept in your iCloud.",
        table: "Profiles", comment: "Profile screen, sharing: the owner's profile that others joined."
    )
    static let participantNote = LocalizedStringResource(
        "Someone shared this profile with you. Everyone in it sees the same accounts and “Safe to spend today”.",
        table: "Profiles", comment: "Profile screen, sharing: a profile shared with this person, when the owner's name is not known."
    )
    static let noICloudNote = LocalizedStringResource(
        "To share this profile, sign in to iCloud in the Settings app. Everything stays on this phone until then.",
        table: "Profiles", comment: "Profile screen, sharing: why inviting is not offered without iCloud."
    )
    static let stopQuestionMessage = LocalizedStringResource(
        "Everyone you invited loses this profile on their phones. It stays on yours.",
        table: "Profiles", comment: "The question before the owner stops sharing a profile."
    )

    /// "Закрыть доступ к «Семья»?"
    static func stopQuestion(_ name: String, in locale: Locale) -> String {
        LocalizedStringResource("Stop sharing “\(name)”?", table: "Profiles", comment: "Title of the question before the owner stops sharing a profile, with its name.").text(in: locale)
    }
}

/// What went wrong with iCloud, as a sentence the person can act on.
enum SyncProblemText {
    static func text(_ problem: SyncProblem, in locale: Locale) -> String {
        switch problem {
        case .noAccount:
            LocalizedStringResource("Sign in to iCloud in the Settings app to share and sync profiles.", table: "Profiles", comment: "A sync problem: no iCloud account.").text(in: locale)
        case .iCloudFull:
            LocalizedStringResource("iCloud storage is full. Free up space, and changes will go on syncing.", table: "Profiles", comment: "A sync problem: the iCloud of the profile's owner is full.").text(in: locale)
        case .retryLater(let seconds):
            LocalizedStringResource(
                "iCloud asked to wait. Try again in \(max(1, (seconds + 59) / 60)) min.", table: "Profiles",
                comment: "A sync problem: the server asked to wait, with the minutes to wait."
            ).text(in: locale)
        case .offline:
            LocalizedStringResource("No connection to iCloud. Changes will go once it’s back.", table: "Profiles", comment: "A sync problem: no network or iCloud did not answer.").text(in: locale)
        case .notPermitted:
            LocalizedStringResource("The owner hasn’t allowed you to change this profile.", table: "Profiles", comment: "A sync problem: a participant with read-only access.").text(in: locale)
        case .other(let code):
            LocalizedStringResource("iCloud didn’t take the change (error \(code)). Try again later.", table: "Profiles", comment: "A sync problem iCloud gave no reason for, with its error code.").text(in: locale)
        }
    }
}
