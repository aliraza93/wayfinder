import ApplicationServices
import AppKit
import CoreGraphics
import Domain
import Foundation

/// Best-effort Chrome / browser page inspector via Accessibility.
///
/// Architectural boundary:
/// - Discovers tabs/windows for **read-only** listing (surface = browserUI — never activated).
/// - Collects clickable candidates **only** from AXWebArea / AXDocument (page content).
/// Never logs document body text.
public struct ChromePageInspector: Sendable {
    public var maxNodes: Int
    public var maxDepth: Int

    public init(maxNodes: Int = 900, maxDepth: Int = 24) {
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
              let window = preferredWindow(windows)
        else {
            return nil
        }

        var title = ChromeBrowserUIDetector.stringAttribute(window, kAXTitleAttribute as String) ?? ""
        var url = ""
        var headings: [WebNavElement] = []
        var navigation: [WebNavElement] = []
        var links: [WebNavElement] = []
        var buttons: [WebNavElement] = []
        var pagination: [WebNavElement] = []
        var sections: [WebNavElement] = []
        var tabs: [WebNavElement] = []
        var scrollContainers: [WebNavElement] = []
        var tabGroups: [ChromeTabGroup] = []

        // 1) Establish content boundary before any candidate collection.
        let webAreaInfo = ChromeBrowserUIDetector.findWebAreaBounds(in: window)
        let webBounds = webAreaInfo?.bounds

        // 2) Read-only tab + tab-group discovery from the window (browser UI — never activated).
        var tabNodes = 0
        var discoveredGroupTitles: [String] = []
        ChromeBrowserUIDetector.walk(
            window,
            depth: 0,
            nodesVisited: &tabNodes,
            maxNodes: min(280, maxNodes),
            maxDepth: 14
        ) { element, role, name, _ in
            // Best-effort: Chrome sometimes exposes group headers as groups / static text near tabs.
            // We never collapse, rename, or click these — identity listing only.
            if role == "AXGroup" || role == "AXStaticText" {
                let lower = name.lowercased()
                if !name.isEmpty,
                   (lower.contains("group") || role == "AXGroup"),
                   name.count <= 80,
                   !ChromeBrowserUINames.matches(name: name)
                {
                    if !discoveredGroupTitles.contains(name) {
                        discoveredGroupTitles.append(name)
                    }
                }
            }
            guard role == "AXTab" else { return }
            guard let center = ChromeBrowserUIDetector.frameCenter(element) else { return }
            let tab = WebNavElement(
                identity: "tab:\(name.isEmpty ? "\(Int(center.x)):\(Int(center.y))" : name)",
                role: .tab,
                name: name.isEmpty ? "Tab" : String(name.prefix(120)),
                href: nil,
                centerX: Double(center.x),
                centerY: Double(center.y),
                surface: .browserUI,
                classification: .browserUI
            )
            tabs.append(tab)
        }
        // Fallback: if AX does not expose real group membership, record titled groups without inventing tab membership.
        tabGroups = discoveredGroupTitles.prefix(16).enumerated().map { index, groupTitle in
            ChromeTabGroup(
                id: "group:\(index):\(groupTitle)",
                title: groupTitle,
                color: "",
                collapsed: false,
                tabIdentities: []
            )
        }

        // 3) Walk page content only when WebArea exists.
        if let webRoot = webAreaInfo?.element {
            if let docURL = urlAttribute(webRoot) {
                url = docURL
            }
            if title.isEmpty,
               let t = ChromeBrowserUIDetector.stringAttribute(webRoot, kAXTitleAttribute as String),
               !t.isEmpty
            {
                title = t
            }

            var nodesVisited = 0
            ChromeBrowserUIDetector.walk(
                webRoot,
                depth: 0,
                nodesVisited: &nodesVisited,
                maxNodes: maxNodes,
                maxDepth: maxDepth
            ) { element, role, name, depth in
                _ = depth
                if role == "AXWebArea" || role == "AXDocument" {
                    if let docURL = urlAttribute(element) {
                        url = docURL
                    }
                    return
                }

                guard let center = ChromeBrowserUIDetector.frameCenter(element) else { return }
                let surface = ChromeBrowserUIDetector.classify(
                    role: role,
                    name: name,
                    center: center,
                    webArea: webBounds
                )
                // Refuse anything the detector still marks as chrome (defensive).
                guard surface == .pageContent else { return }

                let href = urlAttribute(element) ?? ChromeBrowserUIDetector.stringAttribute(element, "AXURL")
                let identitySeed = href ?? "\(role):\(name):\(Int(center.x)):\(Int(center.y))"
                let identity = URLNormalizer.normalize(href ?? "")
                let id = identity.isEmpty ? identitySeed : identity
                let isPagination = Self.isPaginationName(name, role: role)
                let mappedRole = mapRole(role, isPagination: isPagination)

                var model = WebNavElement(
                    identity: id,
                    role: mappedRole,
                    name: String(name.prefix(120)),
                    href: href.map { URLNormalizer.normalize($0) },
                    centerX: Double(center.x),
                    centerY: Double(center.y),
                    surface: .pageContent,
                    classification: .unknown
                )
                // Classification filled after URL/kind known — provisional here.
                model.classification = .unknown

                switch role {
                case "AXHeading":
                    headings.append(model)
                case "AXLink":
                    if isPagination {
                        pagination.append(model)
                    } else if looksLikeNav(name: name, role: role) {
                        navigation.append(model)
                    } else {
                        links.append(model)
                    }
                case "AXButton":
                    // Buttons inside the page are collected but scorer refuses actionButton/unknown.
                    if isPagination {
                        pagination.append(model)
                    } else if looksLikeNav(name: name, role: role) {
                        navigation.append(model)
                    } else {
                        buttons.append(model)
                    }
                case "AXScrollArea":
                    scrollContainers.append(
                        WebNavElement(
                            identity: "scroll:\(Int(center.x)):\(Int(center.y))",
                            role: .scrollContainer,
                            name: name.isEmpty ? "Scroll area" : String(name.prefix(80)),
                            href: nil,
                            centerX: Double(center.x),
                            centerY: Double(center.y),
                            surface: .pageContent,
                            classification: .unknown
                        )
                    )
                case "AXDisclosureTriangle":
                    sections.append(
                        WebNavElement(
                            identity: model.identity,
                            role: .expandable,
                            name: model.name,
                            href: model.href,
                            centerX: model.centerX,
                            centerY: model.centerY,
                            surface: .pageContent,
                            classification: .unknown
                        )
                    )
                default:
                    // In-page menus and GitHub file rows.
                    if role == "AXMenuItem" || role == "AXMenu" {
                        var navModel = model
                        navModel.role = .navigation
                        navigation.append(navModel)
                    } else if looksLikeRepoEntry(name: name, href: href) {
                        var linkModel = model
                        linkModel.role = .link
                        links.append(linkModel)
                    } else if looksLikeNav(name: name, role: role) {
                        navigation.append(model)
                    }
                }
            }
        }

        // Address-bar fallback for URL only (read — never click).
        if url.isEmpty {
            url = findAddressBarURL(in: window) ?? ""
        }

        let kind = GitHubURLParser.pageKind(for: url)
        let pageURL = URLNormalizer.normalize(url)

        func classifyList(_ items: [WebNavElement]) -> [WebNavElement] {
            items.map { el in
                var copy = el
                copy.classification = WebElementClassifier.classify(
                    name: el.name,
                    href: el.href,
                    role: el.role,
                    surface: el.surface,
                    pageURL: pageURL,
                    pageKind: kind
                )
                return copy
            }
        }

        var snapshot = WebPageSnapshot(
            url: pageURL,
            title: String(title.prefix(160)),
            headings: Array(classifyList(headings).prefix(40)),
            navigation: Array(classifyList(navigation).prefix(80)),
            links: Array(classifyList(links).prefix(180)),
            buttons: Array(classifyList(buttons).prefix(40)),
            pagination: Array(classifyList(pagination).prefix(24)),
            sections: Array(classifyList(sections).prefix(40)),
            tabs: Array(tabs.prefix(40)),
            scrollContainers: Array(scrollContainers.prefix(12)),
            kind: kind,
            inspectedAt: Date()
        )
        // Attach tab groups via a side channel on the crawl session (inspector returns snapshot only).
        // Group titles are recorded in tabs metadata as synthetic browserUI entries for debugging.
        if !tabGroups.isEmpty {
            let groupMeta = tabGroups.map {
                WebNavElement(
                    identity: $0.id,
                    role: .tab,
                    name: "Tab group: \($0.title)",
                    href: nil,
                    centerX: 0,
                    centerY: 0,
                    surface: .browserUI,
                    classification: .browserUI
                )
            }
            snapshot.tabs.append(contentsOf: groupMeta.prefix(16))
        }
        return snapshot
    }

