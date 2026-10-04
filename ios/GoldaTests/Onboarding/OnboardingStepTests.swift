import Foundation
import Testing

@testable import Golda

/// The three steps of the first launch, as Android's `Onboarding` walks them: income, currencies,
/// accounts. The order, the bar and the words are the domain of `OnboardingStep`; the screens only
/// lay them out.
@Suite struct OnboardingStepTests {
    private let ru = Locale(identifier: "ru")
    private let en = Locale(identifier: "en")

    @Test func theStepsGoIncomeThenCurrenciesThenAccounts() {
        #expect(OnboardingStep.allCases == [.income, .currencies, .accounts])
        #expect(OnboardingStep.count == 3)
        #expect(OnboardingStep.income.number == 1 && OnboardingStep.accounts.number == 3)
    }

    @Test func nextAndPreviousWalkTheStepsAndStopAtTheEnds() {
        #expect(OnboardingStep.income.previous == nil)
        #expect(OnboardingStep.income.next == .currencies)
        #expect(OnboardingStep.currencies.previous == .income)
        #expect(OnboardingStep.currencies.next == .accounts)
        #expect(OnboardingStep.accounts.previous == .currencies)
        #expect(OnboardingStep.accounts.next == nil)
        #expect(OnboardingStep.income.isFirst && !OnboardingStep.currencies.isFirst)
        #expect(OnboardingStep.accounts.isLast && !OnboardingStep.currencies.isLast)
    }

    /// Android's bar stands at `(step + 1) / 3`: a third on the first step, full on the last.
    @Test func theBarFillsAThirdAtATime() {
        #expect(OnboardingStep.income.progress == 1.0 / 3)
        #expect(OnboardingStep.currencies.progress == 2.0 / 3)
        #expect(OnboardingStep.accounts.progress == 1)
    }

    @Test func onlyTheLastStepSaysDone() {
        #expect(OnboardingStep.income.advanceTitle.text(in: en) == "Next")
        #expect(OnboardingStep.currencies.advanceTitle.text(in: en) == "Next")
        #expect(OnboardingStep.accounts.advanceTitle.text(in: en) == "Done")
        #expect(OnboardingStep.income.advanceTitle.text(in: ru) == "Дальше")
        #expect(OnboardingStep.accounts.advanceTitle.text(in: ru) == "Готово")
        #expect(OnboardingStep.backTitle.text(in: en) == "Back")
        #expect(OnboardingStep.backTitle.text(in: ru) == "Назад")
    }

    @Test func eachStepIsNamedAndExplainedInBothLanguages() {
        #expect(OnboardingStep.allCases.map { $0.title.text(in: ru) } == ["Доход", "Валюты", "Счета"])
        #expect(OnboardingStep.allCases.map { $0.title.text(in: en) } == ["Income", "Currencies", "Accounts"])
        for step in OnboardingStep.allCases {
            #expect(step.note.text(in: ru).unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }, "\(step)")
            #expect(step.note.text(in: en) != step.note.text(in: ru), "\(step)")
        }
        #expect(OnboardingStep.income.note.text(in: ru).contains("«можно сегодня»"))
        // The main currency is picked on this step, so the note no longer says it is the ruble.
        #expect(OnboardingStep.currencies.note.text(in: en).contains("Big numbers and totals are in the main one"))
        #expect(!OnboardingStep.currencies.note.text(in: ru).contains("Рубль"))
        #expect(OnboardingStep.mainHeader.text(in: ru) == "Основная валюта — в ней крупные цифры и итоги")
    }

    @Test func theBarIsReadAsAPositionInWords() {
        #expect(OnboardingStep.currencies.positionText(in: en) == "Step 2 of 3")
        #expect(OnboardingStep.currencies.positionText(in: ru) == "Шаг 2 из 3")
    }
}
