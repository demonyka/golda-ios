import GoldaCore
import GoldaData
import SwiftUI
import UniformTypeIdentifiers

/// This phone's settings (D16), opened by the gear: the port of Android's `SettingsScreen` without
/// what belongs to a profile (income, payments, markup live on the profile's screen). Ordered by how
/// often a traveller comes here: where you are first, then the rates, the profiles, voice, data,
/// the language and the version; "Стереть всё" stands apart, last and red.
///
/// A row opens a small sheet for its value, or does its one thing; what happened shows as a message
/// at the bottom. Every change is kept at once, so "Готово" only closes.
struct SettingsScreen: View {
    let data: AppData

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var sheet: Sheet?
    @State private var prompt: Prompt?
    @State private var notice: SettingsNotice?
    @State private var isRefreshingRates = false
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isBusy = false
    @State private var backup: BackupDocument?

    private enum Sheet: String, Identifiable {
        case local, main, shown, key, model, markup

        var id: String { rawValue }
    }

    /// The one alert of the screen: a question before something that cannot be undone, or a failure.
    private enum Prompt {
        case restore(Data)
        case erase
        case failure(LocalizedStringResource)
    }

    var body: some View {
        NavigationStack {
            List {
                whereSection
                ratesSection
                profilesSection
                voiceSection
                dataSection
                languageSection
                aboutSection
                eraseSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .navigationTitle(Text(verbatim: SettingsText.title.text(in: locale)))
            // In the bar beside "Готово", like every other sheet, not as a large title under it.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: SettingsText.done.text(in: locale)) { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
            .settingsNotice($notice)
            // The exporter and the importer sit on different views: two file panels on one view
            // fight over the same presentation.
            .fileExporter(
                isPresented: $isExporting, document: backup, contentType: .json,
                defaultFilename: BackupFile.name(on: model.environment.today())
            ) { result in
                backup = nil
                exported(result)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json, .plainText, .data]) { result in
            picked(result)
        }
        .alert(
            Text(verbatim: promptTitle),
            isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
            presenting: prompt
        ) { prompt in
            promptActions(prompt)
        } message: { prompt in
            promptMessage(prompt)
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
    }

    /// The freshest books: the sheet keeps the data it was opened with until the tabs pass new data.
    private var current: AppData { model.data ?? data }

    // MARK: Where I am

    private var whereSection: some View {
        Section {
            Button { sheet = .local } label: {
                SettingRow(
                    title: SettingsText.localCurrency.text(in: locale), symbol: SettingsSymbols.localCurrency,
                    value: SettingsCurrencies.label(model.device.localCurrency),
                    detail: SettingsText.localCurrencyRole.text(in: locale), trailingSymbol: SettingsSymbols.opens
                )
            }
            .accessibilityIdentifier("settings.local")
            Button { sheet = .main } label: {
                SettingRow(
                    title: SettingsText.mainCurrency.text(in: locale), symbol: SettingsSymbols.mainCurrency,
                    value: SettingsCurrencies.label(model.device.baseCurrency),
                    detail: SettingsText.mainCurrencyRole.text(in: locale), trailingSymbol: SettingsSymbols.opens
                )
            }
            .accessibilityIdentifier("settings.main")
            Button { sheet = .shown } label: {
                SettingRow(
                    title: SettingsText.shownCurrencies.text(in: locale), symbol: SettingsSymbols.shownCurrencies,
                    value: SettingsCurrencies.symbols(model.device.displayCurrencies),
                    detail: SettingsText.shownCurrenciesRole.text(in: locale), trailingSymbol: SettingsSymbols.opens
                )
            }
            .accessibilityIdentifier("settings.shown")
        } header: {
            Text(verbatim: SettingsText.whereIAm.text(in: locale))
        }
        .listRowBackground(Theme.Color.card)
    }

    // MARK: Rates

    private var ratesSection: some View {
        Section {
            let rates = RateRow.rows(current.settings, current.rates)
            if !rates.isEmpty {
                // One block of lines to read, not rows to tap, so no separators between them.
                VStack(spacing: Theme.Gap.s) {
                    ForEach(rates) { row in
                        SettingRow(title: row.shown, symbol: nil, value: SettingsText.official(row.official).text(in: locale))
                            .monospacedDigit()
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("settings.rate.\(row.code)")
                    }
                }
                .padding(.vertical, Theme.Gap.xs)
            }
            // The markup belongs to the profile on screen; it is here too because Android kept it with the rates.
            Button { sheet = .markup } label: {
                SettingRow(
                    title: MarkupForm.title.text(in: locale), symbol: ProfileSymbols.markup,
                    value: ProfileIncome.markupText(current.profile.settings.markup), trailingSymbol: SettingsSymbols.opens
                )
            }
            .accessibilityIdentifier("settings.markup")
            Button(action: refreshRates) {
                HStack {
                    SettingRow(
                        title: SettingsText.updateRates.text(in: locale), symbol: SettingsSymbols.refreshRates,
                        detail: RatesDay.text(current.ratesDate, locale: locale)
                    )
                    if isRefreshingRates { ProgressView() }
                }
            }
            .disabled(isRefreshingRates)
            .accessibilityIdentifier("settings.refreshRates")
        } header: {
            Text(verbatim: SettingsText.rates.text(in: locale))
        } footer: {
            Text(verbatim: SettingsText.markupNote(Fmt.percent(current.profile.settings.markup)).text(in: locale))
        }
        .listRowBackground(Theme.Color.card)
    }

    // MARK: Profiles

    private var profilesSection: some View {
        Section {
            // The profiles screen takes the place of the settings over the tabs.
            Button { router.present(.profiles) } label: {
                SettingRow(
                    title: SettingsText.profiles.text(in: locale), symbol: SettingsSymbols.profiles,
                    value: model.activeProfile?.name ?? current.profile.name, trailingSymbol: SettingsSymbols.opens
                )
            }
            .accessibilityIdentifier("settings.profiles")
        } footer: {
            Text(verbatim: SettingsText.profilesFooter.text(in: locale))
        }
        .listRowBackground(Theme.Color.card)
    }

    // MARK: Voice

    private var voiceSection: some View {
        Section {
            Button { sheet = .key } label: {
                SettingRow(
                    title: SettingsText.geminiKey.text(in: locale), symbol: SettingsSymbols.geminiKey,
                    value: (model.hasGeminiKey ? SettingsText.keySaved : SettingsText.keyMissing).text(in: locale),
                    trailingSymbol: SettingsSymbols.opens
                )
            }
            .accessibilityIdentifier("settings.key")
            Button { sheet = .model } label: {
                SettingRow(
                    title: SettingsText.model.text(in: locale), symbol: SettingsSymbols.model,
                    detail: GeminiModelText.row(model.device.geminiModel, in: locale), trailingSymbol: SettingsSymbols.opens
                )
            }
            .accessibilityIdentifier("settings.model")
            Toggle(isOn: Binding(get: { model.device.voiceConsent }, set: { model.setVoiceConsent($0) })) {
                SettingRow(title: SettingsText.voiceConsent.text(in: locale), symbol: SettingsSymbols.voiceConsent)
            }
            .accessibilityIdentifier("settings.voiceConsent")
        } header: {
            Text(verbatim: SettingsText.voice.text(in: locale))
        } footer: {
            Text(verbatim: SettingsText.voiceFooter.text(in: locale))
        }
        .listRowBackground(Theme.Color.card)
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            Button(action: export) {
                SettingRow(
                    title: SettingsText.saveBackup.text(in: locale), symbol: SettingsSymbols.saveBackup,
                    detail: SettingsText.saveBackupDetail.text(in: locale)
                )
            }
            .disabled(isBusy)
            .accessibilityIdentifier("settings.export")
            Button { isImporting = true } label: {
                SettingRow(
                    title: SettingsText.restore.text(in: locale), symbol: SettingsSymbols.restore,
                    detail: SettingsText.restoreDetail.text(in: locale)
                )
            }
            .disabled(isBusy)
            .accessibilityIdentifier("settings.import")
            // The Sunday notification itself is scheduled by a later stage; the switch is kept now.
            Toggle(isOn: Binding(get: { model.device.reconcileReminder }, set: { model.setReconcileReminder($0) })) {
                SettingRow(
                    title: SettingsText.reconcileReminder.text(in: locale), symbol: SettingsSymbols.reminder,
                    detail: SettingsText.reconcileReminderDetail.text(in: locale)
                )
            }
            .accessibilityIdentifier("settings.reminder")
        } header: {
            Text(verbatim: SettingsText.data.text(in: locale))
        }
        .listRowBackground(Theme.Color.card)
    }

    // MARK: Language

    private var languageSection: some View {
        Section {
            // No switch in the app (D12): the system keeps a language per app, on Golda's page in
            // the iOS Settings, which this opens.
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                SettingRow(
                    title: SettingsText.appLanguage.text(in: locale), symbol: SettingsSymbols.language,
                    value: AppLanguageName.text(locale), trailingSymbol: SettingsSymbols.leavesApp
                )
            }
            .accessibilityIdentifier("settings.language")
        } header: {
            Text(verbatim: SettingsText.language.text(in: locale))
        } footer: {
            Text(verbatim: SettingsText.languageFooter.text(in: locale))
        }
        .listRowBackground(Theme.Color.card)
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            SettingRow(
                title: SettingsText.version.text(in: locale), symbol: SettingsSymbols.version,
                value: AppVersion.text(Bundle.main.infoDictionary)
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.version")
            NavigationLink {
                LicencesPage()
            } label: {
                SettingRow(title: SettingsText.licences.text(in: locale), symbol: SettingsSymbols.licences)
            }
            .accessibilityIdentifier("settings.licences.row")
        } header: {
            Text(verbatim: SettingsText.about.text(in: locale))
        }
        .listRowBackground(Theme.Color.card)
    }

