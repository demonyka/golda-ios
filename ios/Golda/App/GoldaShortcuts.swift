import AppIntents

/// The voice note for Siri, Spotlight and the Action Button, ready from the install on. The
/// phrases' Russian lives in `AppShortcuts.xcstrings`; Siri requires the app's name in each.
struct GoldaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartVoiceNoteIntent(),
            phrases: [
                "Say a purchase in \(.applicationName)",
                "Record a purchase in \(.applicationName)",
                "Add a purchase to \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Say a purchase", table: "EntryPoints"),
            systemImageName: "mic.fill"
        )
    }
}