    private func preferredWindow(_ windows: [AXUIElement]) -> AXUIElement? {
        for window in windows.prefix(8) {
            var mainRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMainAttribute as CFString, &mainRef) == .success,
               let number = mainRef as? NSNumber,
               number.boolValue
            {
                return window
            }
        }
        return windows.first
    }

    private func mapRole(_ role: String, isPagination: Bool) -> WebNavRole {
        if isPagination { return .pagination }
        switch role {
        case "AXLink": return .link
        case "AXButton": return .button
        case "AXHeading": return .heading
        case "AXDisclosureTriangle": return .expandable
        case "AXTab": return .tab
        case "AXScrollArea": return .scrollContainer
        default: return .unknown
        }
    }

    static func isPaginationName(_ name: String, role: String) -> Bool {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty { return false }
        if lower == "next" || lower == "previous" || lower == "prev" { return true }
        if lower == "→" || lower == "›" || lower == "←" || lower == "‹" { return true }
        if lower.contains("next page") || lower.contains("previous page") { return true }
        if lower.contains("load more") || lower == "more" || lower.contains("show more") { return true }
        if role == "AXLink" || role == "AXButton" {
            if lower.count <= 3, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: lower)) {
                return true
            }
        }
        return false
    }

    private func looksLikeNav(name: String, role: String) -> Bool {
        let lower = name.lowercased()
        if role.contains("Menu") { return true }
        return lower.contains("nav") || lower.contains("menu") || lower.contains("sidebar")
            || lower.contains("contents") || lower.contains("table of contents")
            || lower == "toc"
    }

    private func looksLikeRepoEntry(name: String, href: String?) -> Bool {
        if let href, href.contains("/blob/") || href.contains("/tree/") { return true }
        if GitHubURLParser.isSourceFilePath(name) { return true }
        if name.hasSuffix("/") { return true }
        let lower = name.lowercased()
        let known = ["app", "src", "lib", "tests", "routes", "config", "database", "resources", "public", "docs"]
        return known.contains(lower)
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

    private func findAddressBarURL(in window: AXUIElement) -> String? {
        var nodesVisited = 0
        var found: String?
        ChromeBrowserUIDetector.walk(
            window,
            depth: 0,
            nodesVisited: &nodesVisited,
            maxNodes: 200,
            maxDepth: 14
        ) { element, role, name, _ in
            guard found == nil else { return }
            if role == "AXTextField" || role == "AXComboBox" {
                if let value = ChromeBrowserUIDetector.stringAttribute(element, "AXValue"),
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
