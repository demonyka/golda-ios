import Foundation
import GoldaCore
import GoldaData
import SwiftUI
import Testing
import UIKit

@testable import Golda

/// The Goals tab in each of its states and the goal form, as the lead sees them: drawn in a real
/// window of the hosting app and saved to /tmp/golda-shots/E2 (never committed), in both languages
/// and themes, and at the largest text size. The states the repository never stores (no main goal
/// among several) are built from the sample books directly.
@MainActor @Suite(.timeLimit(.minutes(5))) struct GoalsSnapshotTests {
    static let directory = URL(fileURLWithPath: "/tmp/golda-shots/E2", isDirectory: true)

    /// The sample books, open, with their rate table for rebuilding `AppData` in other states.
    private func samples() async throws -> (AppHarness, AppData, [RateRecord]) {
        let harness = try AppHarness()
        await harness.model.start(command: .samples, profileName: "Личный")
        let data = try await harness.data()
        let rates = try await harness.environment.database.read { try $0.rates() }
        return (harness, data, rates)
    }

    /// [data] with other goals.
    private func data(_ data: AppData, goals: [Goal], device: DeviceSettings, rates: [RateRecord]) -> AppData {
        AppData(
            snapshot: ProfileSnapshot(
                profile: data.profile, accounts: data.accounts, operations: data.operations, obligations: data.obligations,
                goals: goals, wishes: data.wishes
            ),
            device: device, rates: rates, zone: data.zone
        )
    }

    @Test func theTabInEachState() async throws {
        let (harness, samples, rates) = try await samples()
        let device = harness.model.device
        let bike = try #require(samples.goals.first { $0.name == "Велосипед" })
        var cushion = try #require(samples.goals.first { $0.name == "Подушка" })
        var plainBike = bike
        plainBike.isMain = false
        cushion.isMain = true
        // The cushion reached and celebrated already, so its wave is flat in the picture.
        harness.device.update { $0.celebratedGoalId[samples.profile.id] = cushion.id }
        await eventually { harness.model.celebratedGoalId == cushion.id }

        var notMain = cushion
        notMain.isMain = false
        let states: [(String, AppData)] = [
            ("main", samples),
            ("reached", data(samples, goals: [cushion, plainBike], device: device, rates: rates)),
            ("empty", data(samples, goals: [], device: device, rates: rates)),
            ("pick-main", data(samples, goals: [plainBike, notMain], device: device, rates: rates)),
        ]
        for (name, data) in states {
            for language in ["ru", "en"] {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    try await windowImage("tab-\(name)-\(language)", style: style) {
                        MainTabs(data: data, mic: StubMicModel(), tab: .goals)
                            .environment(harness.model)
                            .environment(\.locale, Locale(identifier: language))
                    }
                }
            }
        }
        // "Решено" open, scrolled down by a window tall enough for the whole list.
        for language in ["ru", "en"] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                try await windowImage("tab-decided-\(language)", size: CGSize(width: 402, height: 1_100), style: style) {
                    screen(samples, harness: harness, language: language, showsDecided: true)
                }
            }
        }
        // The largest text size: a window several screens tall, so every row is in the picture.
        for (name, data) in states {
            try await windowImage("tab-\(name)-ru-ax5", size: CGSize(width: 402, height: 2_400), style: .light) {
                screen(data, harness: harness, language: "ru", showsDecided: true)
                    .dynamicTypeSize(.accessibility5)
            }
        }
    }

    @Test func theGoalForm() async throws {
        let (harness, samples, _) = try await samples()
        let bike = try #require(samples.goals.first { $0.name == "Велосипед" })
        let cushion = try #require(samples.goals.first { $0.name == "Подушка" })
        let forms: [(String, Goal?)] = [("new", nil), ("edit-main", bike), ("edit-account", cushion)]
        for (name, goal) in forms {
            for language in ["ru", "en"] {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    try await windowImage("form-\(name)-\(language)", style: style) {
                        GoalFormSheet(data: samples, editing: goal, onDismiss: {}, onDelete: { _ in })
                            .environment(harness.model)
                            .environment(\.locale, Locale(identifier: language))
                    }
                }
            }
            try await windowImage("form-\(name)-ru-ax5", size: CGSize(width: 402, height: 2_400), style: .light) {
                GoalFormSheet(data: samples, editing: goal, onDismiss: {}, onDelete: { _ in })
                    .environment(harness.model)
                    .environment(\.locale, Locale(identifier: "ru"))
                    .dynamicTypeSize(.accessibility5)
            }
        }
    }

    private func screen(_ data: AppData, harness: AppHarness, language: String, showsDecided: Bool) -> some View {
        NavigationStack {
            GoalsScreen(data: data, showsDecided: showsDecided)
                .navigationTitle(Text(AppTab.goals.title))
        }
        .environment(harness.model)
        .environment(AppRouter())
        .environment(\.locale, Locale(identifier: language))
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
        try data.write(to: Self.directory.appendingPathComponent("hosted-\(name)-\(suffix).png"))
    }
}
