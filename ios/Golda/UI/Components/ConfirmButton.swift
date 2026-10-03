import SwiftUI

/// A sheet's confirmation ("Добавить", "Сохранить", "Готово"), for its `.confirmationAction`
/// toolbar item. The confirm role draws it as prominent glass in the system blue (D34).
struct ConfirmButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(role: .confirm, action: action) {
            ConfirmLabel(title: title)
        }
    }
}

private struct ConfirmLabel: View {
    let title: String

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if isEnabled {
            // White on the blue in both themes. In the dark one the toolbar draws a text label in
            // black (iOS 26.2), unlike its own checkmark, alerts and every other blue button.
            Text(verbatim: title)
                .foregroundStyle(.white)
        } else {
            // The system's grey capsule and ink, so it reads as unavailable rather than as a
            // second, plainer button.
            Text(verbatim: title)
        }
    }
}
