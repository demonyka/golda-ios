import SwiftUI

/// The microphone, the app's main action: the round glass button at the thumb, above the tab bar.
///
/// It goes on a tab's own screen, inside the navigation stack, as a bottom safe-area inset. There
/// the system insets the screen's list by the button's real height, so the last rows scroll clear
/// of it; an inset put around the stack instead never reaches the lists in it (iOS 26.2), and they
/// end under the mic. Pushed pages carry no mic, as on Android, where a page covers the toolbar.
struct MicPlacement: ViewModifier {
    let mic: any MicModel

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                MicFloatingButton(state: mic.state, level: mic.level) { mic.tap() }
                    .accessibilityIdentifier("mic")
                    .padding(.trailing, Theme.Gap.m)
                    .padding(.bottom, Theme.Gap.s)
            }
    }
}
