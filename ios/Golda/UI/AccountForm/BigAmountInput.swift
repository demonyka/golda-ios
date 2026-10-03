import SwiftUI
import UIKit

/// The big amount typed into a form: bare, centred, with tabular figures, a grey "0" before anything
/// is typed and the currency symbol on the digits' baseline, the iOS side of Android's
/// `HeroAmountField`. "1500" reads "1 500" as it is typed. The size steps down as the number grows,
/// so a long amount still fits a line.
struct BigAmountInput: View {
    @Binding var text: String
    let symbol: String
    /// The text cannot be read as an amount: it turns red.
    var isInvalid = false
    @Binding var isFocused: Bool
    /// What VoiceOver calls the field: the caption over it.
    let label: String
    let identifier: String

    @ScaledMetric(relativeTo: .largeTitle) private var baseSize: CGFloat = 48

    var body: some View {
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        HStack(alignment: .firstTextBaseline, spacing: Theme.Gap.s) {
            Spacer(minLength: 0)
            GroupedAmountField(
                text: $text, isFocused: $isFocused, font: font, isInvalid: isInvalid, label: label, identifier: identifier
            )
            // A UIKit field has no baseline SwiftUI can see; the text sits centred in its height.
            .alignmentGuide(.firstTextBaseline) { d in (d.height - font.lineHeight) / 2 + font.ascender }
            Text(verbatim: symbol)
                .font(Font(font))
                .foregroundStyle(Theme.Color.muted)
                .lineLimit(1)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Gap.s)
    }

    /// Shrinks with the length rather than with a measured width: a field cannot shrink its own
    /// text to fit, and these steps keep a seven-figure amount with kopecks on one line.
    private var size: CGFloat {
        let capped = min(baseSize, 72)
        switch text.count {
        case ...7: return capped
        case ...10: return capped * 0.8
        default: return capped * 0.62
        }
    }
}

/// A `UITextField` that groups thousands as the amount is typed, the way Android's `Grouping` shows
/// it. The grouping happens inside the keystroke, so the caret keeps its place among the digits and
/// a fast typist loses nothing; a SwiftUI field rewritten from outside drops keys typed meanwhile.
private struct GroupedAmountField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let font: UIFont
    let isInvalid: Bool
    let label: String
    let identifier: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .decimalPad
        field.textAlignment = .center
        field.borderStyle = .none
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.font = font
        field.textColor = UIColor(named: isInvalid ? "danger" : "text")
        field.attributedPlaceholder = NSAttributedString(
            string: "0", attributes: [.font: font, .foregroundColor: UIColor(named: "line") ?? .placeholderText]
        )
        field.accessibilityLabel = label
        field.accessibilityIdentifier = identifier
        field.invalidateIntrinsicContentSize()
        // Focus moves after this update: a responder change inside one is ignored.
        if isFocused, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isFocused, field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    /// As wide as the text (or the "0") and the caret, never wider than offered.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: UITextField, context: Context) -> CGSize? {
        let natural = field.intrinsicContentSize
        let width = natural.width + 4
        return CGSize(width: min(width, proposal.width ?? width), height: natural.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: GroupedAmountField

        init(parent: GroupedAmountField) {
            self.parent = parent
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            if parent.isFocused { parent.isFocused = false }
        }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let edit = AmountInput.edit(field.text ?? "", range: range, replacement: string)
            field.text = edit.text
            if let position = field.position(from: field.beginningOfDocument, offset: edit.caret) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
            parent.text = edit.text
            return false
        }
    }
}
