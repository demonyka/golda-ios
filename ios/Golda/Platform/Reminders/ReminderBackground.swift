import BackgroundTasks
import Foundation
import OSLog
import UserNotifications

private let log = Logger(subsystem: "com.f4studio.golda", category: "Reminders")

/// The background refresh that plans the reminders again while the app is closed, so a debt's next
/// reminder takes the place of the one that went off (only the nearest of each is pending). The
/// identifier is in `BGTaskSchedulerPermittedIdentifiers`, with the `fetch` background mode.
@MainActor
enum ReminderBackground {
    static let identifier = "com.f4studio.golda.reminders"

    /// The scheduler of the app's model: a background launch builds the model as any launch does,
    /// but may never show a window, so the task plans through it directly.
    static weak var scheduler: ReminderScheduler?
    private static var isRegistered = false

    /// Once per process, before the launch finishes, as the system requires; the "Try again" of a
    /// failed launch only points `scheduler` at the new model.
    static func register() {
        guard !isRegistered else { return }
        isRegistered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { run(TaskBox(task: task)) }
        }
    }

    /// Asks to be woken at [millis] or later; the system decides when. Planning submits again each
    /// time, which replaces the request before. The simulator has no background refresh and says so.
    static func submit(at millis: Int64) {
        guard isRegistered else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSince1970: Double(millis) / 1000)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.info("The background refresh was not scheduled: \(String(describing: error))")
        }
    }

    private static func run(_ box: TaskBox) {
        let work = Task {
            await scheduler?.replan()
            box.task.setTaskCompleted(success: !Task.isCancelled)
        }
        box.task.expirationHandler = { work.cancel() }
    }

    /// The system's task, handed to the main actor that runs it; the system calls it on the main
    /// queue (`using: .main`), so it never crosses threads.
    private struct TaskBox: @unchecked Sendable {
        let task: BGTask
    }
}

/// Taps on the reminders, for the app's model. Set before the launch finishes, so a tap that
/// launched the app reaches it too. It is not the app delegate: the voice entry points own that.
///
/// The methods run on the main actor (a `@preconcurrency` conformance): the system's completion
/// handler behind each async method must be called on the main thread, and UIKit aborts otherwise.
@MainActor
final class ReminderTaps: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = ReminderTaps()

    private weak var model: AppModel?

    /// What the notifications need before the launch finishes: taps reach [model], and the
    /// background refresh plans with its scheduler. Not in the unit-test host, which builds models
    /// of its own and must not touch the system.
    static func attach(_ model: AppModel, options: LaunchOptions) {
        guard !options.isHostingTests else { return }
        shared.model = model
        UNUserNotificationCenter.current().delegate = shared
        ReminderBackground.scheduler = model.reminders
        ReminderBackground.register()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let tap = ReminderTap(userInfo: response.notification.request.content.userInfo) else { return }
        model?.openReminder(tap)
    }

    /// With the app open, a reminder still shows, as on Android.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
