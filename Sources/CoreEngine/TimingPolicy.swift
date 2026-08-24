import Foundation

/// Injectable clock — tests use a fake; production uses wall clock.
public protocol EngineClock: Sendable {
    var now: Date { get }
}

public struct SystemClock: EngineClock {
    public init() {}
    public var now: Date { Date() }
}

/// Deterministic clock for tests. No real sleeps.
public final class FakeClock: EngineClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    public init(start: Date = Date(timeIntervalSince1970: 0)) {
        self._now = start
    }

    public var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    public func advance(by seconds: TimeInterval) {
        lock.lock()
        _now = _now.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// Predicate-based wait with timeout. All timing goes through the injected clock.
public struct TimingPolicy: Sendable {
    public let clock: EngineClock
    /// Called on each poll so tests can advance `FakeClock` without wall sleeps.
    public let onPoll: (@Sendable () -> Void)?

    public init(clock: EngineClock, onPoll: (@Sendable () -> Void)? = nil) {
        self.clock = clock
        self.onPoll = onPoll
    }

    /// Returns `true` if the predicate became true before timeout; otherwise `false`.
    public func wait(
        timeoutSeconds: TimeInterval,
        predicate: @Sendable () -> Bool
    ) async -> Bool {
        if predicate() {
            return true
        }
        let deadline = clock.now.addingTimeInterval(timeoutSeconds)
        var polls = 0
        while clock.now < deadline {
            if Task.isCancelled {
                return false
            }
            onPoll?()
            if onPoll == nil {
                // Production / wall clock: sleep so waits honor real timeouts.
                try? await Task.sleep(nanoseconds: 10_000_000) // 10 ms
            } else {
                await Task.yield()
            }
            if predicate() {
                return true
            }
            polls += 1
            // Safety valve for clocks that never advance (tests without onPoll).
            if polls > 10_000 {
                return predicate()
            }
        }
        return predicate()
    }
}
