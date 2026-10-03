import GoldaCore
import SwiftUI

/// A debt's terms on its page: one `Section` for an inset-grouped `List`, with the rate, the payment
/// and when it is next due, a loan's months and interest left and its last payment, a credit card's
/// interest-free period, and "Погасить досрочно…" that opens `PrepaySheet`. Bad news is red. For an
/// account that is not a debt, or a debt with no terms typed in, it draws nothing.
struct DebtDetailsView: View {
    let state: AccountState
    let data: AppData
    /// The day "next payment" and the payoff month are counted from.
    let today: LocalDate

    @Environment(\.locale) private var locale
    @State private var isPrepaying = false

    var body: some View {
        if let details = DebtDetailsModel(state: state, today: today) {
            let rows = details.rows(in: locale)
            if !rows.isEmpty || details.canPrepay {
                Section {
                    ForEach(rows) { row in
                        DebtDetailsRow(row: row)
                            .listRowBackground(Theme.Color.card)
                    }
                    if details.canPrepay {
                        Button {
                            isPrepaying = true
                        } label: {
                            Text(verbatim: DebtDetailsModel.prepayTitle.text(in: locale))
                                .fontWeight(.medium)
                        }
                        .listRowBackground(Theme.Color.card)
                        .accessibilityIdentifier("debt.prepay")
                        // On the row, not the section: a section hands its modifiers to every row.
                        .sheet(isPresented: $isPrepaying) {
                            PrepaySheet(state: state, data: data) { isPrepaying = false }
                        }
                    }
                } header: {
                    Text(verbatim: DebtDetailsModel.header.text(in: locale))
                }
            }
        }
    }
}

/// A title with its value on the right, or a sentence of its own; amounts are read in words.
private struct DebtDetailsRow: View {
    let row: DebtDetailsModel.Row

    var body: some View {
        Group {
            if let value = row.value {
                LabeledContent {
                    Text(verbatim: value)
                        .monospacedDigit()
                        .foregroundStyle(row.isWarning ? Theme.Color.danger : Theme.Color.muted)
                } label: {
                    Text(verbatim: row.title)
                        .foregroundStyle(row.isWarning ? Theme.Color.danger : Theme.Color.text)
                }
            } else {
                Text(verbatim: row.title)
                    .monospacedDigit()
                    .foregroundStyle(row.isWarning ? Theme.Color.danger : Theme.Color.text)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.value == nil ? (row.spokenValue ?? row.title) : row.title))
        .accessibilityValue(Text(verbatim: row.value == nil ? "" : (row.spokenValue ?? row.value ?? "")))
        .accessibilityIdentifier("debt.\(String(describing: row.kind))")
    }
}

// MARK: - Previews

#Preview("The sample loan and card") {
    @Previewable @State var model = AppModel.preview()
    NavigationStack {
        if let data = model.data {
            List {
                ForEach(data.accounts.filter(\.isDebt)) { account in
                    if let state = data.states[account.id] {
                        DebtDetailsView(state: state, data: data, today: model.environment.today())
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
        }
    }
    .environment(model)
    .task { await model.start(command: .samples) }
}
