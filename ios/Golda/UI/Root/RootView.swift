import SwiftUI

/// The welcome screen until there is a profile and onboarding is done, then the tabs.
struct RootView: View {
    @Environment(AppModel.self) private var model
    let mic: any MicModel

    var body: some View {
        switch model.phase {
        case .loading:
            // A few milliseconds at launch: a blank page carries on, where a spinner would only flash.
            Theme.Color.page.ignoresSafeArea()
        case .welcome:
            WelcomeView()
        case .main(let data):
            #if DEBUG
            // A screen asked for by a launch argument, for UI tests and screenshots (`DebugScreen`).
            if DebugScreen.requested() == .accountForm {
                AccountFormDebugHost(data: data)
            } else {
                MainTabs(data: data, mic: mic)
            }
            #else
            MainTabs(data: data, mic: mic)
            #endif
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
    RootView(mic: StubMicModel())
        .environment(model)
        .task { await model.start(command: .samples) }
}

#Preview("Welcome") {
    @Previewable @State var model = AppModel.preview()
    RootView(mic: StubMicModel())
        .environment(model)
        .task { await model.start() }
}
