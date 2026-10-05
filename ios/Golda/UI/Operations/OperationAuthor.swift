import Foundation
import GoldaSync

/// Who wrote an operation in a shared profile (D67): this person, or someone they share it with.
enum OperationAuthor: Equatable, Sendable {
    case me
    case person(String)

    /// "Вы", or the person's name.
    func text(in locale: Locale) -> String {
        switch self {
        case .me: LocalizedStringResource("You", comment: "Beside an operation in a shared profile: this person wrote it. Russian “Вы”.").text(in: locale)
        case .person(let name): name
        }
    }
}

/// The writers of a shared profile's operations, by operation id.
struct Authorship: Equatable, Sendable {
    var byOperation: [UUID: OperationAuthor]

    /// Who wrote each of [operations], from who created its record on the server ([creators], the
    /// user record names; [currentUser] is how the server names this person) and the people in the
    /// profile's share. An operation the server has not seen yet was written here. A creator the
    /// share does not name gets no name rather than a wrong one. Nil when no one else has joined:
    /// alone, names say nothing.
    static func resolve(
        operations: [UUID], creators: [UUID: String], participants: [SyncParticipant], currentUser: String
    ) -> Authorship? {
        guard participants.filter({ $0.status == .joined }).count > 1 else { return nil }
        var byOperation: [UUID: OperationAuthor] = [:]
        for id in operations {
            guard let creator = creators[id], creator != currentUser else {
                byOperation[id] = .me
                continue
            }
            guard let person = participants.first(where: { $0.id == creator }) else { continue }
            if person.isCurrentUser {
                byOperation[id] = .me
            } else if let name = person.shortName ?? person.name {
                byOperation[id] = .person(name)
            }
        }
        return Authorship(byOperation: byOperation)
    }
}
