import Foundation
import Testing

@testable import GoldaCore

/// D68: categories of the profile's own, beside the built-in ones, which stay as they are; the voice
/// model gets them with what goes into them, and how this person filed things before.
@Suite struct CustomCategoryTests {
    let pets = CustomCategory(id: uid(1), name: "Кот", kind: .expense, hint: "корм, ветеринар, наполнитель", symbol: "cat")
    let rent = CustomCategory(id: uid(2), name: "Сдача квартиры", kind: .income, hint: "")

    @Test func aKeyOfItsOwnThatNoBuiltInHas() {
        #expect(pets.key == "custom.\(uid(1).uuidString.lowercased())")
        #expect(CustomCategory.id(ofKey: pets.key) == uid(1))
        #expect(CustomCategory.id(ofKey: "eating_out") == nil)
        #expect(CustomCategory.id(ofKey: "custom.nonsense") == nil)
        #expect(!Category.builtIn.contains { CustomCategory.id(ofKey: $0.key) != nil })
    }

    @Test func itIsACategoryWithItsHint() {
        #expect(pets.category == Category(key: pets.key, name: "Кот", kind: .expense, hint: "корм, ветеринар, наполнитель"))
        // A blank hint is no hint.
        #expect(rent.category.hint == nil)
        #expect(Category.all(custom: [rent, pets]).map(\.key) == Category.builtIn.map(\.key) + [rent.key, pets.key])
    }

    @Test func theFallbackOfEachKindIsItsOther() {
        #expect(Category.other(.expense) == "other")
        #expect(Category.other(.income) == "other_income")
    }

    @Test func thePromptListsTheOwnCategoriesWithWhatGoesInThem() {
        let prompt = VoicePrompt.system(
            accounts: [], categories: Category.all(custom: [pets, rent]), settings: Settings(), today: LocalDate(2026, 10, 5)
        )
        #expect(prompt.contains("\(pets.key) (Кот: корм, ветеринар, наполнитель)"))
        #expect(prompt.contains("\(rent.key) (Сдача квартиры)"))
        #expect(prompt.contains("Своя категория пользователя"))
        // Without examples there is no section for them.
        #expect(!prompt.contains("раньше раскладывал"))
    }

    @Test func thePromptShowsHowThingsWereFiledBefore() {
        let examples = [CategoryExample(note: "шаурма", categoryKey: "eating_out"), CategoryExample(note: "корм", categoryKey: pets.key)]
        let prompt = VoicePrompt.system(
            accounts: [], categories: Category.all(custom: [pets]), settings: Settings(), today: LocalDate(2026, 10, 5), examples: examples
        )
        #expect(prompt.contains("- шаурма → eating_out\n- корм → \(pets.key)"))
    }

    @Test func examplesAreTheLatestFilingOfEachNote() {
        func op(_ day: Int64, _ note: String, _ key: String?, type: OpType = .expense) -> GoldaCore.Operation {
            GoldaCore.Operation(id: UUID(), type: type, timestamp: day * 86_400_000, categoryKey: key, note: note)
        }
        let operations = [
            op(1, "Шаурма", "other"),
            op(5, "шаурма ", "eating_out"),
            op(3, "корм", pets.key),
            op(4, "", "groceries"),
            op(6, "такси", nil),
            op(7, "обмен", nil, type: .transfer),
            op(8, "старое", "custom.\(uid(9).uuidString.lowercased())"),
        ]
        let examples = CategoryExample.latest(operations, categories: Category.all(custom: [pets]), limit: 10)
        // The newest first; a note filed twice counts as it was filed last; no note, no category, or
        // a category that is gone teaches nothing.
        #expect(examples == [CategoryExample(note: "шаурма", categoryKey: "eating_out"), CategoryExample(note: "корм", categoryKey: pets.key)])
        #expect(CategoryExample.latest(operations, categories: Category.builtIn, limit: 1).count == 1)
    }
}
