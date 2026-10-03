import SwiftUI

/// This phone's settings. A stand-in until step 2e replaces this file: the gear on every tab opens
/// it, "Готово" closes it.
struct SettingsScreen: View {
    let data: AppData

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            List {}
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.Color.page)
                .navigationTitle(Text(verbatim: Self.title.text(in: locale)))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        ConfirmButton(title: Self.doneTitle.text(in: locale)) { dismiss() }
                            .accessibilityIdentifier("settings.done")
                    }
                }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
    }

    static let title = LocalizedStringResource("Settings", comment: "Toolbar button (gear) and screen title.")
    static let doneTitle = LocalizedStringResource("Done", comment: "Closes a screen whose changes are already kept.")
}
