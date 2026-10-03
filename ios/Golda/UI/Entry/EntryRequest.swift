import Foundation
import GoldaCore

/// What the operation form opens with: nothing for a new operation from "+", the operation to edit
/// from a tapped row, a purchase being weighed up ("Сомневаюсь", from the voice) or the wish being
/// bought from the wishlist.
struct EntryRequest: Equatable, Sendable {
    var editing: OperationFull?
    var consider: Consider?
    var wishId: UUID?

    init(editing: OperationFull? = nil, consider: Consider? = nil, wishId: UUID? = nil) {
        self.editing = editing
        self.consider = consider
        self.wishId = wishId
    }
}
