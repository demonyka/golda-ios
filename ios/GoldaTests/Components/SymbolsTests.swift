import GoldaCore
import Testing
import UIKit

@testable import Golda

/// Every SF Symbol name the app uses must exist in the SDK it is built with: a misspelt or
/// renamed symbol draws nothing, silently.
@Suite struct SymbolsTests {
    @Test func everySymbolNameResolves() {
        for name in Symbols.allNames {
            #expect(UIImage(systemName: name) != nil, "SF Symbol “\(name)” does not exist")
        }
    }

    @Test func aMissingNameWouldBeCaught() {
        // The guard of the test above: the check really does tell a real name from a made-up one.
        #expect(UIImage(systemName: "definitely.not.a.symbol") == nil)
    }

    @Test func everyBuiltInCategoryHasASymbol() {
        for key in Symbols.categoryKeys {
            #expect(!Symbols.category(key).isEmpty)
        }
        // Categories of your own, and none at all, get the box.
        #expect(Symbols.category("my-own") == Symbols.other)
        #expect(Symbols.category(nil) == Symbols.other)
    }

    @Test func categoriesShowDifferentSymbolsExceptTheBox() {
        let names = Symbols.categoryKeys.filter { Symbols.category($0) != Symbols.other }.map { Symbols.category($0) }
        #expect(Set(names).count == names.count)
    }

    @Test func everyAccountTypeHasASymbol() {
        for type in AccountType.allCases {
            #expect(UIImage(systemName: Symbols.accountType(type)) != nil)
        }
        #expect(Set(AccountType.allCases.map(Symbols.accountType)).count == AccountType.allCases.count)
    }

    @Test func theSelectedTabTakesTheFilledSymbol() {
        for tab in Symbols.Tab.allCases {
            #expect(tab.symbol(selected: true) == tab.symbol(selected: false) + ".fill")
        }
    }

    @Test func anOperationShowsItsCategoryOrItsKind() {
        #expect(Symbols.operation(categoryKey: "groceries", type: .expense) == "cart")
        #expect(Symbols.operation(categoryKey: nil, type: .transfer) == Symbols.transfer)
        #expect(Symbols.operation(categoryKey: nil, type: .adjustment) == Symbols.reconcile)
        #expect(Symbols.operation(categoryKey: nil, type: .expense) == Symbols.other)
    }
}
