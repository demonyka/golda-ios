import GoldaCore
import GoldaData
import SwiftUI

/// The small sheets over the settings, one value each (DESIGN.md: a `.sheet` with `.medium` or its
/// own height). Each has its confirmation in the system blue and says what the value is for.

// MARK: - Local and main currency

/// The local or the main currency, out of the shown ones, as Android's `LocalCurrencyChoice` and
/// `BaseCurrencyChoice`. A tap picks and closes, as there; "Готово" closes without a change.
struct CurrencyPickSheet: View {
    enum Kind: Sendable {
        case local, main
    }

    let kind: Kind
    var onDismiss: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SettingsCurrencies.pickOptions(model.device, selected: selected), id: \.self) { code in
                        Button {
                            pick(code)
                        } label: {
                            HStack {
                                Text(verbatim: SettingsCurrencies.label(code))
                                    .foregroundStyle(Theme.Color.text)
                                Spacer()
                                if code == selected {
                                    // Graphite: what is picked (D34).
                                    Image(systemName: SettingsSymbols.picked)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.Color.graphite)
                                }
                            }
                            .frame(minHeight: Theme.minimumTarget)
                            .contentShape(.rect)
                        }
                        .accessibilityAddTraits(code == selected ? .isSelected : [])
                        .accessibilityIdentifier("settings.pick.\(code)")
                    }
                } footer: {
                    Text(verbatim: footer.text(in: locale))
                }
                .listRowBackground(Theme.Color.card)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .navigationTitle(Text(verbatim: title.text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: SettingsText.done.text(in: locale), action: onDismiss)
                        .accessibilityIdentifier("settings.pick.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.Color.page)
    }

    private var selected: String {
        switch kind {
        case .local: model.device.localCurrency
        case .main: model.device.baseCurrency
        }
    }

    private var title: LocalizedStringResource {
        switch kind {
        case .local: SettingsText.localCurrency
        case .main: SettingsText.mainCurrency
        }
    }

    private var footer: LocalizedStringResource {
        switch kind {
        case .local: SettingsText.localCurrencyFooter
        case .main: SettingsText.mainCurrencyFooter
        }
    }

    private func pick(_ code: String) {
        switch kind {
        case .local: model.setLocalCurrency(code)
        case .main: model.setMainCurrency(code)
        }
        onDismiss()
    }
}

// MARK: - Shown currencies

/// A switch per currency, as Android's `DisplayCurrencyToggles`. Each flip is kept at once; the
/// ruble cannot be hidden.
struct ShownCurrenciesSheet: View {
    var onDismiss: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SettingsCurrencies.shownOptions(model.device)) { option in
                        Toggle(isOn: Binding(get: { option.isOn }, set: { _ in model.toggleShownCurrency(option.code) })) {
                            Text(verbatim: SettingsCurrencies.label(option.code))
                                .foregroundStyle(Theme.Color.text)
                        }
                        .disabled(option.isLocked)
                        .frame(minHeight: Theme.minimumTarget)
                        .accessibilityIdentifier("settings.shown.\(option.code)")
                    }
                } footer: {
                    Text(verbatim: SettingsText.shownCurrenciesFooter.text(in: locale))
                }
                .listRowBackground(Theme.Color.card)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .navigationTitle(Text(verbatim: SettingsText.shownCurrencies.text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: SettingsText.done.text(in: locale), action: onDismiss)
                        .accessibilityIdentifier("settings.shown.done")
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
    }
}

// MARK: - Gemini key

