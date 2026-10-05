import Foundation
import GoldaCore

/// The profile's categories as the screens show them (D68): the built-in ones by their key, in the
/// app's language, and the person's own by the name and symbol they gave. A key of an own category
/// that is gone (deleted on the other phone, its operations not here yet) reads as "Прочее".
struct CategoryCatalog: Equatable, Sendable {
    let custom: [CustomCategory]
    private let byKey: [String: CustomCategory]

    init(_ custom: [CustomCategory]) {
        self.custom = custom
        byKey = Dictionary(custom.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static let builtIn = CategoryCatalog([])

    /// Every category of [kind]: the built-in ones, then the person's own.
    func categories(_ kind: CategoryKind) -> [GoldaCore.Category] {
        GoldaCore.Category.all(custom: custom).filter { $0.kind == kind }
    }

    func own(_ key: String) -> CustomCategory? { byKey[key] }

    func name(_ key: String, in locale: Locale) -> String {
        if let own = byKey[key] { return own.name }
        return CategoryName.resource(key).text(in: locale)
    }

    func symbol(_ key: String?) -> String {
        if let key, let own = byKey[key] { return own.symbol ?? Symbols.other }
        return Symbols.category(key)
    }

    func title(_ key: String?) -> CategoryTitle {
        if let key, let own = byKey[key] { return .own(own.name) }
        return CategoryTitle(key)
    }
}
