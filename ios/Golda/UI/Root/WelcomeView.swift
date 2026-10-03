import SwiftUI

/// A stand-in for onboarding until step 2e: one button creates the first profile and opens the app.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isStarting = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(verbatim: "Golda")
                .font(.largeTitle.weight(.bold))
            Text("A voice-first money tracker for people who earn in one currency and live in another.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: start) {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            // The screen's one way on: prominent glass in the system blue, as an iOS "Continue" (D34).
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(isStarting)
            .accessibilityIdentifier("welcome.start")
        }
        .padding(Theme.Gap.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.page)
    }

    private func start() {
        isStarting = true
        Task {
            do {
                try await model.completeWelcome(profileName: AppModel.firstProfileName)
            } catch {
                // Nothing was opened; the button is there to try again.
                isStarting = false
            }
        }
    }
}
