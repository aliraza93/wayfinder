import Foundation

/// Declarative allowlist of inert navigation key codes.
///
/// Only arrows, Page Up/Down, Home, and End. No character keys, Return, Delete,
/// or Cmd/Ctrl chords. Values are macOS virtual key codes (`CGKeyCode` / HID).
public enum InertKeyAllowlist: Sendable {
    public static let keyCodes: Set<UInt16> = [
        123, // left arrow
        124, // right arrow
        125, // down arrow
        126, // up arrow
        116, // page up
        121, // page down
        115, // home
        119, // end
    ]

    public static func contains(_ keyCode: UInt16) -> Bool {
        keyCodes.contains(keyCode)
    }
}
