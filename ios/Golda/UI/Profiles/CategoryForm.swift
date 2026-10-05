import Foundation
import GoldaCore

/// Everything the category form knows and decides (D68): a name, spending or income, a symbol, and
/// in the person's words what goes into it, which the voice model reads. Built-in categories are
/// not edited, so only one's own come here; a category's kind is fixed once it has operations, so
/// it is picked only for a new one.
struct CategoryForm: Equatable, Sendable {
    /// The category being changed; nil for a new one.
    let editing: CustomCategory?
    /// The id a new category gets, fixed for the life of the form, as a payment's is.
    let categoryId: UUID

    var name: String
    var kind: CategoryKind
    var symbol: String
    var hint: String

    init(editing: CustomCategory?, kind: CategoryKind = .expense, categoryId: UUID = UUID()) {
        self.editing = editing
        self.categoryId = editing?.id ?? categoryId
        name = editing?.name ?? ""
        self.kind = editing?.kind ?? kind
        symbol = editing?.symbol ?? Self.symbols[0]
        hint = editing?.hint ?? ""
    }

    var isNew: Bool { editing == nil }

    var canSave: Bool { output != nil }

    /// What saving writes; nil while the name is blank.
    var output: CustomCategory? {
        guard let name = ProfileName.cleaned(name) else { return nil }
        let hint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        return CustomCategory(id: categoryId, name: name, kind: kind, hint: hint, symbol: symbol)
    }

    /// What a category can wear: the things people keep their own categories for.
    static let symbols = [
        "tag", "pawprint", "cat", "dog", "car", "fuelpump", "parkingsign", "bicycle",
        "tram", "figure.run", "dumbbell", "heart", "cross.case", "scissors", "sparkles", "tshirt",
        "bag", "gift", "birthday.cake", "balloon", "cup.and.saucer", "wineglass", "takeoutbag.and.cup.and.straw", "leaf",
        "stroller", "graduationcap", "book", "gamecontroller", "music.note", "film", "camera", "laptopcomputer",
        "iphone", "wifi", "bolt", "drop", "flame", "hammer", "paintbrush", "wrench.and.screwdriver",
        "house", "building.2", "banknote", "creditcard", "chart.line.uptrend.xyaxis", "airplane", "suitcase", "globe",
    ]

    // MARK: Text

    var title: LocalizedStringResource {
        isNew
            ? LocalizedStringResource("New category", table: "Profiles", comment: "Title of the category form when adding one.")
            : LocalizedStringResource("Category", table: "Profiles", comment: "A category of one’s own: the title of the category form when changing one, and the last row of the categories, “+ Category”.")
    }

    var saveTitle: LocalizedStringResource {
        isNew
            ? LocalizedStringResource("Add", table: "Profiles", comment: "Payment form: the main action that adds the payment.")
            : LocalizedStringResource("Save", table: "Profiles", comment: "Sheets of the profile screen: the main action that saves the change.")
    }

    static let namePrompt = LocalizedStringResource("Category name", table: "Profiles", comment: "Category form: the placeholder of the category's name, like “Cat”.")
    static let expenseTitle = LocalizedStringResource("Spending", table: "Profiles", comment: "Category form: the category is for expenses.")
    static let incomeTitle = LocalizedStringResource("Income", table: "Profiles", comment: "Profile screen: the header of the income group.")
    static let kindTitle = LocalizedStringResource("Kind", table: "Profiles", comment: "Category form: what VoiceOver calls the spending/income picker.")
    static let symbolTitle = LocalizedStringResource("Icon", table: "Profiles", comment: "Category form: the header over the grid of icons.")
    static let hintPrompt = LocalizedStringResource("What goes in it", table: "Profiles", comment: "Category form: the placeholder of the words that tell voice what belongs here.")
    static let hintNote = LocalizedStringResource(
        "For voice: with “food, vet” here, “litter 20 lari” lands in this category.", table: "Profiles",
        comment: "Category form: the footer under what goes in the category."
    )
    static let deleteTitle = LocalizedStringResource("Delete category", table: "Profiles", comment: "Category form and row: deletes the category, after asking.")

    /// "Удалить «Кот»?", the question before deleting.
    static func deleteQuestion(_ name: String, in locale: Locale) -> String {
        LocalizedStringResource("Delete “\(name)”?", table: "Profiles", comment: "Category: the question before deleting it, with its name.").text(in: locale)
    }

    /// What deleting does to the category's operations.
    static func deleteMessage(operations: Int, kind: CategoryKind, in locale: Locale) -> String {
        guard operations > 0 else {
            return LocalizedStringResource("There are no operations in it.", table: "Profiles", comment: "Category: before deleting one with no operations.").text(in: locale)
        }
        let other = CategoryName.resource(Category.other(kind)).text(in: locale)
        return LocalizedStringResource(
            "Its operations (\(operations)) will move to “\(other)”.", table: "Profiles",
            comment: "Category: before deleting one, how many operations move to “Other”."
        ).text(in: locale)
    }
}
