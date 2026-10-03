import GoldaCore
import SwiftUI
import Testing
import UIKit

@testable import Golda

/// Renders every component in light and dark into PNGs for a human to look at. The files go to
/// /tmp and are never committed; the checks are only that something was drawn, that the theme
/// resolved (the page colour under the view is the right one for the scheme) and that dark differs from light.
@Suite @MainActor struct ComponentSnapshotTests {
    static let directory = URL(fileURLWithPath: "/tmp/golda-shots/T", isDirectory: true)

    private static let pageHex: [ColorScheme: UInt32] = [.light: 0xF4F4F5, .dark: 0x1F1F23]

    /// Renders `content` on the page colour at `width` points in both schemes and returns the two images.
    @discardableResult
    private func shoot(
        _ name: String,
        width: CGFloat = 390,
        dynamicType: DynamicTypeSize = .large,
        @ViewBuilder _ content: () -> some View
    ) throws -> (light: UIImage, dark: UIImage) {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        var images: [ColorScheme: UIImage] = [:]
        for scheme in [ColorScheme.light, .dark] {
            let view = content()
                .padding(Theme.Gap.m)
                .frame(width: width)
                .background(Theme.Color.page)
                .environment(\.colorScheme, scheme)
                .dynamicTypeSize(dynamicType)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            let image = try #require(renderer.uiImage, "\(name) \(scheme) did not render")
            let data = try #require(image.pngData())
            let suffix = scheme == .light ? "light" : "dark"
            try data.write(to: Self.directory.appendingPathComponent("\(name)-\(suffix).png"))
            #expect(image.size.width == width, "\(name) \(scheme) width")
            #expect(image.size.height > 20, "\(name) \(scheme) height")
            #expect(isClose(pixel(image, x: 1, y: 1), Self.pageHex[scheme]), "\(name): the page colour in \(scheme)")
            images[scheme] = image
        }
        let light = try #require(images[.light]), dark = try #require(images[.dark])
        #expect(light.pngData() != dark.pngData(), "\(name): dark is not just light again")
        return (light, dark)
    }

    /// Colour conversion may move a channel by one step; more than that is a different colour.
    private func isClose(_ a: UInt32?, _ b: UInt32?) -> Bool {
        guard let a, let b else { return false }
        return [16, 8, 0].allSatisfy { shift in
            abs(Int((a >> UInt32(shift)) & 0xFF) - Int((b >> UInt32(shift)) & 0xFF)) <= 2
        }
    }

