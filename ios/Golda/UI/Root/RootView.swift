import SwiftUI

/// The welcome screen until there is a profile and onboarding is done, then the tabs.
struct RootView: View {
    @Environment(AppModel.self) private var model
    let micLayout: MicLayout
    let mic: any MicModel

    var body: some View {
        switch model.phase {
        case .loading:
            // A few milliseconds at launch: a blank page carries on, where a spinner would only flash.
            Theme.Color.page.ignoresSafeArea()
        case .welcome:
            WelcomeView()
        case .main(let data):
            MainTabs(data: data, micLayout: micLayout, mic: mic)
        }
    }
}

extension AppModel {
    /// A model over a throwaway environment, for previews.
    static func preview() -> AppModel {
        do {
            return AppModel(environment: try .inMemory(defaultsSuite: "golda.preview"))
        } catch {
            fatalError("An in-memory database failed to open: \(error)")
        }
    }
}

#Preview("Samples") {
    @Previewable @State var model = AppModel.preview()
    RootView(micLayout: .accessory, mic: StubMicModel())
        .environment(model)
        .task { await model.start(command: .samples) }
}

#Preview("Floating mic") {
    @Previewable @State var model = AppModel.preview()
    RootView(micLayout: .floating, mic: StubMicModel())
        .environment(model)
        .task { await model.start(command: .samples) }
}

#Preview("Welcome") {
    @Previewable @State var model = AppModel.preview()
    RootView(micLayout: .accessory, mic: StubMicModel())
        .environment(model)
        .task { await model.start() }
}
