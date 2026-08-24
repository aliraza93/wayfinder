import Domain
import Foundation

/// Single safety gate for all action execution. Do not duplicate these checks elsewhere.
public struct SafetyPolicy: Sendable {
    private let tagsFor: @Sendable (ActionKind) -> CapabilityTags

    public init(tagsFor: @escaping @Sendable (ActionKind) -> CapabilityTags = { $0.capabilityTags }) {
        self.tagsFor = tagsFor
    }

    /// Validates an action against capability tags and the inert-primitive rules.
    public func validate(action: ActionKind, target: TargetApp) -> Decision {
        let tags = tagsFor(action)

        if tags.mutatesText {
            return .deny(reason: "mutatesText is forbidden for all targets (including \(target.classification))")
        }

        switch tags.primitive {
        case .scrollWheel, .inertKey, .navigationChord, .targetedClick:
            // Synthetic input primitives — allowed when non-mutating.
            return .allow
        case .appControl:
            if tags.verifiable {
                return .allow
            }
            return .deny(reason: "appControl actions must be verifiable")
        case .none:
            // Timing / no-op — not synthetic input.
            return .allow
        }
    }

    /// Validates a key code against the inert-key allowlist. Outside the set → deny.
    public func validateKey(_ keyCode: UInt16) -> Decision {
        if InertKeyAllowlist.contains(keyCode) {
            return .allow
        }
        return .deny(reason: "key code \(keyCode) is not in the inert-key allowlist")
    }

    /// Throws `ForbiddenActionError` when denied — never returns silently on denial.
    public func requireAllowed(action: ActionKind, target: TargetApp) throws {
        switch validate(action: action, target: target) {
        case .allow:
            return
        case .deny(let reason):
            throw ForbiddenActionError(action: action, target: target, reason: reason)
        }
    }

    /// Throws `ForbiddenActionError` when the key is not allowlisted.
    public func requireAllowedKey(_ keyCode: UInt16) throws {
        switch validateKey(keyCode) {
        case .allow:
            return
        case .deny(let reason):
            throw ForbiddenActionError(keyCode: keyCode, reason: reason)
        }
    }
}
