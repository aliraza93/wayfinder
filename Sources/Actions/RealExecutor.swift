import CoreEngine
import Domain
import Foundation
import InputSynthesis
import Safety
import WaypointAccessibility

public enum RealExecutorError: Error, Equatable, Sendable {
    case unsupportedAction
    case invalidScroll
}

/// Real `ActionExecutor`: Safety → FocusGuard → InputSynthesis (via `EventSynth`).
public actor RealExecutor: ActionExecutor {
    private let synth: EventSynth

    public init(synth: EventSynth) {
        self.synth = synth
    }

    public func execute(action: ActionKind, target: TargetApp) async throws {
        switch action {
        case .scroll(let direction, let amount):
            let delta = ScrollAction.deltaY(direction: direction, amount: amount)
            guard let primitive = ScrollPrimitive.make(deltaY: delta) else {
                throw RealExecutorError.invalidScroll
            }
            try await synth.emitScroll(primitive, action: action, target: target)

        case .wait:
            // Engine handles waits through TimingPolicy; nothing to synthesize.
            return

        default:
            throw RealExecutorError.unsupportedAction
        }
    }
}
