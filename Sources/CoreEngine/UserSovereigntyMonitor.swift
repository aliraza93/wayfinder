import Domain
import Foundation

/// Abstract view of an incoming input event for sovereignty filtering (no AppKit in CoreEngine).
public struct IncomingInputEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case scroll
        case key
        case other
    }

    public var carriesSelfTag: Bool
    public var kind: Kind

    public init(carriesSelfTag: Bool, kind: Kind) {
        self.carriesSelfTag = carriesSelfTag
        self.kind = kind
    }
}

public protocol SecureInputProbe: Sendable {
    func isSecureEventInputEnabled() -> Bool
}

public struct NullSecureInputProbe: SecureInputProbe {
    public init() {}
    public func isSecureEventInputEnabled() -> Bool { false }
}

/// Listen-only sovereignty: ignores self-tagged events, fires on untagged user input / stop.
/// Platform taps feed `consider(_:)`; CoreEngine stays free of AppKit/CGEvent.
public actor UserSovereigntyMonitor: UserSovereigntySignal {
    private var stopRequested = false
    private var userIntervened = false
    private let secureInput: any SecureInputProbe

    public init(secureInput: any SecureInputProbe = NullSecureInputProbe()) {
        self.secureInput = secureInput
    }

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

    /// Tag-filter: tagged → ignore; untagged scroll/key → user intervened.
    public func consider(_ event: IncomingInputEvent) {
        if event.carriesSelfTag {
            return
        }
        switch event.kind {
        case .scroll, .key:
            userIntervened = true
        case .other:
            break
        }
    }

    /// Pure filter decision for unit tests (does not mutate state).
    public static func shouldIgnore(_ event: IncomingInputEvent) -> Bool {
        event.carriesSelfTag
    }

    public static func shouldSignalIntervention(_ event: IncomingInputEvent) -> Bool {
        !event.carriesSelfTag && (event.kind == .scroll || event.kind == .key)
    }

    /// Surfaces Secure Input as a precondition failure — do not retry/loop.
    public func ensureSecureInputClear() throws {
        if secureInput.isSecureEventInputEnabled() {
            throw DomainError.precondition("Secure Input is enabled; synthetic navigation cannot proceed")
        }
    }
}
