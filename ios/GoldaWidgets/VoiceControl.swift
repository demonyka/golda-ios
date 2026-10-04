import AppIntents
import SwiftUI
import WidgetKit

/// Android's Quick Settings tile: a Control Center button, also what the Action Button and the Lock
/// Screen's controls can run. It runs `StartVoiceNoteIntent`, which brings the app up recording.
struct VoiceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.f4studio.golda.voice.control") {
            ControlWidgetButton(action: StartVoiceNoteIntent()) {
                Label {
                    Text("Say a purchase", tableName: "EntryPoints")
                } icon: {
                    Image(systemName: "mic.fill")
                }
            }
        }
        .displayName(LocalizedStringResource("Say a purchase", table: "EntryPoints"))
        .description(LocalizedStringResource("One tap and say what you spent", table: "EntryPoints"))
    }
}
