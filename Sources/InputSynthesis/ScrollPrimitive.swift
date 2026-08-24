import Foundation
import Safety

/// Constructible scroll-wheel primitive only (no other mouse buttons/chords).
public struct ScrollPrimitive: Equatable, Sendable {
    public var deltaY: Int32

    private init(deltaY: Int32) {
        self.deltaY = deltaY
    }

    /// Returns `nil` if delta is zero (nothing to emit).
    public static func make(deltaY: Int32) -> ScrollPrimitive? {
        guard deltaY != 0 else { return nil }
        return ScrollPrimitive(deltaY: deltaY)
    }
}
