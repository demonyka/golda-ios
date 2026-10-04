import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// Rates that answer from a closure.
struct StubRatesSource: RatesSource {
    let answer: @Sendable () throws -> [CbrRate]

    func fetch() async throws -> [CbrRate] { try answer() }

    static let offline = StubRatesSource { throw URLError(.notConnectedToInternet) }
}

/// An app over an in-memory environment of its own (database, defaults suite, keys), offline, in
/// UTC, on a clock that stands at 2026-10-02 10:00, the day the Kotlin tests call today.
@MainActor
final class AppHarness {
    nonisolated static let utc = TimeZone(secondsFromGMT: 0)!
    nonisolated static let now = LocalDate(2026, 10, 2).atTimeMillis(hour: 10, in: utc)

    let suiteName = "golda.tests.\(UUID().uuidString)"
    let environment: AppEnvironment
    let model: AppModel

    init(ratesSource: any RatesSource = StubRatesSource.offline) throws {
        environment = try AppEnvironment.inMemory(
            defaultsSuite: suiteName, ratesSource: ratesSource, clock: { AppHarness.now }, zone: { AppHarness.utc }
        )
        model = AppModel(environment: environment)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    var repository: Repository { environment.repository }
    var device: DeviceSettingsStore { environment.deviceSettings }

    /// A profile made through the repository, as if by an earlier launch, with [accounts] opened
    /// without balances.
    @discardableResult
    func profile(_ name: String, accounts: [Account] = []) async throws -> UUID {
        let id = try await repository.createProfile(name: name).id
        for account in accounts { try await repository.saveAccount(account, profileId: id) }
        return id
    }

    /// A phone that went through onboarding with [active] open.
    func onboard(active: UUID?) {
        device.update {
            $0.onboarded = true
            $0.activeProfileId = active
        }
    }

    /// The open profile's data once it is there.
    func data(sourceLocation: SourceLocation = #_sourceLocation) async throws -> AppData {
        await eventually(sourceLocation: sourceLocation) { self.model.data != nil }
        return try #require(model.data, sourceLocation: sourceLocation)
    }
}

/// Waits until [condition] holds, giving the model's observers the main actor in between; records
/// an issue after [timeout].
@MainActor
func eventually(
    timeout: Duration = .seconds(5), sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        guard clock.now < deadline else {
            Issue.record("The condition did not hold within \(timeout)", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

extension AppModel.Phase {
    var isOnboarding: Bool {
        if case .onboarding = self { return true }
        return false
    }

    var data: AppData? {
        if case .main(let data) = self { return data }
        return nil
    }

    /// The failure screen's technical message.
    var failure: String? {
        if case .failed(let reason) = self { return reason }
        return nil
    }
}

extension Account {
    static func card(_ name: String, currency: String = "RUB", sort: Int = 0) -> Account {
        Account(name: name, currency: currency, type: .card, includeInFree: true, sort: sort)
    }
}
