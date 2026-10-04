import SwiftUI
import WidgetKit

/// The app's ways into a voice note on the system's surfaces, Android's `VoiceWidget` and
/// `VoiceTileService`. They show no data, so they need no App Group: each only opens the app,
/// which starts the note (`VoiceEntry`).
@main
struct GoldaWidgets: WidgetBundle {
    var body: some Widget {
        VoiceWidget()
        VoiceControl()
    }
}
