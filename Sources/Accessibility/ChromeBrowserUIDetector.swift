import ApplicationServices
import AppKit
import CoreGraphics
import Domain
import Foundation

/// Classifies Chrome-owned UI vs web page content. Used by the inspector and ActionExecutor.
public enum ChromeBrowserUIDetector: Sendable {
    public struct WebAreaBounds: Equatable, Sendable {
        public var originX: Double
        public var originY: Double
        public var width: Double
        public var height: Double

        public init(originX: Double, originY: Double, width: Double, height: Double) {
            self.originX = originX
            self.originY = originY
            self.width = width
            self.height = height
        }

        public var cgRect: CGRect {
            CGRect(x: originX, y: originY, width: width, height: height)
        }

        public func contains(x: Double, y: Double, inset: Double = 2) -> Bool {
            let r = cgRect.insetBy(dx: inset, dy: inset)
            return r.contains(CGPoint(x: x, y: y))
        }
    }

    /// Roles that are Chrome chrome even when names are empty.
    private static let browserRoles: Set<String> = [
        "AXTab",
        "AXTabGroup",
        "AXToolbar",
        "AXMenuBar",
        "AXMenuBarItem",
        "AXMenu",
        "AXMenuItem",
    ]

    public static func classify(
        role: String,
        name: String,
        center: CGPoint?,
        webArea: WebAreaBounds?
    ) -> WebNavSurface {
        if browserRoles.contains(role) {
            return .browserUI
        }
        let mappedRole: WebNavRole
        switch role {
        case "AXLink": mappedRole = .link
        case "AXButton": mappedRole = .button
        case "AXTab": mappedRole = .tab
        default: mappedRole = .unknown
        }
        if ChromeBrowserUINames.matches(name: name, role: mappedRole) {
            return .browserUI
        }
        if let webArea, let center {
            // Above the web content = toolbar / tab strip / omnibox.
            if Double(center.y) < webArea.originY - 1 {
                return .browserUI
            }
            if !webArea.contains(x: Double(center.x), y: Double(center.y), inset: 0) {
                // Outside web area (side chrome, bookmarks bar, etc.).
                return .browserUI
            }
            return .pageContent
        }
        // Without a WebArea we cannot safely activate — treat as unknown (refuse later).
        return .unknown
    }

    public static func findWebAreaBounds(in window: AXUIElement) -> (element: AXUIElement, bounds: WebAreaBounds)? {
        var nodes = 0
        var found: (AXUIElement, WebAreaBounds)?
        walk(window, depth: 0, nodesVisited: &nodes, maxNodes: 400, maxDepth: 18) { element, role, _, _ in
            guard found == nil else { return }
            if role == "AXWebArea" || role == "AXDocument" {
                if let bounds = frameBounds(element) {
                    found = (element, bounds)
                }
            }
        }
        return found
    }

    public static func isPointInsideWebArea(bundleID: String, x: Double, y: Double) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.activationPolicy == .regular })
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else {
            return false
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first
        else {
            return false
        }
        guard let web = findWebAreaBounds(in: window) else {
            return false
        }
        return web.bounds.contains(x: x, y: y, inset: 4)
    }

    // MARK: - AX helpers (shared with inspector)

    static func walk(
        _ element: AXUIElement,
        depth: Int,
        nodesVisited: inout Int,
        maxNodes: Int,
        maxDepth: Int,
        visit: (AXUIElement, String, String, Int) -> Void
    ) {
        guard depth <= maxDepth, nodesVisited < maxNodes else { return }
        nodesVisited += 1
        let role = stringAttribute(element, kAXRoleAttribute as String) ?? ""
        let name = stringAttribute(element, kAXTitleAttribute as String)
            ?? stringAttribute(element, kAXDescriptionAttribute as String)
            ?? stringAttribute(element, "AXValue")
            ?? ""
        visit(element, role, name, depth)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else {
            return
        }
        for child in children.prefix(80) {
            walk(child, depth: depth + 1, nodesVisited: &nodesVisited, maxNodes: maxNodes, maxDepth: maxDepth, visit: visit)
            if nodesVisited >= maxNodes { return }
        }
    }

    static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref
        else {
            return nil
        }
        if let s = value as? String { return s }
        if CFGetTypeID(value) == CFStringGetTypeID() {
            return value as? String
        }
        return nil
    }

    static func frameBounds(_ element: AXUIElement) -> WebAreaBounds? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef
        else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width >= 4, size.height >= 4
        else {
            return nil
        }
        return WebAreaBounds(
            originX: Double(origin.x),
            originY: Double(origin.y),
            width: Double(size.width),
            height: Double(size.height)
        )
    }

    static func frameCenter(_ element: AXUIElement) -> CGPoint? {
        guard let b = frameBounds(element) else { return nil }
        return CGPoint(x: b.originX + b.width / 2, y: b.originY + b.height / 2)
    }
}
