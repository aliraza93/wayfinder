import Foundation

/// Abstract stop / user-intervention signal. Firing it must transition the engine to Stopping.
public protocol UserSovereigntySignal: Sendable {
    func shouldHalt() async -> Bool
    func requestStop() async
    func noteUserIntervention() async
}

public actor ManualSovereigntySignal: UserSovereigntySignal {
    private var stopRequested = false
    private var userIntervened = false

    public init() {}

    public func shouldHalt() async -> Bool {
        stopRequested || userIntervened
    }

    public func requestStop() async {
        stopRequested = true
    }

    public func noteUserIntervention() async {
        userIntervened = true
    }

    public func reset() {
        stopRequested = false
        userIntervened = false
    }
}
