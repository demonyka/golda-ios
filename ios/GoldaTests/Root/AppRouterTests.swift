import Foundation
import GoldaCore
import Testing

@testable import Golda

@MainActor @Suite struct AppRouterTests {
    private let coffee = HomeFixture.operation(.expense, at: HomeFixture.at(hour: 9), note: "Кофе", [(HomeFixture().cash, -800, -24_000)])

    @Test func nothingIsPresentedAtFirst() {
        #expect(AppRouter().presented == nil)
    }

    @Test func presentingOpensTheRouteAndDismissingClosesIt() {
        let router = AppRouter()
        router.present(.settings)
        #expect(router.presented == .settings)
        router.present(.entry(EntryRequest(editing: coffee)))
        #expect(router.presented == .entry(EntryRequest(editing: coffee)))
        router.dismiss()
        #expect(router.presented == nil)
    }

    @Test func aNewEntryAsksForNothing() {
        let request = EntryRequest()
        #expect(request.editing == nil)
        #expect(request.consider == nil)
        #expect(request.wishId == nil)
    }

    /// The sheet is re-presented when the identity changes, so each operation gets a fresh form,
    /// while the same request keeps its identity.
    @Test func eachScreenAndEachOperationHasItsOwnIdentity() {
        let tea = HomeFixture.operation(.expense, at: HomeFixture.at(hour: 10), note: "Чай", [(HomeFixture().cash, -500, -15_000)])
        let wish = UUID()
        let routes: [AppRoute] = [
            .entry(EntryRequest()),
            .entry(EntryRequest(editing: coffee)),
            .entry(EntryRequest(editing: tea)),
            .entry(EntryRequest(wishId: wish)),
            .settings, .profiles, .voiceConsent,
        ]
        #expect(Set(routes.map(\.id)).count == routes.count)
        #expect(AppRoute.entry(EntryRequest(editing: coffee)).id == AppRoute.entry(EntryRequest(editing: coffee)).id)
        #expect(AppRoute.entry(EntryRequest(wishId: wish)).id == "entry." + wish.uuidString)
    }
}
