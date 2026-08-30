import Foundation

/// Default single workflow — one orchestrator for the whole workspace.
public enum UniversalWorkspaceNavigation {
    public static let workflowName = "Universal Workspace Navigation"
}

/// Legacy alias kept so older configs/UI strings still resolve.
public enum ReadAndReviewWorkspace {
    public static let workflowName = UniversalWorkspaceNavigation.workflowName
}

/// How configured / discovered targets are ordered.
public enum ReviewTargetOrder: String, Equatable, Sendable, CaseIterable {
    /// Files → tabs → apps, interleaved by app class so Cursor↔Chrome both get turns.
    case sequential
    /// Shuffle then interleave by app class.
    case random
    /// Keep configured Targets / files / tabs order (no class interleave).
    case configuredPriority
    /// Prefer Cursor → Chrome → Finder → Preview → Safari → others.
    case applicationPriority
    /// Prefer least-visited identities this session (rotation).
    case targetRotation

    public var title: String {
        switch self {
        case .sequential: return "Sequential"
        case .random: return "Random order"
        case .configuredPriority: return "Configured priority"
        case .applicationPriority: return "Application priority"
        case .targetRotation: return "Target rotation"
        }
    }
}

/// Deliberate navigation pacing profiles (not for imitating human activity monitors).
public enum NavigationPacingProfile: String, Equatable, Sendable, CaseIterable, Identifiable {
    case relaxed
    case deliberate
    case normal
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .deliberate: return "Deliberate"
        case .normal: return "Normal"
        case .custom: return "Custom"
        }
    }
}

/// User-tunable pacing when profile is `.custom`.
public struct NavigationPacingCustom: Equatable, Sendable {
    public var minReviewSeconds: Double
    public var maxReviewSeconds: Double
    public var scrollIntervalSeconds: Double
    public var navigationPauseSeconds: Double
    public var pageTransitionPauseSeconds: Double
    public var maxConsecutiveActions: Int

    public init(
        minReviewSeconds: Double = 20,
        maxReviewSeconds: Double = 300,
        scrollIntervalSeconds: Double = 1.4,
        navigationPauseSeconds: Double = 1.8,
        pageTransitionPauseSeconds: Double = 2.0,
        maxConsecutiveActions: Int = 3
    ) {
        self.minReviewSeconds = minReviewSeconds
        self.maxReviewSeconds = maxReviewSeconds
        self.scrollIntervalSeconds = scrollIntervalSeconds
        self.navigationPauseSeconds = navigationPauseSeconds
        self.pageTransitionPauseSeconds = pageTransitionPauseSeconds
        self.maxConsecutiveActions = maxConsecutiveActions
    }

    public static let `default` = NavigationPacingCustom()

    public mutating func normalize() {
        minReviewSeconds = min(max(5, minReviewSeconds), 600)
        maxReviewSeconds = min(max(10, maxReviewSeconds), 1_800)
        if minReviewSeconds >= maxReviewSeconds {
            maxReviewSeconds = minReviewSeconds + 1
        }
        scrollIntervalSeconds = min(max(0.2, scrollIntervalSeconds), 8)
        navigationPauseSeconds = min(max(0.2, navigationPauseSeconds), 8)
        pageTransitionPauseSeconds = min(max(0.2, pageTransitionPauseSeconds), 10)
        maxConsecutiveActions = min(max(1, maxConsecutiveActions), 12)
    }
}

/// Legacy speed labels kept for Codable migration of older workflows.
public enum NavigationSpeedPreset: String, Equatable, Sendable, CaseIterable, Identifiable {
    case slow
    case normal
    case fast
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        case .custom: return "Custom"
        }
    }

    public var defaultIntervalSeconds: Double {
        switch self {
        case .slow: return 0.85
        case .normal: return 0.35
        case .fast: return 0.12
        case .custom: return 0.35
        }
    }

    /// Maps archived Speed values onto Navigation Pacing.
    public var asPacingProfile: NavigationPacingProfile {
        switch self {
        case .slow: return .relaxed
        case .normal: return .normal
        case .fast: return .normal
        case .custom: return .custom
        }
    }
}

/// Optional extras beyond the Targets allowlist when “discover open apps” is on.
/// Editors/browsers always come from the Targets list — never every open IDE/browser.
public struct DiscoveryScope: Equatable, Sendable {
    /// Kept for config compatibility; editors are allowlist-only (see `NavigationAppPolicy`).
    public var includeEditors: Bool
    /// Kept for config compatibility; browsers are allowlist-only.
    public var includeBrowsers: Bool
    public var includeFinder: Bool
    public var includePreview: Bool
    public var includeOther: Bool

