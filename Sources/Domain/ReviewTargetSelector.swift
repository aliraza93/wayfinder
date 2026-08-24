import Foundation

/// Builds and walks the configured file/tab queue for a single Read & Review workflow.
public struct ReviewTargetSelector: Sendable {
    public var settings: ReviewWorkspaceSettings
    public var editorBundleID: String?
    public var browserBundleID: String?

    public init(
        settings: ReviewWorkspaceSettings,
        editorBundleID: String? = nil,
        browserBundleID: String? = nil
    ) {
        self.settings = settings
        self.editorBundleID = editorBundleID
        self.browserBundleID = browserBundleID
    }

    public func makeQueue() -> [ReviewTarget] {
        var queue: [ReviewTarget] = []
        for path in settings.filePaths {
            let resolved = settings.resolvedFilePath(path)
            let name = (resolved as NSString).lastPathComponent
            queue.append(.editorFile(path: resolved, displayName: name.isEmpty ? path : name))
        }
        for (index, label) in settings.chromeTabLabels.enumerated() {
            queue.append(.chromeTab(label: label, index: index))
        }
        if queue.isEmpty {
            if editorBundleID != nil {
                queue.append(.editorFile(path: "", displayName: "(current editor)"))
            }
            if browserBundleID != nil {
                queue.append(.chromeTab(label: "(current tab)", index: 0))
            }
        }
        switch settings.targetOrder {
        case .sequential: return queue
        case .random: return queue.shuffled()
        }
    }
}

private enum ReviewEnterPhase: Sendable {
    case focusApp
    case selectSurface
    case crawl
}

/// Session controller: focus app → select file/tab → progressive crawl → next target.
public struct ReviewSessionController: Sendable {
    public var settings: ReviewWorkspaceSettings
    public var editorBundleID: String?
    public var browserBundleID: String?
    public var queue: [ReviewTarget]
    public var index: Int
    public var dwellEndsAt: Date?
    public var dwellStartedAt: Date?
    public var current: ReviewTarget?
    public var targetsCompleted: Int
    public var nextPreview: ReviewTarget?
    public var crawlStepsOnTarget: Int
    private var enterPhase: ReviewEnterPhase

    public init(
        settings: ReviewWorkspaceSettings,
        queue: [ReviewTarget],
        editorBundleID: String? = nil,
        browserBundleID: String? = nil
    ) {
        self.settings = settings
        self.queue = queue
        self.editorBundleID = editorBundleID
        self.browserBundleID = browserBundleID
        self.index = 0
        self.dwellEndsAt = nil
        self.dwellStartedAt = nil
        self.current = queue.first
        self.targetsCompleted = 0
        self.nextPreview = queue.count > 1 ? queue[1] : nil
        self.crawlStepsOnTarget = 0
        self.enterPhase = .focusApp
    }

    public var dwellAllocatedSeconds: Double? {
        guard let start = dwellStartedAt, let end = dwellEndsAt else { return nil }
        return end.timeIntervalSince(start)
    }

    public var dwellElapsedSeconds: Double? {
        guard let start = dwellStartedAt else { return nil }
        return Date().timeIntervalSince(start)
    }

    public mutating func nextPick(now: Date) -> TimedReviewPick? {
        guard !queue.isEmpty else { return nil }

        if current == nil {
            return startTarget(at: 0, now: now)
        }

        switch enterPhase {
        case .focusApp:
            return focusAppPick()
        case .selectSurface:
            return selectSurfacePick()
        case .crawl:
            break
        }

        if let end = dwellEndsAt, now >= end {
            targetsCompleted += 1
            recordMetaCompleted = true
            let nextIndex = index + 1
            if nextIndex >= queue.count {
                if settings.loopTargets {
                    if settings.targetOrder == .random { queue.shuffle() }
                    return startTarget(at: 0, now: now)
                }
                return nil
            }
            return startTarget(at: nextIndex, now: now)
        }

        crawlStepsOnTarget += 1
        return TimedReviewPick(
            action: progressiveCrawlAction(),
            gapSeconds: settings.actionIntervalSeconds,
            metaKind: "navigationExecuted",
            identity: current?.identity
        )
    }

    /// Set when a target dwell just completed (engine records TargetCompleted).
    public var recordMetaCompleted: Bool = false

    private mutating func startTarget(at i: Int, now: Date) -> TimedReviewPick {
        let safe = ((i % queue.count) + queue.count) % queue.count
        index = safe
        current = queue[safe]
        enterPhase = .focusApp
        crawlStepsOnTarget = 0
        let dwell = settings.randomDwellSeconds()
        dwellStartedAt = now
        dwellEndsAt = now.addingTimeInterval(dwell)
        let upcoming = (safe + 1) % queue.count
        nextPreview = queue.count > 1 ? queue[upcoming] : nil
        return focusAppPick()
    }

    private mutating func focusAppPick() -> TimedReviewPick {
        enterPhase = .selectSurface
        switch current! {
        case .editorFile:
            let id = editorBundleID ?? ""
            if id.isEmpty {
                return selectSurfacePick()
            }
            return TimedReviewPick(
                action: .activateApp(bundleID: id),
                gapSeconds: max(0.5, settings.actionIntervalSeconds),
                metaKind: "applicationFocused",
                identity: current?.identity
            )
        case .chromeTab:
            let id = browserBundleID ?? ""
            if id.isEmpty {
                return selectSurfacePick()
            }
            return TimedReviewPick(
                action: .activateApp(bundleID: id),
                gapSeconds: max(0.5, settings.actionIntervalSeconds),
                metaKind: "applicationFocused",
                identity: current?.identity
            )
        }
    }

    private mutating func selectSurfacePick() -> TimedReviewPick {
        enterPhase = .crawl
        switch current! {
        case .editorFile(let path, _):
            if path.isEmpty {
                return TimedReviewPick(
                    action: .switchTab(direction: .next),
                    gapSeconds: max(0.4, settings.actionIntervalSeconds),
                    metaKind: "fileSelected",
                    identity: current?.identity
                )
            }
            return TimedReviewPick(
                action: .openExistingFile(path: path),
                gapSeconds: max(0.5, settings.actionIntervalSeconds),
                metaKind: "fileOpened",
                identity: current?.identity
            )
        case .chromeTab(_, let tabIndex):
            let direction: WindowDirection = (tabIndex % 2 == 0) ? .next : .previous
            return TimedReviewPick(
                action: .switchTab(direction: direction),
                gapSeconds: max(0.45, settings.actionIntervalSeconds),
                metaKind: "tabSelected",
                identity: current?.identity
            )
        }
    }

    private func progressiveCrawlAction() -> ActionKind {
        let step = crawlStepsOnTarget
        if step > 0, step % 14 == 0 { return .pageNavigate(.pageDown) }
        if step > 0, step % 40 == 0 { return .pageNavigate(.end) }
        if step > 8, step % 19 == 0 {
            return .arrowNavigate(direction: .up, presses: 1, intervalSeconds: 0)
        }
        if step % 11 == 0 { return .contentClick }
        if step % 7 == 0 { return .pageNavigate(.pageDown) }
        switch step % 5 {
        case 0, 1, 2:
            return .arrowNavigate(direction: .down, presses: 1, intervalSeconds: 0)
        case 3:
            return .scroll(direction: .down, amount: 4)
        default:
            return .arrowNavigate(direction: .down, presses: 1, intervalSeconds: 0)
        }
    }
}