    /// The colour of one pixel as 0xRRGGBB, in sRGB.
    private func pixel(_ image: UIImage, x: Int, y: Int) -> UInt32? {
        guard let cg = image.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cg, in: CGRect(x: -x * 3, y: -(cg.height - 1 - y * 3), width: cg.width, height: cg.height))
            return true
        }
        guard drawn else { return nil }
        return UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2])
    }

    // MARK: Components

    @Test func wavyBar() throws {
        try shoot("wavy-bar") { WavyBarGallery() }
    }

    @Test func wavyBarAtAccessibilitySize() throws {
        try shoot("wavy-bar-xxxl", dynamicType: .accessibility3) { WavyBarGallery() }
    }

    @Test func bigNumber() throws {
        try shoot("big-number") {
            VStack(spacing: Theme.Gap.m) {
                HeroCard {
                    VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                        Text(verbatim: "Можно сегодня").font(.subheadline).foregroundStyle(.secondary)
                        BigNumber(minor: 184_900, currency: "RUB")
                        Text(verbatim: "≈ 52,2 ₾ · 20 $").font(.body).tabularDigits().foregroundStyle(.secondary)
                    }
                }
                HeroCard {
                    VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                        Text(verbatim: "Всего · копейки тише").font(.subheadline).foregroundStyle(.secondary)
                        BigNumber(minor: 17_475, currency: "USD", fraction: .always, quietColor: Theme.Color.muted)
                    }
                }
                HeroCard {
                    VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                        Text(verbatim: "Длинное число").font(.subheadline).foregroundStyle(.secondary)
                        BigNumber(minor: 123_456_789_000, currency: "RUB", fraction: .always, quietColor: Theme.Color.muted)
                    }
                }
                HeroCard(isError: true) {
                    VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                        Text(verbatim: "Перерасход").font(.subheadline).foregroundStyle(.secondary)
                        BigNumber(minor: -32_000, currency: "RUB")
                    }
                }
                HeroCard { BigNumber(minor: 800, currency: "GEL", alignment: .center) }
            }
        }
    }

    @Test func bigNumberAtAccessibilitySize() throws {
        try shoot("big-number-xxxl", dynamicType: .accessibility3) {
            VStack(spacing: Theme.Gap.m) {
                HeroCard { BigNumber(minor: 184_900, currency: "RUB") }
                HeroCard { BigNumber(minor: 123_456_789_000, currency: "RUB", fraction: .always, quietColor: Theme.Color.muted) }
            }
        }
    }

    @Test func cards() throws {
        try shoot("cards") {
            VStack(spacing: Theme.Gap.m) {
                HeroCard {
                    VStack(alignment: .leading, spacing: Theme.Gap.s) {
                        Text(verbatim: "Hero card").font(.subheadline).foregroundStyle(.secondary)
                        Text(verbatim: "1 849 ₽").font(.largeTitle.weight(.semibold)).tabularDigits()
                        WavyBar(progress: 0.65, hero: true)
                    }
                }
                HeroCard(isError: true) {
                    VStack(alignment: .leading, spacing: Theme.Gap.s) {
                        Text(verbatim: "Hero card, error").font(.subheadline).foregroundStyle(.secondary)
                        Text(verbatim: "−320 ₽").font(.largeTitle.weight(.semibold)).tabularDigits()
                        WavyBar(progress: 1, hero: true, flat: false)
                    }
                }
                Card { Text(verbatim: "A plain card").font(.body) }
                Card(tone: .error) { Text(verbatim: "A plain card, error").font(.body) }
            }
        }
    }

    @Test func glyphCircles() throws {
        try shoot("glyph-circle") {
            Card {
                VStack(alignment: .leading, spacing: Theme.Gap.m) {
                    HStack(spacing: Theme.Gap.m) {
                        ForEach(Symbols.categoryKeys.prefix(6), id: \.self) { GlyphCircle(Symbols.category($0)) }
                    }
                    HStack(spacing: Theme.Gap.m) {
                        GlyphCircle(Symbols.category("eating_out"))
                        VStack(alignment: .leading) {
                            Text(verbatim: "Кофе").font(.body)
                            Text(verbatim: "Наличные ₾").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(verbatim: "−8 ₾").font(.body).tabularDigits()
                    }
                }
            }
        }
    }

    @Test func symbols() throws {
        try shoot("symbols") {
            let names = Array(Set(Symbols.allNames)).sorted()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Gap.s), count: 4), spacing: Theme.Gap.m) {
                ForEach(names, id: \.self) { name in
                    VStack(spacing: Theme.Gap.xs) {
                        GlyphCircle(name)
                        Text(verbatim: name).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                    }
                }
            }
        }
    }

    @Test func undoToasts() throws {
        try shoot("undo-toast") {
            VStack(spacing: Theme.Gap.m) {
                UndoToastView(toast: UndoToast("Кофе −8 ₾") {}, onAction: {})
                UndoToastView(
                    toast: UndoToast("Шаурма −15 ₾ · Кофе −8 ₾\nЭто 23 ₾ из сегодняшних 52 ₾", length: .long) {},
                    onAction: {}
                )
                UndoToastView(toast: UndoToast("«Аренда» удалена", actionTitle: "Вернуть") {}, onAction: {})
            }
        }
    }

    @Test func undoToastAtAccessibilitySize() throws {
        try shoot("undo-toast-xxxl", dynamicType: .accessibility3) {
            UndoToastView(toast: UndoToast("Кофе −8 ₾\nИз отложенного") {}, onAction: {})
        }
    }

    @Test func micInEveryState() throws {
        try shoot("mic") {
            VStack(spacing: Theme.Gap.l) {
                ForEach([MicState.idle, .recording, .thinking], id: \.self) { state in
                    MicFloatingButton(state: state, level: 0.1) {}
                }
            }
        }
    }

    @Test func micWaveformFollowsTheLevel() throws {
        try shoot("mic-levels") {
            VStack(spacing: Theme.Gap.m) {
                ForEach([0.0, 0.02, 0.08, 0.3], id: \.self) { level in
                    HStack(spacing: Theme.Gap.l) {
                        LevelWaveform(level: level, ink: Theme.Color.gold, maxHeight: 40, barWidth: 5)
                        MicFloatingButton(state: .recording, level: level) {}
                    }
                }
            }
        }
    }
}
