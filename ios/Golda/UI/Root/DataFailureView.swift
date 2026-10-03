import SwiftUI

/// What the app shows when its data cannot be opened or read. Calm, since nothing is lost, with one
/// way on; the screen stands in for everything, as none of it can be shown without the data.
struct DataFailureView: View {
    /// The technical message: debug builds show it, a user would only be alarmed by it.
    let reason: String
    let retry: @MainActor () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Couldn’t open your data", tableName: "Failure", comment: "Title of the screen shown when the app’s data cannot be opened or read.")
            } icon: {
                Image(systemName: "externaldrive.badge.exclamationmark")
            }
        } description: {
            Text("Your records couldn’t be read. Nothing was deleted.", tableName: "Failure", comment: "Under the title of the failure screen: the records could not be read, and they are still there.")
        } actions: {
            Button(action: retry) {
                Text("Try again", tableName: "Failure", comment: "Button that opens the data once more after it failed.")
                    .font(.headline)
            }
            // The screen's one way on: prominent glass in the system blue (D34).
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .accessibilityIdentifier("failure.retry")
            #if DEBUG
            Text(verbatim: reason)
                .font(.footnote.monospaced())
                .foregroundStyle(Theme.Color.muted)
                .multilineTextAlignment(.center)
                .lineLimit(8)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .padding(.top, Theme.Gap.m)
                .accessibilityIdentifier("failure.reason")
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.page)
    }
}

#Preview {
    DataFailureView(reason: "SQLite error 1: no such column: createdAt") {}
}
