import SwiftUI

extension VoiceEntryRequests {
    /// Starts the note asked for from outside exactly as a tap on [mic] does (the consent screen
    /// first, the usual toasts after), once [mic] can show it: the app in the foreground, where
    /// alone the microphone records, and nothing presented over the mic. As on Android only an
    /// idle mic starts; a note being recorded or worked out is left alone.
    func deliver(to mic: any MicModel, sceneIsActive: Bool, micIsCovered: Bool) {
        guard sceneIsActive, !micIsCovered, take() else { return }
        if mic.state == .idle { mic.tap() }
    }
}

/// Hands a voice note asked for from outside to the mic of the tab on screen. Pages pushed over
/// the tab's screen carry no mic, so they go; a screen presented over the tabs stays, with what
/// is typed in it, and the note starts once it closes.
struct VoiceEntryDelivery: ViewModifier {
    let mic: any MicModel
    let isSelected: Bool
    @Binding var path: NavigationPath

    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    private let requests = VoiceEntryRequests.shared

    func body(content: Content) -> some View {
        content
            .onChange(of: requests.isPending, initial: true) { deliver() }
            .onChange(of: scenePhase) { deliver() }
            .onChange(of: router.presented == nil) { deliver() }
    }

    private func deliver() {
        guard isSelected, requests.isPending else { return }
        if !path.isEmpty { path = NavigationPath() }
        requests.deliver(to: mic, sceneIsActive: scenePhase == .active, micIsCovered: router.presented != nil)
    }
}
