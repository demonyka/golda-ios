import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The small sheets of a profile's screen, the rules of Android's `RateSheet`, `TaxHoursSheet` and
/// `NumberSheet` for the markup: what they start with, what they accept, and the settings they save.
@Suite struct ProfileFormsTests {
    private let ru = Locale(identifier: "ru")
    private let en = Locale(identifier: "en")
    private let hourly = ProfileIncomeTests.hourly

    // MARK: Rate

    @Test func theRateStartsWithTheStoredOneGrouped() throws {
        var form = IncomeRateForm(hourly)
        #expect(form.isHourly)
        #expect(form.text == "1\u{202F}000")
        #expect(form.value == 1000)
        #expect(form.caption.text(in: ru) == "в час, до налога")
        #expect(form.caption.text(in: en) == "an hour, before tax")

        form.text = "1\u{202F}250,5"
        let saved = try #require(form.applied(to: hourly))
        #expect(saved.incomeHourly)
        #expect(saved.hourlyRate == 1250.5)
        #expect(saved.monthlySalary == hourly.monthlySalary)
        #expect(saved.taxPercent == hourly.taxPercent)
        #expect(saved.payday == hourly.payday)
    }

    /// Switching to a salary keeps what was typed, as on Android, and saves it as the salary; the
    /// hourly rate stays stored for a switch back.
    @Test func switchingToASalarySavesTheNumberAsTheSalary() throws {
        var form = IncomeRateForm(hourly)
        form.isHourly = false
        #expect(form.caption.text(in: ru) == "в месяц, до налога")
        #expect(form.caption.text(in: en) == "a month, before tax")
        form.text = "150\u{202F}000"
        let saved = try #require(form.applied(to: hourly))
        #expect(!saved.incomeHourly)
        #expect(saved.monthlySalary == 150_000)
        #expect(saved.hourlyRate == 1000)
    }

    @Test func aSalaryOpensWithTheSalary() {
        let form = IncomeRateForm(ProfileIncomeTests.monthly)
        #expect(!form.isHourly)
        #expect(form.text == "150\u{202F}000")
    }

    @Test func noRateYetStartsEmptyAndCannotBeSavedEmpty() {
        var form = IncomeRateForm(ProfileSettings())
        #expect(form.text.isEmpty)
        #expect(!form.canSave)
        #expect(!form.isInvalid, "nothing typed is not a mistake")
        form.text = "0"
        #expect(form.canSave, "zero is a rate, as on Android")
    }

    @Test func textThatIsNotANumberCannotBeSaved() {
        var form = IncomeRateForm(hourly)
        for text in ["abc", "-5", "1,2,3", "∞"] {
            form.text = text
            #expect(form.value == nil, "\(text)")
            #expect(form.isInvalid, "\(text)")
            #expect(form.applied(to: hourly) == nil, "\(text)")
        }
        form.text = "1500.25"
        #expect(form.value == 1500.25)
    }

    // MARK: Tax and hours

    @Test func taxAndHoursStartWithTheStoredOnes() throws {
        var form = TaxHoursForm(hourly)
        #expect(form.taxText == "10")
        #expect(form.hoursText == "40")
        #expect(form.invalidFields.isEmpty)
        form.taxText = "13"
        form.hoursText = "37,5"
        let saved = try #require(form.applied(to: hourly))
        #expect(saved.taxPercent == 13)
        #expect(saved.hoursPerWeek == 37.5)
        #expect(saved.hourlyRate == hourly.hourlyRate)
        #expect(saved.incomeHourly == hourly.incomeHourly)
    }

    @Test func noTaxIsZeroButNoHoursIsAMistake() {
        var form = TaxHoursForm(hourly)
        form.taxText = " "
        #expect(form.tax == 0)
        #expect(form.applied(to: hourly)?.taxPercent == 0)
        form.hoursText = ""
        #expect(form.hours == nil)
        #expect(form.invalidFields == [.hours])
        #expect(!form.canSave)
    }

    @Test func taxIsAPercentAndAWeekHas168Hours() {
        var form = TaxHoursForm(hourly)
        form.taxText = "100"
        form.hoursText = "168"
        #expect(form.canSave)
        form.taxText = "100,5"
        form.hoursText = "169"
        #expect(form.invalidFields == [.tax, .hours])
        #expect(form.applied(to: hourly) == nil)
        form.taxText = "-1"
        form.hoursText = "40"
        #expect(form.invalidFields == [.tax])
    }

    // MARK: Markup

    @Test func theMarkupIsTypedInPercent() throws {
        var form = MarkupForm(markup: 0.1)
        #expect(form.text == "10")
        form.text = "7,5"
        let saved = try #require(form.applied(to: hourly))
        #expect(saved.markup == 0.075)
        #expect(saved.payday == hourly.payday)
        #expect(MarkupForm.caption.text(in: ru) == "Наценка к курсу ЦБ")
        #expect(MarkupForm.caption.text(in: en) == "Markup over the CBR rate")
        #expect(MarkupForm.note.text(in: ru) == "Обновляется сама после обмена рублей")
        #expect(MarkupForm.note.text(in: en) == "Updates itself after each ruble exchange")
    }

    @Test func aLearnedMarkupOpensWithItsDecimals() {
        #expect(MarkupForm(markup: 0.0734).text == "7,34")
        #expect(MarkupForm(markup: 0).text == "")
    }

    @Test func theMarkupNeedsANumberThatIsNotNegative() {
        var form = MarkupForm(markup: 0.1)
        form.text = ""
        #expect(!form.canSave)
        #expect(!form.isInvalid)
        form.text = "-2"
        #expect(form.isInvalid)
        #expect(form.applied(to: hourly) == nil)
        form.text = "0"
        #expect(form.applied(to: hourly)?.markup == 0)
    }

    // MARK: Name

    @Test func aNameIsTrimmedAndCannotBeBlank() {
        #expect(ProfileName.cleaned("  Семья \n") == "Семья")
        #expect(ProfileName.cleaned("   ") == nil)
        #expect(ProfileName.cleaned("") == nil)
    }
}
