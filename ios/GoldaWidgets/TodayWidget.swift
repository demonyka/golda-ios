import GoldaCore
import SwiftUI
import WidgetKit

/// «Можно сегодня» outside the app: Home's big number with the mic at hand, and "+" in the medium
/// size, on the Home Screen; the figure alone on the Lock Screen. The app writes the figures into
/// the App Group (`TodaySnapshot`); a tap beside the buttons opens Home.
///
/// A kind of its own, apart from the voice widget: the gallery describes each kind in one line,
/// and a Lock Screen circle in this kind would be expected to show the budget, not a way to record.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodaySnapshot.widgetKind, provider: TodayWidgetTimeline()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Safe to spend today", tableName: "Widgets", comment: "Home hero caption over the big number: what can be spent today."))
        .description(Text("What you can spend today, with the mic at hand", tableName: "Widgets", comment: "The «Можно сегодня» widget in the widget gallery."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let state: TodayWidgetState
}

/// The entries `TodayTimeline` picks from what the app wrote: no figure after the days it covers,
/// until the app or its background refresh writes again and reloads the widget.
struct TodayWidgetTimeline: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(date: .now, state: .day(.sample, profile: nil))
    }

    /// The gallery shows a sample before the app has written anything, so the look can be judged.
    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayWidgetEntry) -> Void) {
        let entry = entries(now: .now)[0]
        completion(context.isPreview && entry.state == .notSetUp ? placeholder(in: context) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodayWidgetEntry>) -> Void) {
        completion(Timeline(entries: entries(now: .now), policy: .never))
    }

    private func entries(now: Date) -> [TodayWidgetEntry] {
        TodayTimeline.entries(for: TodaySnapshotStore.appGroupStore?.read(), now: now, zone: .current)
            .map { TodayWidgetEntry(date: $0.date, state: $0.state) }
    }
}

extension TodaySnapshot.Day {
    /// The gallery's and the placeholder's figures.
    static var sample: TodaySnapshot.Day {
        TodaySnapshot.Day(
            date: LocalDate(epochMillis: Int64(Date.now.timeIntervalSince1970 * 1000), in: .current).description,
            currency: "RUB", leftMinor: 184_900, perDay: "2\u{202F}648 ₽", others: "", daysToPayday: 8,
            progress: 0.7, isOverspent: false
        )
    }
}

#Preview("Small", as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayWidgetEntry(date: .now, state: .day(.sample, profile: nil))
    TodayWidgetEntry(date: .now, state: .outdated(profile: nil))
    TodayWidgetEntry(date: .now, state: .notSetUp)
}

#Preview("Medium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayWidgetEntry(date: .now, state: .day(.sample, profile: "Семья"))
    TodayWidgetEntry(date: .now, state: .outdated(profile: nil))
    TodayWidgetEntry(date: .now, state: .notSetUp)
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    TodayWidgetEntry(date: .now, state: .day(.sample, profile: nil))
}
