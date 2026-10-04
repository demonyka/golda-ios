import Foundation
import GoldaCore

/// What the «Можно сегодня» widgets show: Home's hero of the profile on screen, written by the app
/// into the App Group, since the widgets cannot open the database. It holds today and tomorrow,
/// tomorrow being what Home would show then if nothing more were recorded (the budget needs only
/// the balances and the day), so the widget turns over at midnight by itself (`TodayTimeline`).
///
/// Compiled into the widgets too. The big number is in minor units of the main currency, written
/// with the app's `Fmt`; the day's share is Home's own text, so the widget and Home always agree.
struct TodaySnapshot: Codable, Equatable, Sendable {
    /// The «Можно сегодня» widget's kind, the one the app asks WidgetKit to reload.
    static let widgetKind = "com.f4studio.golda.today"
    /// Bumped when the shape changes: a widget reads only the shape it knows. 2: the day's share
    /// became Home's text instead of minor units.
    static let currentVersion = 2
    var version = TodaySnapshot.currentVersion
    /// The profile the figures are of.
    let profileName: String
    /// The phone has other profiles too, so the widget says whose figure it is.
    let namesProfile: Bool
    /// One per day, in order: today, then tomorrow.
    let days: [Day]

    init(profileName: String, namesProfile: Bool, days: [Day]) {
        self.profileName = profileName
        self.namesProfile = namesProfile
        self.days = days
    }

    struct Day: Codable, Equatable, Sendable {
        /// The day the figures are for, `2026-10-02`.
        let date: String
        /// The main currency the figures are in.
        let currency: String
        /// What is left that day, in minor units of [currency]; negative once overspent.
        let leftMinor: Int64
        /// "2 648 ₽", the day's share as Home writes it (`Base.approx`), taken from Home and not
        /// formatted again: rounded to minor units first, "5,649 $" would be "5,65" and then "5,7 $"
        /// where Home writes "5,6 $".
        let perDay: String
        /// "52,2 ₾ · 20 $", the other currencies as Home writes them; empty when there are none.
        let others: String
        let daysToPayday: Int
        /// 0...1, what is left of the day's share: the wavy bar.
        let progress: Double
        /// The day's spending went past its share: the figure turns red.
        let isOverspent: Bool

        var day: LocalDate? { LocalDate(iso: date) }

        /// "1 849 ₽", the big number as Home writes it (`Base.whole`).
        var left: String { Fmt.split(leftMinor, currency).whole + " " + Currencies.symbol(currency) }
    }
}

/// The snapshot's place in the App Group's defaults, shared by the app and its widgets.
struct TodaySnapshotStore: @unchecked Sendable {
    // UserDefaults is thread-safe; the SDK does not mark it Sendable.
    static let appGroup = "group.com.f4studio.golda"
    static let key = "today.snapshot"

    let defaults: UserDefaults

    /// The App Group's defaults. Nil only when the suite is refused, which happens for the app's
    /// own bundle id, never for a group.
    static var appGroupStore: TodaySnapshotStore? {
        UserDefaults(suiteName: appGroup).map(TodaySnapshotStore.init)
    }

    /// Nil when nothing was written, or in a shape this build does not know.
    func read() -> TodaySnapshot? {
        guard let data = defaults.data(forKey: Self.key),
              let snapshot = try? JSONDecoder().decode(TodaySnapshot.self, from: data),
              snapshot.version == TodaySnapshot.currentVersion
        else { return nil }
        return snapshot
    }

    /// Writes [snapshot], or removes it when nil; whether that changed anything, so the widgets
    /// are asked to reload only for a change.
    @discardableResult
    func write(_ snapshot: TodaySnapshot?) -> Bool {
        guard let snapshot else {
            guard defaults.object(forKey: Self.key) != nil else { return false }
            defaults.removeObject(forKey: Self.key)
            return true
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(snapshot), data != defaults.data(forKey: Self.key) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }
}

/// What a widget shows at a moment.
enum TodayWidgetState: Equatable, Sendable {
    /// Nothing written: the app was never opened, or onboarding is not over.
    case notSetUp
    /// The figures of the day it is; [profile] when the widget names it.
    case day(TodaySnapshot.Day, profile: String?)
    /// The days written are over: a past day's figure would mislead, so none shows until the app,
    /// or its background refresh, writes again.
    case outdated(profile: String?)
}

/// The widget's timeline from a snapshot: the day it is now, each later day from its midnight,
/// and no figure from the midnight after the last one.
enum TodayTimeline {
    struct Entry: Equatable, Sendable {
        let date: Date
        let state: TodayWidgetState
    }

    static func entries(for snapshot: TodaySnapshot?, now: Date, zone: TimeZone) -> [Entry] {
        guard let snapshot, !snapshot.days.isEmpty else { return [Entry(date: now, state: .notSetUp)] }
        let profile = snapshot.namesProfile ? snapshot.profileName : nil
        let today = LocalDate(epochMillis: Int64((now.timeIntervalSince1970 * 1000).rounded(.down)), in: zone)
        let days = snapshot.days.compactMap { day in day.day.map { (date: $0, figures: day) } }
        func midnight(_ date: LocalDate) -> Date {
            Date(timeIntervalSince1970: Double(date.startOfDayMillis(in: zone)) / 1000)
        }

        let current = days.first { $0.date == today }
        var entries = [Entry(date: now, state: current.map { .day($0.figures, profile: profile) } ?? .outdated(profile: profile))]
        for day in days where day.date > today {
            entries.append(Entry(date: midnight(day.date), state: .day(day.figures, profile: profile)))
        }
        if let last = days.last, last.date >= today {
            entries.append(Entry(date: midnight(last.date.plusDays(1)), state: .outdated(profile: profile)))
        }
        return entries
    }
}
