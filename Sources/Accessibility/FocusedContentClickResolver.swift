import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// Where within the window content to place a click (avoids racing to the bottom).
public enum ContentClickVerticalBand: Sendable {
    case full
    case upperMid
    case middle
}

/// Resolves a click point inside the frontmost window of a target app (content inset).
/// Uses window frame geometry only — never reads document text.
public struct FocusedContentClickResolver: Sendable {
    public init() {}

    /// Returns a point in global screen coordinates, or `nil` if the window cannot be resolved.
    public func resolvePoint(
        bundleID: String,
        randomize: Bool = true,
        verticalBand: ContentClickVerticalBand = .full
    ) -> CGPoint? {
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
        // Leave room for the left sidebar so content clicks hit the editor.
        let insetTop: CGFloat = 88
        let insetLeft: CGFloat = max(200, size.width * 0.28)
        let insetSide: CGFloat = 40
        let insetBottom: CGFloat = 48
        let minX = origin.x + insetLeft
        let maxX = origin.x + size.width - insetSide
        let minY = origin.y + insetTop
        let maxY = origin.y + size.height - insetBottom
        guard maxX > minX, maxY > minY else {
            return CGPoint(x: origin.x + size.width * 0.6, y: origin.y + size.height * 0.35)
        }

        let (yLo, yHi): (CGFloat, CGFloat)
        switch verticalBand {
        case .full:
            yLo = minY
            yHi = maxY
        case .upperMid:
            // Top ~55% of the content — never the bottom strip.
            yLo = minY
            yHi = minY + (maxY - minY) * 0.55
        case .middle:
            yLo = minY + (maxY - minY) * 0.25
            yHi = minY + (maxY - minY) * 0.65
        }

        if randomize {
            let tx = CGFloat.random(in: 0.2...0.8)
            let ty = CGFloat.random(in: 0.15...0.85)
            return CGPoint(
                x: minX + (maxX - minX) * tx,
                y: yLo + (yHi - yLo) * ty
            )
        }
        return CGPoint(x: (minX + maxX) / 2, y: (yLo + yHi) / 2)
    }
}
