import SwiftUI

/// The microphone, the app's main action: the round glass button at the thumb, above the tab bar,
/// with the voice's toasts above it.
///
/// It goes on a tab's own screen, inside the navigation stack, as a bottom safe-area inset. There
/// the system insets the screen's list by the button's real height, so the last rows scroll clear
/// of it; an inset put around the stack instead never reaches the lists in it (iOS 26.2), and they
/// end under the mic. Pushed pages carry no mic, as on Android, where a page covers the toolbar.
///
/// The screens the voice asks for (consent, "хочу купить") open through the router once nothing
/// else is open, so a note understood late never pulls a form from under the person's fingers.
struct MicPlacement: ViewModifier {
    let mic: any MicModel

    /// Absent where a snapshot puts the mic on a bare screen.
    @Environment(AppRouter.self) private var router: AppRouter?

    func body(content: Content) -> some View {
        content
            // Inside the mic's inset, like the screen's own toast, so it floats above the mic and the tab bar.
            .undoToast(Binding(get: { mic.toast }, set: { mic.toast = $0 }))
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                MicFloatingButton(state: mic.state, level: mic.level) { mic.tap() }
                    .accessibilityIdentifier("mic")
                    .padding(.trailing, Theme.Gap.m)
                    .padding(.bottom, Theme.Gap.s)
            }
            .onChange(of: mic.route, initial: true) { presentRequestedRoute() }
            .onChange(of: router?.presented == nil) { presentRequestedRoute() }
    }

    private func presentRequestedRoute() {
        guard let router, router.presented == nil, let route = mic.route else { return }
        mic.route = nil
        router.present(route)
    }
}
