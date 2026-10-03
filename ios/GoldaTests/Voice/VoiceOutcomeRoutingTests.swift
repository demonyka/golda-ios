import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// What each outcome of the voice service becomes: a toast with its button, or a screen (Android's
/// collector of `repo.voice` in `rememberVoice`).
@MainActor @Suite struct VoiceOutcomeRoutingTests {
    private let ru = Locale(identifier: "ru")

    /// A shawarma booked in the harness's open profile, as the service would have, and its outcome.
    private func bookedShawarma(_ h: MicHarness, late: Bool = false) async throws -> (UUID, VoiceOutcome.Done) {
        let lari = try await Account.named("Карта ₾", in: h.profileId, h.app)
        let draft = Draft(type: .expense, timestamp: AppHarness.now, accountId: lari.id, amountMinor: 1_500, categoryKey: "eating_out", note: "Шаурма")
        let id = try await h.app.repository.save(draft, profileId: h.profileId)
        let impact = try await h.app.repository.impact(operationId: id, profileId: h.profileId)
        let done = VoiceOutcome.Done(
            profileId: h.profileId, transcript: "Шаурма 15 лари", recorded: [VoiceOutcome.Recorded(operationId: id, draft: draft)],
            considering: [], misunderstood: false, late: late, impact: impact
        )
        return (id, done)
    }

    private func done(_ h: MicHarness, transcript: String = "", considering: [Consider] = [], misunderstood: Bool = false, profileId: UUID? = nil) -> VoiceOutcome {
        .done(VoiceOutcome.Done(
            profileId: profileId ?? h.profileId, transcript: transcript, recorded: [], considering: considering,
            misunderstood: misunderstood, late: false, impact: nil
        ))
    }

    @Test func aBookedNoteSaysWhatItBookedAndUndoTakesItBack() async throws {
        let h = try MicHarness()
        try await h.open()
        let (id, done) = try await bookedShawarma(h)

        await h.mic.react(to: .done(done))
        let toast = try #require(h.mic.toast)
        let books = await h.app.model.voiceBooks(profileId: h.profileId)
        #expect(toast.message == VoiceNotice.recorded(done, books: books, locale: ru).message)
        #expect(toast.message.hasPrefix("Шаурма 15 ₾\n"))
        #expect(toast.actionTitle == "Отменить")
        #expect(toast.length == .long)
        #expect(h.calls.confirmations == 1)
        #expect(h.mic.route == nil)

        toast.action()
        let profileId = h.profileId
        await eventuallyAsync { try await h.app.environment.database.read { try $0.operation(id, profileId: profileId) } == nil }
    }

    /// Undo acts in the note's profile even when another one is open by now.
    @Test func undoReachesTheNotesProfileWhicheverIsOpen() async throws {
        let h = try MicHarness()
        try await h.open()
        let (id, done) = try await bookedShawarma(h)
        let other = try await h.app.model.createProfile(name: "Семья")
        #expect(h.app.model.activeProfileId == other.id)

        await h.mic.react(to: .done(done))
        // With two profiles the toast names the note's one.
        #expect(h.mic.toast?.message.hasSuffix("\nПрофиль: Личный") == true)
        h.mic.toast?.action()
        let profileId = h.profileId
        await eventuallyAsync { try await h.app.environment.database.read { try $0.operation(id, profileId: profileId) } == nil }
    }

    @Test func aPurchaseToWeighUpOpensTheFormInSomnevayus() async throws {
        let h = try MicHarness()
        try await h.open()
        let headphones = Consider(title: "Наушники", amountMinor: 12_000, currency: "USD")

        await h.mic.react(to: done(h, transcript: "Хочу купить наушники", considering: [headphones]))
        #expect(h.mic.route == .entry(EntryRequest(consider: headphones)))
        #expect(h.mic.toast == nil)
    }

    @Test func aPurchaseFromAnotherProfileOpensThatProfileFirst() async throws {
        let h = try MicHarness()
        try await h.open()
        let other = try await h.app.model.createProfile(name: "Семья")
        let bike = Consider(title: "Велосипед", amountMinor: 50_000, currency: "GEL")

        await h.mic.react(to: done(h, considering: [bike], profileId: h.profileId))
        #expect(h.app.model.activeProfileId == h.profileId)
        #expect(h.app.model.activeProfileId != other.id)
        #expect(h.mic.route == .entry(EntryRequest(consider: bike)))
    }

    @Test func wordsThatAreNotUnderstoodAreQuotedWithAWayToAddByHand() async throws {
        let h = try MicHarness()
        try await h.open()

        await h.mic.react(to: done(h, transcript: "ну это самое", misunderstood: true))
        let toast = try #require(h.mic.toast)
        #expect(toast.message == "Не разобрать: «ну это самое». Можно записать через «+»")
        #expect(toast.actionTitle == "Записать")
        toast.action()
        #expect(h.mic.route == .entry(EntryRequest()))
    }

    @Test func aStrayTapWithABlankTranscriptSaysNothing() async throws {
        let h = try MicHarness()
        try await h.open()

        await h.mic.react(to: done(h, transcript: "  ", misunderstood: true))
        #expect(h.mic.toast == nil)
        #expect(h.mic.route == nil)
    }

    @Test func noKeyAsksForOneInTheSettings() async throws {
        let h = try MicHarness()
        try await h.open()

        await h.mic.react(to: .waiting(.noKey))
        let toast = try #require(h.mic.toast)
        #expect(toast.message == "Добавь ключ Gemini в настройках — запись сохранена")
        #expect(toast.actionTitle == "Настройки")
        toast.action()
        #expect(h.mic.route == .settings)
    }

    @Test func noConnectionAndFailuresAreToldAndOnlyDismissed() async throws {
        let h = try MicHarness()
        try await h.open()

        await h.mic.react(to: .waiting(.offline))
        #expect(h.mic.toast?.message == "Нет связи — запись разберётся позже")
        #expect(h.mic.toast?.actionTitle == "ОК")

        await h.mic.react(to: .failed(.rejected(message: "API key not valid")))
        #expect(h.mic.toast?.message == "Gemini: API key not valid")
        h.mic.toast?.action()
        #expect(h.mic.route == nil)
    }

    @Test func aNoteWaitingForConsentOpensTheConsentScreenUntilNotNow() async throws {
        let h = try MicHarness()
        try await h.open(consent: false)

        await h.mic.react(to: .needsConsent)
        #expect(h.mic.route == .voiceConsent)
        #expect(h.mic.toast == nil)

        h.mic.route = nil
        h.mic.answerConsent(false)
        // Not again this run: the person has just said no.
        await h.mic.react(to: .needsConsent)
        #expect(h.mic.route == nil)
    }

    /// The outcomes arrive through the service's stream, those of the queue included.
    @Test func outcomesOfTheQueueReachTheToastThroughTheStream() async throws {
        let h = try MicHarness()
        try await h.open()
        await h.mic.start()
        #expect(h.notes.hasFollowers)

        h.notes.send(.waiting(.noKey))
        await eventually { h.mic.toast != nil }
        #expect(h.mic.toast?.message == "Добавь ключ Gemini в настройках — запись сохранена")
    }
}

/// Waits until the async [condition] holds; records an issue after [timeout].
@MainActor
func eventuallyAsync(
    timeout: Duration = .seconds(5), sourceLocation: SourceLocation = #_sourceLocation, _ condition: () async throws -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while (try? await condition()) != true {
        guard clock.now < deadline else {
            Issue.record("The condition did not hold within \(timeout)", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}
