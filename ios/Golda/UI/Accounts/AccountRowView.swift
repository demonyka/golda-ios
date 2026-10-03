import SwiftUI

/// One account in a grouped list: the name with the budget dot, the line under it, and the balance
/// with its cents quieter. It only lays out what `AccountRowModel` worked out.
struct AccountRowView: View {
    let row: AccountRowModel

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// "Free money is marked, not painted": a small graphite dot after the name, 8 pt at the
    /// default size. It grows a little with the text, or at the largest sizes it reads as a full stop.
    @ScaledMetric(relativeTo: .body) private var scaledDot: CGFloat = 8
    /// Half the name's x-height: the dot's centre sits there, on the middle of the lowercase letters.
    @ScaledMetric(relativeTo: .body) private var dotLift: CGFloat = 4.5

    private var dotSize: CGFloat { min(scaledDot, 12) }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // At the largest sizes the balance goes under the name: side by side neither fits.
                VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                    texts
                    balance
                }
            } else {
                HStack(spacing: Theme.Gap.m) {
                    texts
                    Spacer(minLength: Theme.Gap.s)
                    balance
                }
            }
        }
        .padding(.vertical, Theme.Gap.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.accessibilityLabel(in: locale)))
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Two lines, not Android's one: beside a long balance, and in reconcile mode beside
            // "Сходится" too, one line cut "Накопительный" down to "Накопите…".
            HStack(alignment: .firstTextBaseline, spacing: Theme.Gap.s) {
                Text(verbatim: row.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(lineLimit)
                if row.isInBudget {
                    let lift = dotLift
                    Circle()
                        .fill(Theme.Color.graphite)
                        .frame(width: dotSize, height: dotSize)
                        // On the name's first line, at the middle of its lowercase letters.
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + lift }
                }
            }
            Text(verbatim: row.subline.text(in: locale).keepingDotsOnTheLine)
                .font(.subheadline)
                .tabularDigits()
                .foregroundStyle(Theme.Color.muted)
                .lineLimit(lineLimit)
        }
    }

    private var lineLimit: Int? { dynamicTypeSize.isAccessibilitySize ? nil : 2 }

    private var balance: some View {
        Text(Self.quietCents(row.balance))
            .font(.title3)
            .tabularDigits()
            .foregroundStyle(Theme.Color.text)
            .lineLimit(1)
            .contentTransition(.numericText(value: Double(row.state.balanceMinor)))
            // The balance keeps its width; the name gives way first.
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
    }

    /// "78,01 $" with the cents in the quiet ink, as Android's `centsOf` does.
    static func quietCents(_ amount: String) -> AttributedString {
        let parts = AmountParts(parsing: amount)
        var fraction = AttributedString(parts.fraction)
        fraction.foregroundColor = Theme.Color.muted
        return AttributedString(parts.whole) + fraction + AttributedString(parts.symbol.isEmpty ? "" : " " + parts.symbol)
    }
}

/// Reconcile mode's control at the end of a row: "Сходится" while the account is unchecked, a
/// graphite check once it is.
struct ReconcileMark: View {
    let isChecked: Bool
    var onMatch: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var checkSize: CGFloat = 40

    static let matchTitle = LocalizedStringResource(
        "Matches",
        comment: "Reconcile mode, a button on each account: the bank shows the same balance."
    )
    static let checkedLabel = LocalizedStringResource("Checked", comment: "VoiceOver, reconcile mode: this account has been checked against the bank.")

    var body: some View {
        Group {
            if isChecked {
                Image(systemName: Symbols.reconcile)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.onGraphite)
                    .frame(width: checkSize, height: checkSize)
                    .background(Theme.Color.graphite, in: Circle())
                    .accessibilityLabel(Text(verbatim: Self.checkedLabel.text(in: locale)))
                    .accessibilityIdentifier("accounts.checked")
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            } else {
                Button(action: onMatch) {
                    Text(verbatim: Self.matchTitle.text(in: locale))
                        .lineLimit(1)
                }
                .buttonStyle(ReconcileButtonStyle())
                .accessibilityIdentifier("accounts.match")
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: isChecked)
    }
}

/// The tonal capsule of the reconcile actions ("Сходится", "Сверить"): `soft` with the text ink, a
/// full 44 pt tall. Gold stays for the one main action of a screen.
struct ReconcileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Color.text)
            .padding(.horizontal, Theme.Gap.m)
            .frame(minHeight: Theme.minimumTarget)
            .background(Theme.Color.soft, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
