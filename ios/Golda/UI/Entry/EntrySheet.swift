import GoldaCore
import SwiftUI

/// The operation form. A stand-in until step 2c replaces this file: "+" on every tab opens it
/// empty, an operation's row opens it with that operation, which it shows as its row. "Отмена"
/// closes it.
struct EntrySheet: View {
    let data: AppData
    let request: EntryRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            List {
                if let editing = request.editing, let row = OperationRowModel(editing, in: data) {
                    OperationRowView(row: row)
                        .listRowBackground(Theme.Color.card)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: row.accessibilityLabel(in: locale)))
                        .accessibilityIdentifier("entry.editing")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .navigationTitle(Text(verbatim: (request.editing == nil ? Self.newTitle : Self.editTitle).text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: Self.cancelTitle.text(in: locale))
                    }
                    .accessibilityIdentifier("entry.cancel")
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
    }

    static let newTitle = LocalizedStringResource("New operation", comment: "Operation form: the title for a new operation.")
    static let editTitle = LocalizedStringResource("Operation", comment: "Operation form: the title when an operation is open for editing.")
    static let cancelTitle = LocalizedStringResource("Cancel", comment: "Button that closes a dialog without changes.")
}

// MARK: - Previews

#Preview("New") {
    @Previewable @State var model = AppModel.preview()
    Color.clear
        .sheet(isPresented: .constant(true)) {
            if let data = model.data {
                EntrySheet(data: data, request: EntryRequest())
            }
        }
        .environment(model)
        .task { await model.start(command: .samples) }
}
