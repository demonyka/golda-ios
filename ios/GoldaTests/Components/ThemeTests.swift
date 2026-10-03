import SwiftUI
import Testing
import UIKit

@testable import Golda

/// The colour sets must carry exactly the hexes of the table in DESIGN.md, in both appearances.
@Suite struct ThemeTests {
    /// token: (light, dark), copied from DESIGN.md "Цвет".
    static let table: [String: (light: UInt32, dark: UInt32)] = [
        "page": (0xF4F4F5, 0x1F1F23),
        "card": (0xFFFFFF, 0x2A2A2F),
        "soft": (0xE4E4E7, 0x3F3F46),
        "line": (0xD4D4D8, 0x52525B),
        "muted": (0x71717A, 0xA1A1AA),
        "text": (0x27272A, 0xF4F4F5),
        "graphite": (0x52525B, 0xD4D4D8),
        "onGraphite": (0xFFFFFF, 0x18181B),
        "danger": (0xDC2626, 0xF87171),
        "dangerSoft": (0xFEE2E2, 0x4C1D1D),
        "onDangerSoft": (0x991B1B, 0xFECACA),
    ]

    private func hex(of name: String, style: UIUserInterfaceStyle) -> UInt32? {
        guard let color = UIColor(named: name, in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: style)) else { return nil }
        return hex(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
    }

    private func hex(_ resolved: UIColor) -> UInt32? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha), alpha == 1 else { return nil }
        func byte(_ value: CGFloat) -> UInt32 { UInt32((value * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    @Test func everyTokenHasItsHexInLightAndDark() {
        for (name, expected) in Self.table {
            #expect(hex(of: name, style: .light) == expected.light, "\(name) light")
            #expect(hex(of: name, style: .dark) == expected.dark, "\(name) dark")
        }
    }

    @Test func theTokensInCodeAreTheTokensInTheTable() {
        #expect(Set(Theme.Color.allNames) == Set(Self.table.keys))
    }

    /// The accent is the system blue (D34): confirmations, alert buttons and the cursor look as in
    /// every iOS app. The set exists only because the build names it, and it points at the system
    /// colour rather than copying a hex: iOS 26 moved the blue (#0088FF, was #007AFF), and the
    /// reference also follows Increase Contrast.
    @Test @MainActor func theAccentColourIsTheSystemBlue() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for contrast in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection { traits in
                    traits.userInterfaceStyle = style
                    traits.accessibilityContrast = contrast
                }
                let accent = UIColor(named: "AccentColor", in: .main, compatibleWith: traits)?.resolvedColor(with: traits)
                #expect(accent != nil)
                #expect(accent.flatMap(hex) == hex(UIColor.systemBlue.resolvedColor(with: traits)), "\(style.rawValue), contrast \(contrast.rawValue)")
            }
        }
    }

    /// Gold left the interface with D34; it lives on only in the app icon.
    @Test func thereIsNoGoldToken() {
        for name in ["gold", "onGold"] {
            #expect(UIColor(named: name, in: .main, compatibleWith: nil) == nil, "\(name) is still in the catalog")
            #expect(!Theme.Color.allNames.contains(name))
        }
    }

    @Test func spacingIsTheDocumentedScale() {
        #expect([Theme.Gap.xs, Theme.Gap.s, Theme.Gap.m, Theme.Gap.l, Theme.Gap.xl] == [4, 8, 16, 24, 40])
        #expect(Theme.Radius.card == 28)
    }

    /// Every ink on the fill made for it clears 4.5:1 (WCAG AA for text) in both themes.
    @Test func inkOnItsFillIsReadable() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            func ratio(_ foreground: String, _ background: String) -> Double {
                let a = luminance(hex(of: foreground, style: style) ?? 0)
                let b = luminance(hex(of: background, style: style) ?? 0)
                return (max(a, b) + 0.05) / (min(a, b) + 0.05)
            }
            #expect(ratio("onDangerSoft", "dangerSoft") >= 4.5, "onDangerSoft on dangerSoft \(style.rawValue)")
            #expect(ratio("onGraphite", "graphite") >= 4.5, "onGraphite on graphite \(style.rawValue)")
            #expect(ratio("text", "card") >= 4.5, "text on card \(style.rawValue)")
            #expect(ratio("muted", "card") >= 4.5, "muted on card \(style.rawValue)")
        }
    }

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}
