import ApplicationServices
import AppKit
import CoreGraphics
import Domain
import Foundation

/// Best-effort Chrome / browser page inspector via Accessibility.
/// Reads roles, names, URLs, and frames only — never document body text for logs.
public struct ChromePageInspector: Sendable {
    public var maxNodes: Int
    public var maxDepth: Int

    public init(maxNodes: Int = 400, maxDepth: Int = 18) {
        self.maxNodes = maxNodes
        self.maxDepth = maxDepth
    }

    public func inspectFrontmostPage(bundleID: String) -> WebPageSnapshot? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.activationPolicy == .regular })
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first
        else {
            return nil
        }

        var title = stringAttribute(window, kAXTitleAttribute as String) ?? ""
        var url = ""
        var headings: [WebNavElement] = []
        var navigation: [WebNavElement] = []
        var links: [WebNavElement] = []
        var buttons: [WebNavElement] = []
        var pagination: [WebNavElement] = []
        var sections: [WebNavElement] = []

        var nodesVisited = 0
        walk(window, depth: 0, nodesVisited: &nodesVisited) { element, role, name, depth in
            _ = depth
            if role == "AXWebArea" || role == "AXDocument" {
                if let docURL = urlAttribute(element) {
                    url = docURL
                }
                if title.isEmpty, let t = stringAttribute(element, kAXTitleAttribute as String), !t.isEmpty {
                    title = t
                }
            }

            guard let center = frameCenter(element) else { return }

            let href = urlAttribute(element) ?? stringAttribute(element, "AXURL")
            let identitySeed = href ?? "\(role):\(name):\(Int(center.x)):\(Int(center.y))"
            let identity = URLNormalizer.normalize(href ?? "") 
            let id = identity.isEmpty ? identitySeed : identity

            let lowerName = name.lowercased()
            let isPagination =
                lowerName == "next" || lowerName == "previous" || lowerName == "prev"
                || lowerName.contains("next page") || lowerName.contains("load more")
                || (role == "AXLink" || role == "AXButton") && (
                    lowerName == "1" || lowerName == "2" || lowerName == "3"
                )

            let elementModel = WebNavElement(
                identity: id,
                role: mapRole(role, isPagination: isPagination),
                name: String(name.prefix(120)),
                href: href.map { URLNormalizer.normalize($0) },
                centerX: Double(center.x),
                centerY: Double(center.y)
            )

            switch role {
            case "AXHeading":
                headings.append(elementModel)
            case "AXLink":
                if isPagination {
                    pagination.append(elementModel)
                } else if looksLikeNav(name: name, role: role) {
                    navigation.append(elementModel)
                } else {
                    links.append(elementModel)
                }
            case "AXButton":
                if isPagination {
                    pagination.append(elementModel)
                } else {
                    buttons.append(elementModel)
                }
            case "AXTab", "AXTabGroup":
                sections.append(elementModel)
            case "AXDisclosureTriangle":
                var expandable = elementModel
                expandable = WebNavElement(
                    identity: elementModel.identity,
                    role: .expandable,
                    name: elementModel.name,
                    href: elementModel.href,
                    centerX: elementModel.centerX,
                    centerY: elementModel.centerY
                )
                sections.append(expandable)
            default:
                if looksLikeNav(name: name, role: role) {
                    navigation.append(elementModel)
                }
            }
        }

        // Address-bar fallback: some Chrome builds expose URL only on a text field.
        if url.isEmpty {
            url = findAddressBarURL(in: window) ?? ""
        }

        let kind = GitHubURLParser.pageKind(for: url)
        return WebPageSnapshot(
            url: URLNormalizer.normalize(url),
            title: String(title.prefix(160)),
            headings: Array(headings.prefix(40)),
            navigation: Array(navigation.prefix(60)),
            links: Array(links.prefix(120)),
            buttons: Array(buttons.prefix(40)),
            pagination: Array(pagination.prefix(20)),
            sections: Array(sections.prefix(40)),
            kind: kind,
            inspectedAt: Date()
        )
    }

    private func walk(
        _ element: AXUIElement,
        depth: Int,
        nodesVisited: inout Int,
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
            walk(child, depth: depth + 1, nodesVisited: &nodesVisited, visit: visit)
            if nodesVisited >= maxNodes { return }
        }
    }

    private func mapRole(_ role: String, isPagination: Bool) -> WebNavRole {
        if isPagination { return .pagination }
        switch role {
        case "AXLink": return .link
        case "AXButton": return .button
        case "AXHeading": return .heading
        case "AXDisclosureTriangle": return .expandable
        case "AXTab", "AXTabGroup", "AXMenuBar", "AXMenuItem": return .navigation
        default: return .unknown
        }
    }

    private func looksLikeNav(name: String, role: String) -> Bool {
        let lower = name.lowercased()
        if role.contains("Menu") || role == "AXTab" { return true }
        return lower.contains("nav") || lower.contains("menu") || lower.contains("sidebar")
            || lower.contains("contents") || lower.contains("table of contents")
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
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

    private func urlAttribute(_ element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        let attrs = ["AXURL", "AXDocument"]
        for attr in attrs {
            if AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
               let value = ref
            {
                if let url = value as? URL {
                    return url.absoluteString
                }
                if let s = value as? String, s.contains("://") || s.hasPrefix("/") {
                    return s
                }
            }
        }
        return nil
    }

    private func frameCenter(_ element: AXUIElement) -> CGPoint? {
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
        return CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }

    private func findAddressBarURL(in window: AXUIElement) -> String? {
        var nodesVisited = 0
        var found: String?
        walk(window, depth: 0, nodesVisited: &nodesVisited) { element, role, name, _ in
            guard found == nil else { return }
            if role == "AXTextField" || role == "AXComboBox" {
                if let value = stringAttribute(element, "AXValue"),
                   value.contains("://") || value.hasPrefix("www.")
                {
                    found = value
                }
            }
            _ = name
        }
        return found
    }
}

/// Live inspection source for the engine.
public struct LiveWebPageInspectionSource: WebPageInspectionSource {
    private let inspector: ChromePageInspector

    public init(inspector: ChromePageInspector = ChromePageInspector()) {
        self.inspector = inspector
    }

    public func inspectFrontmostPage(bundleID: String) -> WebPageSnapshot? {
        inspector.inspectFrontmostPage(bundleID: bundleID)
    }
}
