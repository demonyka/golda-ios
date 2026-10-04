import Foundation
import GoldaCore
import Testing

@testable import GoldaData

/// Android's `Repo.understand` and `processVoiceQueue`, plus what iOS adds: consent before any
/// byte leaves the phone, and a note booked into the profile it was recorded in.
@Suite(.timeLimit(.minutes(1))) final class VoiceServiceTests {
    let voice: VoiceHarness
    let personal: UUID
    let rub = RepositoryLedgerTests.rubCard
    let usd = RepositoryLedgerTests.multiUsd
    /// GEL cash, third in the list the model sees.
    let cash = RepositoryLedgerTests.cash
    let hourAgo: Int64

    var service: VoiceService { voice.service }

    init() async throws {
        voice = try VoiceHarness()
        hourAgo = voice.now - 3_600_000
        let personal = try await voice.base.profile(accounts: [rub, usd, cash])
        self.personal = personal
        voice.device.update { $0.activeProfileId = personal }
    }

    static func coffee(_ transcript: String = "Кофе 8 лари") -> VoiceResult {
        VoiceResult(transcript: transcript, items: [VoiceItem(intent: "expense", amount: "8", currency: "GEL", note: "кофе")])
    }

    // MARK: Understood

    @Test func severalThingsSaidBecomeSeveralOperations() async throws {
        let transcript = "Кофе 8 лари и круассан 6"
        voice.provider.answer(VoiceResult(transcript: transcript, items: [
            VoiceItem(intent: "expense", amount: "8", currency: "GEL", note: "кофе", category: "eating_out"),
            VoiceItem(intent: "expense", amount: "6", currency: "GEL", note: "круассан"),
        ]))
        let file = try voice.note(personal, recordedAt: voice.now)

        let done = try #require(await service.understand(file: file).done)
        #expect(done.profileId == personal)
        #expect(done.transcript == transcript)
        #expect(done.recorded.map(\.draft) == [
            Draft(type: .expense, timestamp: voice.now, accountId: cash.id, amountMinor: 800, categoryKey: "eating_out", note: "Кофе", voiceText: transcript),
            Draft(type: .expense, timestamp: voice.now, accountId: cash.id, amountMinor: 600, note: "Круассан", voiceText: transcript),
        ])
        #expect(done.considering.isEmpty && !done.misunderstood && !done.late)

        let operations = try await voice.operations(personal)
        // Newest first: the second thing said was written last.
        #expect(operations.map(\.op.id) == done.recorded.map(\.operationId).reversed())
        #expect(operations.map(\.op.note) == ["Круассан", "Кофе"])
        #expect(operations.allSatisfy { $0.op.voiceText == transcript && $0.op.timestamp == voice.now })
        #expect(!voice.exists(file))
        #expect(voice.device.current.lastAccountId[personal] == cash.id)

        // The comment is about the last expense; no income is set, so no hours of work.
        let croissant = try #require(operations.first)
        let impact = try #require(done.impact)
        #expect(impact.costRub == -croissant.postings.reduce(0) { $0 + $1.rubMinor })
        #expect(impact.costRub > 0)
        #expect(impact.hoursOfWork == nil)
    }

    @Test func aNoteIsBookedIntoTheProfileItWasRecordedInAtTheTimeItWasRecorded() async throws {
        let familyCard = Account(id: StoreFixture.id(20), name: "Семейная карта", currency: "GEL", type: .card, includeInFree: true)
        let family = try await voice.base.profile("Семья", accounts: [familyCard])
        let file = try voice.note(personal, recordedAt: hourAgo)
        // By the time the note is understood, "Семья" is open and another model is set.
        voice.device.update {
            $0.activeProfileId = family
            $0.geminiModel = "gemini-test"
        }
        voice.provider.answer(Self.coffee())
        let prompt = VoicePrompt.system(
            accounts: [rub, usd, cash], categories: Category.builtIn,
            settings: Settings(profile: ProfileSettings(), device: voice.device.current, profileId: personal),
            today: RepositoryHarness.today
        )

        let done = try #require(await service.processQueue().first?.done)
        #expect(done.profileId == personal)
        #expect(done.late)
        let call = try #require(voice.provider.calls.first)
        #expect(call.audio.lastPathComponent == file.lastPathComponent)
        #expect(call.system == prompt)
        #expect(call.model == "gemini-test")

        let booked = try await voice.operations(personal)
        #expect(booked.map(\.op.note) == ["Кофе"])
        #expect(booked.first?.op.timestamp == hourAgo)
        #expect(booked.first?.postings.map(\.accountId) == [cash.id])
        #expect(try await voice.operations(family).isEmpty)
        #expect(voice.device.current.lastAccountId[family] == nil)
    }

    @Test func wantingToBuyIsWeighedNotSpent() async throws {
        voice.provider.answer(VoiceResult(transcript: "Хочу купить наушники за 200 долларов", items: [
            VoiceItem(intent: "consider", amount: "200", currency: "USD", note: "наушники"),
        ]))
        let file = try voice.note(personal, recordedAt: voice.now)

        let done = try #require(await service.understand(file: file).done)
        #expect(done.considering == [Consider(title: "Наушники", amountMinor: 20_000, currency: "USD")])
        #expect(done.recorded.isEmpty && done.impact == nil && !done.misunderstood)
        #expect(try await voice.operations(personal).isEmpty)
        #expect(!voice.exists(file))
    }

    @Test func anUnnamedPurchaseIsLeftForTheScreenToNameUnlessTheAppGivesAWord() async throws {
        let unnamed = VoiceResult(transcript: "Хочу купить за 50 долларов", items: [VoiceItem(intent: "consider", amount: "50", currency: "USD")])
        voice.provider.answer(unnamed)
        let plain = try #require(await service.understand(file: try voice.note(personal, recordedAt: voice.now)).done)
        #expect(plain.considering == [Consider(title: "", amountMinor: 5_000, currency: "USD")])

        let named = try VoiceHarness(unnamedPurchase: "Покупка")
        let profile = try await named.base.profile()
        named.provider.answer(unnamed)
        let done = try #require(await named.service.understand(file: try named.note(profile, recordedAt: named.now)).done)
        #expect(done.considering == [Consider(title: "Покупка", amountMinor: 5_000, currency: "USD")])
    }

    @Test func nothingAboutMoneyIsNotUnderstoodAndTheNoteIsDone() async throws {
        voice.provider.answer(VoiceResult(transcript: "Какая сегодня погода", items: []))
        let file = try voice.note(personal, recordedAt: voice.now)

        let outcome = await service.understand(file: file)
        #expect(outcome == .done(VoiceOutcome.Done(
            profileId: personal, transcript: "Какая сегодня погода", recorded: [], considering: [], misunderstood: true, late: false,
            impact: nil
        )))
        #expect(try await voice.operations(personal).isEmpty)
        #expect(!voice.exists(file))
    }

    @Test func whatWasUnderstoodIsBookedEvenWhenSomethingWasNot() async throws {
        voice.provider.answer(VoiceResult(transcript: "Кофе 8 лари и что-то ещё", items: [
            VoiceItem(intent: "expense", amount: "8", currency: "GEL", note: "кофе"),
            VoiceItem(intent: "unknown", note: "что-то ещё"),
        ]))
        let done = try #require(await service.understand(file: try voice.note(personal, recordedAt: voice.now)).done)
        #expect(done.recorded.count == 1)
        #expect(done.misunderstood)
        #expect(try await voice.operations(personal).count == 1)
    }

    // MARK: Kept for later

    @Test func withoutConsentNothingLeavesThePhone() async throws {
        voice.device.update { $0.voiceConsent = false }
        // Consent is asked for first, before the key.
        try voice.base.secrets.delete(SecretKey.gemini)
        let file = try voice.note(personal, recordedAt: hourAgo)
        let second = try voice.note(personal, recordedAt: hourAgo + 60_000)
        let settings = voice.device.current

        #expect(await service.understand(file: file) == .needsConsent)
        // The queue stops at once: every note would wait for the same consent.
        #expect(await service.processQueue() == [.needsConsent])

        #expect(voice.provider.calls.isEmpty)
        #expect(voice.exists(file) && voice.exists(second))
        #expect(try await voice.operations(personal).isEmpty)
        #expect(voice.device.current == settings)
    }

    @Test func withoutAKeyTheNoteWaits() async throws {
        try voice.base.secrets.delete(SecretKey.gemini)
        let file = try voice.note(personal, recordedAt: hourAgo)

        #expect(await service.understand(file: file) == .waiting(.noKey))
        #expect(voice.provider.calls.isEmpty)
        #expect(voice.exists(file))

        // A key that went between the check and the call counts the same.
        try voice.base.secrets.write("AIza-test", for: SecretKey.gemini)
        voice.provider.fail(VoiceProviderError.noKey)
        #expect(await service.understand(file: file) == .waiting(.noKey))
        #expect(voice.exists(file))
    }

    @Test(arguments: [
        VoiceProviderError.offline(message: "HTTP 503") as any Error,
        URLError(.notConnectedToInternet) as any Error,
    ])
    func offlineTheNoteWaitsAndIsKept(error: any Error) async throws {
        voice.provider.fail(error)
        let file = try voice.note(personal, recordedAt: hourAgo)

        #expect(await service.understand(file: file) == .waiting(.offline))
        #expect(voice.exists(file))
        #expect(try await voice.operations(personal).isEmpty)
    }

    @Test func anUnsupportedLocationWaitsAndKeepsTheNote() async throws {
        let file = try voice.note(personal, recordedAt: hourAgo)
        voice.provider.fail(VoiceProviderError.unsupportedLocation)

        #expect(await service.understand(file: file) == .waiting(.unsupportedLocation))
        #expect(voice.exists(file))
        #expect(try await voice.operations(personal).isEmpty)
    }

    @Test func aRefusalFailsAndKeepsTheNote() async throws {
        let file = try voice.note(personal, recordedAt: hourAgo)
        voice.provider.fail(VoiceProviderError.rejected(message: "API key not valid. Please pass a valid API key."))
        #expect(await service.understand(file: file) == .failed(.rejected(message: "API key not valid. Please pass a valid API key.")))
        #expect(voice.exists(file))

        voice.provider.fail(VoiceProviderError.malformedAnswer)
        #expect(await service.understand(file: file) == .failed(.malformedAnswer))
        #expect(voice.exists(file))
        #expect(try await voice.operations(personal).isEmpty)
    }

    @Test func aNoteIsBookedWholeOrNotAtAll() async throws {
        let repository = voice.repository
        let cashId = cash.id
        let personal = personal
        voice.provider.answer { _ in
            // The cash account is deleted while the note is on its way.
            try await repository.deleteAccount(cashId, profileId: personal)
            return VoiceResult(transcript: "Хлеб 100 рублей с карты и вода 2 лари наличными", items: [
                VoiceItem(intent: "expense", amount: "100", currency: "RUB", note: "хлеб", accountId: "1"),
                VoiceItem(intent: "expense", amount: "2", currency: "GEL", note: "вода", accountId: "3"),
            ])
        }
        let file = try voice.note(personal, recordedAt: hourAgo)

        #expect(await service.understand(file: file) == .failed(.storage))
        // The bread went back with the water, so another try books both once.
        #expect(try await voice.operations(personal).isEmpty)
        #expect(voice.exists(file))
        #expect(voice.device.current.lastAccountId[personal] == nil)
    }

    @Test func aNoteWhoseProfileIsGoneGoesWithIt() async throws {
        let family = try await voice.base.profile("Семья")
        let file = try voice.note(family, recordedAt: hourAgo)
        try await voice.repository.deleteProfile(family)

        #expect(await service.understand(file: file) == .failed(.profileGone))
        #expect(voice.provider.calls.isEmpty)
        #expect(!voice.exists(file))
    }

    @Test func aMissingNoteIsLost() async {
        let file = voice.queue.directory.appending(path: "1759399200000.\(personal.uuidString).wav")
        #expect(await service.understand(file: file) == .failed(.lost))
        #expect(voice.provider.calls.isEmpty)
    }

    // MARK: The queue

    @Test func theQueueStopsAtTheFirstNoteThatHasToWait() async throws {
        let notes = try (0..<3).map { try voice.note(personal, recordedAt: hourAgo + Int64($0) * 60_000) }
        let waiting = notes[1].lastPathComponent
        voice.provider.answer { audio in
            if audio.lastPathComponent == waiting { throw VoiceProviderError.offline(message: "HTTP 503") }
            return VoiceServiceTests.coffee()
        }

        let outcomes = await service.processQueue()
        #expect(outcomes.count == 2)
        #expect(outcomes.first?.done?.late == true)
        #expect(outcomes.last == .waiting(.offline))
        // The third note was never sent: it would wait for the same connection.
        #expect(voice.provider.calls.map(\.audio.lastPathComponent) == notes[0...1].map(\.lastPathComponent))
        #expect(!voice.exists(notes[0]) && voice.exists(notes[1]) && voice.exists(notes[2]))
        #expect(try await voice.operations(personal).map(\.op.timestamp) == [hourAgo])
    }

    @Test func aFailedNoteDoesNotHoldUpTheQueue() async throws {
        let refused = try voice.note(personal, recordedAt: hourAgo)
        let fine = try voice.note(personal, recordedAt: hourAgo + 60_000)
        let refusedName = refused.lastPathComponent
        voice.provider.answer { audio in
            if audio.lastPathComponent == refusedName { throw VoiceProviderError.rejected(message: "HTTP 400") }
            return VoiceServiceTests.coffee()
        }

        let outcomes = await service.processQueue()
        #expect(outcomes.first == .failed(.rejected(message: "HTTP 400")))
        #expect(outcomes.last?.done != nil)
        #expect(voice.exists(refused) && !voice.exists(fine))
    }

    @Test func aNoteStillBeingWrittenIsLeftAlone() async throws {
        let fresh = try voice.note(personal, recordedAt: voice.now - 1_000)
        voice.provider.answer(Self.coffee())

        #expect(await service.processQueue().isEmpty)
        #expect(voice.provider.calls.isEmpty)
        #expect(voice.exists(fresh))

        // Two and a half seconds since the last write: done recording.
        voice.base.clock.set(voice.now + 1_500)
        #expect(await service.processQueue().count == 1)
        #expect(!voice.exists(fresh))
    }

    /// A note the recorder still holds is its to send, however long ago it was last written: a
    /// queue run that reaches it first would book it behind the recorder's back, and the recorder's
    /// own call would find nothing and say the note was lost.
    @Test func aNoteTheRecorderHoldsIsLeftToTheRecorder() async throws {
        let earlier = try voice.note(personal, recordedAt: hourAgo)
        let recording = try service.newNote(profileId: personal, recordedAt: voice.now)
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: recording)
        try setModified(recording, voice.now)
        voice.provider.answer(Self.coffee())
        // Stopped well before the queue gets to it.
        voice.base.clock.set(voice.now + 10_000)

        let queued = await service.processQueue()
        #expect(queued.count == 1)
        #expect(!voice.exists(earlier) && voice.exists(recording))

        let outcome = try #require(await service.understand(file: recording).done)
        #expect(!outcome.late)
        #expect(!voice.exists(recording))
        #expect(try await voice.operations(personal).count == 2)
    }

    /// Once the recorder's call is through, a note it left behind (it had to wait) is the queue's.
    @Test func aNoteTheRecorderLeftWaitingGoesBackToTheQueue() async throws {
        let recording = try service.newNote(profileId: personal, recordedAt: hourAgo)
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: recording)
        try setModified(recording, hourAgo)
        voice.provider.fail(VoiceProviderError.offline(message: "HTTP 503"))
        #expect(await service.understand(file: recording) == .waiting(.offline))

        voice.provider.answer(Self.coffee())
        #expect(await service.processQueue().count == 1)
        #expect(!voice.exists(recording))
    }

    // MARK: One at a time

    @Test func twoNotesAtOnceAreUnderstoodOneAfterTheOther() async throws {
        let gauge = Gauge()
        voice.provider.answer { audio in
            gauge.enter(audio.lastPathComponent)
            try await Task.sleep(for: .milliseconds(30))
            gauge.leave(audio.lastPathComponent)
            return VoiceServiceTests.coffee()
        }
        let first = try voice.note(personal, recordedAt: hourAgo)
        let second = try voice.note(personal, recordedAt: hourAgo + 60_000)
        let service = service

        async let one = service.understand(file: first)
        async let two = service.understand(file: second)
        let outcomes = await [one, two]

        #expect(outcomes.allSatisfy { $0.done != nil })
        #expect(gauge.peak == 1)
        // Whichever came first was through before the other started.
        let events = gauge.events
        try #require(events.count == 4)
        #expect(events[0].hasPrefix("start") && events[1] == events[0].replacingOccurrences(of: "start", with: "end"))
        #expect(events[2].hasPrefix("start") && events[3] == events[2].replacingOccurrences(of: "start", with: "end"))
        #expect(try await voice.operations(personal).count == 2)
    }

    @Test func theQueueAndTheRecorderNeverBookTheSameNoteTwice() async throws {
        voice.provider.answer { _ in
            try await Task.sleep(for: .milliseconds(30))
            return VoiceServiceTests.coffee()
        }
        let file = try voice.note(personal, recordedAt: hourAgo)
        let service = service

        async let fromQueue = service.processQueue()
        async let fromRecorder = service.understand(file: file)
        _ = await (fromQueue, fromRecorder)

        #expect(voice.provider.calls.count == 1)
        #expect(try await voice.operations(personal).count == 1)
    }

    @Test func understandingFinishesWhenTheCallerGivesUp() async throws {
        voice.provider.answer { _ in
            try await Task.sleep(for: .milliseconds(50))
            return VoiceServiceTests.coffee()
        }
        let file = try voice.note(personal, recordedAt: hourAgo)
        let service = service

        let task = Task { await service.understand(file: file) }
        task.cancel()
        #expect(await task.value.done != nil)
        #expect(try await voice.operations(personal).count == 1)
        #expect(!voice.exists(file))
    }

    // MARK: Observing

    @Test func everyObserverHearsEveryOutcome() async throws {
        var first = service.outcomes().makeAsyncIterator()
        var second = service.outcomes().makeAsyncIterator()
        voice.provider.answer(Self.coffee())

        let outcome = await service.understand(file: try voice.note(personal, recordedAt: hourAgo))
        #expect(outcome.done != nil)
        #expect(await first.next() == outcome)
        #expect(await second.next() == outcome)

        // The queue's outcomes too.
        voice.device.update { $0.voiceConsent = false }
        _ = try voice.note(personal, recordedAt: hourAgo + 60_000)
        await service.processQueue()
        #expect(await first.next() == .needsConsent)
        #expect(await second.next() == .needsConsent)
    }
}
