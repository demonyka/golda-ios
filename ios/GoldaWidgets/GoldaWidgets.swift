import SwiftUI
import WidgetKit

/// The app on the system's surfaces: «Можно сегодня» with "+" and the mic (`TodayWidget`), which
/// reads the figures the app leaves in the App Group, and the ways into a voice note, Android's
/// `VoiceWidget` and `VoiceTileService`, which start a note (`StartVoiceNoteIntent`, `VoiceEntry`),
/// and the Live Activity of a note recorded without the app.
@main
struct GoldaWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        VoiceWidget()
        VoiceControl()
        VoiceActivityWidget()
    }
}
