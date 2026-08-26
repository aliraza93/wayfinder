import Foundation

/// Injected live discovery for the universal planner. Pure Domain — AppControl implements.
public protocol ApplicationDiscoverySource: Sendable {
    func discoverApplications() -> [DiscoveredApplication]
}

/// No-op discovery (tests / headless).
public struct EmptyApplicationDiscovery: ApplicationDiscoverySource {
    public init() {}
    public func discoverApplications() -> [DiscoveredApplication] { [] }
}

/// Legacy helpers + bridge into `ReviewSessionController` for timed continuous runs.
public enum TimedReviewNavigation {
    public static let actionIntervalSeconds: Double = 0.35

    public static func steps() -> [Step] {
        steps(targets: [], settings: .default)
    }

    public static func steps(
        targets: [TargetApp],
        reviewFilePaths: [String] = [],
        settings: ReviewWorkspaceSettings = .default
    ) -> [Step] {
        var merged = settings
        if merged.filePaths.isEmpty, !reviewFilePaths.isEmpty {
            merged.filePaths = reviewFilePaths
        }
        merged.normalize()

        var actions: [ActionKind] = []
        for path in merged.filePaths {
            actions.append(.openExistingFile(path: merged.resolvedFilePath(path)))
        }
        if !merged.chromeTabLabels.isEmpty {
            actions.append(.switchTab(direction: .next))
            actions.append(.switchTab(direction: .previous))
        }
        actions.append(contentsOf: ReviewSessionController.seedCrawlActions())
        actions.append(.activateApp(bundleID: targets.first(where: { $0.classification == .editor })?.bundleID ?? ""))
        actions.append(.activateApp(bundleID: targets.first(where: { $0.classification == .browser })?.bundleID ?? ""))
        actions.append(.returnToPrevious)

        return actions
            .filter {
                if case .activateApp(let id) = $0 { return !id.isEmpty }
                return true
            }
            .map { action in
                Step(
                    action: action,
                    timeoutSeconds: 4,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .skip
                )
            }
    }

    public static func makeController(
        settings: ReviewWorkspaceSettings,
        targets: [TargetApp],
        discovered: [DiscoveredApplication] = []
    ) -> ReviewSessionController {
        var normalized = settings
        normalized.normalize()
        let editorID = targets.first(where: { $0.classification == .editor })?.bundleID
        let browserID = targets.first(where: { $0.classification == .browser })?.bundleID
        let selector = ReviewTargetSelector(
            settings: normalized,
            editorBundleID: editorID,
            browserBundleID: browserID,
            discovered: discovered,
            workflowTargets: targets
        )
        return ReviewSessionController(
            settings: normalized,
            queue: selector.makeQueue(),
            editorBundleID: editorID,
            browserBundleID: browserID
        )
    }
}

extension ReviewSessionController {
    fileprivate static func seedCrawlActions() -> [ActionKind] {
        [
            .arrowNavigate(direction: .down, presses: 1, intervalSeconds: 0),
            .arrowNavigate(direction: .up, presses: 1, intervalSeconds: 0),
            .pageNavigate(.pageDown),
            .pageNavigate(.pageUp),
            .pageNavigate(.home),
            .contentClick,
            .highlightNavigate(direction: .down),
            .switchTab(direction: .next),
        ]
    }
}