    // MARK: Erase

    private var eraseSection: some View {
        Section {
            Button(role: .destructive) {
                prompt = .erase
            } label: {
                SettingRow(
                    title: SettingsText.eraseEverything.text(in: locale), symbol: SettingsSymbols.erase, isDestructive: true
                )
            }
            .disabled(isBusy)
            .accessibilityIdentifier("settings.erase")
        }
        .listRowBackground(Theme.Color.card)
    }

    // MARK: Sheets

    @ViewBuilder private func sheetContent(_ sheet: Sheet) -> some View {
        let close = { self.sheet = nil }
        switch sheet {
        case .local: CurrencyPickSheet(kind: .local, onDismiss: close)
        case .main: CurrencyPickSheet(kind: .main, onDismiss: close)
        case .shown: ShownCurrenciesSheet(onDismiss: close)
        case .key:
            GeminiKeySheet(hasKey: model.hasGeminiKey, onFinish: { message in
                close()
                show(message)
            }, onDismiss: close)
        case .model: GeminiModelSheet(current: model.device.geminiModel, onDismiss: close)
        case .markup: MarkupSheet(markup: current.profile.settings.markup, onSave: saveMarkup)
        }
    }

    // MARK: Alert

    private var promptTitle: String {
        switch prompt {
        case .restore: SettingsText.restoreQuestion.text(in: locale)
        case .erase: SettingsText.eraseQuestion.text(in: locale)
        case .failure(let message): message.text(in: locale)
        case nil: ""
        }
    }

