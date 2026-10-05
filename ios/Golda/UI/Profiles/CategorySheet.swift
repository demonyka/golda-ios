import GoldaCore
import SwiftUI

/// The form of a category of one's own (D68), for a new one or for [editing] one: its name,
/// spending or income (a new one only), an icon, and what goes in it, for voice. "Отмена" on the
/// left; on the right the trash when editing and "Добавить" or "Сохранить" in the system blue
/// (D34). The trash asks first: the category's operations move to "Прочее", which no undo
/// gathers back. The rules live in `CategoryForm`.
struct CategorySheet: View {
    var onSave: (CustomCategory) -> Void
    var onDelete: (CustomCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var form: CategoryForm
    @FocusState private var isNameFocused: Bool

    init(editing: CustomCategory?, onSave: @escaping (CustomCategory) -> Void, onDelete: @escaping (CustomCategory) -> Void) {
        self.onSave = onSave
        self.onDelete = onDelete
        _form = State(initialValue: CategoryForm(editing: editing))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Theme.Gap.m) {
                        GlyphCircle(form.symbol)
                            .accessibilityHidden(true)
                        TextField(text: $form.name, prompt: Text(verbatim: CategoryForm.namePrompt.text(in: locale))) {
                            Text(verbatim: CategoryForm.namePrompt.text(in: locale))
                        }
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .accessibilityLabel(Text(verbatim: CategoryForm.namePrompt.text(in: locale)))
                        .accessibilityIdentifier("categoryForm.name")
                    }
                    if form.isNew {
                        Picker(selection: $form.kind) {
                            Text(verbatim: CategoryForm.expenseTitle.text(in: locale)).tag(CategoryKind.expense)
                            Text(verbatim: CategoryForm.incomeTitle.text(in: locale)).tag(CategoryKind.income)
                        } label: {
                            Text(verbatim: CategoryForm.kindTitle.text(in: locale))
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("categoryForm.kind")
                    }
                }
                .listRowBackground(Theme.Color.card)

                Section {
                    TextField(text: $form.hint, prompt: Text(verbatim: CategoryForm.hintPrompt.text(in: locale)), axis: .vertical) {
                        Text(verbatim: CategoryForm.hintPrompt.text(in: locale))
                    }
                    .lineLimit(1...4)
                    .accessibilityLabel(Text(verbatim: CategoryForm.hintPrompt.text(in: locale)))
                    .accessibilityIdentifier("categoryForm.hint")
                } footer: {
                    Text(verbatim: CategoryForm.hintNote.text(in: locale))
                }
                .listRowBackground(Theme.Color.card)

                Section {
                    symbolGrid
                        .listRowInsets(EdgeInsets(top: Theme.Gap.s, leading: Theme.Gap.s, bottom: Theme.Gap.s, trailing: Theme.Gap.s))
                } header: {
                    Text(verbatim: CategoryForm.symbolTitle.text(in: locale))
                }
                .listRowBackground(Theme.Color.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text(verbatim: form.title.text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
        .onAppear {
            if form.isNew { isNameFocused = true }
        }
    }

    /// Six across; the picked one turns graphite, as every pick does in Golda.
    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Gap.s), count: 6), spacing: Theme.Gap.s) {
            ForEach(CategoryForm.symbols, id: \.self) { name in
                let picked = name == form.symbol
                Button {
                    form.symbol = name
                } label: {
                    Image(systemName: name)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: Theme.minimumTarget)
                        .foregroundStyle(picked ? Theme.Color.onGraphite : Theme.Color.text)
                        .background(picked ? Theme.Color.graphite : Theme.Color.soft, in: Circle())
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: name))
                .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
            }
        }
        .sensoryFeedback(.selection, trigger: form.symbol)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Text("Cancel", tableName: "Profiles", comment: "Closes an alert or a sheet without changes.")
            }
            .accessibilityIdentifier("categoryForm.cancel")
        }
        if let editing = form.editing {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    // The screen asks before it deletes, so the sheet gives way to its question.
                    dismiss()
                    onDelete(editing)
                } label: {
                    Label {
                        Text(verbatim: CategoryForm.deleteTitle.text(in: locale))
                    } icon: {
                        Image(systemName: Symbols.delete)
                    }
                }
                .accessibilityIdentifier("categoryForm.delete")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            ConfirmButton(title: form.saveTitle.text(in: locale)) {
                guard let output = form.output else { return }
                onSave(output)
                dismiss()
            }
            .disabled(!form.canSave)
            .accessibilityIdentifier("categoryForm.save")
        }
    }
}

#Preview("New") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CategorySheet(editing: nil, onSave: { _ in }, onDelete: { _ in })
    }
    .environment(\.locale, Locale(identifier: "ru"))
}
