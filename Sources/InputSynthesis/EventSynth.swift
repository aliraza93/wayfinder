import CoreEngine
import CoreGraphics
import Domain
import Foundation
import Safety
import WaypointAccessibility

public enum EventSynthError: Error, Equatable, Sendable {
    case safetyDenied(String)
    case focusNotOk(FocusGuardResult)
    case secureInputEnabled
    case invalidPrimitive
}

/// Posted representation for tests / recording (never includes document content).
public struct SynthesizedEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case scroll(deltaY: Int32)
        case inertKey(keyCode: UInt16, keyDown: Bool)
    }

    public var kind: Kind
    public var tagged: Bool

    public init(kind: Kind, tagged: Bool) {
        self.kind = kind
        self.tagged = tagged
    }
}

public protocol EventPoster: Sendable {
    func post(_ event: SynthesizedEvent)
}

/// Posts real CGEvents to the session (frontmost focus). Always applies self-tag.
public struct CGEventPoster: EventPoster {
    public init() {}

    public func post(_ event: SynthesizedEvent) {
        switch event.kind {
        case .scroll(let deltaY):
            if let cg = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: deltaY,
                wheel2: 0,
                wheel3: 0
            ) {
                SelfEventTag.apply(to: cg)
                cg.post(tap: .cghidEventTap)
            }
        case .inertKey(let keyCode, let keyDown):
            if let cg = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) {
                // No modifier flags — chords are forbidden.
                cg.flags = []
                SelfEventTag.apply(to: cg)
                cg.post(tap: .cghidEventTap)
            }
        }
    }
}

/// Recording poster for unit tests (no CGEvent emission).
public final class RecordingEventPoster: EventPoster, @unchecked Sendable {
    public private(set) var events: [SynthesizedEvent] = []
    public init() {}
    public func post(_ event: SynthesizedEvent) {
        events.append(event)
    }
}

/// Sole emitter of synthetic input. Always: Secure Input check → Safety → FocusGuard → tagged post.
public struct EventSynth: Sendable {
    private let safety: SafetyPolicy
    private let focusGuard: FocusGuard
    private let poster: any EventPoster
    private let sovereignty: UserSovereigntyMonitor

    public init(
        safety: SafetyPolicy = SafetyPolicy(),
        focusGuard: FocusGuard,
        poster: any EventPoster = CGEventPoster(),
        sovereignty: UserSovereigntyMonitor
    ) {
        self.safety = safety
        self.focusGuard = focusGuard
        self.poster = poster
        self.sovereignty = sovereignty
    }

    public func emitScroll(
        _ primitive: ScrollPrimitive,
        action: ActionKind,
        target: TargetApp
    ) async throws {
        try await prepare(action: action, target: target)
        poster.post(SynthesizedEvent(kind: .scroll(deltaY: primitive.deltaY), tagged: true))
    }

    public func emitInertKey(
        _ primitive: InertKeyPrimitive,
        action: ActionKind,
        target: TargetApp
    ) async throws {
        try await prepare(action: action, target: target)
        // key down + up
        poster.post(SynthesizedEvent(kind: .inertKey(keyCode: primitive.keyCode, keyDown: true), tagged: true))
        poster.post(SynthesizedEvent(kind: .inertKey(keyCode: primitive.keyCode, keyDown: false), tagged: true))
    }

    private func prepare(action: ActionKind, target: TargetApp) async throws {
        do {
            try await sovereignty.ensureSecureInputClear()
        } catch {
            throw EventSynthError.secureInputEnabled
        }

        switch safety.validate(action: action, target: target) {
        case .allow:
            break
        case .deny(let reason):
            throw EventSynthError.safetyDenied(reason)
        }

        let focus = await focusGuard.assert(target: target)
        guard focus == .ok else {
            throw EventSynthError.focusNotOk(focus)
        }
    }
}