    @ViewBuilder private func promptActions(_ prompt: Prompt) -> some View {
        switch prompt {
        case .restore(let file):
            // Red: everything there is now gives way to the file.
            Button(role: .destructive) { restore(file) } label: {
                Text(verbatim: SettingsText.restore.text(in: locale))
            }
            Button(role: .cancel) {} label: {
                Text(verbatim: SettingsText.cancel.text(in: locale))
            }
        case .erase:
            Button(role: .destructive, action: erase) {
                Text(verbatim: SettingsText.erase.text(in: locale))
            }
            Button(role: .cancel) {} label: {
                Text(verbatim: SettingsText.cancel.text(in: locale))
            }
        case .failure:
            Button(role: .cancel) {} label: {
                Text(verbatim: SettingsText.ok.text(in: locale))
            }
        }
    }

    @ViewBuilder private func promptMessage(_ prompt: Prompt) -> some View {
        switch prompt {
        case .restore: Text(verbatim: SettingsText.restoreWarning.text(in: locale))
        case .erase: Text(verbatim: SettingsText.eraseWarning.text(in: locale))
        case .failure: EmptyView()
        }
    }

    // MARK: Actions

    private func show(_ message: LocalizedStringResource) {
        show(message.text(in: locale))
    }

    private func show(_ message: String) {
        notice = SettingsNotice(message: message)
    }

