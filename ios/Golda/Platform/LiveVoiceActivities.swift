import ActivityKit
import Foundation
import GoldaData
import OSLog
import UIKit
import UserNotifications

private let log = Logger(subsystem: "com.f4studio.golda", category: "Voice")

/// The Live Activities of notes recorded outside the app, through ActivityKit.
@MainActor
final class LiveVoiceActivities: VoiceActivities {
    typealias State = VoiceActivityAttributes.ContentState

    var areAllowed: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func begin(_ state: State) throws -> any VoiceActivityHandle {
        let activity = try Activity.request(
            attributes: VoiceActivityAttributes(),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        return Handle(activity)
    }

    func showUndone(_ ticket: VoiceUndoTicket) async {
        // An activity that has ended stays on the Lock Screen for a minute and can still be given
        // its last words.
        for activity in Activity<VoiceActivityAttributes>.activities where activity.content.state.undo == ticket {
            await activity.end(
                ActivityContent(state: VoiceActivityContent.undone(activity.content.state), staleDate: nil),
                dismissalPolicy: .after(.now + TimeInterval(VoiceActivityContent.undoneLingering.components.seconds))
            )
        }
    }

    /// Holds the activity's id, not the activity: `Activity` is not `Sendable`, so it is looked up
    /// afresh off the main actor for each call and never crosses from one to the other.
    private final class Handle: VoiceActivityHandle {
        private let id: String
        /// How long the final state stays in the Dynamic Island before the activity ends.
        static let glance: Duration = .seconds(5)

        init(_ activity: Activity<VoiceActivityAttributes>) {
            id = activity.id
        }

        func update(_ state: State) async {
            await Self.update(id, ActivityContent(state: state, staleDate: nil))
        }

        func end(_ state: State?, lingering: Duration) async {
            let content = state.map { ActivityContent(state: $0, staleDate: nil) }
            if let content {
                // An ended activity leaves the Dynamic Island at once and stays only on the Lock
                // Screen; on an unlocked phone the last words would never be seen. They stay a
                // moment in the island first (the simulator showed the island empty right away).
                await Self.update(id, content)
                try? await Task.sleep(for: Self.glance)
            }
            let policy: ActivityUIDismissalPolicy = state == nil ? .immediate : .after(.now + TimeInterval(lingering.components.seconds))
            await Self.end(id, content, policy)
        }

        private nonisolated static func activity(_ id: String) -> Activity<VoiceActivityAttributes>? {
            Activity<VoiceActivityAttributes>.activities.first { $0.id == id }
        }

        private nonisolated static func update(_ id: String, _ content: ActivityContent<State>) async {
            await activity(id)?.update(content)
        }

        private nonisolated static func end(_ id: String, _ content: ActivityContent<State>?, _ policy: ActivityUIDismissalPolicy) async {
            await activity(id)?.end(content, dismissalPolicy: policy)
        }
    }
}

/// A notification about a note that needs the app. Only when notifications are allowed already: a
/// note from the Lock Screen is no moment to ask (D49 asks at the first need inside the app). Its
/// tap opens the app, where the mic says the rest; reminders' taps are told apart by `ReminderTap`,
/// which reads nothing from this one.
@MainActor
final class LiveVoiceAlerts: VoiceAlerts {
    private let center: any NotificationCenterClient

    init(center: any NotificationCenterClient) {
        self.center = center
    }

    func post(_ message: String) async {
        guard await center.permission() == .allowed else { return }
        let content = UNMutableNotificationContent()
        content.body = message
        content.sound = .default
        content.threadIdentifier = "voice"
        let request = UNNotificationRequest(identifier: "voice.\(UUID().uuidString)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            log.error("A voice notification failed: \(String(describing: error))")
        }
    }
}

extension BackgroundVoiceNote {
    /// The real thing over the app's model: its own recorder (the mic's stays with the mic), the
    /// app's voice service, the chimes, ActivityKit and the notifications. The debug stub records
    /// without a microphone, as the mic does under `-golda.voiceStub`.
    static func live(model: AppModel, mic: VoiceMicModel) -> BackgroundVoiceNote {
        let environment = model.environment
        var recorder: any VoiceRecording = LiveVoiceRecorder()
        #if DEBUG
        if VoiceStubOptions.current != nil { recorder = StubVoiceRecorder() }
        #endif
        return BackgroundVoiceNote(
            model: model, recorder: recorder, notes: environment.voice, cues: LiveVoiceCues.shared,
            activities: LiveVoiceActivities(), alerts: LiveVoiceAlerts(center: environment.notifications),
            hasKey: { environment.voiceKeys.read(SecretKey.gemini) != nil },
            keepRunning: {
                // Gemini answers in a few seconds; without this, iOS may suspend the app as soon
                // as the microphone is off and the note would be worked out on the next launch.
                let id = UIApplication.shared.beginBackgroundTask(withName: "voice note")
                return { UIApplication.shared.endBackgroundTask(id) }
            },
            handOff: { [weak mic] outcome in mic?.keepUntilShown(outcome) }
        )
    }
}
