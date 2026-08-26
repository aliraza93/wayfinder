import Foundation

/// Kind of discoverable navigation surface (read-only discovery — never mutates).
public enum NavigationTargetKind: String, Equatable, Sendable, Codable, CaseIterable {
    case application
    case window
    case file
    case tab
    case document
    case navigation

    public var displayTitle: String {
        switch self {
        case .application: return "Applications"
        case .window: return "Windows"
        case .file: return "Files"
        case .tab: return "Tabs"
        case .document: return "Documents"
        case .navigation: return "Navigation targets"
        }
    }
}

/// Accessibility readability for a discovered app (coarse — no document body).
public enum DiscoveryAccessibilityStatus: String, Equatable, Sendable, Codable {
    case readable
    case limited
    case unavailable

    public var title: String {
        switch self {
        case .readable: return "Readable"
        case .limited: return "Limited"
        case .unavailable: return "Unavailable"
        }
    }
}

/// Normalized navigation target from workspace discovery.
/// User must approve before a workflow may use it.
public struct NavigationTarget: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: NavigationTargetKind
    public var displayName: String
    public var bundleID: String
    public var processID: Int32?
    public var windowTitle: String?
    /// Optional path/URL identity (never document body).
    public var identityPath: String?
    public var classification: TargetAppClass
    public var accessibilityStatus: DiscoveryAccessibilityStatus
    public var approved: Bool

    public init(
        id: String = UUID().uuidString,
        kind: NavigationTargetKind,
        displayName: String,
        bundleID: String,
        processID: Int32? = nil,
        windowTitle: String? = nil,
        identityPath: String? = nil,
        classification: TargetAppClass,
        accessibilityStatus: DiscoveryAccessibilityStatus = .limited,
        approved: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bundleID = bundleID
        self.processID = processID
        self.windowTitle = windowTitle
        self.identityPath = identityPath
        self.classification = classification
        self.accessibilityStatus = accessibilityStatus
        self.approved = approved
    }
}

/// One window observed during discovery (title = chrome identity, not body text).
public struct DiscoveredWindowInfo: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var index: Int

    public init(id: String = UUID().uuidString, title: String, index: Int) {
        self.id = id
        self.title = title
        self.index = index
    }
}

/// One application and its discovered surfaces.
public struct DiscoveredAppDetail: Equatable, Sendable, Identifiable {
    public var id: String { bundleID }
    public var displayName: String
    public var bundleID: String
    public var processID: Int32
    public var classification: TargetAppClass
    public var isActive: Bool
    public var accessibilityStatus: DiscoveryAccessibilityStatus
    public var windows: [DiscoveredWindowInfo]
    public var targets: [NavigationTarget]

    public init(
        displayName: String,
        bundleID: String,
        processID: Int32,
        classification: TargetAppClass,
        isActive: Bool,
        accessibilityStatus: DiscoveryAccessibilityStatus,
        windows: [DiscoveredWindowInfo],
        targets: [NavigationTarget]
    ) {
        self.displayName = displayName
        self.bundleID = bundleID
        self.processID = processID
        self.classification = classification
        self.isActive = isActive
        self.accessibilityStatus = accessibilityStatus
        self.windows = windows
        self.targets = targets
    }
}

/// Full workspace discovery snapshot (read-only).
public struct WorkspaceDiscoverySnapshot: Equatable, Sendable {
    public var scannedAt: Date
    public var apps: [DiscoveredAppDetail]

    public init(scannedAt: Date = Date(), apps: [DiscoveredAppDetail] = []) {
        self.scannedAt = scannedAt
        self.apps = apps
    }

    public var allTargets: [NavigationTarget] {
        apps.flatMap(\.targets)
    }

    public var approvedTargets: [NavigationTarget] {
        allTargets.filter(\.approved)
    }

    public mutating func setApproved(_ id: String, approved: Bool) {
        for ai in apps.indices {
            for ti in apps[ai].targets.indices where apps[ai].targets[ti].id == id {
                apps[ai].targets[ti].approved = approved
            }
        }
    }

    public mutating func setAllApproved(_ approved: Bool) {
        for ai in apps.indices {
            for ti in apps[ai].targets.indices {
                apps[ai].targets[ti].approved = approved
            }
        }
    }

    public func targets(ofKind kind: NavigationTargetKind) -> [NavigationTarget] {
        allTargets.filter { $0.kind == kind }
    }
}

/// Pure ranking / target synthesis for discovery (no AppKit).
public enum WorkspaceDiscoveryPlanner: Sendable {
    /// Lower = higher priority in the Discovery list.
    public static func priority(bundleID: String, classification: TargetAppClass) -> Int {
        if bundleID.hasPrefix("com.todesktop.") { return 0 } // Cursor
        if bundleID.hasPrefix("com.google.Chrome") { return 1 }
        if bundleID == "com.apple.finder" { return 2 }
        if bundleID == "com.apple.Preview" { return 3 }
        if bundleID == "com.apple.Safari" { return 4 }
        switch classification {
        case .editor: return 5
        case .browser: return 6
        case .finder: return 7
        case .generic: return ApplicationClassifier.isPreview(bundleID: bundleID) ? 3 : 10
        }
    }

