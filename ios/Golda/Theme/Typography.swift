import SwiftUI

extension View {
    /// Tabular figures, so columns of amounts line up (the Android `tnum`). Use it on every amount.
    func tabularDigits() -> some View {
        monospacedDigit()
    }
}

extension Font {
    /// The same for a font that is passed around instead of applied to a view.
    func tabularDigits() -> Font {
        monospacedDigit()
    }
}
