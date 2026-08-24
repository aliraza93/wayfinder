import Domain
import Foundation

public enum EngineState: Equatable, Sendable {
    case idle
    case arming
    case running
    case paused
    case stopping
    case error(String)
}

public enum StepPhase: Equatable, Sendable {
    case pending
    case validating
    case executing
    case settling
    case completed
    case failed
}

public enum StepOutcome: Equatable, Sendable {
    case completed
    case failed
    case denied
    case skipped
    case aborted
}
