import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The queue runs at launch, on each return to the foreground, after consent and when the key
/// changes (ARCHITECTURE, "Голос"), and its outcomes reach the mic like any other.
@MainActor @Suite struct VoiceQueueTriggerTests {
    @Test func launchRunsTheQueueOnceAndFollowsTheOutcomes() async throws {
        let h = try MicHarness()
        try await h.open()
        #expect(h.notes.queueRuns == 0)

        await h.mic.start()
        #expect(h.notes.queueRuns == 1)
        #expect(h.notes.hasFollowers)
        // A second call changes nothing.
        await h.mic.start()
        #expect(h.notes.queueRuns == 1)
    }

    @Test func eachReturnToTheForegroundRunsTheQueue() async throws {
        let h = try MicHarness()
        try await h.open()
        await h.mic.start()

        h.foreground.yield()
        await eventually { h.notes.queueRuns == 2 }
        h.foreground.yield()
        await eventually { h.notes.queueRuns == 3 }
    }

    @Test func agreeingRunsTheQueueForTheNotesThatWaitedForConsent() async throws {
        let h = try MicHarness()
        try await h.open(consent: false)
        await h.mic.start()

        h.mic.answerConsent(true)
        await eventually { h.notes.queueRuns == 2 }
    }
}

/// The real voice service under the app, with the debug stub's provider: what the settings screen
/// gets from `AppModel.processVoiceQueue()` after a key is saved, and the whole round from a tap.
@MainActor @Suite struct VoiceServiceInAppTests {
    /// An app whose voice answers with [script] at once; one profile with a lari card is open and
    /// consent is given.
    @MainActor private final class ServiceHarness {
        let suite = "golda.tests.voice.\(UUID().uuidString)"
        let environment: AppEnvironment
        let model: AppModel
        var profileId = UUID()

        init(script: VoiceStubScript, key: String? = "test-key") throws {
            environment = try AppEnvironment.inMemory(
                defaultsSuite: suite, ratesSource: StubRatesSource.offline, clock: { AppHarness.now }, zone: { AppHarness.utc },
                voiceProvider: CannedVoiceProvider(script: script, delay: .zero),
                voiceSecrets: InMemorySecretStore(key.map { [SecretKey.gemini: $0] } ?? [:])
            )
            model = AppModel(environment: environment)
        }

        deinit {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }

        func open() async throws {
            profileId = try await environment.repository.createProfile(name: "Личный").id
            try await environment.repository.saveAccount(Account.card("Карта ₾", currency: "GEL"), profileId: profileId)
            environment.deviceSettings.update {
                $0.onboarded = true
                $0.activeProfileId = profileId
                $0.voiceConsent = true
            }
            await model.start()
        }

        func operations() async throws -> [OperationFull] {
            let profileId = profileId
            return try await environment.database.read { try $0.operations(profileId: profileId) }
        }
    }

    @Test func theKeyHookBooksANoteThatWaited() async throws {
        let h = try ServiceHarness(script: .shawarma)
        try await h.open()
        let recordedAt = AppHarness.now - 60_000
        try StubWAV.leaveNote(in: h.environment.voiceQueue, profileId: h.profileId, now: AppHarness.now)
        #expect(h.environment.voiceQueue.pending().count == 1)

        await h.model.processVoiceQueue().value

        let booked = try await h.operations().filter { $0.op.type == .expense }
        #expect(booked.map(\.op.note) == ["Шаурма"])
        // Dated when it was said, not when it was understood.
        #expect(booked.first?.op.timestamp == recordedAt)
        #expect(h.environment.voiceQueue.pending().isEmpty)
    }

    @Test func withoutAKeyTheNoteStaysAndTheToastSaysWhy() async throws {
        let h = try ServiceHarness(script: .shawarma, key: nil)
        try await h.open()
        let mic = VoiceMicModel(model: h.model, recorder: StubVoiceRecorder(), notes: h.environment.voice, locale: Locale(identifier: "en"))
        try StubWAV.leaveNote(in: h.environment.voiceQueue, profileId: h.profileId, now: AppHarness.now)

        await mic.start()
        await eventually { mic.toast != nil }
        #expect(mic.toast?.message == "Add a Gemini key in settings; the note is kept")
        #expect(h.environment.voiceQueue.pending().count == 1)
    }

    /// Two taps: a WAV in the queue, "Шаурма 15 ₾" booked, the toast with "Отменить", and undo.
    @Test func twoTapsBookTheNoteAndUndoRemovesIt() async throws {
        let h = try ServiceHarness(script: .shawarma)
        try await h.open()
        let mic = VoiceMicModel(model: h.model, recorder: StubVoiceRecorder(), notes: h.environment.voice, locale: Locale(identifier: "ru"))
        await mic.start()

        mic.tap()
        #expect(mic.state == .recording)
        mic.tap()
        #expect(mic.state == .thinking)
        await eventually { mic.toast != nil && mic.state == .idle }

        let toast = try #require(mic.toast)
        #expect(toast.message.hasPrefix("Шаурма 15 ₾\n"), "\(toast.message)")
        #expect(toast.message.contains("на сегодня осталось") || toast.message.contains("перерасход"))
        #expect(toast.actionTitle == "Отменить")
        let booked = try await h.operations().filter { $0.op.type == .expense }
        #expect(booked.map(\.op.note) == ["Шаурма"])
        #expect(booked.first?.op.voiceText == "Шаурма 15 лари")
        #expect(h.environment.voiceQueue.pending().isEmpty)

        toast.action()
        await eventuallyAsync { try await h.operations().filter { $0.op.type == .expense }.isEmpty }
    }

    @Test func aPurchaseToWeighUpOpensTheFormAndBooksNothing() async throws {
        let h = try ServiceHarness(script: .consider)
        try await h.open()
        let mic = VoiceMicModel(model: h.model, recorder: StubVoiceRecorder(), notes: h.environment.voice, locale: Locale(identifier: "ru"))
        await mic.start()

        mic.tap()
        mic.tap()
        await eventually { mic.route != nil }
        #expect(mic.route == .entry(EntryRequest(consider: Consider(title: "Наушники", amountMinor: 12_000, currency: "USD"))))
        #expect(mic.toast == nil)
        #expect(try await h.operations().filter { $0.op.type == .expense }.isEmpty)
    }
}
