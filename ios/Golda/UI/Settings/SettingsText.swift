import Foundation

/// Every line of the settings screen and its sheets, from the `Settings` table. Kept in one place
/// so a test can walk them all and check each has its Russian (CLAUDE.md: both languages, in one
/// change); the lines with a value in them are functions below the plain ones.
enum SettingsText {
    // MARK: Screen

    static let title = resource("Settings", "Title of this phone's settings.")
    static let done = resource("Done", "Closes the settings or a sheet whose changes are already kept.")
    static let cancel = resource("Cancel", "Closes a sheet without changes.")
    static let save = resource("Save", "Keeps what was typed in a settings sheet.")
    static let ok = resource("OK", "Closes a message that something failed.")

    // MARK: Where I am

    static let whereIAm = resource("Where I am", "Settings: header of the currency group.")
    static let localCurrency = resource("Local currency", "Settings: the currency of the country you are in.")
    static let localCurrencyRole = resource("For new purchases and voice", "Settings: what the local currency is for, under its row.")
    static let localCurrencyFooter = resource(
        "Amounts said without a currency are in it, and new purchases start in it.",
        "Local currency sheet: what picking it changes."
    )
    static let mainCurrency = resource("Main currency", "Settings: the currency big numbers and totals are shown in.")
    static let mainCurrencyRole = resource("Big numbers and totals", "Settings: what the main currency is for, under its row.")
    static let mainCurrencyFooter = resource(
        "Big numbers and totals are shown in it, at today's rate. The books stay in rubles.",
        "Main currency sheet: what picking it changes."
    )
    static let shownCurrencies = resource("Show amounts in", "Settings: the currencies every amount is also shown in.")
    static let shownCurrenciesRole = resource("Every amount also in these", "Settings: what the shown currencies are for, under their row.")
    static let shownCurrenciesFooter = resource(
        "The ruble always stays. Hiding the local or the main currency turns it into the ruble.",
        "Shown currencies sheet: the rules of the switches."
    )

    // MARK: Rates

    static let rates = resource("Rates", "Settings: header of the exchange rates group.")
    static let updateRates = resource("Update rates", "Settings: fetches fresh rates from the Bank of Russia.")
    static let ratesUpdated = resource("Rates updated", "Message after fresh rates arrived.")
    static let ratesFailed = resource("Didn't work. No network?", "Message when fresh rates could not be fetched.")
    static let markupFailed = resource("The markup was not saved. Try again.", "Message when the profile's markup could not be saved.")

    // MARK: Profiles

    static let profiles = resource("Profiles", "Settings: the row that opens the profiles screen.")
    static let profilesFooter = resource(
        "Each profile keeps its own accounts, goals, income and markup.",
        "Settings: what lives in a profile, under the profiles row."
    )

    // MARK: Voice

    static let voice = resource("Voice", "Settings: header of the voice notes group.")
    static let geminiKey = resource("Gemini key", "Settings: the API key voice notes are sent with.")
    static let keySaved = resource("Saved", "Settings: there is a Gemini key on this phone.")
    static let keyMissing = resource("None", "Settings: there is no Gemini key on this phone.")
    static let pasteKey = resource("Paste the key", "Gemini key sheet: the placeholder of the secure field.")
    static let keyFooter = resource(
        "Made in Google AI Studio. Kept in this iPhone's Keychain and never put in a backup.",
        "Gemini key sheet: where the key comes from and where it is kept."
    )
    static let removeKey = resource("Remove key", "Gemini key sheet: deletes the stored key.")
    static let keyStored = resource("Key saved", "Message after the Gemini key was stored.")
    static let keyRemoved = resource("Key removed", "Message after the Gemini key was deleted.")
    static let keyFailed = resource("The key was not saved. Try again.", "Message when the Keychain refused the key.")
    static let model = resource("Model", "Settings: the Gemini model voice notes are parsed by.")
    static let modelTitle = resource("Gemini model", "Title of the sheet that changes the Gemini model.")
    static let modelFooter = resource(
        "Voice notes are parsed by this model. Change it to move to a newer one.",
        "Gemini model sheet: what the model is and why change it."
    )
    static let voiceConsent = resource("Send voice to Gemini", "Settings: the switch that allows sending recordings to Google Gemini.")
    static let voiceFooter = resource(
        "Recordings go to Google Gemini with your key only while this is on.",
        "Settings: what the voice consent switch allows."
    )

    // MARK: Data

    static let data = resource("Data", "Settings: header of the backup group.")
    static let saveBackup = resource("Save a backup", "Settings: writes everything to one file.")
    static let saveBackupDetail = resource("Everything but the key, in one file", "Settings: what a backup holds, under its row.")
    static let restore = resource("Restore", "Settings: replaces everything with a backup file; also the button that confirms it.")
    static let restoreDetail = resource("From a backup file", "Settings: where restoring reads from, under its row.")
    static let restoreQuestion = resource("Restore from the file?", "Title of the confirmation before a backup replaces everything.")
    static let restoreWarning = resource(
        "Everything in Golda now will be replaced by the file. The Gemini key stays.",
        "Confirmation before restoring: what happens to the current data and the key."
    )
    static let backupSaved = resource("Backup saved", "Message after the backup file was written.")
    static let backupFailed = resource("Could not save the file", "Message when the backup file could not be written.")
    static let restoreFailed = resource("That file did not fit; nothing changed", "Message when a file could not be restored.")
    static let reconcileReminder = resource("Reconcile reminder", "Settings: the weekly nudge to compare balances with the bank.")
    static let reconcileReminderDetail = resource("Sundays at 19:00", "Settings: when the reconcile reminder comes.")

