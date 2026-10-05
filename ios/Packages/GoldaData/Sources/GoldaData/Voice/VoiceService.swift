import Foundation
import GoldaCore
import Synchronization

/// Understands voice notes and books what they say, one note at a time: Android's
/// `Repo.understand` and `processVoiceQueue`. Every outcome also goes to `outcomes()`, which the
/// app follows to say "Записано" with "Отменить", or why a note waits.
///
/// A note is booked into the profile that was active when it was recorded (its file name says
/// which), with that profile's accounts, settings and markup, whatever profile is open now.
public actor VoiceService {
    /// A note written to within this long may still be recording; the queue leaves it alone.
    static let settleMillis: Int64 = 2_000

    public nonisolated let queue: VoiceQueue
    private let repository: Repository
    private let provider: any VoiceProvider
    private let secrets: any SecretStore
    private let deviceSettings: DeviceSettingsStore
    private let unnamedPurchase: String
    private let clock: @Sendable () -> Int64
    private let zone: @Sendable () -> TimeZone
    private nonisolated let observers = VoiceOutcomeObservers()
    /// The last note asked for; the next one starts when it is through.
    private var tail: Task<Void, Never>?
    /// Names of the notes handed out by `newNote` whose recorder has not sent them yet. Read and
    /// written off the actor, since the recorder asks for a file synchronously.
    private nonisolated let recording = Mutex<Set<String>>([])

    /// [unnamedPurchase] titles a "хочу купить" said without a name; empty leaves the title empty
    /// for the screen to name. [clock] (epoch milliseconds) and [zone] are injected so tests run
    /// on a fixed time; [zone] is read on each use, since the phone travels.
    public init(
        repository: Repository,
        provider: any VoiceProvider,
        secrets: any SecretStore,
        deviceSettings: DeviceSettingsStore,
        queue: VoiceQueue = .live,
        unnamedPurchase: String = "",
        clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        zone: @escaping @Sendable () -> TimeZone = { TimeZone.current }
    ) {
        self.repository = repository
        self.provider = provider
        self.secrets = secrets
        self.deviceSettings = deviceSettings
        self.queue = queue
        self.unnamedPurchase = unnamedPurchase
        self.clock = clock
        self.zone = zone
    }

    /// Every outcome from now on, those of the queue included. Each caller gets its own stream.
    public nonisolated func outcomes() -> AsyncStream<VoiceOutcome> {
        observers.stream()
    }

    /// Where a note recorded now, in [profileId], goes. The note is the recorder's until its
    /// `understand(file:)` is through: the queue leaves it alone however long ago it was last
    /// written. Otherwise a queue run that started while the note was recording could reach it
    /// after the recorder stopped, book it as late, and leave the recorder's own call to find
    /// nothing and say the note was lost.
    public nonisolated func newNote(profileId: UUID, recordedAt: Int64) throws -> URL {
        let file = try queue.newFile(profileId: profileId, recordedAt: recordedAt, fileExtension: "wav")
        recording.withLock { _ = $0.insert(file.lastPathComponent) }
        return file
    }

    /// Understands one recorded note and books what it says; the file is removed once it is booked.
    /// [late] marks a note understood after the moment it was recorded. Runs to the end even when
    /// the caller is cancelled, as Android's non-cancellable write did.
    @discardableResult
    public func understand(file: URL, late: Bool = false) async -> VoiceOutcome {
        // A note left waiting (no network, no key) is the queue's from now on.
        defer { recording.withLock { _ = $0.remove(file.lastPathComponent) } }
        return await serially { service in await service.understandLocked(file, late: late) }
    }

    /// Notes recorded offline, before the key was set or before consent, oldest first. Stops at the
    /// first that has to wait: the rest would wait for the same reason. Returns what became of each
    /// note it tried.
    @discardableResult
    public func processQueue() async -> [VoiceOutcome] {
        await serially { service in await service.processQueueLocked() }
    }

    // MARK: One at a time

    /// Runs [body] after everything asked for before it, the way Android's `voiceLock` did. An
    /// actor alone would let a second note start while the first awaits the network.
    private func serially<T: Sendable>(_ body: @escaping @Sendable (VoiceService) async -> T) async -> T {
        let previous = tail
        let task = Task {
            await previous?.value
            return await body(self)
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    private func processQueueLocked() async -> [VoiceOutcome] {
        var outcomes: [VoiceOutcome] = []
        for file in queue.pending() {
            // Checked as each file is reached, not once for the run: the recorder may have
            // stopped and asked for its note while earlier ones went to the model.
            if recording.withLock({ $0.contains(file.lastPathComponent) }) { continue }
            if let modified = queue.modifiedAt(of: file), clock() - modified < Self.settleMillis { continue }
            let outcome = await understandLocked(file, late: true)
            outcomes.append(outcome)
            switch outcome {
            case .waiting, .needsConsent: return outcomes
            case .done, .failed: continue
            }
        }
        return outcomes
    }

    private func understandLocked(_ file: URL, late: Bool) async -> VoiceOutcome {
        let outcome = await work(on: file, late: late)
        observers.send(outcome)
        return outcome
    }

    // MARK: The work

    /// What the note's profile looks like to the model and to `VoiceMapper`: the same accounts, in
    /// the same order, for both (D25).
    private struct Books: Sendable {
        var accounts: [Account]
        var settings: Settings
        var rates: Rates
        var categories: VoiceCategories
    }

    private func work(on file: URL, late: Bool) async -> VoiceOutcome {
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return .failed(.lost) }
        let device = deviceSettings.current
        // First of all: without consent not a byte of the note leaves the phone.
        guard device.voiceConsent else { return .needsConsent }
        // Gemini is the only provider (D8), so its key is the one that decides.
        guard secrets.read(SecretKey.gemini) != nil else { return .waiting(.noKey) }

        // A name without a profile was not made by this queue; the open profile is the best guess.
        guard let profileId = queue.profileId(of: file) ?? device.activeProfileId else { return discard(file) }
        let books: Books?
        do {
            books = try await self.books(profileId, device)
        } catch {
            return .failed(.storage)
        }
        guard let books else { return discard(file) }

        let zone = zone()
        let system = VoicePrompt.system(
            accounts: books.accounts, categories: books.categories.categories, settings: books.settings,
            today: LocalDate(epochMillis: clock(), in: zone), examples: books.categories.examples
        )
        let result: VoiceResult
        do {
            result = try await provider.parse(audio: file, system: system, model: device.geminiModel)
        } catch let error as VoiceProviderError {
            switch error {
            case .noKey: return .waiting(.noKey)
            case .offline: return .waiting(.offline)
            case .rejected(let message): return .failed(.rejected(message: message))
            case .malformedAnswer: return .failed(.malformedAnswer)
            case .unsupportedLocation: return .waiting(.unsupportedLocation)
            }
        } catch {
            // A provider that lets its transport's error through: the network, as on Android.
            return .waiting(.offline)
        }

        let actions = VoiceMapper.actions(
            result, accounts: books.accounts, categories: books.categories.categories, settings: books.settings, rates: books.rates,
            recordedAt: queue.recordedAt(of: file), zone: zone, unnamedPurchase: unnamedPurchase
        )
        let drafts = actions.compactMap { action -> Draft? in
            if case .record(let draft) = action { draft } else { nil }
        }
        let ids: [UUID]
        do {
            ids = try await repository.save(drafts, profileId: profileId)
        } catch {
            return .failed(.storage)
        }
        // Booked, so the note is done. Should the delete fail, the note would come round again and
        // be booked twice; Android ignored that too, and there is no better place for it to go.
        try? queue.delete(file)

        let recorded = zip(ids, drafts).map { VoiceOutcome.Recorded(operationId: $0, draft: $1) }
        // The comment is a nicety: failing to read it leaves it out rather than failing the note.
        let impact: Impact? = if let expense = recorded.last(where: { $0.draft.type == .expense }) {
            try? await repository.impact(operationId: expense.operationId, profileId: profileId)
        } else {
            nil
        }
        return .done(VoiceOutcome.Done(
            profileId: profileId,
            transcript: result.transcript,
            recorded: recorded,
            considering: actions.compactMap { action -> Consider? in
                if case .consider(let consider) = action { consider } else { nil }
            },
            misunderstood: actions.contains { action in
                if case .notUnderstood = action { true } else { false }
            },
            late: late,
            impact: impact
        ))
    }

    /// The profile's accounts by `sort`, its composed settings and its rates in one read; nil when
    /// the profile is gone.
    private func books(_ profileId: UUID, _ device: DeviceSettings) async throws -> Books? {
        try await repository.database.read { store in
            guard let profile = try store.profile(profileId) else { return nil }
            return Books(
                accounts: try store.accounts(profileId: profileId),
                settings: Settings(profile: profile.settings, device: device, profileId: profileId),
                rates: try Repository.rates(store, markup: profile.settings.markup),
                categories: try Repository.voiceCategories(store, profileId: profileId)
            )
        }
    }

    /// A note whose profile was deleted since goes with it, as everything else the profile owned
    /// did; kept, it would fail again on every run of the queue.
    private func discard(_ file: URL) -> VoiceOutcome {
        try? queue.delete(file)
        return .failed(.profileGone)
    }
}

/// Everyone following the outcomes. Each stream gets every outcome sent after it was made, like a
/// collector of Android's `SharedFlow`, and none is dropped for a slow reader: notes are few.
final class VoiceOutcomeObservers: @unchecked Sendable {
    // Guards `continuations`: outcomes are sent from the service while screens start and stop
    // listening on their own tasks.
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<VoiceOutcome>.Continuation] = [:]

    func stream() -> AsyncStream<VoiceOutcome> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { self.continuations[id] = nil }
            }
        }
    }

    func send(_ outcome: VoiceOutcome) {
        lock.withLock {
            for continuation in continuations.values { continuation.yield(outcome) }
        }
    }
}
