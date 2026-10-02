import Foundation

extension Sequence {
    /// A sort that keeps equal elements in their original order, like Kotlin's `sortedBy`, so lists
    /// with ties look the same on both platforms.
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated()
            .sorted { l, r in
                areInIncreasingOrder(l.element, r.element)
                    || (!areInIncreasingOrder(r.element, l.element) && l.offset < r.offset)
            }
            .map(\.element)
    }
}

extension Array where Element: Hashable {
    /// Kotlin's `distinct()`: the first of each, in order.
    func distinct() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
