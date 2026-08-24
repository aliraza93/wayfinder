import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// Resolves a click point inside the frontmost window of a target app (content inset).
/// Uses window frame geometry only — never reads document text.
public struct FocusedContentClickResolver: Sendable {
    public init() {}

    /// Returns a point in global screen coordinates, or `nil` if the window cannot be resolved.
    public func resolvePoint(bundleID: String, randomize: Bool = true) -> CGPoint? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.activationPolicy == .regular })
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard status == .success, let windows = windowsRef as? [AXUIElement], let window = windows.first else {
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
              size.width > 80, size.height > 120
        else {
            return nil
        }

        // Inset away from title bar / edges — stay in document/page chrome.
        let insetTop: CGFloat = 72
        let insetSide: CGFloat = 48
        let insetBottom: CGFloat = 40
        let minX = origin.x + insetSide
        let maxX = origin.x + size.width - insetSide
        let minY = origin.y + insetTop
        let maxY = origin.y + size.height - insetBottom
        guard maxX > minX, maxY > minY else {
            return CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        }

        if randomize {
            let tx = CGFloat.random(in: 0.25...0.75)
            let ty = CGFloat.random(in: 0.25...0.75)
            return CGPoint(
                x: minX + (maxX - minX) * tx,
                y: minY + (maxY - minY) * ty
            )
        }
        return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }
}
