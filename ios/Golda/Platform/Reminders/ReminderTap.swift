import Foundation

/// What a tapped reminder opens: its profile, then a place in it. It travels in the notification's
/// `userInfo`, so it is plain strings there; anything that does not read back opens nothing.
struct ReminderTap: Equatable, Sendable {
    enum Destination: Equatable, Sendable {
        /// Goals, with the wish in «Сомневаюсь» again while it still waits (SPEC 6.4).
        case wish(UUID)
        /// Accounts: a payment is due or an interest-free period ends.
        case accounts
        /// Accounts in reconcile mode (SPEC 9).
        case reconcile
    }

    /// Nil for a reminder that belongs to no profile (the Sunday one): it opens where the person is.
    var profileId: UUID?
    var destination: Destination

    private enum Key {
        static let open = "golda.open"
        static let profile = "golda.profile"
        static let wish = "golda.wish"
    }

    var userInfo: [String: String] {
        var info: [String: String] = [:]
        switch destination {
        case .wish(let id):
            info[Key.open] = "wish"
            info[Key.wish] = id.uuidString
        case .accounts: info[Key.open] = "accounts"
        case .reconcile: info[Key.open] = "reconcile"
        }
        if let profileId { info[Key.profile] = profileId.uuidString }
        return info
    }

    init(profileId: UUID?, destination: Destination) {
        self.profileId = profileId
        self.destination = destination
    }

    init?(userInfo: [AnyHashable: Any]) {
        switch userInfo[Key.open] as? String {
        case "wish":
            guard let id = (userInfo[Key.wish] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            destination = .wish(id)
        case "accounts": destination = .accounts
        case "reconcile": destination = .reconcile
        default: return nil
        }
        profileId = (userInfo[Key.profile] as? String).flatMap(UUID.init(uuidString:))
    }
}
