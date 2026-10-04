import Foundation
import GoldaCore
import GoldaData
import OSLog
import WidgetKit

private let log = Logger(subsystem: "com.f4studio.golda", category: "Widgets")

extension TodaySnapshot {
    /// The hero of [data] for [today] and for the day after, the second as Home would show it then
    /// if nothing more were recorded. [namesProfile]: the phone has other profiles too.
    init(data: AppData, today: LocalDate, namesProfile: Bool) {
        self.init(
            profileName: data.profile.name,
            namesProfile: namesProfile,
            days: [today, today.plusDays(1)].map { Day(HomeHero(data: data, today: $0), on: $0) }
        )
    }
}

extension TodaySnapshot.Day {
    init(_ hero: HomeHero, on date: LocalDate) {
        self.init(
            date: date.description,
            currency: hero.currency,
            leftMinor: hero.leftMinor,
            perDay: hero.perDay,
            others: hero.others,
            daysToPayday: hero.daysLeft,
            progress: hero.progress,
            isOverspent: hero.isOverspent
        )
    }
}

/// Where the widgets read what they show, and how they are asked to read it again.
struct WidgetChannel: Sendable {
    let store: TodaySnapshotStore
    let reload: @MainActor @Sendable () -> Void

    /// The App Group the widgets read, and WidgetKit.
    static func appGroup() -> WidgetChannel {
        guard let store = TodaySnapshotStore.appGroupStore else {
            preconditionFailure("UserDefaults refused the App Group \(TodaySnapshotStore.appGroup)")
        }
        return WidgetChannel(store: store, reload: { WidgetCenter.shared.reloadTimelines(ofKind: TodaySnapshot.widgetKind) })
    }

    /// A suite of its own, wiped as it opens, that no widget reads.
    static func inMemory(suite: String = "golda.widgets.inMemory") -> WidgetChannel {
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("UserDefaults refused the suite \(suite)")
        }
        defaults.removePersistentDomain(forName: suite)
        return WidgetChannel(store: TodaySnapshotStore(defaults: defaults), reload: {})
    }
}

/// Keeps the snapshot the widgets read equal to the hero of the profile on screen (ARCHITECTURE,
/// "Вне приложения"): the model hands it each new `AppData`, and the background refresh, where the
/// model may never have read the books, has it read them itself. The widgets reload only when what
/// they show changed.
@MainActor
final class TodayWidgetPublisher {
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    private var channel: WidgetChannel { environment.widgets }

    /// Writes [snapshot], or clears it when nil (no books to show: onboarding).
    func publish(_ snapshot: TodaySnapshot?) {
        if channel.store.write(snapshot) { channel.reload() }
    }

    /// The hero of [data] for the day it is now.
    func publish(_ data: AppData, profileCount: Int) {
        publish(TodaySnapshot(data: data, today: environment.today(), namesProfile: profileCount > 1))
    }

    /// From a fresh read of the books: the profile this phone has open, or the first one, as the
    /// model resolves it. Nothing is shown before onboarding is over.
    func publishFromBooks() async {
        let device = environment.deviceSettings.current
        guard device.onboarded else {
            publish(nil)
            return
        }
        let read: (profiles: [Profile], snapshot: ProfileSnapshot?, rates: [RateRecord])
        do {
            read = try await environment.database.read { store in
                let profiles = try store.profiles()
                let active = profiles.first { $0.id == device.activeProfileId } ?? profiles.first
                return (profiles, try active.flatMap { try store.snapshot(profileId: $0.id) }, try store.rates())
            }
        } catch {
            log.error("Reading the books for the widgets failed: \(String(describing: error))")
            return
        }
        guard let snapshot = read.snapshot else {
            publish(nil)
            return
        }
        let data = AppData(snapshot: snapshot, device: device, rates: read.rates, zone: environment.zone())
        publish(data, profileCount: read.profiles.count)
    }
}
