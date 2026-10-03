import GoldaCore
import SwiftUI

/// Opening balances and reconciliation adjustments: nothing to edit, only to remove. The signed
/// amount big, the account and the day under it, and "Удалить" at the bottom in red, which asks
/// nothing and offers "Вернуть" in the toast. The port of Android's `BookkeepingSheet`.
struct BookkeepingSheet: View {
    let data: AppData
    let operation: OperationFull
    let today: LocalDate

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.showUndoToast) private var showUndoToast
    @State private var isBusy = false
    @State private var failed = false

    private var posting: Posting? { operation.postings.first }
    private var account: Account? { posting.flatMap { data.accountById[$0.accountId] } }
    private var code: String { account?.currency ?? "RUB" }
    private var amount: String { Fmt.amount(posting?.amountMinor ?? 0, code, signed: true) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Gap.s) {
                    BigNumber(
                        AmountParts(parsing: amount),
                        value: Currencies.toMajor(posting?.amountMinor ?? 0, code),
                        maxSize: 64,
                        alignment: .center,
                        spokenText: SpokenAmount.text(amount, locale: locale)
                    )
                    .foregroundStyle(Theme.Color.text)
                    .accessibilityIdentifier("bookkeeping.amount")
                    Text(verbatim: detail)
                        .font(.body)
                        .foregroundStyle(Theme.Color.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("bookkeeping.detail")
                }
                .padding(.horizontal, Theme.Gap.m)
                .padding(.top, Theme.Gap.l)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.Color.page)
            .safeAreaInset(edge: .bottom) { deleteButton }
            .navigationTitle(Text(verbatim: EntryText.bookkeepingTitle(operation.op.type).text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: EntryText.close.text(in: locale))
                    }
                    .accessibilityIdentifier("entry.cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.Color.page)
        .alert(Text(verbatim: EntryText.deleteFailed.text(in: locale)), isPresented: $failed) {
            Button(role: .cancel) {} label: {
                Text(verbatim: EntryText.ok.text(in: locale))
            }
        }
    }

    /// "Карта ₽ · Сегодня".
    private var detail: String {
        let day = DayLabel(Ledger.localDate(operation.op.timestamp, data.zone), today: today).text(in: locale)
        return [account?.name, day].compactMap { $0 }.joined(separator: " · ")
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: delete) {
            Text(verbatim: EntryText.delete.text(in: locale))
                .font(.headline)
                .foregroundStyle(Theme.Color.danger)
                .frame(maxWidth: .infinity, minHeight: Theme.minimumTarget)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        // A bar over the sheet: past this size it would cover the amount it deletes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .disabled(isBusy)
        .padding(.horizontal, Theme.Gap.m)
        .padding(.bottom, Theme.Gap.s)
        .accessibilityIdentifier("bookkeeping.delete")
    }

    /// Gone at once, back with "Вернуть".
    private func delete() {
        guard !isBusy else { return }
        isBusy = true
        let model = model, locale = locale, showUndoToast = showUndoToast, operation = operation
        Task {
            do {
                let token = try await model.deleteOperation(operation.op.id)
                dismiss()
                guard let token else { return }
                showUndoToast(UndoToast(
                    EntryAnnouncement.deleted(operation, in: locale),
                    actionTitle: EntryAnnouncement.restore.text(in: locale),
                    length: .long
                ) {
                    Task { try? await model.restoreOperation(token) }
                })
            } catch {
                isBusy = false
                failed = true
            }
        }
    }
}
