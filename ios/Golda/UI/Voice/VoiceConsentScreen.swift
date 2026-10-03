import SwiftUI

/// Asks before the first recording goes to the voice provider (D9). A stand-in until stage 3
/// replaces this file; nothing opens it yet. "Отмена" closes it.
struct VoiceConsentScreen: View {
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
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text(verbatim: Self.cancelTitle.text(in: locale))
                        }
                        .accessibilityIdentifier("voiceConsent.cancel")
                    }
                }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
    }

    static let title = LocalizedStringResource("Voice notes", comment: "Title of the screen that asks before a recording is sent to the voice provider.")
    static let cancelTitle = LocalizedStringResource("Cancel", comment: "Button that closes a dialog without changes.")
}