    public static func sortApps(_ apps: [DiscoveredAppDetail]) -> [DiscoveredAppDetail] {
        apps.sorted {
            let p0 = priority(bundleID: $0.bundleID, classification: $0.classification)
            let p1 = priority(bundleID: $1.bundleID, classification: $1.classification)
            if p0 != p1 { return p0 < p1 }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Adapter-style target discovery from window titles only (read-only, no activation).
    public static func discoverTargets(
        displayName: String,
        bundleID: String,
        processID: Int32,
        classification: TargetAppClass,
        accessibilityStatus: DiscoveryAccessibilityStatus,
        windows: [DiscoveredWindowInfo]
    ) -> [NavigationTarget] {
        var targets: [NavigationTarget] = []
        var seen = Set<String>()

        func append(_ target: NavigationTarget) {
            let key = "\(target.kind.rawValue)|\(target.displayName.lowercased())|\(target.bundleID)"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            targets.append(target)
        }

        append(
            NavigationTarget(
                kind: .application,
                displayName: displayName,
                bundleID: bundleID,
                processID: processID,
                classification: classification,
                accessibilityStatus: accessibilityStatus,
                approved: false
            )
        )

        for window in windows {
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            append(
                NavigationTarget(
                    kind: .window,
                    displayName: title,
                    bundleID: bundleID,
                    processID: processID,
                    windowTitle: title,
                    classification: classification,
                    accessibilityStatus: accessibilityStatus,
                    approved: false
                )
            )

            switch classification {
            case .editor:
                for fileName in editorFileHints(from: title) {
                    append(
                        NavigationTarget(
                            kind: .file,
                            displayName: fileName,
                            bundleID: bundleID,
                            processID: processID,
                            windowTitle: title,
                            identityPath: fileName,
                            classification: classification,
                            accessibilityStatus: accessibilityStatus,
                            approved: false
                        )
                    )
                }
            case .browser:
                append(
                    NavigationTarget(
                        kind: .tab,
                        displayName: shortenTitle(title),
                        bundleID: bundleID,
                        processID: processID,
                        windowTitle: title,
                        classification: classification,
                        accessibilityStatus: accessibilityStatus,
                        approved: false
                    )
                )
                append(
                    NavigationTarget(
                        kind: .navigation,
                        displayName: shortenTitle(title),
                        bundleID: bundleID,
                        processID: processID,
                        windowTitle: title,
                        classification: classification,
                        accessibilityStatus: accessibilityStatus,
                        approved: false
                    )
                )
            case .finder:
                append(
                    NavigationTarget(
                        kind: .document,
                        displayName: shortenTitle(title),
                        bundleID: bundleID,
                        processID: processID,
                        windowTitle: title,
                        identityPath: title,
                        classification: classification,
                        accessibilityStatus: accessibilityStatus,
                        approved: false
                    )
                )
            case .generic:
                if ApplicationClassifier.isPreview(bundleID: bundleID) {
                    append(
                        NavigationTarget(
                            kind: .document,
                            displayName: shortenTitle(title),
                            bundleID: bundleID,
                            processID: processID,
                            windowTitle: title,
                            identityPath: title,
                            classification: classification,
                            accessibilityStatus: accessibilityStatus,
                            approved: false
                        )
                    )
                } else {
                    append(
                        NavigationTarget(
                            kind: .navigation,
                            displayName: shortenTitle(title),
                            bundleID: bundleID,
                            processID: processID,
                            windowTitle: title,
                            classification: classification,
                            accessibilityStatus: accessibilityStatus,
                            approved: false
                        )
                    )
                }
            }
        }

        return targets
    }

    /// Cursor/VS Code titles often look like `File.swift — Workspace` or `Workspace — File.swift`.
    private static func editorFileHints(from title: String) -> [String] {
        let separators = [" — ", " - ", " – ", " | "]
        var parts = [title]
        for sep in separators {
            if title.contains(sep) {
                parts = title.components(separatedBy: sep)
                break
            }
        }
        let candidates = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var files: [String] = []
        for part in candidates {
            let name = (part as NSString).lastPathComponent
            if looksLikeFileName(name) {
                files.append(name)
            }
        }
        return files
    }

    private static func looksLikeFileName(_ name: String) -> Bool {
        let lower = name.lowercased()
        let exts = [
            ".swift", ".ts", ".tsx", ".js", ".jsx", ".py", ".rb", ".go", ".rs",
            ".java", ".kt", ".php", ".cs", ".md", ".json", ".yml", ".yaml",
            ".html", ".css", ".scss", ".txt", ".sh", ".sql", ".c", ".h", ".cpp",
        ]
        return exts.contains { lower.hasSuffix($0) }
    }

    private static func shortenTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(77)) + "…"
    }
}