    public init(
        includeEditors: Bool = true,
        includeBrowsers: Bool = true,
        includeFinder: Bool = false,
        includePreview: Bool = false,
        includeOther: Bool = false
    ) {
        self.includeEditors = includeEditors
        self.includeBrowsers = includeBrowsers
        self.includeFinder = includeFinder
        self.includePreview = includePreview
        self.includeOther = includeOther
    }

    public static let `default` = DiscoveryScope()

    public func allows(_ classification: TargetAppClass, bundleID: String) -> Bool {
        switch classification {
        case .editor: return includeEditors
        case .browser: return includeBrowsers
        case .finder: return includeFinder
        case .generic:
            if ApplicationClassifier.isPreview(bundleID: bundleID) {
                return includePreview
            }
            return includeOther
        }
    }
}

/// Hard rules: Targets allowlist + never crawl system prefs / Waypoint / etc.
public enum NavigationAppPolicy: Sendable {
    /// Bundle IDs that must never be navigation targets (even if “other apps” is on).
    public static let forbiddenBundleIDs: Set<String> = [
        "com.twixrsolutions.waypoint",
        "com.apple.systempreferences",
        "com.apple.Preferences",
        "com.apple.Setting.Accessibility",
        "com.apple.preference.security",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.Spotlight",
        "com.apple.TextInputMenuAgent",
        "com.apple.siri.Siri",
        "com.apple.Siri",
        "com.apple.ActivityMonitor",
    ]

    public static func isForbidden(_ bundleID: String) -> Bool {
        if forbiddenBundleIDs.contains(bundleID) { return true }
        if bundleID.hasPrefix("com.apple.preference") { return true }
        if bundleID.hasPrefix("com.apple.Setting") { return true }
        if bundleID.hasPrefix("com.apple.systempreferences") { return true }
        return false
    }

    /// Whether a live-discovered app may enter the queue.
    /// Editors/browsers: only if listed in Targets. Finder/Preview/Other: scope flags only.
    public static func allowsDiscovered(
        _ app: DiscoveredApplication,
        settings: ReviewWorkspaceSettings,
        workflowTargets: [TargetApp]
    ) -> Bool {
        let bundleID = app.bundleID
        if isForbidden(bundleID) { return false }

        let allowlist = Set(workflowTargets.map(\.bundleID))
        if allowlist.contains(bundleID) {
            return true
        }

        switch app.classification {
        case .editor, .browser:
            // Never auto-add Xcode/Safari/etc. — must be an explicit Target.
            return false
        case .finder:
            return settings.discovery.includeFinder
        case .generic:
            if ApplicationClassifier.isPreview(bundleID: bundleID) {
                return settings.discovery.includePreview
            }
            return settings.discovery.includeOther
        }
    }
}

/// Pure bundle-id → class heuristics (no AppKit).
public enum ApplicationClassifier: Sendable {
    public static func classify(bundleID: String) -> TargetAppClass {
        if isEditor(bundleID: bundleID) { return .editor }
        if isBrowser(bundleID: bundleID) { return .browser }
        if isFinder(bundleID: bundleID) { return .finder }
        return .generic
    }

    public static func isEditor(bundleID: String) -> Bool {
        bundleID.hasPrefix("com.microsoft.VSCode")
            || bundleID.hasPrefix("com.visualstudio.code")
            || bundleID.hasPrefix("com.todesktop.")
            || bundleID == "com.apple.dt.Xcode"
    }

    public static func isBrowser(bundleID: String) -> Bool {
        bundleID.hasPrefix("com.google.Chrome")
            || bundleID == "com.apple.Safari"
            || bundleID.hasPrefix("company.thebrowser.Browser") // Arc
            || bundleID == "com.brave.Browser"
            || bundleID == "org.mozilla.firefox"
    }

    public static func isFinder(bundleID: String) -> Bool {
        bundleID == "com.apple.finder"
    }

    public static func isPreview(bundleID: String) -> Bool {
        bundleID == "com.apple.Preview"
    }
}

/// Snapshot of a user-facing app suitable for navigation planning (Domain-safe).
public struct DiscoveredApplication: Equatable, Sendable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var displayName: String
    public var classification: TargetAppClass
    public var isActive: Bool

    public init(
        bundleID: String,
        displayName: String,
        classification: TargetAppClass,
        isActive: Bool
    ) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.classification = classification
        self.isActive = isActive
    }
}

