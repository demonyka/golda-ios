import CloudKit
import GoldaSync
import OSLog
import SwiftUI
import UIKit

private let log = Logger(subsystem: "com.f4studio.golda", category: "Launch")

@main
struct GoldaApp: App {
    /// The quick action on the app icon, which SwiftUI does not hear.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var options: LaunchOptions
    @State private var launch: AppLaunch
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let options = LaunchOptions.current
        _options = State(initialValue: options)
        _launch = State(initialValue: AppLaunch.open(options))
    }

    var body: some Scene {
        WindowGroup {
            switch launch {
            case .opened(let model, let voice):
                RootView(mic: voice)
                    .environment(model)
                    // The widgets' links: the tabs start the note (`VoiceEntryDelivery`), open
                    // the form or Home (`MainTabs`).
                    .onOpenURL { url in AppLinkRequests.shared.open(url) }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .background, !options.isHostingTests { model.publishWidgetsOnLeaving() }
                        // Back in the app: iCloud may have been signed in meanwhile, and the other
                        // phones may have written.
                        if phase == .active, !options.isHostingTests { Task { await model.sync.start() } }
                    }
                    .task {
                        // A unit-test host stays idle: the tests build and drive their own models.
                        guard !options.isHostingTests else { return }
                        await model.start(command: options.command)
                        // After the launch command, which wipes this phone's settings with the books.
                        await voice.start()
                        model.startReminders()
                        await model.sync.start()
                        #if DEBUG
                        if options.seedsCloudKitSchema { await seedCloudKitSchema() }
                        #endif
                    }
            case .failed(let reason):
                DataFailureView(reason: reason, retry: reopen)
            }
        }
    }

    #if DEBUG
    private func seedCloudKitSchema() async {
        do {
            try await CloudKitSchemaSeed.run(in: CKContainer(identifier: SyncBackend.containerIdentifier))
            log.notice("CloudKit schema seeded")
        } catch {
            log.error("Seeding the CloudKit schema failed: \(String(describing: error))")
        }
    }
    #endif

    private func reopen() {
        #if DEBUG
        // `-golda.failDatabase` fails the first opening only, so a UI test sees "Try again" work.
        options.failsDatabase = false
        #endif
        launch = AppLaunch.open(options)
    }
}

/// The app's model and mic over its data, or why the data could not be opened (the file refused,
/// a migration threw). A failure shows the same screen as one met later by `AppModel`, so the app
/// never ends on a crash or a blank page; "Try again" opens it all afresh.
@MainActor
enum AppLaunch {
    case opened(AppModel, VoiceMicModel)
    case failed(reason: String)

    static func open(_ options: LaunchOptions) -> AppLaunch {
        let environment: AppEnvironment
        do {
            environment = try AppEnvironment.make(for: options)
        } catch {
            log.error("Opening the data failed: \(String(describing: error))")
            return .failed(reason: String(describing: error))
        }
        let model = AppModel(environment: environment)
        let voice = VoiceMicModel.live(model: model)
        // A key saved in Settings lets the notes that waited for one go through.
        model.onGeminiKeyChanged = { [weak model] in model?.processVoiceQueue() }
        // Before the launch finishes: a tapped notification may be what launched the app.
        ReminderTaps.attach(model, options: options)
        // Before the launch finishes too: a voice intent may be what launched the app, in the
        // background, with no window. The unit-test host keeps requests in the app.
        if !options.isHostingTests {
            let background = BackgroundVoiceNote.live(model: model, mic: voice)
            // A run that died mid-note left its Live Activity saying the microphone is on; no note
            // of this run has begun yet, so whatever runs now is such a leftover.
            background.endLeftovers()
            VoiceNoteLauncher.shared.background = background
            VoiceNoteLauncher.shared.appIsActive = { UIApplication.shared.applicationState == .active }
        }
        // An invitation the scene was launched with goes to this run's sync.
        if !options.isHostingTests { ShareInvitations.attach(model.sync) }
        return .opened(model, voice)
    }
}
