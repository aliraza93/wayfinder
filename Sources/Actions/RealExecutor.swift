import CoreEngine
import Domain
import Foundation
import InputSynthesis
import Safety
import WaypointAccessibility

public enum RealExecutorError: Error, Equatable, Sendable {
    case unsupportedAction
    case invalidScroll
    case invalidInertKey
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
            let capped = min(max(1, amount), 100)
            let delta = ScrollAction.deltaY(direction: direction, amount: capped)
            guard let primitive = ScrollPrimitive.make(deltaY: delta) else {
                throw ActionError("invalid scroll delta")
            }
            try await synth.emitScroll(primitive, action: action, target: target)

        case .pageNavigate(let move):
            let keyCode: UInt16
            switch move {
            case .pageUp: keyCode = 116
            case .pageDown: keyCode = 121
            case .home: keyCode = 115
            case .end: keyCode = 119
            }
            guard let primitive = InertKeyPrimitive.make(keyCode: keyCode) else {
                throw ActionError("invalid inert key for pageNavigate")
            }
            try await synth.emitInertKey(primitive, action: action, target: target)

        case .wait:
            // Engine handles waits through TimingPolicy; nothing to synthesize.
            return

        default:
            throw ActionError("unsupported action for RealExecutor")
        }
    }
}