    /// Saves the profile's markup as it is now, so one learned from an exchange while the sheet was
    /// open is kept; a failure says so.
    private func saveMarkup(_ change: @escaping ProfileSettingsChange) {
        let settings = current.profile.settings
        guard let changed = change(settings), changed != settings else { return }
        let model = model, profileId = current.profile.id
        Task {
            do {
                try await model.saveProfileSettings(changed, profileId: profileId)
            } catch {
                prompt = .failure(SettingsText.markupFailed)
            }
        }
    }

    private func refreshRates() {
        guard !isRefreshingRates else { return }
        isRefreshingRates = true
        Task {
            let fresh = await model.refreshRates()
            isRefreshingRates = false
            show(fresh ? SettingsText.ratesUpdated : SettingsText.ratesFailed)
        }
    }

    /// The file is made first and handed to the system's save panel, so a failure to read the books
    /// says so before any panel opens.
    private func export() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                backup = BackupDocument(data: try await model.exportBackup())
                isExporting = true
            } catch {
                show(SettingsText.backupFailed)
            }
        }
    }

    private func exported(_ result: Result<URL, any Error>) {
        switch result {
        case .success: show(SettingsText.backupSaved)
        case .failure(let error):
            // Closing the panel is a choice, not a failure.
            if (error as? CocoaError)?.code != .userCancelled { show(SettingsText.backupFailed) }
        }
    }

    /// Reads the picked file whole, while the system lets the app into it, then asks.
    private func picked(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            do {
                prompt = .restore(try Data(contentsOf: url))
            } catch {
                show(SettingsText.restoreFailed)
            }
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled { show(SettingsText.restoreFailed) }
        }
    }

    private func restore(_ file: Data) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let summary = try await model.restoreBackup(file)
                show(RestoreMessage(summary).text(in: locale))
            } catch {
                // `Backups` reads and checks the whole file before it touches anything.
                show(SettingsText.restoreFailed)
            }
        }
    }

    /// Everything goes, and the app goes back to the welcome screen, which takes this sheet with it.
    private func erase() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            do {
                try await model.eraseEverything()
            } catch {
                isBusy = false
                prompt = .failure(SettingsText.eraseFailed)
            }
        }
    }
}

/// The backup as a file for the system's save panel.
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Previews

#Preview("Samples") {
    @Previewable @State var model = AppModel.preview()
    Color.clear
        .sheet(isPresented: .constant(true)) {
            if let data = model.data {
                SettingsScreen(data: data)
            }
        }
        .environment(model)
        .environment(AppRouter())
        .task { await model.start(command: .samples) }
}

#Preview("Samples, dark, Russian") {
    @Previewable @State var model = AppModel.preview()
    Color.clear
        .sheet(isPresented: .constant(true)) {
            if let data = model.data {
                SettingsScreen(data: data)
            }
        }
        .environment(model)
        .environment(AppRouter())
        .environment(\.locale, Locale(identifier: "ru"))
        .preferredColorScheme(.dark)
        .task { await model.start(command: .samples) }
}
