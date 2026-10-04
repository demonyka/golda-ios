import Foundation
import GoldaCore
import OSLog
import Synchronization
import UserNotifications

private let log = Logger(subsystem: "com.f4studio.golda", category: "Notifications")

/// Whether the app may show notifications.
enum NotificationPermission: Equatable, Sendable {
    /// Never asked: the system asks once, at the first need.
    case notAsked
    case denied
    /// Allowed, quietly (provisional) included.
    case allowed
}

/// A notification the app hands to the system: the words, when it goes off and what a tap opens.
struct NotificationRequest: Equatable, Sendable {
    /// The planner's id: the same reminder keeps it across plans.
    var id: String
    var title: String
    /// The profile it is about, when there are several; empty otherwise.
    var subtitle: String
    var body: String
    /// Notifications of one kind are grouped together, as Android's channels keep them apart.
    var thread: String
    var trigger: Reminder.Time
    var tap: ReminderTap

    /// Everything about it in one line, kept with the pending request: a request whose signature
    /// is already pending is left alone, and any change replaces it.
    var signature: String {
        let when = switch trigger {
        case .instant(let millis): "at \(millis)"
        case .day(let date, let hour, let minute): "on \(date) \(hour):\(minute)"
        case .weekly(let day, let hour, let minute): "weekly \(day.rawValue) \(hour):\(minute)"
        }
        let opens = tap.userInfo.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return [id, title, subtitle, body, thread, when, opens].joined(separator: "\u{1F}")
    }
}

/// The system's local notifications, as far as the reminders use them. The app runs on
/// `UNUserNotificationCenter`; tests, previews and UI test runs on `InMemoryNotificationCenter`,
/// which never asks the person or leaves a notification on the simulator.
protocol NotificationCenterClient: Sendable {
    func permission() async -> NotificationPermission
    /// Asks the person; true when notifications are allowed afterwards.
    func requestPermission() async -> Bool
    /// The signature of each pending request, by id.
    func pending() async -> [String: String]
    func add(_ request: NotificationRequest) async throws
    func removePending(_ ids: [String]) async
}

/// The real thing.
struct UserNotificationCenterClient: NotificationCenterClient {
    static let signatureKey = "golda.signature"

    func permission() async -> NotificationPermission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notAsked
        case .denied: .denied
        default: .allowed
        }
    }

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("Asking for notifications failed: \(String(describing: error))")
            return false
        }
    }

    func pending() async -> [String: String] {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return Dictionary(
            requests.map { ($0.identifier, $0.content.userInfo[Self.signatureKey] as? String ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func add(_ request: NotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.subtitle = request.subtitle
        content.body = request.body
        content.threadIdentifier = request.thread
        content.sound = .default
        var info: [String: String] = request.tap.userInfo
        info[Self.signatureKey] = request.signature
        content.userInfo = info
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: request.id, content: content, trigger: Self.trigger(request.trigger))
        )
    }

    func removePending(_ ids: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// A moment stays a moment; a day and a weekly time are wall-clock components, matched in
    /// whatever zone the phone is in when they come, so a payment is reminded of at ten local time
    /// after a flight. The planner's dates are Gregorian; the components are given in the phone's
    /// own calendar, which a Thai or Japanese phone may not have set to Gregorian.
    static func trigger(_ time: Reminder.Time) -> UNNotificationTrigger {
        switch time {
        case .instant(let millis):
            let interval = Date(timeIntervalSince1970: Double(millis) / 1000).timeIntervalSinceNow
            // The system refuses an interval that is not ahead; a moment just passed comes at once.
            return UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
        case .day(let date, let hour, let minute):
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = .current
            let parts = DateComponents(year: date.year, month: date.month, day: date.day, hour: hour, minute: minute)
            guard let moment = gregorian.date(from: parts) else {
                return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            }
            let local = Calendar.current.dateComponents([.era, .year, .month, .day, .hour, .minute], from: moment)
            return UNCalendarNotificationTrigger(dateMatching: local, repeats: false)
        case .weekly(let day, let hour, let minute):
            // `DayOfWeek` counts from Monday, `weekday` from Sunday, in every calendar.
            let parts = DateComponents(hour: hour, minute: minute, weekday: day.rawValue % 7 + 1)
            return UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
        }
    }
}

/// The notifications kept in memory, with the person's answer set by the test. It asks no one and
/// shows nothing.
final class InMemoryNotificationCenter: NotificationCenterClient {
    private struct State {
        var permission = NotificationPermission.notAsked
        var answersAllow = true
        var requests: [String: NotificationRequest] = [:]
        var askedCount = 0
        var addedCount = 0
    }

    private let state = Mutex(State())

    init() {}

    /// What is pending, by id.
    var requests: [String: NotificationRequest] { state.withLock { $0.requests } }
    /// How many times the person was asked.
    var askedCount: Int { state.withLock { $0.askedCount } }
    /// How many requests were handed over, replacements included.
    var addedCount: Int { state.withLock { $0.addedCount } }
    /// What the person answers when asked.
    var answersAllow: Bool {
        get { state.withLock { $0.answersAllow } }
        set { state.withLock { $0.answersAllow = newValue } }
    }

    func allow() { state.withLock { $0.permission = .allowed } }
    func deny() { state.withLock { $0.permission = .denied } }

    func permission() async -> NotificationPermission { state.withLock { $0.permission } }

    func requestPermission() async -> Bool {
        state.withLock { state in
            // As the system: the person is asked once, and the answer stays.
            if state.permission == .notAsked {
                state.askedCount += 1
                state.permission = state.answersAllow ? .allowed : .denied
            }
            return state.permission == .allowed
        }
    }

    func pending() async -> [String: String] {
        state.withLock { $0.requests.mapValues(\.signature) }
    }

    func add(_ request: NotificationRequest) async throws {
        state.withLock { state in
            state.requests[request.id] = request
            state.addedCount += 1
        }
    }

    func removePending(_ ids: [String]) async {
        state.withLock { state in ids.forEach { state.requests[$0] = nil } }
    }
}
