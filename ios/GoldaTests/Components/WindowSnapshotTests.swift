import SwiftUI
import Testing
import UIKit

@testable import Golda

/// `ImageRenderer` cannot draw UIKit-backed pieces (`ProgressView`, Liquid Glass, the tab bar).
/// These shots put the views in a real window of the hosting app and take its picture, so the lead
/// sees them as they will look. The PNGs go to /tmp and are never committed.
@Suite @MainActor struct WindowSnapshotTests {
    private func windowImage<V: View>(
        _ name: String,
        size: CGSize = CGSize(width: 390, height: 844),
        style: UIUserInterfaceStyle,
        @ViewBuilder _ content: () -> V
    ) async throws {
        // A hosted test bundle runs inside the app and has a scene; without one there is nothing to look at.
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        try FileManager.default.createDirectory(at: ComponentSnapshotTests.directory, withIntermediateDirectories: true)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = UIHostingController(rootView: content())
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(900))
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let suffix = style == .dark ? "dark" : "light"
        let data = try #require(image.pngData())
        try data.write(to: ComponentSnapshotTests.directory.appendingPathComponent("window-\(name)-\(suffix).png"))
    }

    @Test func micStatesInAWindow() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            try await windowImage("mic", size: CGSize(width: 390, height: 640), style: style) {
                VStack(spacing: Theme.Gap.l) {
                    ForEach([MicState.idle, .recording, .thinking], id: \.self) { state in
                        MicFloatingButton(state: state, level: 0.1) {}
                    }
                }
                .padding(Theme.Gap.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Color.page)
            }
        }
    }

    /// A sheet's toolbar: "Отмена" in plain glass and the confirmation in the system blue, enabled
    /// and disabled. The confirmation's text must be light on the blue in both themes.
    @Test func sheetToolbarsInAWindow() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            try await windowImage("sheet-toolbars", size: CGSize(width: 390, height: 300), style: style) {
                VStack(spacing: 0) {
                    ForEach([true, false], id: \.self) { enabled in
                        NavigationStack {
                            Theme.Color.page
                                .navigationTitle(Text(verbatim: enabled ? "Новый счёт" : "Без названия"))
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button {} label: { Text(verbatim: "Отмена") }
                                    }
                                    ToolbarItem(placement: .confirmationAction) {
                                        ConfirmButton(title: "Добавить") {}
                                            .disabled(!enabled)
                                    }
                                }
                        }
                        .frame(height: 120)
                    }
                }
            }
        }
    }

    /// The mic at home: a TabView with four tabs, the floating mic and a toast above it over a list.
    @Test func tabViewWithMicAndToast() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            try await windowImage("tabs", style: style) { TabsHarness(mic: StubMicModel()) }
            let recording = StubMicModel()
            recording.tap()
            try await windowImage("tabs-recording", style: style) { TabsHarness(mic: recording) }
        }
    }
}

/// Stands in for the app shell in the window shots only.
private struct TabsHarness: View {
    var mic: any MicModel
    @State private var toast: UndoToast? = UndoToast("Кофе −8 ₾\nИз отложенного", length: .long) {}

    var body: some View {
        TabView {
            ForEach(Symbols.Tab.allCases, id: \.self) { tab in
                Tab(String(describing: tab), systemImage: tab.symbol(selected: false)) {
                    ScrollView {
                        VStack(spacing: Theme.Gap.s) {
                            HeroCard {
                                VStack(alignment: .leading, spacing: Theme.Gap.s) {
                                    Text(verbatim: "Можно сегодня").font(.subheadline).foregroundStyle(.secondary)
                                    BigNumber(minor: 184_900, currency: "RUB")
                                    WavyBar(progress: 0.65, hero: true)
                                }
                            }
                            ForEach(0..<8, id: \.self) { _ in
                                Card {
                                    HStack(spacing: Theme.Gap.m) {
                                        GlyphCircle(Symbols.category("eating_out"))
                                        Text(verbatim: "Кофе").font(.body)
                                        Spacer()
                                        Text(verbatim: "−8 ₾").font(.body).tabularDigits()
                                    }
                                }
                            }
                        }
                        .padding(Theme.Gap.m)
                    }
                    .background(Theme.Color.page)
                    .undoToast($toast)
                    .modifier(MicPlacement(mic: mic))
                }
            }
        }
        .tabBarMinimizeBehavior(.never)
    }
}
