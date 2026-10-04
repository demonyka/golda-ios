import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The plan of every profile handed to the system's notifications (a stub here): what is scheduled,
/// what a second plan leaves alone, what goes when it is no longer due, and when the person is asked.
@MainActor @Suite(.timeLimit(.minutes(1))) struct ReminderSchedulerTests {
    let harness: AppHarness
    let center: InMemoryNotificationCenter

    init() throws {
        harness = try AppHarness()
        center = try #require(harness.environment.notifications as? InMemoryNotificationCenter)
        harness.model.reminders.locale = { Locale(identifier: "ru_RU") }
    }

    var model: AppModel { harness.model }
    var scheduler: ReminderScheduler { harness.model.reminders }

    /// "Личный" owes on a loan due on the 25th and waits on headphones; "Семья" waits on a bike.
    /// The clock stands on Friday 2 October 2026 at 10:00 UTC.
    private func twoProfiles() async throws -> (personal: UUID, family: UUID, loan: UUID) {
        let loan = Account(name: "Кредит", currency: "RUB", type: .loan, includeInFree: false, paymentDay: 25, paymentMinor: 1_000_000)
        let personal = try await harness.profile("Личный")
        try await harness.repository.saveAccount(loan, profileId: personal, openingMinor: -5_000_000)
        let family = try await harness.profile("Семья")
        _ = try await harness.repository.think(Consider(title: "Наушники", amountMinor: 12_000, currency: "USD"), profileId: personal)
        _ = try await harness.repository.think(Consider(title: "Велосипед", amountMinor: 8_000_000, currency: "RUB"), profileId: family)
        harness.onboard(active: personal)
        return (personal, family, loan.id)
    }

    private func wish(_ title: String) async throws -> Wish {
        try #require(try await harness.environment.database.read { store in
            try store.profiles().compactMap { try store.snapshot(profileId: $0.id) }.flatMap(\.wishes)
        }.first { $0.title == title })
    }

    @Test func everyProfilesRemindersAreScheduled() async throws {
        let (personal, family, loan) = try await twoProfiles()
        center.allow()
        await scheduler.replan()

        let pending = center.requests
        let headphones = try await wish("Наушники"), bike = try await wish("Велосипед")
        #expect(Set(pending.keys) == ["wish.\(headphones.id)", "wish.\(bike.id)", "payment.\(loan)", "reconcile"])
        let payment = try #require(pending["payment.\(loan)"])
        #expect(payment.title == "Кредит")
        #expect(payment.body == "Через 3 дня платёж: 10\u{202F}000 ₽")
        #expect(payment.subtitle == "Личный", "two profiles: each says whose")
        #expect(payment.trigger == .day(LocalDate(2026, 10, 22), hour: 10, minute: 0))
        #expect(payment.tap == ReminderTap(profileId: personal, destination: .accounts))
        #expect(pending["wish.\(bike.id)"]?.tap == ReminderTap(profileId: family, destination: .wish(bike.id)))
        #expect(pending["wish.\(bike.id)"]?.subtitle == "Семья")
        #expect(pending["reconcile"]?.tap == ReminderTap(profileId: nil, destination: .reconcile))
    }

    @Test func nothingIsScheduledWithoutPermission() async throws {
        _ = try await twoProfiles()
        await scheduler.replan()
        #expect(center.requests.isEmpty)
        center.deny()
        await scheduler.replan()
        #expect(center.requests.isEmpty)
    }

    @Test func aSecondPlanLeavesWhatIsAlreadyScheduledAlone() async throws {
        _ = try await twoProfiles()
        center.allow()
        await scheduler.replan()
        let added = center.addedCount
        await scheduler.replan()
        #expect(center.addedCount == added)
        #expect(center.requests.count == 4)
    }

    @Test func aDecidedWishAndASwitchedOffReconcileAreTakenBack() async throws {
        let (personal, _, _) = try await twoProfiles()
        center.allow()
        await scheduler.replan()
        let headphones = try await wish("Наушники")
        try await harness.repository.skip(Consider(title: "Наушники", amountMinor: 12_000, currency: "USD"), wishId: headphones.id, profileId: personal)
        harness.device.update { $0.reconcileReminder = false }
        await scheduler.replan()
        #expect(center.requests["wish.\(headphones.id)"] == nil)
        #expect(center.requests["reconcile"] == nil)
        #expect(center.requests.count == 2)
    }

    @Test func oneProfileNeedsNoName() async throws {
        let personal = try await harness.profile("Личный")
        _ = try await harness.repository.think(Consider(title: "Наушники", amountMinor: 12_000, currency: "USD"), profileId: personal)
        center.allow()
        await scheduler.replan()
        #expect(center.requests.values.allSatisfy { $0.subtitle.isEmpty })
    }

    /// Followed, the books are planned again after a change, without anyone asking.
    @Test func aChangeToAnyProfileIsPlannedAgain() async throws {
        let (_, family, _) = try await twoProfiles()
        center.allow()
        scheduler.debounce = .milliseconds(10)
        scheduler.start()
        await eventually { center.requests.count == 4 }

        let wish = try await harness.repository.think(Consider(title: "Самокат", amountMinor: 3_000_000, currency: "RUB"), profileId: family)
        await eventually { center.requests["wish.\(wish.id)"] != nil }
        harness.device.update { $0.reconcileReminder = false }
        await eventually { center.requests["reconcile"] == nil }
        scheduler.stop()
    }

    // MARK: Asking

    @Test func permissionIsAskedOnceAndThePlanFollows() async throws {
        _ = try await twoProfiles()
        await scheduler.askPermission()
        #expect(center.askedCount == 1)
        #expect(center.requests.count == 4)
        await scheduler.askPermission()
        #expect(center.askedCount == 1, "asked already")
    }

    @Test func aRefusalIsNotAskedAgain() async throws {
        _ = try await twoProfiles()
        center.answersAllow = false
        await scheduler.askPermission()
        await scheduler.askPermission()
        #expect(center.askedCount == 1)
        #expect(center.requests.isEmpty)
    }

    /// D36: "Подумаю" asks at the first need, and so does turning the Sunday reminder on.
    @Test func thinkingAboutAPurchaseAsks() async throws {
        let personal = try await harness.profile("Личный")
        harness.onboard(active: personal)
        await model.start()
        _ = try await harness.data()
        _ = try await model.thinkAbout(Consider(title: "Наушники", amountMinor: 12_000, currency: "USD"))
        await eventually { center.askedCount == 1 }
    }

    @Test func turningTheReconcileReminderOnAsks() async throws {
        let personal = try await harness.profile("Личный")
        harness.onboard(active: personal)
        await model.start()
        model.setReconcileReminder(false)
        try await Task.sleep(for: .milliseconds(50))
        #expect(center.askedCount == 0, "turning it off asks nothing")
        model.setReconcileReminder(true)
        await eventually { center.askedCount == 1 }
    }

    /// The Sunday reminder is on from the start (D49): finishing onboarding is its first need.
    @Test func finishingOnboardingAsksWhileTheSundayReminderIsOn() async throws {
        try await model.beginOnboarding()
        model.finishOnboarding()
        await eventually { center.askedCount == 1 }
    }

    @Test func finishingOnboardingWithTheSundayReminderOffAsksNothing() async throws {
        try await model.beginOnboarding()
        harness.device.update { $0.reconcileReminder = false }
        model.finishOnboarding()
        try await Task.sleep(for: .milliseconds(50))
        #expect(center.askedCount == 0)
    }

    @Test func aDebtWithADateAsks() async throws {
        let personal = try await harness.profile("Личный")
        harness.onboard(active: personal)
        await model.start()
        _ = try await harness.data()
        try await model.saveAccount(.card("Карта"), openingMinor: 0)
        try await Task.sleep(for: .milliseconds(50))
        #expect(center.askedCount == 0, "nothing to remind of")
        let loan = Account(name: "Кредит", currency: "RUB", type: .loan, includeInFree: false, paymentDay: 25, paymentMinor: 1_000_000)
        try await model.saveAccount(loan, openingMinor: -5_000_000)
        await eventually { center.askedCount == 1 }
    }
}
