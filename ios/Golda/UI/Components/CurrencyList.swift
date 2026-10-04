import Foundation
import GoldaCore
import SwiftUI

/// What the currencies are called on screen. The system knows every ISO name in both languages, so
/// none of them is in a catalog of ours.
enum CurrencyNames {
    /// "Аргентинский песо", "Argentine Peso": the system's name in the interface language, with a
    /// capital as a list row starts (the Russian names come in lower case); the code when the system
    /// has no name for it.
    static func name(_ code: String, in locale: Locale) -> String {
        let language = interfaceLanguage(locale)
        guard let name = language.localizedString(forCurrencyCode: code), !name.isEmpty else { return code }
        return name.prefix(1).uppercased(with: language) + name.dropFirst()
    }

    /// The app speaks Russian and English; on a phone in any other language its strings are English,
    /// and so are the names, rather than German names among English words.
    static func interfaceLanguage(_ locale: Locale) -> Locale {
        locale.language.languageCode?.identifier == "ru" ? Locale(identifier: "ru") : Locale(identifier: "en")
    }

    private static let english = Locale(identifier: "en")

    /// Whether [code] is what [query] looks for: the code or the name contains it, in any case and
    /// without accents. The English name counts in Russian too, since "peso" is typed as often as
    /// "песо".
    static func matches(_ code: String, _ query: String, in locale: Locale) -> Bool {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if wanted.isEmpty { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return [code, name(code, in: locale), name(code, in: english)]
            .contains { $0.range(of: wanted, options: options, locale: interfaceLanguage(locale)) != nil }
    }

    /// [codes] by name in [locale], as a list reads them.
    static func byName(_ codes: [String], in locale: Locale) -> [String] {
        let language = interfaceLanguage(locale)
        let named = codes.map { (code: $0, name: name($0, in: locale)) }
        return named
            .sorted { $0.name.compare($1.name, options: [.caseInsensitive], locale: language) == .orderedAscending }
            .map(\.code)
    }
}

/// A long currency list in its sections, each narrowed to what is searched: [yours] first (the
/// local and shown ones, when a form picks one), then the popular ones, then every other one by
/// name. Each currency stands in one section only.
struct CurrencySections: Equatable, Sendable {
    let yours: [String]
    let popular: [String]
    let others: [String]

    /// [extra] adds codes the catalogue lacks (a shown lev from an old backup) at the end, so they
    /// can still be turned off.
    init(yours: [String] = [], extra: [String] = [], matching query: String, in locale: Locale) {
        let mine = Set(yours)
        let found = { (code: String) in CurrencyNames.matches(code, query, in: locale) }
        let unknown = Currencies.ordered(extra).filter { !Currencies.all.contains($0) && !mine.contains($0) }
        let rest = Currencies.all.dropFirst(Currencies.popular.count).filter { !mine.contains($0) }
        self.yours = yours.filter(found)
        popular = Currencies.popular.filter { !mine.contains($0) && found($0) }
        others = CurrencyNames.byName(rest.filter(found), in: locale) + unknown.filter(found)
    }

    var isEmpty: Bool { yours.isEmpty && popular.isEmpty && others.isEmpty }
}

/// The words of the currency lists.
enum CurrencyText {
    static let yours = resource("Your currencies", "Currency list of a form: the header over the person's own currencies, the local and the shown ones.")
    static let popular = resource("Popular", "Currency lists: the header over the popular currencies (ruble, dollar, euro, lari…).")
    static let others = resource("Other currencies", "Currency lists: the header over every other currency, by name.")
    static let search = resource("Name or code", "Currency lists: the prompt of the search field, which finds a currency by its name or its code.")

    private static let table = "Currencies"

    private static func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> LocalizedStringResource {
        LocalizedStringResource(key, table: table, comment: comment)
    }
}

/// A currency's row: its name, and under it the symbol and code ("₾ GEL") that the rest of the app
/// writes it with.
struct CurrencyNameLabel: View {
    let code: String

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: CurrencyNames.name(code, in: locale))
                .foregroundStyle(Theme.Color.text)
            Text(verbatim: SettingsCurrencies.label(code))
                .font(.subheadline)
                .foregroundStyle(Theme.Color.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A form's currency row: the currency picked, and a tap opens every currency to pick another, the
/// person's own ones first. Lives in a `NavigationStack`, as every form sheet does.
struct CurrencyPickRow: View {
    let title: Text
    let selection: String
    /// The local and shown currencies, and the edited thing's own: offered first.
    let yours: [String]
    /// "accountForm.currency": the row; the list's rows are "accountForm.currency.GEL".
    let identifier: String
    var onPick: (String) -> Void

    var body: some View {
        NavigationLink {
            CurrencyPickList(title: title, selection: selection, yours: yours, identifier: identifier, onPick: onPick)
        } label: {
            LabeledContent {
                Text(verbatim: SettingsCurrencies.label(selection))
            } label: {
                title
            }
        }
        .accessibilityIdentifier(identifier)
    }
}

/// Every currency, searchable: the person's own ones, the popular ones, then the rest by name. A tap
/// picks and goes back.
struct CurrencyPickList: View {
    /// The form row's title, so the list says what it picks.
    let title: Text
    let selection: String
    let yours: [String]
    let identifier: String
    var onPick: (String) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let sections = CurrencySections(yours: yours, matching: query, in: locale)
        List {
            section(sections.yours, header: CurrencyText.yours)
            section(sections.popular, header: CurrencyText.popular)
            section(sections.others, header: CurrencyText.others)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.page)
        .overlay {
            if sections.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(verbatim: CurrencyText.search.text(in: locale)))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func section(_ codes: [String], header: LocalizedStringResource) -> some View {
        if !codes.isEmpty {
            Section {
                ForEach(codes, id: \.self) { code in
                    Button {
                        onPick(code)
                        dismiss()
                    } label: {
                        HStack {
                            CurrencyNameLabel(code: code)
                            Spacer()
                            if code == selection {
                                // Graphite: what is picked (D34).
                                Image(systemName: SettingsSymbols.picked)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.Color.graphite)
                            }
                        }
                        .frame(minHeight: Theme.minimumTarget)
                        .contentShape(.rect)
                    }
                    .accessibilityAddTraits(code == selection ? .isSelected : [])
                    .accessibilityIdentifier("\(identifier).\(code)")
                }
            } header: {
                Text(verbatim: header.text(in: locale))
            }
            .listRowBackground(Theme.Color.card)
        }
    }
}
