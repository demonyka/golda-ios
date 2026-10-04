import Foundation
import GoldaCore
import Testing

@testable import Golda

/// The long currency lists: names in the interface language, the popular ones first, the rest by
/// name, and the search.
@Suite struct CurrencyListTests {
    private let ru = Locale(identifier: "ru"), en = Locale(identifier: "en")

    @Test func aCurrencyIsCalledByItsNameInTheInterfaceLanguage() {
        #expect(CurrencyNames.name("ARS", in: ru) == "Аргентинский песо")
        #expect(CurrencyNames.name("ARS", in: en) == "Argentine Peso")
        #expect(CurrencyNames.name("GEL", in: Locale(identifier: "ru_GE")) == "Грузинский лари")
        // The interface is Russian or English; any other language reads the English names.
        #expect(CurrencyNames.name("ARS", in: Locale(identifier: "de_DE")) == "Argentine Peso")
        // No name to be had: the code.
        #expect(CurrencyNames.name("ZZZ", in: ru) == "ZZZ")
    }

    @Test func thePopularOnesComeFirstThenTheRestByName() {
        for locale in [ru, en] {
            let sections = CurrencySections(matching: "", in: locale)
            #expect(sections.yours.isEmpty)
            #expect(sections.popular == Currencies.popular)
            #expect(Set(sections.others) == Set(Currencies.all).subtracting(Currencies.popular))
            #expect(sections.others.count == Currencies.all.count - Currencies.popular.count)
            let names = sections.others.map { CurrencyNames.name($0, in: locale) }
            let sorted = names.sorted { $0.compare($1, options: [.caseInsensitive], locale: locale) == .orderedAscending }
            #expect(names == sorted, "\(locale.identifier)")
        }
        // In Russian, the Australian dollar (А) comes before the Argentine peso (Ар) and the zloty (П) after both.
        let russian = CurrencySections(matching: "", in: ru).others
        #expect(russian.firstIndex(of: "AUD")! < russian.firstIndex(of: "ARS")!)
        #expect(russian.firstIndex(of: "ARS")! < russian.firstIndex(of: "PLN")!)
    }

    @Test func yourCurrenciesComeFirstAndOnlyOnce() {
        let sections = CurrencySections(yours: ["GEL", "RUB", "USD", "ARS"], matching: "", in: ru)
        #expect(sections.yours == ["GEL", "RUB", "USD", "ARS"])
        #expect(sections.popular == ["EUR", "GBP", "THB", "TRY", "KZT", "AMD", "CNY", "AED", "VND", "IDR"])
        #expect(!sections.others.contains("ARS"))
        // Yours outside the catalogue (an old account in levs) is yours like any other.
        #expect(CurrencySections(yours: ["RUB", "BGN"], matching: "", in: ru).yours == ["RUB", "BGN"])
    }

    @Test func extraCodesOutsideTheCatalogueComeLast() {
        let sections = CurrencySections(extra: ["RUB", "BGN", "ARS"], matching: "", in: ru)
        #expect(sections.others.last == "BGN")
        #expect(sections.others.filter { $0 == "ARS" }.count == 1)
        #expect(!sections.others.contains("RUB"))
    }

    @Test func searchFindsByNameOrCodeInAnyCase() {
        #expect(CurrencySections(matching: "арг", in: ru).others == ["ARS"])
        #expect(CurrencySections(matching: "ars", in: ru).others.contains("ARS"))
        #expect(CurrencySections(matching: "  ARS ", in: en).others.contains("ARS"))
        #expect(CurrencySections(matching: "лари", in: ru).popular == ["GEL"])
        // The English name works in Russian too: people type "peso" as often as "песо".
        let pesos = CurrencySections(matching: "peso", in: ru)
        #expect(pesos.others.contains("ARS") && pesos.others.contains("MXN"))
        #expect(CurrencySections(matching: "песо", in: ru).others.contains("ARS"))
        // Your own ones are searched too.
        #expect(CurrencySections(yours: ["GEL", "RUB"], matching: "gel", in: en).yours == ["GEL"])
        #expect(CurrencySections(matching: "qqqq", in: ru).isEmpty)
        #expect(!CurrencySections(matching: "", in: ru).isEmpty)
    }
}
