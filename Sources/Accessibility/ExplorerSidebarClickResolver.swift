import ApplicationServices
import AppKit
import CoreGraphics
import Domain
import Foundation

/// Resolves a click point inside the editor’s left file explorer (sidebar).
/// Never uses Return/typing — open/select via targeted click only.
public struct ExplorerSidebarClickResolver: Sendable {
    public init() {}

    /// Point inside the project sidebar file list (global screen coords).
    /// `hop` varies the vertical position so repeated switches land on different rows.
    public func resolveFileRowClick(
        bundleID: String,
        direction: WindowDirection,
        hop: Int
    ) -> CGPoint? {
        guard let frame = primaryWindowFrame(bundleID: bundleID) else { return nil }

        // Cursor/VS Code: click the filename column (not the far-left disclosure / multi-select hit zone).
        let activityBar: CGFloat = 48
        let sidebarWidth = min(320, max(180, frame.size.width * 0.28))
        // Bias toward the label text (~70% into the sidebar) so we hit files, not chevrons.
        let x = frame.origin.x + activityBar + sidebarWidth * 0.72

        let listTop = frame.origin.y + 130
        let listBottom = frame.origin.y + frame.size.height - 100
        guard listBottom > listTop + 40 else { return nil }

        let slots = 12
        let slot = abs(hop) % slots
        let index = direction == .next ? slot : (slots - 1 - slot)
        let t = (CGFloat(index) + 0.5) / CGFloat(slots)
        let y = listTop + (listBottom - listTop) * t
        return CGPoint(x: x, y: y)
    }

    /// True when AX focused element looks like an editable text surface (do not press Return).
    public func focusedElementLooksEditable(bundleID: String) -> Bool {
        guard let app = runningApp(bundleID: bundleID) else { return true }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
            let focused = focusedRef
        else {
            return true // fail closed — assume editable
        }
        let element = focused as! AXUIElement
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String
        else {
            return true
        }
        let editable: Set<String> = [
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            "AXTextArea",
            "AXTextField",
            "AXComboBox",
        ]
        return editable.contains(role)
    }

    private func primaryWindowFrame(bundleID: String) -> (origin: CGPoint, size: CGSize)? {
        guard let app = runningApp(bundleID: bundleID) else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first
        else {
            return nil
        }
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef
        else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 200, size.height > 200
        else {
            return nil
        }
        return (origin, size)
    }

    private func runningApp(bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.activationPolicy == .regular })
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }
}
