import Carbon
import CoreEngine
import CoreGraphics
import Foundation

/// Live Secure Input probe (`IsSecureEventInputEnabled`).
public struct SystemSecureInputProbe: SecureInputProbe {
    public init() {}
    public func isSecureEventInputEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }
}

/// Maps CGEvents into `IncomingInputEvent` for the CoreEngine monitor (listen-only).
public enum SovereigntyEventMapper {
    public static func map(_ event: CGEvent) -> IncomingInputEvent? {
        let tagged = SelfEventTag.isTagged(event)
        let type = event.type
        let kind: IncomingInputEvent.Kind
        switch type {
        case .scrollWheel:
            kind = .scroll
        case .keyDown, .keyUp:
            kind = .key
        default:
            return nil
        }
        return IncomingInputEvent(carriesSelfTag: tagged, kind: kind)
    }
}