    // MARK: Language

    static let language = resource("Language", "Settings: header of the language group.")
    static let appLanguage = resource("App language", "Settings: the row that opens Golda's page in the iOS Settings.")
    static let languageFooter = resource(
        "Changed in the iOS Settings → Golda → Language.",
        "Settings: where the app language is changed."
    )

    // MARK: About

    static let about = resource("About", "Settings: header of the version and licences group.")
    static let version = resource("Version", "Settings: the app's version and build.")
    static let licences = resource("Licences", "Settings: the row and the page with the licences.")
    static let goldaCredit = resource(
        "Golda for iOS is a port of Golda for Android by Shamil Aminov, under the MIT licence.",
        "Licences page: the original app and its author."
    )
    static let grdbCredit = resource(
        "Golda keeps its data with GRDB by Gwendal Roué, under the MIT licence.",
        "Licences page: the database library and its author."
    )
    static let tailwindCredit = resource(
        "The colours come from the Tailwind CSS palette by Tailwind Labs, under the MIT licence.",
        "Licences page: where the colour values come from."
    )

    // MARK: Erase

    static let eraseEverything = resource("Erase everything", "Settings: the last row, which deletes all data on this phone.")
    static let eraseQuestion = resource("Erase everything?", "Title of the confirmation before all data is erased.")
    static let eraseWarning = resource(
        "Every profile with its accounts, operations and goals, this iPhone's settings and the Gemini key will be gone for good.",
        "Confirmation before erasing: what goes."
    )
    static let erase = resource("Erase", "Confirms erasing everything.")
    static let eraseFailed = resource("Not everything was erased. Try again.", "Message when erasing stopped half way.")

    // MARK: Lines with a value

    /// "ЦБ на 2 октября", over the rates.
    static func ratesOf(_ day: String) -> LocalizedStringResource {
        LocalizedStringResource("CBR of \(day)", table: table, comment: "Settings: the day of the official rates, “CBR of October 2”.")
    }

    /// "ЦБ 83,25", the official rate at the end of a rate row.
    static func official(_ rate: String) -> LocalizedStringResource {
        LocalizedStringResource("CBR \(rate)", table: table, comment: "Settings: the official rate at the end of a rate row, “CBR 83.25”.")
    }

    /// Under the rates: the shown rates carry the profile's markup.
    static func markupNote(_ markup: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "At the CBR rate plus the profile's markup, \(markup).", table: table,
            comment: "Settings: under the rates, how the shown rates are made, with the markup “10 %”."
        )
    }

    /// "gemini-3.5-flash-lite · по умолчанию".
    static func defaultModel(_ name: String) -> LocalizedStringResource {
        LocalizedStringResource("\(name) · default", table: table, comment: "Settings: the Gemini model's name when it is the default one.")
    }

    /// "Вернуть gemini-3.5-flash-lite".
    static func backTo(_ name: String) -> LocalizedStringResource {
        LocalizedStringResource("Back to \(name)", table: table, comment: "Gemini model sheet: puts the default model's name back.")
    }

    /// "Восстановлено: 3 счёта, 14 операций".
    static func restored(_ counts: String) -> LocalizedStringResource {
        LocalizedStringResource("Restored: \(counts)", table: table, comment: "Message after a backup was restored, with what came back, “2 accounts, 14 operations”.")
    }

    static func profilesCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(count) profiles", table: table, comment: "A number of profiles, inside the restore message.")
    }

    static func accountsCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(count) accounts", table: table, comment: "A number of accounts, inside the restore message.")
    }

    static func operationsCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(count) operations", table: table, comment: "A number of operations, inside the restore message.")
    }

    /// The plain lines, for the test that checks every one of them is translated.
    static let all: [LocalizedStringResource] = [
        title, done, cancel, save, ok,
        whereIAm, localCurrency, localCurrencyRole, localCurrencyFooter, mainCurrency, mainCurrencyRole, mainCurrencyFooter,
        shownCurrencies, shownCurrenciesRole, shownCurrenciesFooter,
        rates, updateRates, ratesUpdated, ratesFailed, markupFailed,
        profiles, profilesFooter,
        voice, geminiKey, keySaved, keyMissing, pasteKey, keyFooter, removeKey, keyStored, keyRemoved, keyFailed,
        model, modelTitle, modelFooter, voiceConsent, voiceFooter,
        data, saveBackup, saveBackupDetail, restore, restoreDetail, restoreQuestion, restoreWarning,
        backupSaved, backupFailed, restoreFailed, reconcileReminder, reconcileReminderDetail,
        language, appLanguage, languageFooter,
        about, version, licences, goldaCredit, grdbCredit, tailwindCredit,
        eraseEverything, eraseQuestion, eraseWarning, erase, eraseFailed,
    ]

    private static let table = "Settings"

    private static func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> LocalizedStringResource {
        LocalizedStringResource(key, table: table, comment: comment)
    }
}