/// User settings for the universal navigation session.
public struct ReviewWorkspaceSettings: Equatable, Sendable {
    public var workspacePath: String
    public var filePaths: [String]
    public var chromeTabLabels: [String]
    public var dwellMinSeconds: Double
    public var dwellMaxSeconds: Double
    /// Navigation pacing profile (replaces legacy Speed).
    public var pacing: NavigationPacingProfile
    public var pacingCustom: NavigationPacingCustom
    /// Legacy Speed field — synced from `pacing` for older readers; prefer `pacing`.
    public var speed: NavigationSpeedPreset
    /// Legacy single interval — maps to custom scroll interval when pacing is `.custom`.
    public var customIntervalSeconds: Double
    public var targetOrder: ReviewTargetOrder
    public var loopTargets: Bool
    /// When true, discover running apps and merge them into the queue.
    public var discoverRunningApps: Bool
    public var discovery: DiscoveryScope
    /// Re-scan running apps between targets during long sessions.
    public var refreshTargetsBetweenDwells: Bool
    /// Smart Chrome / browser web navigation (docs, GitHub, domain policy).
    public var chrome: ChromeNavigationSettings

    public init(
        workspacePath: String = "",
        filePaths: [String] = [],
        chromeTabLabels: [String] = [],
        dwellMinSeconds: Double = 30,
        dwellMaxSeconds: Double = 180,
        pacing: NavigationPacingProfile? = nil,
        pacingCustom: NavigationPacingCustom = .default,
        speed: NavigationSpeedPreset? = nil,
        customIntervalSeconds: Double = 1.4,
        targetOrder: ReviewTargetOrder = .sequential,
        loopTargets: Bool = true,
        discoverRunningApps: Bool = false,
        discovery: DiscoveryScope = .default,
        refreshTargetsBetweenDwells: Bool = false,
        chrome: ChromeNavigationSettings = .default
    ) {
        self.workspacePath = workspacePath
        self.filePaths = filePaths
        self.chromeTabLabels = chromeTabLabels
        self.dwellMinSeconds = dwellMinSeconds
        self.dwellMaxSeconds = dwellMaxSeconds
        let resolvedPacing = pacing ?? speed?.asPacingProfile ?? .relaxed
        self.pacing = resolvedPacing
        var custom = pacingCustom
        if resolvedPacing == .custom {
            custom.scrollIntervalSeconds = customIntervalSeconds
        }
        self.pacingCustom = custom
        self.speed = speed ?? Self.legacySpeed(for: resolvedPacing)
        self.customIntervalSeconds = customIntervalSeconds
        self.targetOrder = targetOrder
        self.loopTargets = loopTargets
        self.discoverRunningApps = discoverRunningApps
        self.discovery = discovery
        self.refreshTargetsBetweenDwells = refreshTargetsBetweenDwells
        self.chrome = chrome
    }

    private static func legacySpeed(for pacing: NavigationPacingProfile) -> NavigationSpeedPreset {
        switch pacing {
        case .relaxed: return .slow
        case .deliberate, .normal: return .normal
        case .custom: return .custom
        }
    }

    public static let `default` = ReviewWorkspaceSettings()

    /// Defaults used by the single Universal Workspace Navigation workflow.
    public static var universalDefault: ReviewWorkspaceSettings {
        UniversalWorkflowBridge.defaultSettings
    }

    public mutating func normalize() {
        dwellMinSeconds = min(max(5, dwellMinSeconds), 600)
        dwellMaxSeconds = min(max(10, dwellMaxSeconds), 900)
        if dwellMinSeconds >= dwellMaxSeconds {
            dwellMaxSeconds = dwellMinSeconds + 1
        }
        pacingCustom.normalize()
        if pacing == .custom {
            customIntervalSeconds = pacingCustom.scrollIntervalSeconds
        } else {
            customIntervalSeconds = min(max(0.05, customIntervalSeconds), 8.0)
        }
        speed = Self.legacySpeed(for: pacing)
        filePaths = filePaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        chromeTabLabels = chromeTabLabels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        workspacePath = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        chrome.normalize()
    }

    public func validated() -> (ok: Bool, message: String?) {
        var copy = self
        copy.normalize()
        if copy.dwellMinSeconds >= copy.dwellMaxSeconds {
            return (false, "dwell minimum must be less than maximum")
        }
        return (true, nil)
    }

    /// Baseline review-phase gap (profile mid). Prefer `gapSeconds(for:)` for phase-aware pacing.
    public var actionIntervalSeconds: Double {
        PacingController.gapSeconds(
            profile: pacing,
            custom: pacingCustom,
            context: .review(weight: 0.5)
        )
    }

    public func gapSeconds(for context: PacingContext) -> Double {
        PacingController.gapSeconds(
            profile: pacing,
            custom: pacingCustom,
            context: context
        )
    }

