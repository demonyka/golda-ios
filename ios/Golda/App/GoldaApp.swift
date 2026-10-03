import SwiftUI

@main
struct GoldaApp: App {
    private let options: LaunchOptions
    @State private var model: AppModel
    /// The microphone and every voice note's outcome, for the life of the app.
    @State private var voice: VoiceMicModel

    init() {
        let options = LaunchOptions.current
        let environment: AppEnvironment
        do {
            environment = try AppEnvironment.make(for: options)
        } catch {
            // Without its database the app has nothing to show and nothing to save into.
            fatalError("Golda could not open its data: \(error)")
        }
        self.options = options
        let model = AppModel(environment: environment)
        _model = State(initialValue: model)
        _voice = State(initialValue: VoiceMicModel.live(model: model))
    }

    var body: some Scene {
        WindowGroup {
            RootView(mic: voice)
                .environment(model)
                .task {
                    // A unit-test host stays idle: the tests build and drive their own models.
                    guard !options.isHostingTests else { return }
                    await model.start(command: options.command)
                    // After the launch command, which wipes this phone's settings with the books.
                    await voice.start()
                }
        }
    }
}
