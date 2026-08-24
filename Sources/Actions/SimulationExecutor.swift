import CoreEngine
import Domain
import Foundation

/// Records “would do X” without touching macOS.
public actor SimulationExecutor: ActionExecutor {
    public private(set) var log: [(action: ActionKind, bundleID: String)] = []
    public var shouldFail: Bool = false

    public init() {}

    public func execute(action: ActionKind, target: TargetApp) async throws {
        if shouldFail {
            throw SimulationError.forcedFailure
        }
        log.append((action, target.bundleID))
    }

    public func reset() {
        log.removeAll()
        shouldFail = false
    }

    public func setShouldFail(_ value: Bool) {
        shouldFail = value
    }
}

public enum SimulationError: Error, Equatable, Sendable {
    case forcedFailure
}
