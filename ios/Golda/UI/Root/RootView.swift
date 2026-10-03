import SwiftUI

/// The welcome screen until there is a profile and onboarding is done, then the tabs.
struct RootView: View {
    @Environment(AppModel.self) private var model
    let micLayout: MicLayout

    var body: some View {
        switch model.phase {
        case .loading:
            // A few milliseconds at launch: the launch screen's blank page carries on, where a
            // spinner would only flash.
            Color(uiColor: .systemBackground).ignoresSafeArea()
        case .welcome:
            WelcomeView()
        case .main(let data):
            MainTabs(data: data, micLayout: micLayout)
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
    RootView(micLayout: .accessory)
        .environment(model)
        .task { await model.start(command: .samples) }
}

#Preview("Floating mic") {
    @Previewable @State var model = AppModel.preview()
    RootView(micLayout: .floating)
        .environment(model)
        .task { await model.start(command: .samples) }
}

#Preview("Welcome") {
    @Previewable @State var model = AppModel.preview()
    RootView(micLayout: .accessory)
        .environment(model)
        .task { await model.start() }
}
