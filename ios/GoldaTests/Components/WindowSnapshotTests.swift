import SwiftUI
import Testing
import UIKit

@testable import Golda

/// `ImageRenderer` cannot draw UIKit-backed pieces (`ProgressView`, Liquid Glass, the tab bar and its
/// accessory). These shots put the views in a real window of the hosting app and take its picture,
/// so the lead sees them as they will look. The PNGs go to /tmp and are never committed.
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
                        VStack(spacing: Theme.Gap.m) {
                            MicAccessoryContent(state: state, level: 0.1) {}
                                .glassEffect(.regular, in: .capsule)
                            MicFloatingButton(state: state, level: 0.1) {}
                        }
                    }
                }
                .padding(Theme.Gap.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Color.page)
            }
        }
    }

    /// The accessory at home: a TabView with four tabs, the wide mic and a toast over a list.
    @Test func tabViewWithAccessoryAndToast() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            try await windowImage("tabs", style: style) { TabsHarness(state: .idle) }
            try await windowImage("tabs-recording", style: style) { TabsHarness(state: .recording) }
        }
    }
}

/// Stands in for the app shell in the window shots only.
private struct TabsHarness: View {
    var state: MicState
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
                }
            }
        }
        .tabViewBottomAccessory { MicAccessoryContent(state: state, level: 0.1) {} }
    }
}
