import SwiftUI

@main
struct GoldaApp: App {
    private let options: LaunchOptions
    @State private var model: AppModel

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
        _model = State(initialValue: AppModel(environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            RootView(micLayout: options.micLayout)
                .environment(model)
                .task {
                    // A unit-test host stays idle: the tests build and drive their own models.
                    guard !options.isHostingTests else { return }
                    await model.start(command: options.command)
                }
        }
    }
}