/// The key in a secure field: "Сохранить" keeps it in the Keychain, "Удалить ключ" (only when there
/// is one) takes it away. The sheet never shows the stored key, only replaces it.
struct GeminiKeySheet: View {
    let hasKey: Bool
    /// What happened, for the message under the settings; the sheet closes after it.
    var onFinish: (LocalizedStringResource) -> Void
    var onDismiss: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var key = ""
    @State private var failed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(text: $key, prompt: Text(verbatim: SettingsText.pasteKey.text(in: locale))) {
                        Text(verbatim: SettingsText.geminiKey.text(in: locale))
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(save)
                    .frame(minHeight: Theme.minimumTarget)
                    // A field with a prompt hides its label from VoiceOver.
                    .accessibilityLabel(Text(verbatim: SettingsText.geminiKey.text(in: locale)))
                    .accessibilityIdentifier("settings.key.field")
                } footer: {
                    Text(verbatim: SettingsText.keyFooter.text(in: locale))
                }
                .listRowBackground(Theme.Color.card)
                if hasKey {
                    Section {
                        Button(role: .destructive, action: remove) {
                            Text(verbatim: SettingsText.removeKey.text(in: locale))
                                .foregroundStyle(Theme.Color.danger)
                        }
                        .accessibilityIdentifier("settings.key.remove")
                    }
                    .listRowBackground(Theme.Color.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .navigationTitle(Text(verbatim: SettingsText.geminiKey.text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDismiss) {
                        Text(verbatim: SettingsText.cancel.text(in: locale))
                    }
                    .accessibilityIdentifier("settings.key.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: SettingsText.save.text(in: locale), action: save)
                        .disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("settings.key.save")
                }
            }
            .alert(Text(verbatim: SettingsText.keyFailed.text(in: locale)), isPresented: $failed) {
                Button(role: .cancel) {} label: {
                    Text(verbatim: SettingsText.ok.text(in: locale))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.Color.page)
        .task {
            // Over the settings sheet, focus asked for while this one slides in is dropped; asked
            // once it is up, the keyboard opens for the paste.
            try? await Task.sleep(for: .milliseconds(450))
            isFocused = true
        }
    }

    private var trimmed: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmed.isEmpty else { return }
        do {
            try model.saveGeminiKey(trimmed)
            onFinish(SettingsText.keyStored)
        } catch {
            failed = true
        }
    }

    private func remove() {
        do {
            try model.removeGeminiKey()
            onFinish(SettingsText.keyRemoved)
        } catch {
            failed = true
        }
    }
}

// MARK: - Gemini model

/// The model's name as text, so a newer model needs no new build; "Вернуть …" puts the default back.
struct GeminiModelSheet: View {
    var onDismiss: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(current: String, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _name = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $name, prompt: Text(verbatim: GeminiModelText.defaultName)) {
                        Text(verbatim: SettingsText.model.text(in: locale))
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(save)
                    .frame(minHeight: Theme.minimumTarget)
                    // A field with a prompt hides its label from VoiceOver.
                    .accessibilityLabel(Text(verbatim: SettingsText.model.text(in: locale)))
                    .accessibilityIdentifier("settings.model.field")
                } footer: {
                    Text(verbatim: SettingsText.modelFooter.text(in: locale))
                }
                .listRowBackground(Theme.Color.card)
                if GeminiModelText.saveable(name) != GeminiModelText.defaultName {
                    Section {
                        Button {
                            name = GeminiModelText.defaultName
                        } label: {
                            Text(verbatim: SettingsText.backTo(GeminiModelText.defaultName).text(in: locale))
                        }
                        .accessibilityIdentifier("settings.model.default")
                    }
                    .listRowBackground(Theme.Color.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .navigationTitle(Text(verbatim: SettingsText.modelTitle.text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDismiss) {
                        Text(verbatim: SettingsText.cancel.text(in: locale))
                    }
                    .accessibilityIdentifier("settings.model.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: SettingsText.save.text(in: locale), action: save)
                        .disabled(GeminiModelText.saveable(name) == nil)
                        .accessibilityIdentifier("settings.model.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.Color.page)
    }

    private func save() {
        guard let name = GeminiModelText.saveable(name) else { return }
        model.setGeminiModel(name)
        onDismiss()
    }
}
