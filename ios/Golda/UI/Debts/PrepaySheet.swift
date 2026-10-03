import GoldaCore
import SwiftUI

/// The early-repayment calculator of a loan, the port of Android's `PrepayDialog` as a sheet: an
/// amount, then both options (finish sooner, or pay less each month) with the interest each saves,
/// and how that compares with the best savings account. Nothing is saved; "Готово", the sheet's
/// confirmation in the system blue, closes it.
struct PrepaySheet: View {
    let state: AccountState
    let data: AppData
    var onDismiss: () -> Void

    @Environment(\.locale) private var locale
    @State private var text = ""
    @State private var isTyping = false

    var body: some View {
        let calculator = PrepayModel(state: state, data: data)
        NavigationStack {
            List {
                if let calculator {
                    amountSection(calculator)
                    if let result = calculator.result(for: text) {
                        resultSections(result)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(Text(verbatim: PrepayModel.title.text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: Self.doneTitle.text(in: locale), action: onDismiss)
                        .accessibilityIdentifier("prepay.done")
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
        .onAppear { isTyping = true }
    }

    private func amountSection(_ calculator: PrepayModel) -> some View {
        Section {
            BigAmountInput(
                text: $text, symbol: Currencies.symbol(calculator.currency), isFocused: $isTyping,
                label: PrepayModel.amountCaption.text(in: locale), identifier: "prepay.amount"
            )
            .listRowBackground(Theme.Color.card)
        } header: {
            Text(verbatim: PrepayModel.amountCaption.text(in: locale))
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                Text(verbatim: calculator.owedLine(in: locale))
                if calculator.result(for: text) == nil {
                    Text(verbatim: PrepayModel.prompt.text(in: locale))
                }
            }
            .monospacedDigit()
        }
    }

    @ViewBuilder private func resultSections(_ result: PrepayModel.Result) -> some View {
        Section {
            row(PrepayModel.paidOffTitle, value: result.sooner(in: locale), id: "prepay.sooner")
            row(PrepayModel.interestSavedTitle, money: result.money(result.prepay.savedByTermMinor), id: "prepay.savedByTerm")
        } header: {
            Text(verbatim: PrepayModel.shortenTitle.text(in: locale))
        }
        Section {
            row(
                PrepayModel.newPaymentTitle, value: result.paymentAfter(in: locale),
                spoken: SpokenAmount.text(result.money(result.prepay.paymentAfterMinor), locale: locale), id: "prepay.paymentAfter"
            )
            row(PrepayModel.interestSavedTitle, money: result.money(result.prepay.savedByPaymentMinor), id: "prepay.savedByPayment")
        } header: {
            Text(verbatim: PrepayModel.lowerTitle.text(in: locale))
        } footer: {
            if result.savingsLine(in: locale) == nil {
                Text(verbatim: PrepayModel.note.text(in: locale))
            }
        }
        if let savings = result.savingsLine(in: locale), let verdict = result.verdict(in: locale) {
            Section {
                VStack(alignment: .leading, spacing: Theme.Gap.s) {
                    Text(verbatim: savings)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Color.muted)
                    Text(verbatim: verdict)
                        .font(.headline)
                        .foregroundStyle(Theme.Color.text)
                }
                .monospacedDigit()
                .padding(.vertical, Theme.Gap.xs)
                .listRowBackground(Theme.Color.card)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: [result.savingsLine(in: locale, spoken: true), result.verdict(in: locale, spoken: true)].compactMap { $0 }.joined(separator: " ")))
                .accessibilityIdentifier("prepay.comparison")
            } header: {
                Text(verbatim: PrepayModel.comparisonTitle.text(in: locale))
            } footer: {
                Text(verbatim: PrepayModel.note.text(in: locale))
            }
        }
    }

    static let doneTitle = LocalizedStringResource("Done", table: "AccountForm", comment: "Closes the early repayment calculator.")

    private func row(_ title: LocalizedStringResource, money: String, id: String) -> some View {
        row(title, value: money, spoken: SpokenAmount.text(money, locale: locale), id: id)
    }

    private func row(_ title: LocalizedStringResource, value: String, spoken: String? = nil, id: String) -> some View {
        let title = title.text(in: locale)
        return LabeledContent {
            Text(verbatim: value)
                .monospacedDigit()
                .foregroundStyle(Theme.Color.text)
        } label: {
            Text(verbatim: title)
                .foregroundStyle(Theme.Color.muted)
        }
        .listRowBackground(Theme.Color.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: spoken ?? value))
        .accessibilityIdentifier(id)
    }
}

// MARK: - Previews

#Preview("The sample loan") {
    @Previewable @State var model = AppModel.preview()
    Color.clear
        .sheet(isPresented: .constant(true)) {
            if let data = model.data, let loan = data.accounts.first(where: { $0.type == .loan }), let state = data.states[loan.id] {
                PrepaySheet(state: state, data: data) {}
            }
        }
        .environment(model)
        .task { await model.start(command: .samples) }
}