    public func randomDwellSeconds() -> Double {
        Double.random(in: dwellMinSeconds...dwellMaxSeconds)
    }

    /// Smart per-app dwell: mid-biased random. With multiple apps, soft-cap so others get turns
    /// without starving long-file reading when the session is hours long.
    public func smartAppDwellSeconds(distinctAppCount: Int = 1) -> Double {
        let lo = dwellMinSeconds
        var hi = dwellMaxSeconds
        if distinctAppCount >= 2 {
            hi = min(dwellMaxSeconds, max(dwellMinSeconds + 15, dwellMinSeconds * 3.0))
        }
        if lo >= hi { return lo }
        let mid = (lo + hi) / 2
        let half = (hi - lo) / 2
        let biasedLo = max(lo, mid - half * 0.55)
        let biasedHi = min(hi, mid + half * 0.55)
        if biasedLo >= biasedHi { return Double.random(in: lo...hi) }
        return Double.random(in: biasedLo...biasedHi)
    }

    /// Random reading time for one file/tab inside an app dwell (shorter than full target dwell).
    public func randomFileDwellSeconds(distinctAppCount: Int = 1) -> Double {
        let multi = distinctAppCount >= 2
        let fileMin = max(8.0, dwellMinSeconds * (multi ? 0.4 : 0.45))
        // Soft share of session: long pages can use most of the dwell range even with multiple apps.
        var fileMax = max(fileMin + 4, min(dwellMaxSeconds, dwellMaxSeconds * (multi ? 0.75 : 0.9)))
        if multi {
            fileMax = min(fileMax, max(fileMin + 4, dwellMinSeconds * 2.2))
        }
        if fileMin >= fileMax { return fileMin }
        return Double.random(in: fileMin...fileMax)
    }

    /// Content-weight-scaled file dwell (preferred over plain random when weight is known).
    public func weightedFileDwellSeconds(
        weight: Double,
        distinctAppCount: Int = 1
    ) -> Double {
        let w = min(1.4, max(0.2, weight))
        let bias = PacingController.reviewDurationBias(profile: pacing)
        let multi = distinctAppCount >= 2
        let fileMin = max(8.0, dwellMinSeconds * (multi ? 0.4 : 0.45))
        var fileMax = max(fileMin + 4, min(dwellMaxSeconds, dwellMaxSeconds * (multi ? 0.75 : 0.9)))
        if multi {
            fileMax = min(fileMax, max(fileMin + 4, dwellMinSeconds * 2.2))
        }
        let midBase = fileMin >= fileMax ? fileMin : (fileMin + fileMax) / 2
        let scaled = midBase * (0.55 + w) * bias
        let paced = PacingController.reviewDurationSeconds(
            profile: pacing,
            custom: pacingCustom,
            weight: w,
            dwellMaxSeconds: dwellMaxSeconds
        )
        // Prefer weight ordering: blend structure mid-base with paced review span.
        return min(dwellMaxSeconds, max(8, (scaled + paced) / 2))
    }

    /// Pause after switching files/tabs before crawling the next one.
    public func randomInterFilePauseSeconds() -> Double {
        gapSeconds(for: .surfaceSwitch)
    }

    /// Extra seconds granted when content still seems long (heuristic).
    public func randomFileDwellExtensionSeconds() -> Double {
        let span = max(4.0, (dwellMaxSeconds - dwellMinSeconds) * 0.3)
        return Double.random(in: (span * 0.5)...span)
    }

    public func resolvedFilePath(_ relativeOrAbsolute: String) -> String {
        let trimmed = relativeOrAbsolute.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return (trimmed as NSString).expandingTildeInPath
        }
        let root = (workspacePath as NSString).expandingTildeInPath
        if root.isEmpty { return trimmed }
        return (root as NSString).appendingPathComponent(trimmed)
    }
}

/// Normalized navigation surface in the universal queue.
public enum ReviewTarget: Equatable, Sendable {
    case editorFile(path: String, displayName: String)
    case chromeTab(label: String, index: Int)
    /// Discovered running app window — crawl with adapter-safe inert navigation only.
    case discoveredApp(bundleID: String, displayName: String, classification: TargetAppClass)

    public var identity: String {
        switch self {
        case .editorFile(_, let displayName): return displayName
        case .chromeTab(let label, _): return label
        case .discoveredApp(_, let displayName, _): return displayName
        }
    }

    public var kindLabel: String {
        switch self {
        case .editorFile: return "file"
        case .chromeTab: return "tab"
        case .discoveredApp: return "application"
        }
    }

    public var bundleIDHint: String? {
        switch self {
        case .discoveredApp(let bundleID, _, _): return bundleID
        default: return nil
        }
    }
}
