import Synchronization
import Testing

@testable import Golda

/// A clock that only moves when the test says so, so toast timing is checked without waiting.
final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol, Sendable {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        var deadline: Instant
        var continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Int: Sleeper] = [:]
        var nextID = 0
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = state.withLock { state -> Int in
            defer { state.nextID += 1 }
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let due = state.withLock { state -> Bool in
                    if deadline <= state.now { return true }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return false
                }
                if due {
                    continuation.resume()
                } else if Task.isCancelled {
                    cancel(id)
                }
            }
        } onCancel: {
            cancel(id)
        }
    }

    private func cancel(_ id: Int) {
        let sleeper = state.withLock { $0.sleepers.removeValue(forKey: id) }
        sleeper?.continuation.resume(throwing: CancellationError())
    }

    func advance(by duration: Duration) {
        let due = state.withLock { state -> [Sleeper] in
            state.now = state.now.advanced(by: duration)
            let ids = state.sleepers.filter { $0.value.deadline <= state.now }.map(\.key)
            return ids.compactMap { state.sleepers.removeValue(forKey: $0) }
        }
        for sleeper in due { sleeper.continuation.resume() }
    }
}

@Suite struct UndoToastTimingTests {
    @Test func theTwoLengthsAreFourAndTenSeconds() {
        #expect(UndoToastTiming.duration(.short) == .seconds(4))
        #expect(UndoToastTiming.duration(.long) == .seconds(10))
    }

    @Test func voiceOverMakesAShortToastAsLongAsALongOne() {
        #expect(UndoToastTiming.visibleDuration(.short, voiceOverRunning: false) == .seconds(4))
        #expect(UndoToastTiming.visibleDuration(.short, voiceOverRunning: true) == .seconds(10))
        #expect(UndoToastTiming.visibleDuration(.long, voiceOverRunning: true) == .seconds(10))
        #expect(UndoToastTiming.visibleDuration(.long, voiceOverRunning: false) == .seconds(10))
    }

    /// Lets the task under test run up to its first suspension.
    private func untilSleeping(_ clock: ManualClock) async {
        for _ in 0..<1_000 where clock.sleeperCount == 0 { await Task.yield() }
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    @Test func aShortToastRunsOutAtFourSecondsAndNotBefore() async {
        let clock = ManualClock()
        let finished = Mutex<Bool?>(nil)
        let task = Task {
            let ranOut = await UndoToastTiming.runOut(after: UndoToastTiming.duration(.short), on: clock)
            finished.withLock { $0 = ranOut }
            return ranOut
        }
        await untilSleeping(clock)
        #expect(clock.sleeperCount == 1)

        clock.advance(by: .milliseconds(3_900))
        await settle()
        #expect(finished.withLock { $0 } == nil, "still showing at 3.9 s")

        clock.advance(by: .milliseconds(100))
        let ranOut = await task.value
        #expect(ranOut)
        #expect(clock.sleeperCount == 0)
    }

    @Test func aLongToastStaysUntilTenSeconds() async {
        let clock = ManualClock()
        let finished = Mutex(false)
        let task = Task {
            let ranOut = await UndoToastTiming.runOut(after: UndoToastTiming.duration(.long), on: clock)
            finished.withLock { $0 = true }
            return ranOut
        }
        await untilSleeping(clock)

        clock.advance(by: .seconds(4))
        await settle()
        #expect(!finished.withLock { $0 }, "a long toast outlives the short one")

        clock.advance(by: .milliseconds(5_900))
        await settle()
        #expect(!finished.withLock { $0 })

        clock.advance(by: .milliseconds(100))
        #expect(await task.value)
    }

    @Test func aDismissedToastDoesNotRunOut() async {
        let clock = ManualClock()
        let task = Task { await UndoToastTiming.runOut(after: .seconds(4), on: clock) }
        await untilSleeping(clock)

        // The host cancels the wait when the toast is tapped, replaced or leaves the screen.
        task.cancel()
        #expect(await task.value == false)
        #expect(clock.sleeperCount == 0)
    }

    @Test func aReplacementRestartsTheTime() async {
        let clock = ManualClock()
        let first = Task { await UndoToastTiming.runOut(after: .seconds(4), on: clock) }
        await untilSleeping(clock)
        clock.advance(by: .seconds(3))

        // A second toast arrives at 3 s: the first wait is cancelled, a new one of 4 s starts.
        first.cancel()
        #expect(await first.value == false)
        let second = Task { await UndoToastTiming.runOut(after: .seconds(4), on: clock) }
        await untilSleeping(clock)

        clock.advance(by: .seconds(3))
        await settle()
        #expect(clock.sleeperCount == 1, "the replacement has had 3 of its 4 seconds")
        clock.advance(by: .seconds(1))
        #expect(await second.value)
    }

    @Test func aToastIsIdentifiedByItsOwnIdentity() {
        let a = UndoToast("Coffee −8 ₾") {}
        let b = UndoToast("Coffee −8 ₾") {}
        #expect(a == a)
        #expect(a != b, "two toasts with the same words are still two toasts")
        #expect(a.length == .short)
        #expect(!a.actionTitle.isEmpty)
    }
}
