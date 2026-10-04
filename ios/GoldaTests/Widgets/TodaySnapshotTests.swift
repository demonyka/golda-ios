import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// What the app leaves for the «Можно сегодня» widgets: Home's hero for today and, as Home would
/// show it if nothing more were recorded, for tomorrow, so the widget turns over at midnight on
/// its own. Books of `HomeHeroTests`: 20 000 ₽ on the card since September 1, payday on the 10th.
@MainActor @Suite struct TodaySnapshotTests {
    typealias F = HomeFixture

    /// [spentToday] kopecks spent this morning.
    private func books(spentToday: Int64 = 50_000) -> HomeFixture {
        var books = HomeFixture()
        books.operations = [
            F.operation(.expense, at: F.at(hour: 9), note: "Обед", category: "eating_out", [(books.rub, -spentToday, -spentToday)]),
            F.operation(.opening, at: F.at(LocalDate(2026, 9, 1), hour: 9), [(books.rub, 2_000_000, 2_000_000)]),
        ]
        return books
    }

    @Test func todayIsTheHeroAsHomeShowsIt() throws {
        let data = books().data
        let snapshot = TodaySnapshot(data: data, today: F.today, namesProfile: false)
        let hero = HomeHero(data: data, today: F.today)
        let today = try #require(snapshot.days.first)

        #expect(snapshot.profileName == "Личный")
        #expect(!snapshot.namesProfile)
        #expect(today.date == "2026-10-02")
        #expect(today.currency == "RUB")
        // (19 500 + 500) ₽ over 8 days is 2 500 ₽ a day; 500 ₽ of it is gone.
        #expect(today.leftMinor == 200_000)
        #expect(today.perDay == "2\u{202F}500 ₽")
        #expect(today.daysToPayday == 8)
        #expect(today.progress == 0.8)
        #expect(!today.isOverspent)
        #expect(today.others == "60,6 ₾ · 22,7 $")
        // The widget writes the figures with the app's own formatting.
        #expect(today.left == hero.left)
        #expect(today.perDay == hero.perDay)
    }

    /// Tomorrow nothing is spent yet: the whole of the day's new share is left.
    @Test func tomorrowIsWhatHomeWouldShowIfNothingMoreWereSpent() throws {
        let data = books().data
        let snapshot = TodaySnapshot(data: data, today: F.today, namesProfile: false)
        #expect(snapshot.days.map(\.date) == ["2026-10-02", "2026-10-03"])
        let tomorrow = snapshot.days[1]
        let hero = HomeHero(data: data, today: F.today.plusDays(1))

        // 19 500 ₽ over the 7 days left.
        #expect(tomorrow.perDay == "2\u{202F}786 ₽")
        #expect(tomorrow.leftMinor == 278_571)
        #expect(tomorrow.daysToPayday == 7)
        #expect(tomorrow.progress == 1)
        #expect(!tomorrow.isOverspent)
        #expect(tomorrow.left == hero.left)
        #expect(tomorrow.perDay == hero.perDay)
        #expect(tomorrow.others == hero.others)
    }

    @Test func overspendingIsCarriedForTheRedFigure() throws {
        let snapshot = TodaySnapshot(data: books(spentToday: 300_000).data, today: F.today, namesProfile: true)
        let today = try #require(snapshot.days.first)

        #expect(snapshot.namesProfile)
        #expect(today.leftMinor == -50_000)
        #expect(today.left == "−500 ₽")
        #expect(today.isOverspent)
        #expect(today.progress == 1)
        // A new day starts within the budget again: 17 000 ₽ over 7 days.
        #expect(!snapshot.days[1].isOverspent)
        #expect(snapshot.days[1].leftMinor == 242_857)
    }

    /// Another main currency: the figures are in its minor units, written as Home writes them.
    @Test func theMainCurrencyIsTheOneHomeShows() throws {
        var books = books()
        books.device.baseCurrency = "GEL"
        let data = books.data
        let today = try #require(TodaySnapshot(data: data, today: F.today, namesProfile: false).days.first)
        let hero = HomeHero(data: data, today: F.today)

        #expect(today.currency == "GEL")
        #expect(today.leftMinor == hero.leftMinor)
        #expect(today.left == hero.left)
        #expect(today.perDay == hero.perDay)
        #expect(today.others == hero.others)
    }

    /// A main currency with decimals: Home rounds the exact share once ("5,6 $" for 5.649). The
    /// widget must not round it to cents first and then again ("5,65" → "5,7 $"), so it carries
    /// Home's own text. Shares from 49 000 to 50 999 kopecks a day, at 88 ₽ a dollar, cross many
    /// of those boundaries.
    @Test func theDaysShareIsWrittenExactlyAsHomeWritesIt() throws {
        var mismatches: [String] = []
        for kopecks in Int64(49_000)..<51_000 {
            var books = HomeFixture()
            books.device.baseCurrency = "USD"
            // 8 days to payday, nothing spent: the share is the opening over 8.
            books.operations = [F.operation(.opening, at: F.at(LocalDate(2026, 9, 1), hour: 9), [(books.rub, kopecks * 8, kopecks * 8)])]
            let data = books.data
            let today = try #require(TodaySnapshot(data: data, today: F.today, namesProfile: false).days.first)
            let hero = HomeHero(data: data, today: F.today)
            if today.perDay != hero.perDay { mismatches.append("\(kopecks): \(today.perDay) ≠ \(hero.perDay)") }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(5))")
    }

