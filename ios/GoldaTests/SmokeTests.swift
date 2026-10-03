import Testing

@testable import Golda

/// Proves that the hosted test bundle loads and can see the app module.
@Suite struct SmokeTests {
    @Test func theAppModuleIsVisible() {
        #expect(String(describing: GoldaApp.self) == "GoldaApp")
    }
}
