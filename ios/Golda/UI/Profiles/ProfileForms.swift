import Foundation
import GoldaCore
import GoldaData

// The small sheets of a profile's screen without their views: what each starts with, what it
// accepts, and the settings saving writes. The rules are Android's `RateSheet`, `TaxHoursSheet` and
// the markup's `NumberSheet`. Each one applies its change to the settings as they are at the moment
// of saving, so a markup learned while a sheet was open is not written back over.

/// How the numbers of these sheets are read and first written.
enum ProfileNumber {
    /// [text] as a number: the narrow spaces a big field groups thousands with are ignored and a
    /// comma is a decimal point. Nil for blank text, for anything that is not a number, and for a
    /// negative one.
    static func parse(_ text: String) -> Double? {
        let bare = text.filter { $0 != "\u{202F}" && $0 != "\u{00A0}" }
        guard let value = Fmt.parseDouble(bare), value >= 0 else { return nil }
        return value
    }

    /// The text a big field starts with: nothing for zero (the grey "0" shows instead), "1 000",
    /// "12,5".
    static func grouped(_ value: Double) -> String {
        value == 0 ? "" : AmountInput.grouped(Fmt.number(value))
    }

    static func isBlank(_ text: String) -> Bool {
        text.allSatisfy(\.isWhitespace)
    }
}

/// "Ставка" or "Зарплата": paid by the hour or by the month, and how much before tax.
struct IncomeRateForm: Equatable, Sendable {
    var isHourly: Bool
    /// As typed. Switching between hourly and monthly keeps it, as on Android.
    var text: String

    init(_ settings: ProfileSettings) {
        isHourly = settings.incomeHourly
        text = ProfileNumber.grouped(settings.incomeHourly ? settings.hourlyRate : settings.monthlySalary)
    }

    var value: Double? { ProfileNumber.parse(text) }

    /// Something is typed that is not a number: the field turns red.
    var isInvalid: Bool { !ProfileNumber.isBlank(text) && value == nil }

    var canSave: Bool { value != nil }

    /// [settings] paid this way; the other kind of pay stays stored for a switch back.
    func applied(to settings: ProfileSettings) -> ProfileSettings? {
        guard let value else { return nil }
        var result = settings
        result.incomeHourly = isHourly
        if isHourly { result.hourlyRate = value } else { result.monthlySalary = value }
        return result
    }

    var caption: LocalizedStringResource {
        isHourly
            ? LocalizedStringResource("an hour, before tax", table: "Profiles", comment: "Rate sheet: under the amount when paid by the hour.")
            : LocalizedStringResource("a month, before tax", table: "Profiles", comment: "Rate sheet: under the amount when paid by the month.")
    }

    static let hourlyTitle = LocalizedStringResource("Hourly", table: "Profiles", comment: "Rate sheet: the segment for pay by the hour.")
    static let monthlyTitle = LocalizedStringResource("Monthly", table: "Profiles", comment: "Rate sheet: the segment for a monthly salary.")
}

/// Tax in percent and hours of work a week, side by side.
struct TaxHoursForm: Equatable, Sendable {
    enum Field: Hashable, Sendable {
        case tax, hours
    }

    var taxText: String
    var hoursText: String

    init(_ settings: ProfileSettings) {
        taxText = Fmt.number(settings.taxPercent)
        hoursText = Fmt.number(settings.hoursPerWeek)
    }

    /// No tax typed is no tax; a percent cannot pass 100.
    var tax: Double? {
        if ProfileNumber.isBlank(taxText) { return 0 }
        return ProfileNumber.parse(taxText).flatMap { (0...100).contains($0) ? $0 : nil }
    }

    /// A week has 168 hours.
    var hours: Double? {
        ProfileNumber.parse(hoursText).flatMap { (0...168).contains($0) ? $0 : nil }
    }

    var invalidFields: Set<Field> {
        var fields: Set<Field> = []
        if tax == nil { fields.insert(.tax) }
        if hours == nil { fields.insert(.hours) }
        return fields
    }

    var canSave: Bool { invalidFields.isEmpty }

    func applied(to settings: ProfileSettings) -> ProfileSettings? {
        guard let tax, let hours else { return nil }
        var result = settings
        result.taxPercent = tax
        result.hoursPerWeek = hours
        return result
    }

    static let taxTitle = LocalizedStringResource("Tax", table: "Profiles", comment: "Tax and hours sheet: the income tax in percent.")
    static let hoursTitle = LocalizedStringResource("Hours a week", table: "Profiles", comment: "Tax and hours sheet: hours of work a week.")
    static let hoursUnit = LocalizedStringResource("h", table: "Profiles", comment: "Tax and hours sheet: the unit after the hours, “40 h”.")
}

/// How much more than the CBR rate rubles cost abroad, typed in percent.
struct MarkupForm: Equatable, Sendable {
    var text: String

    init(markup: Double) {
        let percent = markup * 100
        text = percent == 0 ? "" : Fmt.number(percent)
    }

    /// In percent.
    var value: Double? { ProfileNumber.parse(text) }

    var isInvalid: Bool { !ProfileNumber.isBlank(text) && value == nil }

    var canSave: Bool { value != nil }

    func applied(to settings: ProfileSettings) -> ProfileSettings? {
        guard let value else { return nil }
        var result = settings
        result.markup = value / 100
        return result
    }

    static let title = LocalizedStringResource("Markup over the CBR", table: "Profiles", comment: "Profile screen: the row with the markup over the Bank of Russia rate.")
    static let caption = LocalizedStringResource("Markup over the CBR rate", table: "Profiles", comment: "Markup sheet: the caption over the number.")
    static let note = LocalizedStringResource(
        "Updates itself after each ruble exchange", table: "Profiles",
        comment: "Under the markup: it is learned from every exchange of rubles into another currency."
    )
}

/// A profile's name as typed into the alert.
enum ProfileName {
    /// Trimmed; nil when nothing is left.
    static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
