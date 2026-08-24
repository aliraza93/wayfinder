import AppKit
import ApplicationServices
import Foundation

/// Live AX probe. Reads only focus/frontmost identity — never titles, values, or document text.
public struct SystemAXProbe: AXProbe {
    public init() {}

    public func frontmostAppBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public func focusedWindowExists() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        return result == .success && focusedWindow != nil
    }

    public func focusedElementBundleID() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )
        guard appResult == .success, let focusedAppRef else {
            return frontmostAppBundleID()
        }

        let focusedApp = (focusedAppRef as! AXUIElement)
        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(focusedApp, &pid)
        guard pidResult == .success else {
            return frontmostAppBundleID()
        }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            ?? frontmostAppBundleID()
    }
}
