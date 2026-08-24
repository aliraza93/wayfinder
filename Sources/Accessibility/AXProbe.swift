import Foundation

/// Injectable coarse AX reads. Never returns window titles, document text, or keystrokes.
public protocol AXProbe: Sendable {
    func frontmostAppBundleID() -> String?
    func focusedWindowExists() -> Bool
    func focusedElementBundleID() -> String?
}
