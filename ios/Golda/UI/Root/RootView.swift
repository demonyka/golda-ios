import SwiftUI

/// The welcome screen until there is a profile and onboarding is done, then the tabs; the failure
/// screen whenever the data cannot be read.
struct RootView: View {
    @Environment(AppModel.self) private var model
    let mic: any MicModel

    var body: some View {
        content
            // The consent screen answers the mic wherever it opens from: a tap on the mic or settings.
            .environment(\.voiceConsent, VoiceConsentAction { [mic] agreed in mic.answerConsent(agreed) })
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            // A few milliseconds at launch: a blank page carries on, where a spinner would only flash.
            Theme.Color.page.ignoresSafeArea()
        case .welcome:
            WelcomeView()
        case .main(let data):
            MainTabs(data: data, mic: mic)
        case .failed(let reason):
            DataFailureView(reason: reason) { [model] in
                Task { await model.retry() }
            }
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
