import SwiftUI

// Two places for the microphone, the app's main action, tried side by side in stage 2a (O4, S3).
// Plain system views: the gold button and the voice states come with the theme and with stage 3.

/// The accessory layout: a wide "Say it" bar above the tab bar that folds in with it on scroll.
struct MicAccessoryPlacement: ViewModifier {
    let layout: MicLayout

    func body(content: Content) -> some View {
        switch layout {
        case .accessory:
            content
                .tabViewBottomAccessory { MicAccessoryButton() }
                .tabBarMinimizeBehavior(.onScrollDown)
        case .floating:
            content
        }
    }
}

private struct MicAccessoryButton: View {
    var body: some View {
        // Recording arrives in stage 3.
        Button {} label: {
            Label("Say it", systemImage: "mic.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .accessibilityIdentifier("mic")
    }
}

/// The floating layout: a round glass button above the tab bar, at the thumb.
struct FloatingMicButton: View {
    var body: some View {
        // Recording arrives in stage 3.
        Button {} label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel(Text("Say it"))
        .accessibilityIdentifier("mic")
    }
}
