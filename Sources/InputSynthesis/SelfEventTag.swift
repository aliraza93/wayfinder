import CoreGraphics
import Foundation

/// Stamp applied to every synthetic event so the sovereignty monitor can ignore it.
public enum SelfEventTag: Sendable {
    /// Distinct user-data marker written to `CGEventField.eventSourceUserData`.
    public static let userDataValue: Int64 = 0x57_41_59_50_54_47_31 // "WAYPTG1"

    public static func apply(to event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: userDataValue)
    }

    public static func isTagged(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == userDataValue
    }

    public static func isTagged(userData: Int64) -> Bool {
        userData == userDataValue
    }
}
