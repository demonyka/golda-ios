/// SF Symbols of the settings rows (DESIGN.md, "Иконки"). The ones DESIGN.md names come from
/// `Symbols.Setting`; the rest stand where Android had an Iconoteka glyph. A test checks that the
/// system knows every one.
enum SettingsSymbols {
    static let localCurrency = "location"
    static let mainCurrency = Symbols.Setting.currency.symbol
    static let shownCurrencies = "eye"
    static let refreshRates = Symbols.Setting.rate.symbol
    static let profiles = "person.crop.circle"
    static let geminiKey = Symbols.Setting.key.symbol
    static let model = "cpu"
    static let voiceConsent = "waveform"
    static let saveBackup = "square.and.arrow.up"
    static let restore = "square.and.arrow.down"
    static let reminder = Symbols.Setting.reminder.symbol
    static let language = Symbols.Setting.language.symbol
    /// The language is changed in the iOS Settings, outside the app.
    static let leavesApp = "arrow.up.forward"
    static let version = "info.circle"
    static let licences = "doc.text"
    static let erase = Symbols.delete
    /// The picked currency in a pick sheet.
    static let picked = "checkmark"
    /// A row that opens a sheet.
    static let opens = "chevron.forward"

    static let all = [
        localCurrency, mainCurrency, shownCurrencies, refreshRates, profiles, geminiKey, model, voiceConsent,
        saveBackup, restore, reminder, language, leavesApp, version, licences, erase, picked, opens,
    ]
}
