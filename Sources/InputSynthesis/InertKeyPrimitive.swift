import Foundation
import Safety

/// Constructible inert-key primitive — allowlist only, never chords/modifiers.
public struct InertKeyPrimitive: Equatable, Sendable {
    public var keyCode: UInt16

    private init(keyCode: UInt16) {
        self.keyCode = keyCode
    }

    /// Returns `nil` for any key outside `InertKeyAllowlist` (Return/Delete/characters/Cmd denied).
    public static func make(keyCode: UInt16) -> InertKeyPrimitive? {
        guard InertKeyAllowlist.contains(keyCode) else { return nil }
        return InertKeyPrimitive(keyCode: keyCode)
    }
}
