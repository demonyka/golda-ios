import SwiftUI

/// The design tokens of Golda in one place (DESIGN.md, "Цвет" and "Списки и карточки").
///
/// Colour has three jobs and nothing else (D34): the system blue confirms, graphite is what is
/// picked, red is bad news. The blue is the app's accent, not a token: it comes from the system
/// tint, so confirmations, alert buttons and the cursor look the way they do in every iOS app.
/// Other buttons are plain Liquid Glass. Everything else is a white card on a light grey page.
enum Theme {
    /// Colour tokens. Each name is a colour set in `Assets.xcassets/Theme` with a light and a dark
    /// value, so views never branch on the colour scheme.
    ///
    /// The enum is called `Color` on purpose (`Theme.Color.card`); inside it the system type is
    /// spelled `SwiftUI.Color`.
    enum Color {
        /// Screen and sheet background.
        static let page = token("page")
        /// Cards, list rows, hero tiles.
        static let card = token("card")
        /// Tonal buttons, what could be picked but is not.
        static let soft = token("soft")
        /// Tracks, dividers, the quietest chart marks.
        static let line = token("line")
        /// Secondary text and icons.
        static let muted = token("muted")
        /// Primary text.
        static let text = token("text")
        /// What is picked: a tab, a toggle, a category.
        static let graphite = token("graphite")
        /// Text on `graphite`.
        static let onGraphite = token("onGraphite")
        /// Bad news only: overspending, debts, erasing.
        static let danger = token("danger")
        /// Fill of the hero card when the budget is overspent.
        static let dangerSoft = token("dangerSoft")
        /// Ink on `dangerSoft`.
        static let onDangerSoft = token("onDangerSoft")

        /// Every colour-set name, so a test can check the catalog and this file agree.
        static let allNames = [
            "page", "card", "soft", "line", "muted", "text", "graphite", "onGraphite",
            "danger", "dangerSoft", "onDangerSoft",
        ]

        private static func token(_ name: String) -> SwiftUI.Color {
            // Looked up in the main bundle: the hosted tests run inside the app, so the same sets resolve there.
            SwiftUI.Color(name, bundle: .main)
        }
    }

    /// The spacing scale 4 · 8 · 16 · 24 · 40.
    enum Gap {
        /// A label and its value inside one block.
        static let xs: CGFloat = 4
        /// Items of a group.
        static let s: CGFloat = 8
        /// Screen edge, a small card's padding.
        static let m: CGFloat = 16
        /// Between groups, a hero card's padding.
        static let l: CGFloat = 24
        /// Before an action bar or the next section.
        static let xl: CGFloat = 40
    }

    /// Corner radii. List rows have none of their own: the system sets them in an inset-grouped list.
    enum Radius {
        /// Hero and plain cards, continuous corners.
        static let card: CGFloat = 28
        /// Text fields and other small tonal containers.
        static let field: CGFloat = 16
        /// The undo toast: a capsule for one line, this radius for several.
        static let toast: CGFloat = 28
    }

    /// Touch targets are never smaller than this (DESIGN.md, "Доступность").
    static let minimumTarget: CGFloat = 44
}