    // MARK: The App Group

    @Test func theSnapshotGoesThroughTheStoreUnchanged() throws {
        let suite = "golda.tests.widgets.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TodaySnapshotStore(defaults: defaults)
        let snapshot = TodaySnapshot(data: books().data, today: F.today, namesProfile: true)

        #expect(store.read() == nil)
        #expect(store.write(snapshot))
        #expect(store.read() == snapshot)
        // The same again changes nothing, so the widgets are not asked to reload for it.
        #expect(!store.write(snapshot))
        #expect(store.write(nil))
        #expect(store.read() == nil)
        #expect(!store.write(nil))
    }

    /// A widget left on an older or newer build never shows a shape it does not know.
    @Test func aShapeTheWidgetDoesNotKnowReadsAsNone() throws {
        let suite = "golda.tests.widgets.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TodaySnapshotStore(defaults: defaults)

        defaults.set(Data("not json".utf8), forKey: TodaySnapshotStore.key)
        #expect(store.read() == nil)

        var future = TodaySnapshot(data: books().data, today: F.today, namesProfile: false)
        future.version = TodaySnapshot.currentVersion + 1
        defaults.set(try JSONEncoder().encode(future), forKey: TodaySnapshotStore.key)
        #expect(store.read() == nil)
    }
}

/// Which figures the widget shows when: the day it is, the next day from its midnight, and none
/// once the days the app wrote are over, since a past day's figure would mislead.
@Suite struct TodayTimelineTests {
    private static let zone = TimeZone(identifier: "Europe/Moscow")!

    private func at(_ date: LocalDate, hour: Int) -> Date {
        Date(timeIntervalSince1970: Double(date.atTimeMillis(hour: hour, in: Self.zone)) / 1000)
    }

    private func day(_ date: String, left: Int64) -> TodaySnapshot.Day {
        TodaySnapshot.Day(
            date: date, currency: "RUB", leftMinor: left, perDay: "2\u{202F}500 ₽", others: "", daysToPayday: 8,
            progress: 0.5, isOverspent: false
        )
    }

    private var snapshot: TodaySnapshot {
        TodaySnapshot(profileName: "Семья", namesProfile: false, days: [day("2026-10-02", left: 1), day("2026-10-03", left: 2)])
    }

    @Test func withoutASnapshotTheWidgetAsksToOpenTheApp() {
        let now = at(LocalDate(2026, 10, 2), hour: 15)
        #expect(TodayTimeline.entries(for: nil, now: now, zone: Self.zone) == [.init(date: now, state: .notSetUp)])
        let empty = TodaySnapshot(profileName: "Семья", namesProfile: false, days: [])
        #expect(TodayTimeline.entries(for: empty, now: now, zone: Self.zone) == [.init(date: now, state: .notSetUp)])
    }

    @Test func todayThenTomorrowAtMidnightThenNoFigure() {
        let now = at(LocalDate(2026, 10, 2), hour: 15)
        #expect(TodayTimeline.entries(for: snapshot, now: now, zone: Self.zone) == [
            .init(date: now, state: .day(snapshot.days[0], profile: nil)),
            .init(date: at(LocalDate(2026, 10, 3), hour: 0), state: .day(snapshot.days[1], profile: nil)),
            .init(date: at(LocalDate(2026, 10, 4), hour: 0), state: .outdated(profile: nil)),
        ])
    }

    /// Written yesterday: today is the second day.
    @Test func aSnapshotFromYesterdayShowsItsSecondDay() {
        let now = at(LocalDate(2026, 10, 3), hour: 9)
        #expect(TodayTimeline.entries(for: snapshot, now: now, zone: Self.zone) == [
            .init(date: now, state: .day(snapshot.days[1], profile: nil)),
            .init(date: at(LocalDate(2026, 10, 4), hour: 0), state: .outdated(profile: nil)),
        ])
    }

    @Test func pastItsDaysTheSnapshotShowsNoFigure() {
        let now = at(LocalDate(2026, 10, 5), hour: 9)
        #expect(TodayTimeline.entries(for: snapshot, now: now, zone: Self.zone) == [.init(date: now, state: .outdated(profile: nil))])
    }

    /// The clock went back (a flight west after midnight): no figure until the snapshot's first day.
    @Test func beforeItsFirstDayTheSnapshotWaitsForIt() {
        let now = at(LocalDate(2026, 10, 1), hour: 23)
        #expect(TodayTimeline.entries(for: snapshot, now: now, zone: Self.zone).map(\.date) == [
            now, at(LocalDate(2026, 10, 2), hour: 0), at(LocalDate(2026, 10, 3), hour: 0), at(LocalDate(2026, 10, 4), hour: 0),
        ])
        #expect(TodayTimeline.entries(for: snapshot, now: now, zone: Self.zone).first?.state == .outdated(profile: nil))
    }

    /// With several profiles the widget says whose figure it is.
    @Test func theProfileIsNamedWhenThePhoneHasSeveral() {
        let named = TodaySnapshot(profileName: "Семья", namesProfile: true, days: snapshot.days)
        let now = at(LocalDate(2026, 10, 2), hour: 15)
        let states = TodayTimeline.entries(for: named, now: now, zone: Self.zone).map(\.state)
        #expect(states == [.day(named.days[0], profile: "Семья"), .day(named.days[1], profile: "Семья"), .outdated(profile: "Семья")])
    }
}

