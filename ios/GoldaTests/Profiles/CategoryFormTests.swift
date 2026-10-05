import Foundation
import GoldaCore
import GoldaData
import Testing
import UIKit

@testable import Golda

/// D68: the form of a category of one's own, its words in both languages, and the category on the
/// screens that show categories.
@Suite struct CategoryFormTests {
    static func uid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let ru = Locale(identifier: "ru")
    static let en = Locale(identifier: "en")
    let cat = CustomCategory(id: Self.uid(1), name: "Кот", kind: .expense, hint: "корм, ветеринар", symbol: "cat")

    @Test func aNameMakesACategory() {
        var form = CategoryForm(editing: nil, kind: .income, categoryId: Self.uid(5))
        #expect(form.isNew && !form.canSave)
        #expect(form.symbol == "tag")
        form.name = "  Аренда "
        form.hint = " квартира на Руставели  "
        #expect(form.output == CustomCategory(id: Self.uid(5), name: "Аренда", kind: .income, hint: "квартира на Руставели", symbol: "tag"))
        form.name = "   "
        #expect(form.output == nil)
    }

    @Test func anEditKeepsTheIdAndKind() {
        var form = CategoryForm(editing: cat, kind: .income)
        #expect(!form.isNew && form.kind == .expense && form.symbol == "cat" && form.hint == "корм, ветеринар")
        form.name = "Кошка"
        #expect(form.output?.id == cat.id)
        #expect(form.output?.name == "Кошка")
    }

    @Test func theWordsSpeakBothLanguages() {
        #expect(CategoryForm(editing: nil).title.text(in: Self.ru) == "Новая категория")
        #expect(CategoryForm(editing: cat).title.text(in: Self.en) == "Category")
        #expect(CategoryForm.deleteQuestion("Кот", in: Self.ru) == "Удалить «Кот»?")
        #expect(CategoryForm.deleteQuestion("Кот", in: Self.en) == "Delete “Кот”?")
        #expect(CategoryForm.deleteMessage(operations: 3, kind: .expense, in: Self.ru) == "Операции из неё (3) перейдут в «Прочее».")
        #expect(CategoryForm.deleteMessage(operations: 3, kind: .income, in: Self.en) == "Its operations (3) will move to “Other”.")
        #expect(CategoryForm.deleteMessage(operations: 0, kind: .expense, in: Self.ru) == "В ней нет операций.")
        #expect(CategoryForm.hintNote.text(in: Self.ru).contains("наполнитель"))
    }

    @Test func everyIconExists() {
        #expect(Set(CategoryForm.symbols).count == CategoryForm.symbols.count)
        for name in CategoryForm.symbols {
            #expect(UIImage(systemName: name) != nil, "\(name)")
        }
    }

    @Test func theCatalogNamesOwnCategoriesAsGivenAndForgottenOnesAsOther() {
        let catalog = CategoryCatalog([cat])
        #expect(catalog.name(cat.key, in: Self.en) == "Кот")
        #expect(catalog.name("groceries", in: Self.ru) == "Продукты")
        #expect(catalog.symbol(cat.key) == "cat")
        #expect(catalog.symbol("groceries") == "cart")
        let gone = "custom.\(Self.uid(9).uuidString.lowercased())"
        #expect(catalog.name(gone, in: Self.ru) == "Прочее")
        #expect(catalog.symbol(gone) == Symbols.other)
        #expect(catalog.title(cat.key) == .own("Кот"))
        #expect(catalog.categories(.expense).last?.key == cat.key)
        #expect(catalog.categories(.income).map(\.key) == ["salary", "interest", "gift", "other_income"])
    }
}
