import GoldaCore
import SwiftUI

/// "Сколько на самом деле?" as a small sheet. The balance stands in the field as the big number,
/// and the blue button says "Сходится" until a different number is typed; then the difference shows
/// underneath and the button says what will be recorded. [onReconcile] gets the real balance.
///
/// The confirmation is pinned at the bottom rather than in the toolbar: it names the amount it will
/// record ("Записать −101 ₽"), which a toolbar button has no room for.
///
/// The field is not focused on opening: a glance and "Сходится" is the common case. The balance
/// stands in it as text and is selected whole on the first touch, so typing replaces it and
/// backspace erases it.
struct ReconcileSheet: View {
    let state: AccountState
    var onReconcile: (Int64) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var entry: ReconcileEntry
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 48

    init(state: AccountState, onReconcile: @escaping (Int64) -> Void) {
        self.state = state
        self.onReconcile = onReconcile
        _entry = State(initialValue: ReconcileEntry(state))
    }

    var body: some View {
        NavigationStack {
            // Scrolls only when the text is too big for the sheet, so nothing hides under the bar.
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.Color.page)
            .safeAreaInset(edge: .bottom) { action }
            .navigationTitle(Text(verbatim: state.account.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: Self.cancelTitle.text(in: locale))
                    }
                    .accessibilityIdentifier("reconcile.cancel")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    // The decimal pad has no minus key: a debt or an overdraft flips the sign here.
                    Button {
                        entry.isNegative.toggle()
                    } label: {
                        Text(verbatim: "+/−")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(Text(verbatim: Self.signLabel.text(in: locale)))
                    .accessibilityIdentifier("reconcile.sign")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.Color.page)
    }

    private var content: some View {
        VStack(spacing: Theme.Gap.s) {
            Text(verbatim: Self.question.text(in: locale))
                .font(.subheadline)
                .foregroundStyle(Theme.Color.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // The field below carries the question for VoiceOver.
                .accessibilityHidden(true)
            amountField
            // A space while nothing differs keeps the line's height, so nothing jumps.
            Text(verbatim: entry.differenceText(in: locale) ?? " ")
                .font(.headline)
                .tabularDigits()
                .foregroundStyle(Theme.Color.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .accessibilityLabel(Text(verbatim: entry.differenceText(in: locale, spoken: true) ?? ""))
                .accessibilityHidden(entry.matches || !entry.canSave)
                .accessibilityIdentifier("reconcile.difference")
        }
        .padding(.horizontal, Theme.Gap.m)
        .padding(.top, Theme.Gap.s)
        .frame(maxWidth: .infinity)
    }

    /// The real balance, as big as the sheet allows, with the currency's symbol beside it. While
    /// nothing is typed the account's own balance stands there in full ink.
    private var amountField: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Gap.xs) {
            if entry.isNegative, !entry.text.isEmpty {
                Text(verbatim: "−")
                    .accessibilityHidden(true)
            }
            TextField(text: $entry.text, selection: $selection, prompt: Text(verbatim: entry.placeholder).foregroundStyle(Theme.Color.text)) {
                Text(verbatim: Self.question.text(in: locale))
            }
            .keyboardType(.decimalPad)
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                guard focused else { return }
                // After the tap has placed its caret, or the caret wins over the selection.
                Task { @MainActor in
                    selection = TextSelection(range: entry.text.startIndex..<entry.text.endIndex)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize()
            // A field with a prompt hides its label from VoiceOver, which otherwise heard a bare number.
            .accessibilityLabel(Text(verbatim: Self.question.text(in: locale)))
            .accessibilityIdentifier("reconcile.amount")
            Text(verbatim: Currencies.symbol(state.currency))
                .foregroundStyle(Theme.Color.muted)
                .accessibilityHidden(true)
        }
        .font(.system(size: amountSize, weight: .semibold).monospacedDigit())
        .foregroundStyle(Theme.Color.text)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.vertical, Theme.Gap.s)
        .frame(maxWidth: .infinity)
    }

    /// The sheet's confirmation, prominent glass in the system blue, above the keyboard.
    private var action: some View {
        Button {
            guard let actual = entry.actualMinor, entry.canSave else { return }
            onReconcile(actual)
            dismiss()
        } label: {
            Text(verbatim: entry.actionTitle(in: locale))
                .font(.headline)
                .tabularDigits()
                // The amount must show whole, even at the largest text sizes.
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!entry.canSave)
        .padding(.horizontal, Theme.Gap.m)
        .padding(.bottom, Theme.Gap.s)
        .animation(.snappy, value: entry.actionTitle(in: locale))
        .accessibilityLabel(Text(verbatim: entry.actionTitle(in: locale, spoken: true)))
        .accessibilityIdentifier("reconcile.save")
    }

    static let question = LocalizedStringResource(
        "How much is really there?",
        comment: "Reconcile sheet: asks for the balance the bank shows."
    )
    static let cancelTitle = LocalizedStringResource("Cancel", comment: "Button that closes a dialog without changes.")
    static let signLabel = LocalizedStringResource(
        "Change the sign",
        comment: "VoiceOver: the +/− key above the keyboard of the reconcile sheet."
    )
}

// MARK: - Previews

#Preview("A dollar card") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ReconcileSheet(
            state: AccountState(
                account: Account(name: "Мультивалютная USD", currency: "USD", type: .card, includeInFree: true),
                balanceMinor: 7_801, rubMinor: 717_700
            )
        ) { _ in }
    }
}
