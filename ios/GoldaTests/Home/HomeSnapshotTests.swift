import Foundation
import GoldaCore
import GoldaData
import SwiftUI
import Testing
import UIKit

@testable import Golda

/// Home as the lead sees it in states the sample life never reaches on its own: today overspent,
/// with a credit card's grace period running out. The whole shell is drawn in a real window of the
/// hosting app (the tab bar, the accessory and the toolbar's glass need one) and saved to /tmp; the
/// checks are only that the books are in that state and that the picture was taken.
@MainActor @Suite(.timeLimit(.minutes(1))) struct HomeSnapshotTests {
    static let directory = URL(fileURLWithPath: "/tmp/golda-shots/H", isDirectory: true)

    @Test func overspentWithAGraceWarning() async throws {
        let harness = try AppHarness()
        await harness.model.start(command: .samples, profileName: "Личный")
        let data = try await harness.data()
        let profileId = data.profile.id
        let cash = try #require(data.accounts.first { $0.name == "Наличные ₾" })
        var credit = try #require(data.accounts.first { $0.name == "Кредитка" })

        // A dinner far past the day's budget, and the card's interest-free period ending in two days.
        try await harness.model.save(
            Draft(type: .expense, timestamp: AppHarness.now, accountId: cash.id, amountMinor: 18_000, categoryKey: "eating_out", note: "Ужин")
        )
        credit.graceUntil = Int64(harness.environment.today().plusDays(2).epochDay)
        try await harness.repository.saveAccount(credit, profileId: profileId)
        await eventually { harness.model.data?.operations.count == data.operations.count + 1 && harness.model.data?.accounts.contains(credit) == true }

        let hero = HomeHero(data: try #require(harness.model.data), today: harness.environment.today())
        #expect(hero.isOverspent)
        #expect(hero.graceWarnings.map(\.daysLeft) == [2])

        for layout in [MicLayout.accessory, .floating] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                try await windowImage("overspent-\(layout.rawValue)", style: style) {
                    RootView(micLayout: layout, mic: StubMicModel())
                        .environment(harness.model)
                        .environment(\.locale, Locale(identifier: "ru"))
                }
            }
        }
    }

    /// The view in a phone-sized window of the hosting app, its picture written to the directory.
    private func windowImage<V: View>(
        _ name: String, size: CGSize = CGSize(width: 402, height: 874), style: UIUserInterfaceStyle, @ViewBuilder _ content: () -> V
    ) async throws {
        // A hosted test bundle runs inside the app and has a scene; without one there is nothing to look at.
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = UIHostingController(rootView: content())
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(1_500))
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let data = try #require(image.pngData())
        #expect(data.count > 10_000, "\(name) looks empty")
        let suffix = style == .dark ? "dark" : "light"
        try data.write(to: Self.directory.appendingPathComponent("hosted-\(name)-ru-\(suffix).png"))
    }
}