/// The app keeps the snapshot current: after the launch reads the books, after every change to
/// them, and from the background refresh, which may run without the model ever reading them.
@MainActor @Suite struct TodayWidgetPublisherTests {
    /// Counts the reloads the widgets are asked for.
    @MainActor final class Reloads {
        var count = 0
    }

    private func harness(_ reloads: Reloads) throws -> AppHarness {
        try AppHarness(reloadWidgets: { reloads.count += 1 })
    }

    @discardableResult
    private func onboardedProfile(_ harness: AppHarness, name: String = "Личный") async throws -> UUID {
        let id = try await harness.profile(name)
        try await harness.repository.saveAccount(.card("Карта"), profileId: id, openingMinor: 1_000_000)
        harness.onboard(active: id)
        return id
    }

    @Test func theLaunchWritesTheHeroOfTheProfileOnScreen() async throws {
        let reloads = Reloads()
        let harness = try harness(reloads)
        try await onboardedProfile(harness)

        await harness.model.start()
        let data = try await harness.data()
        await eventually { harness.environment.widgets.store.read() != nil }

        let snapshot = try #require(harness.environment.widgets.store.read())
        #expect(snapshot == TodaySnapshot(data: data, today: harness.environment.today(), namesProfile: false))
        #expect(reloads.count >= 1)
    }

    @Test func writingTheSameAgainDoesNotReloadTheWidgets() async throws {
        let reloads = Reloads()
        let harness = try harness(reloads)
        try await onboardedProfile(harness)
        await harness.model.start()
        _ = try await harness.data()
        await eventually { reloads.count >= 1 }
        let count = reloads.count

        harness.model.publishWidgets()
        #expect(reloads.count == count)
    }

    @Test func aRecordChangesTheFigure() async throws {
        let harness = try harness(Reloads())
        try await onboardedProfile(harness)
        await harness.model.start()
        let data = try await harness.data()
        await eventually { harness.environment.widgets.store.read() != nil }
        let before = try #require(harness.environment.widgets.store.read()?.days.first?.leftMinor)

        let card = try #require(data.accounts.first)
        try await harness.model.save(Draft(type: .expense, timestamp: AppHarness.now, accountId: card.id, amountMinor: 50_000, categoryKey: "eating_out"))
        await eventually { harness.environment.widgets.store.read()?.days.first?.leftMinor == before - 50_000 }
        #expect(harness.environment.widgets.store.read()?.profileName == "Личный")
    }

    /// Before onboarding finishes there is nothing of anyone's to show.
    @Test func beforeOnboardingTheWidgetsShowNoBooks() async throws {
        let harness = try harness(Reloads())
        let id = try await harness.profile("Личный")
        harness.environment.widgets.store.write(TodaySnapshot(profileName: "Старый", namesProfile: false, days: []))
        harness.device.update { $0.activeProfileId = id }

        await harness.model.start()
        await eventually { harness.model.phase.isOnboarding }
        await eventually { harness.environment.widgets.store.read() == nil }
    }

    @Test func aSecondProfileGetsTheWidgetToNameTheOneOnScreen() async throws {
        let harness = try harness(Reloads())
        try await onboardedProfile(harness)
        await harness.model.start()
        _ = try await harness.data()

        try await harness.model.createProfile(name: "Семья")
        await eventually { harness.environment.widgets.store.read()?.profileName == "Семья" }
        #expect(harness.environment.widgets.store.read()?.namesProfile == true)
    }

    /// The background refresh reads the books itself: a background launch may never show a window.
    @Test func theBackgroundRefreshWritesWithoutTheModelsBooks() async throws {
        let reloads = Reloads()
        let harness = try harness(reloads)
        try await onboardedProfile(harness, name: "Семья")

        await harness.model.widgets.publishFromBooks()

        let snapshot = try #require(harness.environment.widgets.store.read())
        #expect(snapshot.profileName == "Семья")
        #expect(snapshot.days.map(\.date) == ["2026-10-02", "2026-10-03"])
        // 10 000 ₽ over the 13 days to the default payday, the 15th.
        #expect(snapshot.days.first?.leftMinor == Int64(1_000_000 / 13))
        #expect(reloads.count == 1)
    }
}
