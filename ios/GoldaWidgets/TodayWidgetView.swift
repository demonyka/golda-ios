import GoldaCore
import SwiftUI
import WidgetKit

/// The «Можно сегодня» widget in each size. The system's background and ink: gold lives only in
/// the app icon (D34), and red only says the day's share is overspent, as on Home. The amounts are
/// private, so a locked phone hides them; the buttons take the tint of a tinted Home Screen.
struct TodayWidgetView: View {
    let entry: TodayWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(AppLink.home.url)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryRectangular:
            TodayRectangularView(state: entry.state)
                .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            TodayInlineView(state: entry.state)
                .containerBackground(.clear, for: .widget)
        case .systemMedium:
            TodayMediumView(state: entry.state)
                .containerBackground(.background, for: .widget)
        default:
            TodaySmallView(state: entry.state)
                .containerBackground(.background, for: .widget)
        }
    }
}

// MARK: - Home Screen

/// The figure and, under it, the mic.
private struct TodaySmallView: View {
    let state: TodayWidgetState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodayCaption(profile: state.profile)
            switch state {
            case .day(let day, _):
                TodayFigure(day: day, size: 30)
                WidgetWave(progress: day.progress, isOverspent: day.isOverspent, size: .row)
                    .padding(.top, 6)
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 4) {
                    Text(TodayText.payday(day.daysToPayday))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    MicButton()
                }
            case .outdated:
                TodayNotice(text: TodayText.outdated)
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    MicButton()
                }
            case .notSetUp:
                TodayNotice(text: TodayText.notSetUp)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Home's hero in brief beside "+" and the mic, the two ways to record.
private struct TodayMediumView: View {
    let state: TodayWidgetState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                TodayCaption(profile: state.profile)
                switch state {
                case .day(let day, _):
                    TodayFigure(day: day, size: 36)
                    if !day.others.isEmpty {
                        Text(verbatim: "≈\u{00A0}" + day.others)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .privacySensitive()
                    }
                    Spacer(minLength: 4)
                    WidgetWave(progress: day.progress, isOverspent: day.isOverspent, size: .hero)
                    Text(TodayText.budgetLine(day))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .privacySensitive()
                        .padding(.top, 2)
                case .outdated:
                    TodayNotice(text: TodayText.outdated)
                    Spacer(minLength: 0)
                case .notSetUp:
                    TodayNotice(text: TodayText.notSetUp)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if state != .notSetUp {
                VStack(spacing: 10) {
                    PlusButton()
                    MicButton()
                }
            }
        }
    }
}

/// "Можно сегодня", and whose when the phone has several profiles.
private struct TodayCaption: View {
    let profile: String?

    var body: some View {
        HStack(spacing: 4) {
            Text("Safe to spend today", tableName: "Widgets")
                .layoutPriority(1)
            if let profile {
                Text(verbatim: "· " + profile)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// The big number, as Home writes it; red once the day's share is overspent.
private struct TodayFigure: View {
    let day: TodaySnapshot.Day
    let size: CGFloat

    var body: some View {
        Text(verbatim: day.left)
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(day.isOverspent ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .privacySensitive()
    }
}

/// Where the figure would be when there is none to show.
private struct TodayNotice: View {
    let text: LocalizedStringResource

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

// MARK: - Buttons

/// The mic: a voice note, started as a tap on the app's mic starts one. The one place the widgets
/// start a note, so the way it starts changes here alone.
///
/// The voice widget's link, `golda://voice`. `Button(intent: StartVoiceNoteIntent())` did not
/// bring the app up from a widget on the iOS 26.2 simulator, though the same intent does from
/// Control Center; an intent that records in the background would go here.
struct MicButton: View {
    var body: some View {
        Link(destination: AppLink.voice.url) {
            // The app's mic glyph (`Symbols.mic`): beside "+" its meaning is plain.
            WidgetButtonFace(symbol: "mic.fill")
        }
        .accessibilityLabel(Text("Say a purchase", tableName: "EntryPoints"))
    }
}

/// "+": the form for a new operation, as the toolbar's "+" opens it.
private struct PlusButton: View {
    var body: some View {
        Link(destination: AppLink.newOperation.url) {
            // The toolbar's glyph (`Symbols.add`).
            WidgetButtonFace(symbol: "plus")
        }
        .accessibilityLabel(Text("Add by hand", tableName: "Widgets"))
    }
}

/// A plain circle of the system's fill under the glyph in the primary ink, like the system's own
/// widget buttons; the glyph takes a tinted Home Screen's tint.
private struct WidgetButtonFace: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(.primary)
            .widgetAccentable()
            .frame(width: 50, height: 50)
            .background(.fill.tertiary, in: .circle)
            .contentShape(.circle)
    }
}

// MARK: - Lock Screen

private struct TodayRectangularView: View {
    let state: TodayWidgetState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Safe to spend today", tableName: "Widgets")
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            switch state {
            case .day(let day, _):
                Text(verbatim: day.left)
                    .font(.system(.title2, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .privacySensitive()
                Text(TodayText.payday(day.daysToPayday))
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            case .outdated:
                Text(TodayText.outdated).font(.caption).lineLimit(2)
            case .notSetUp:
                Text(TodayText.notSetUp).font(.caption).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line over the clock: the figure with its caption, or the figure alone when that is too long.
private struct TodayInlineView: View {
    let state: TodayWidgetState

    var body: some View {
        switch state {
        case .day(let day, _):
            ViewThatFits {
                Text("Safe to spend today: \(day.left)", tableName: "Widgets")
                Text(verbatim: day.left)
            }
            .privacySensitive()
        case .outdated:
            Text(TodayText.outdated)
        case .notSetUp:
            Text(TodayText.notSetUp)
        }
    }
}

// MARK: - Text

/// The widget's lines in the `Widgets` table, the extension's own catalog.
enum TodayText {
    static let outdated = LocalizedStringResource("Open Golda to update", table: "Widgets", comment: "The widget instead of the figure once its days are over and the app has not been opened since.")
    static let notSetUp = LocalizedStringResource("Open Golda to start", table: "Widgets", comment: "The widget before the app is set up: no figure to show yet.")

    /// "8 days to payday", with the Russian forms of "day".
    static func payday(_ days: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(days) days to payday", table: "Widgets", comment: "Home hero: days until the next salary, “8 days to payday”.")
    }

    /// "2 648 ₽ a day · 8 days to payday", as under Home's bar.
    static func budgetLine(_ day: TodaySnapshot.Day) -> String {
        let perDay = String(localized: LocalizedStringResource("\(day.perDay) a day", table: "Widgets", comment: "Home hero: today's budget share, “2 648 ₽ a day”."))
        // A no-break space before the dot, so a wrapped line never starts with it.
        return perDay + "\u{00A0}· " + String(localized: payday(day.daysToPayday))
    }
}

extension TodayWidgetState {
    /// The profile the widget names, if it names one.
    var profile: String? {
        switch self {
        case .day(_, let profile), .outdated(let profile): profile
        case .notSetUp: nil
        }
    }
}
