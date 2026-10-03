import SwiftUI

/// The profiles of this phone. A stand-in until step 2e replaces this file: "Управление профилями"
/// in the profile menu opens it, "Готово" closes it.
struct ProfilesScreen: View {
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
                            .accessibilityIdentifier("profiles.done")
                    }
                }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
    }

    static let title = LocalizedStringResource("Profiles", comment: "Title of the screen that lists, creates, renames and deletes profiles.")
    static let doneTitle = LocalizedStringResource("Done", comment: "Closes a screen whose changes are already kept.")
}
