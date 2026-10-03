import SwiftUI

// Two places for the microphone, the app's main action, tried side by side in stage 2a (O4, S3).
// Both draw the gold mic of the components and are driven by the same `MicModel`.

/// The accessory layout: the wide mic in the tab view's bottom accessory, above the tab bar; it
/// folds into the bar on scroll.
struct MicAccessoryPlacement: ViewModifier {
    let layout: MicLayout
    let mic: any MicModel

    func body(content: Content) -> some View {
        switch layout {
        case .accessory:
            content
                .tabViewBottomAccessory {
                    MicAccessoryContent(state: mic.state, level: mic.level) { mic.tap() }
                        .accessibilityIdentifier("mic")
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        case .floating:
            content
        }
    }
}

/// The floating layout: the round gold mic at the thumb, above the tab bar. It sits in the bottom
/// safe area of each tab's stack, so lists stop short of it, an undo toast inside floats above it,
/// and it stays put while screens are pushed.
struct MicFloatingPlacement: ViewModifier {
    let layout: MicLayout
    let mic: any MicModel

    func body(content: Content) -> some View {
        switch layout {
        case .accessory:
            content
        case .floating:
            content
                .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                    MicFloatingButton(state: mic.state, level: mic.level) { mic.tap() }
                        .accessibilityIdentifier("mic")
                        .padding(.trailing, Theme.Gap.m)
                        .padding(.bottom, Theme.Gap.s)
                }
        }
    }
}
