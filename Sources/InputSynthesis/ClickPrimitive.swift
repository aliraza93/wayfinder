import CoreGraphics
import Foundation

/// Click at an adapter-resolved screen point inside the target content area.
public struct ClickPrimitive: Equatable, Sendable {
    public var x: Double
    public var y: Double

    private init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Rejects non-finite coordinates.
    public static func make(x: Double, y: Double) -> ClickPrimitive? {
        guard x.isFinite, y.isFinite else { return nil }
        return ClickPrimitive(x: x, y: y)
    }

    public var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}
