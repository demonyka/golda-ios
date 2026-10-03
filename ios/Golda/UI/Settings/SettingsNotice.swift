import SwiftUI

/// A short message at the bottom of the settings, the Android snackbar without an action: "Курсы
/// обновлены", "Копия сохранена". The settings are a sheet over the tabs, so the tabs' undo toast
/// would show under it; this one lives inside the sheet and looks the same.
struct SettingsNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

private struct SettingsNoticeHost: ViewModifier {
    @Binding var notice: SettingsNotice?

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverRunning
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let notice {
                    Text(verbatim: notice.message)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Gap.s + Theme.Gap.xs)
                        .padding(.horizontal, Theme.Gap.l - Theme.Gap.xs)
                        .frame(minHeight: Theme.minimumTarget)
                        // The other theme's ink and fill, as the undo toast, so it stands out from the cards.
                        .foregroundStyle(Theme.Color.page)
                        .background(Theme.Color.text, in: RoundedRectangle(cornerRadius: Theme.Radius.toast, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                        .padding(.horizontal, Theme.Gap.m)
                        .padding(.bottom, Theme.Gap.s)
                        .accessibilityIdentifier("settings.notice")
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture { dismiss(notice) }
                        .id(notice.id)
                        .task(id: notice.id) {
                            AccessibilityNotification.Announcement(notice.message).post()
                            let time = UndoToastTiming.visibleDuration(.short, voiceOverRunning: voiceOverRunning)
                            if await UndoToastTiming.runOut(after: time, on: ContinuousClock()) { dismiss(notice) }
                        }
                }
            }
            .animation(.snappy, value: notice?.id)
    }

    /// Only hides the message that asked: a newer one that arrived meanwhile stays.
    private func dismiss(_ shown: SettingsNotice) {
        if notice?.id == shown.id { notice = nil }
    }
}

extension View {
    /// Shows [notice] at the bottom for a few seconds; a new one replaces it.
    func settingsNotice(_ notice: Binding<SettingsNotice?>) -> some View {
        modifier(SettingsNoticeHost(notice: notice))
    }
}
