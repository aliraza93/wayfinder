import Foundation

/// Decision from the Chrome crawl engine for one tick (Domain-pure).
public enum ChromeCrawlDecision: Equatable, Sendable {
    case inspect
    case activate(identity: String, x: Double, y: Double)
    /// Keyboard-only page traversal (never scroll-wheel).
    case keyTraverse(ChromeReadMotion)
    /// Deprecated for Chrome: never mapped to Cmd+[ / toolbar Back.
    case browserBack
    case switchTab(direction: WindowDirection)
    case wait(seconds: Double)
    /// Hand control back to the universal progressive crawler / next app.
    case yieldToUniversal
}

/// Inert keyboard motions used to read page/file content.
public enum ChromeReadMotion: Equatable, Sendable {
    case home
    case pageDown
    case pageUp
    case arrowDown(presses: Int)
    case arrowUp(presses: Int)

    public var asAction: ActionKind {
        switch self {
        case .home:
            return .pageNavigate(.home)
        case .pageDown:
            return .pageNavigate(.pageDown)
        case .pageUp:
            return .pageNavigate(.pageUp)
        case .arrowDown(let presses):
            return .arrowNavigate(direction: .down, presses: max(1, presses), intervalSeconds: 0)
        case .arrowUp(let presses):
            return .arrowNavigate(direction: .up, presses: max(1, presses), intervalSeconds: 0)
        }
    }

    public var isDownward: Bool {
        switch self {
        case .pageDown, .arrowDown: return true
        case .home, .pageUp, .arrowUp: return false
        }
    }
}

/// Injected live page inspection. Accessibility implements; Domain stays pure.
public protocol WebPageInspectionSource: Sendable {
    func inspectFrontmostPage(bundleID: String) -> WebPageSnapshot?
}

public struct EmptyWebPageInspection: WebPageInspectionSource {
    public init() {}
    public func inspectFrontmostPage(bundleID: String) -> WebPageSnapshot? {
        _ = bundleID
        return nil
    }
}

/// Session state for smart Chrome navigation: history, visited, pending, limits.
public struct ChromeCrawlSession: Sendable {
    public var settings: ChromeNavigationSettings
    public var visitedURLs: Set<String>
    public var history: [String]
    public var pending: [WebNavCandidate]
    public var currentURL: String
    /// Parent of the current URL in the crawl stack (empty at root).
    public var parentURL: String
    public var currentDepth: Int
    public var pagesVisited: Int
    public var scrollsOnPage: Int
    public var pageStartedAt: Date?
    public var lastSnapshot: WebPageSnapshot?
    public var lastContentFingerprint: String
    /// Consecutive inspects where fingerprint did not change after scroll (infinite-scroll end).
    public var unchangedScrollInspects: Int
    public var needsInspect: Bool
    public var readingSource: Bool
    /// How many Ctrl+Tab hops attempted while hunting for a fresh tab.
    public var tabSwitchesAttempted: Int
    /// Max Ctrl+Tab hops per workspace before yielding.
    public var maxTabSwitches: Int
    /// Stable keys for tabs/pages already reviewed this run.
    public var visitedTabKeys: Set<String>
    /// Keys activated this run (including name-only file targets).
    public var visitedTargetKeys: Set<String>
    /// Pages fully reviewed this run — skip re-keying when Ctrl+Tab returns.
    public var completedPageKeys: Set<String>
    /// Pending activate whose URL we expect after the next inspect.
    public var awaitingNavigationTo: String?
    /// Consecutive activations that did not change the page URL.
    public var stuckActivationCount: Int
    /// Discovered tab groups for this Chrome workspace (read-only; never mutated).
    public var tabGroups: [ChromeTabGroup]
    /// Last explorer intent (for debug / preview).
    public var lastIntent: ChromeNavigationIntent
    public var explorerState: ChromeExplorerState
    public var lastRejection: String
    /// 0...1+ heuristic of how long this page needs (never from body text).
    public var pageReadWeight: Double
    /// Key-traverse budget for the current page (scales with weight).
    public var pageKeyBudget: Int
    /// Soft max seconds for the current page (scales with weight).
    public var pageTimeBudgetSeconds: Double
    /// Workspace pacing profile (from ReviewWorkspaceSettings).
    public var pacing: NavigationPacingProfile
    public var pacingCustom: NavigationPacingCustom
    /// Consecutive nav activates without a review/wait (forces paced pause).
    public var consecutiveNavActions: Int
    /// BFS queue vs DFS stack controlled by strategy when enqueueing.
    private var pendingIsStack: Bool
    /// Max key moves while reviewing a source file / long article before seeking next nav target.
    private static let minSourceReviewKeys = 8
    private static let maxSourceReviewKeys = 48
    /// Reveal key moves when no candidates — keep bounded to force tab/file variety.
    private static let minRevealKeys = 4
    private static let maxRevealKeys = 24

    public init(
        settings: ChromeNavigationSettings,
        pacing: NavigationPacingProfile = .relaxed,
        pacingCustom: NavigationPacingCustom = .default,
        now: Date = Date()
    ) {
        var normalized = settings
        normalized.normalize()
        self.settings = normalized
        self.visitedURLs = []
        self.history = []
        self.pending = []
        self.currentURL = ""
        self.parentURL = ""
        self.currentDepth = 0
        self.pagesVisited = 0
        self.scrollsOnPage = 0
        self.pageStartedAt = now
        self.lastSnapshot = nil
        self.lastContentFingerprint = ""
        self.unchangedScrollInspects = 0
        self.needsInspect = true
        self.readingSource = false
        self.tabSwitchesAttempted = 0
        self.maxTabSwitches = 12
        self.visitedTabKeys = []
        self.visitedTargetKeys = []
        self.completedPageKeys = []
        self.awaitingNavigationTo = nil
        self.stuckActivationCount = 0
        self.tabGroups = []
        self.lastIntent = .inspect
        self.explorerState = .idle
        self.lastRejection = ""
        self.pageReadWeight = 0.4
        self.pageKeyBudget = Self.minRevealKeys
        self.pageTimeBudgetSeconds = normalized.maxTimePerPageSeconds
        self.pacing = pacing
        self.pacingCustom = pacingCustom
        self.consecutiveNavActions = 0
        self.pendingIsStack = normalized.githubStrategy == .depthFirst
    }

    /// Soft reset when returning to Chrome mid-run — keep visited memory, clear page-local work.
    public mutating func prepareForNewBrowserDwell(now: Date) {
        pending = []
        lastSnapshot = nil
        lastContentFingerprint = ""
        unchangedScrollInspects = 0
        scrollsOnPage = 0
        needsInspect = true
        readingSource = false
        awaitingNavigationTo = nil
        stuckActivationCount = 0
        pageStartedAt = now
        pageReadWeight = 0.4
        pageKeyBudget = Self.minRevealKeys
        pageTimeBudgetSeconds = settings.maxTimePerPageSeconds
        // Allow more tab hops in this dwell; do not clear visitedTabKeys / visitedURLs.
        tabSwitchesAttempted = 0
        explorerState = .discoveringWorkspace
        lastIntent = .inspect
    }

    public mutating func markNeedsInspect() {
        needsInspect = true
        explorerState = .inspectingPage
    }

    public mutating func applySnapshot(_ snapshot: WebPageSnapshot, now: Date) {
        needsInspect = false
        explorerState = .buildingNavigationTargets
        var snap = snapshot
        if snap.kind == .generic {
            snap.kind = GitHubURLParser.pageKind(for: snap.url)
        }
        if snap.kind == .generic, snap.looksLikeDocumentation {
            snap.kind = .documentation
        }

        // Adapt scoring profile from page type unless the user chose custom.
        settings.profile = WebPageStrategySelector.adaptedProfile(for: snap.kind, current: settings.profile)
        if snap.kind == .githubRepoRoot || snap.kind == .githubTree || snap.kind == .githubBlob {
            settings.crawlRepositoryDirectories = true
            settings.crawlSourceFiles = true
        }
        if snap.kind == .documentation || snap.looksLikeDocumentation {
            settings.crawlDocumentation = true
        }

        let fingerprint = snap.contentFingerprint
        if !lastContentFingerprint.isEmpty,
           fingerprint == lastContentFingerprint,
           scrollsOnPage > 0
        {
            unchangedScrollInspects += 1
        } else if fingerprint != lastContentFingerprint {
            unchangedScrollInspects = 0
        }
        lastContentFingerprint = fingerprint
        lastSnapshot = snap
        refreshReadBudgets(for: snap)

        let normalizedURL = URLNormalizer.normalize(snap.url)
        let tabKey = ChromeVisitKey.forPage(url: normalizedURL, title: snap.title)
        let previousURL = currentURL
        let urlChanged = !normalizedURL.isEmpty && normalizedURL != previousURL

        if let expected = awaitingNavigationTo {
            let namePart = expected.replacingOccurrences(of: "name:", with: "")
            let expectedHit = !expected.isEmpty && (
                expected == normalizedURL
                    || (!tabKey.isEmpty && expected == tabKey)
                    || (!normalizedURL.isEmpty && !namePart.isEmpty && normalizedURL.lowercased().contains(namePart))
            )
            if urlChanged || expectedHit {
                stuckActivationCount = 0
                markVisited(expected)
                if urlChanged {
                    visitedURLs.insert(normalizedURL)
                }
            } else if !previousURL.isEmpty {
                // Click did not leave the page — burn the target and prefer something else.
                stuckActivationCount += 1
                visitedTargetKeys.insert(expected)
                lastRejection = "Activation did not change page — skipped \(expected)"
            }
            awaitingNavigationTo = nil
        }

        if urlChanged {
            if !previousURL.isEmpty {
                history.append(previousURL)
                parentURL = previousURL
            } else {
                parentURL = ""
            }
            currentURL = normalizedURL
            currentDepth = history.count
            pagesVisited += 1
            scrollsOnPage = 0
            pageStartedAt = now
            unchangedScrollInspects = 0
            visitedURLs.insert(normalizedURL)
            if !tabKey.isEmpty {
                visitedTabKeys.insert(tabKey)
            }
            readingSource = snap.kind == .githubBlob
                || GitHubURLParser.isSourceFilePath(normalizedURL)
            // Drop stale pending from the previous page — rebuild from this snapshot.
            pending = []
        } else if currentURL.isEmpty, !normalizedURL.isEmpty {
            currentURL = normalizedURL
            pagesVisited = max(1, pagesVisited)
            visitedURLs.insert(normalizedURL)
            if !tabKey.isEmpty {
                visitedTabKeys.insert(tabKey)
            }
            readingSource = snap.kind == .githubBlob
                || GitHubURLParser.isSourceFilePath(normalizedURL)
        } else if !tabKey.isEmpty {
            visitedTabKeys.insert(tabKey)
        }

        // Already fully reviewed this tab earlier in the run → do not re-scroll it.
        // (First landing still enqueues; subsequent returns prefer switching away.)
        let revisitingKnownTab = !tabKey.isEmpty
            && visitedTabKeys.contains(tabKey)
            && !urlChanged
            && pagesVisited > 1
            && pending.isEmpty
            && scrollsOnPage == 0

        let ranked = WebLinkScorer.rankedCandidates(
            snapshot: snap,
            settings: settings,
            visited: visitedURLs.union(visitedTargetKeys),
            depth: currentDepth + 1
        )
        enqueue(ranked)

        if revisitingKnownTab, pending.isEmpty {
            lastRejection = "Already reviewed tab — switching"
        }

        explorerState = .selectingTarget
    }

    /// Ordered preview of what the crawler intends to explore (no side effects).
    public func previewNavigation(limit: Int = 20) -> [String] {
        let ranked = pending.sorted { $0.priority > $1.priority }
        return Array(ranked.prefix(limit).map { candidate in
            let label = candidate.element.name.isEmpty
                ? (candidate.element.href ?? candidate.element.identity)
                : candidate.element.name
            return "\(candidate.typeLabel): \(label)"
        })
    }

    public func debugSnapshot() -> ChromeExplorerDebugSnapshot {
        let snap = lastSnapshot
        let all = snap?.allCandidates ?? []
        let safe = pending.count
        let blocked = max(0, all.count - safe)
        let next = pending.first.map { c in
            c.element.name.isEmpty ? (c.element.href ?? c.element.identity) : c.element.name
        } ?? ""
        return ChromeExplorerDebugSnapshot(
            state: explorerState,
            currentURL: currentURL,
            pageType: snap?.kind ?? .generic,
            intent: lastIntent,
            discoveredCount: all.count,
            safeCount: safe,
            blockedCount: blocked,
            nextTarget: next,
            lastRejection: lastRejection,
            tabGroupCount: tabGroups.count
        )
    }

    public mutating func nextDecision(now: Date) -> ChromeCrawlDecision {
        if needsInspect || lastSnapshot == nil {
            lastIntent = .inspect
            explorerState = .inspectingPage
            return .inspect
        }

        if pagesVisited > settings.maxPages {
            lastIntent = .skip
            explorerState = .completed
            return .yieldToUniversal
        }

        if stuckActivationCount >= 2 {
            lastRejection = "Repeated stuck activations — leaving page"
            return advanceAfterPageBudget()
        }

        let maxConsecutive = PacingController.maxConsecutiveActions(
            profile: pacing,
            custom: pacingCustom
        )
        if PacingController.shouldForcePause(
            consecutiveActions: consecutiveNavActions,
            maxConsecutive: maxConsecutive
        ) {
            consecutiveNavActions = 0
            let pause = PacingController.gapSeconds(
                profile: pacing,
                custom: pacingCustom,
                context: .navigation(
                    weight: pageReadWeight,
                    candidates: pending.count,
                    consecutive: maxConsecutive
                )
            )
            return .wait(seconds: pause)
        }

        if let started = pageStartedAt,
           now.timeIntervalSince(started) >= pageTimeBudgetSeconds
        {
            return advanceAfterPageBudget()
        }

        if scrollsOnPage >= max(pageKeyBudget, settings.maxScrollsPerPage) {
            return advanceAfterPageBudget()
        }

        // Infinite scroll ended: scroll → wait → inspect found no new content.
        if unchangedScrollInspects >= 2 {
            return advanceAfterPageBudget()
        }

        // Already fully reviewed this page with nothing new → switch tab / yield (no re-key).
        if pending.isEmpty,
           !currentURL.isEmpty,
           completedPageKeys.contains(currentURL),
           scrollsOnPage == 0
        {
            lastRejection = "Already completed page — switching"
            return advanceAfterPageBudget()
        }

        let sourceBudget = sourceReviewKeyBudget()

        // A) Source/blob: finish deliberate key-review before opening siblings.
        if readingSource, scrollsOnPage < sourceBudget {
            scrollsOnPage += 1
            consecutiveNavActions = 0
            lastIntent = .scroll
            explorerState = .reviewingContent
            if scrollsOnPage % 2 == 0 {
                needsInspect = true
            }
            return .keyTraverse(nextReadMotion(preferPage: scrollsOnPage % 3 != 0))
        }

        if readingSource {
            // Review complete — mark page done, then allow siblings / tab hop.
            if !currentURL.isEmpty {
                completedPageKeys.insert(currentURL)
            }
            return advanceAfterPageBudget()
        }

        // Tree/docs/general: navigate pending links first.
        if let snap = lastSnapshot, !snap.isEmpty {
            if let next = dequeueNext() {
                consecutiveNavActions += 1
                return activateCandidate(next, pageKind: snap.kind)
            }

            let preferPagination = settings.crawlDocumentation
                || settings.profile == .documentation
                || snap.looksLikeDocumentation
            if preferPagination {
                if let nextPage = preferredPagination(in: snap) {
                    let key = ChromeVisitKey.forElement(nextPage)
                    if !key.isEmpty, !hasVisited(key), currentDepth < settings.maxDepth {
                        consecutiveNavActions += 1
                        return activateElement(nextPage, intent: .openPagination)
                    }
                }
            }
        }

        // Brief key reveal, then leave for another tab/file — avoid repetitive loops.
        let revealBudget = revealKeyBudget()
        if scrollsOnPage < revealBudget {
            scrollsOnPage += 1
            consecutiveNavActions = 0
            lastIntent = .scroll
            explorerState = .scrollingContent
            if scrollsOnPage % 2 == 0 {
                needsInspect = true
                explorerState = .discoveringMore
                let pause = PacingController.gapSeconds(
                    profile: pacing,
                    custom: pacingCustom,
                    context: .review(weight: pageReadWeight, scrolls: scrollsOnPage)
                )
                return .wait(seconds: min(1.2, max(0.35, pause * 0.45)))
            }
            return .keyTraverse(nextReadMotion(preferPage: true))
        }

        return advanceAfterPageBudget()
    }

    public mutating func noteActivationCompleted() {
        needsInspect = true
        readingSource = false
        scrollsOnPage = 0
        unchangedScrollInspects = 0
        pageStartedAt = Date()
        explorerState = .inspectingPage
    }

    private mutating func refreshReadBudgets(for snap: WebPageSnapshot) {
        pageReadWeight = snap.estimatedReadWeight
        let reading = readingSource || snap.kind == .githubBlob || snap.kind == .documentation
        pageTimeBudgetSeconds = PacingController.reviewDurationSeconds(
            profile: pacing,
            custom: pacingCustom,
            weight: pageReadWeight,
            dwellMaxSeconds: settings.maxTimePerPageSeconds
        )
        pageKeyBudget = PacingController.keyBudget(
            profile: pacing,
            custom: pacingCustom,
            weight: pageReadWeight,
            readingSource: reading,
            maxScrollsCeiling: settings.maxScrollsPerPage
        )
        if reading {
            pageKeyBudget = min(max(Self.minSourceReviewKeys, pageKeyBudget), Self.maxSourceReviewKeys)
        } else {
            pageKeyBudget = min(max(Self.minRevealKeys, pageKeyBudget), Self.maxRevealKeys)
        }
    }

    private func sourceReviewKeyBudget() -> Int {
        min(settings.maxScrollsPerPage, max(Self.minSourceReviewKeys, pageKeyBudget))
    }

    private func revealKeyBudget() -> Int {
        min(settings.maxScrollsPerPage, max(Self.minRevealKeys, pageKeyBudget))
    }

    private func nextReadMotion(preferPage: Bool) -> ChromeReadMotion {
        // Oscillate top ↔ mid ↔ bottom. Never End, never scroll-wheel.
        // Phase on scrollsOnPage (0-based before increment already applied by caller).
        let phase = max(0, scrollsOnPage - 1)
        if phase == 0 {
            return .home
        }
        switch phase % 6 {
        case 1:
            return preferPage ? .pageDown : .arrowDown(presses: Int.random(in: 2...4))
        case 2:
            return .arrowDown(presses: Int.random(in: 1...3))
        case 3:
            return preferPage ? .pageUp : .arrowUp(presses: Int.random(in: 2...4))
        case 4:
            return .arrowUp(presses: Int.random(in: 1...3))
        case 5:
            return .pageDown
        default:
            return .pageUp
        }
    }

    private mutating func activateCandidate(
        _ next: WebNavCandidate,
        pageKind: WebPageKind
    ) -> ChromeCrawlDecision {
        // Do not burn visit until URL change confirms success (see applySnapshot).
        awaitingNavigationTo = next.visitKey
        lastIntent = WebPageStrategySelector.intent(for: next, pageKind: pageKind)
        explorerState = .navigating
        return .activate(
            identity: next.element.identity,
            x: next.element.centerX,
            y: next.element.centerY
        )
    }

    private mutating func activateElement(
        _ element: WebNavElement,
        intent: ChromeNavigationIntent
    ) -> ChromeCrawlDecision {
        awaitingNavigationTo = ChromeVisitKey.forElement(element)
        lastIntent = intent
        explorerState = .navigating
        return .activate(
            identity: element.identity,
            x: element.centerX,
            y: element.centerY
        )
    }

    private mutating func markVisitedElement(_ element: WebNavElement) {
        markVisited(ChromeVisitKey.forElement(element))
        if let href = element.href {
            let normalized = URLNormalizer.normalize(href)
            if !normalized.isEmpty {
                visitedURLs.insert(normalized)
                visitedTargetKeys.insert(normalized)
            }
        }
        let name = element.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !name.isEmpty, GitHubURLParser.isSourceFilePath(name) || name.hasSuffix("/") {
            visitedTargetKeys.insert("name:\(name)")
        }
    }

    private mutating func markVisited(_ key: String) {
        guard !key.isEmpty else { return }
        visitedTargetKeys.insert(key)
        if key.contains("://") {
            visitedURLs.insert(URLNormalizer.normalize(key))
        }
    }

    private func hasVisited(_ key: String) -> Bool {
        if key.isEmpty { return false }
        if visitedTargetKeys.contains(key) { return true }
        if visitedURLs.contains(key) { return true }
        let normalized = URLNormalizer.normalize(key)
        return !normalized.isEmpty && visitedURLs.contains(normalized)
    }

    private func preferredPagination(in snap: WebPageSnapshot) -> WebNavElement? {
        let ranked = snap.pagination.filter {
            $0.surface == .pageContent
                && WebLinkSafetyFilter.isActivatable(
                    element: $0,
                    currentURL: snap.url,
                    policy: settings.domainPolicy(augmentingForURL: snap.url)
                )
                && !hasVisited(ChromeVisitKey.forElement($0))
        }
        let nextish = ranked.first {
            let n = $0.name.lowercased()
            return n.contains("next") || n.contains("more") || n.contains("→") || n.contains("›")
        }
        return nextish ?? ranked.first
    }

    private mutating func advanceAfterPageBudget() -> ChromeCrawlDecision {
        if let next = dequeueNext() {
            let snapKind = lastSnapshot?.kind ?? .generic
            return activateCandidate(next, pageKind: snapKind)
        }
        if !currentURL.isEmpty {
            completedPageKeys.insert(currentURL)
        }
        // Never use Chrome Back / Forward / toolbar. Hunt for another existing tab.
        if tabSwitchesAttempted < maxTabSwitches, pagesVisited < settings.maxPages {
            tabSwitchesAttempted += 1
            needsInspect = true
            scrollsOnPage = 0
            unchangedScrollInspects = 0
            readingSource = false
            pending = []
            lastIntent = .switchExistingTab
            explorerState = .discoveringTabs
            return .switchTab(direction: .next)
        }
        lastIntent = .skip
        explorerState = .completed
        return .yieldToUniversal
    }

    private mutating func enqueue(_ candidates: [WebNavCandidate]) {
        let filtered = candidates.filter { candidate in
            if hasVisited(candidate.visitKey) { return false }
            if !settings.crawlIssues, candidate.typeLabel == "link",
               (candidate.element.href ?? "").contains("/issues")
            {
                return settings.crawlIssues
            }
            if candidate.typeLabel == "sourceFile", !settings.crawlSourceFiles { return false }
            if candidate.typeLabel == "directory", !settings.crawlRepositoryDirectories { return false }
            if candidate.element.role == .heading,
               settings.profile == .generalWebsite,
               !settings.crawlDocumentation
            {
                return false
            }
            return true
        }
        let existingKeys = Set(pending.map(\.visitKey))
        let existingIdentities = Set(pending.map(\.element.identity))
        let fresh = filtered.filter {
            !existingKeys.contains($0.visitKey) && !existingIdentities.contains($0.element.identity)
        }
        // Prefer unvisited source files / directories first for variety.
        let ordered = fresh.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.visitKey < rhs.visitKey
        }
        if pendingIsStack {
            pending.append(contentsOf: ordered.reversed())
        } else {
            pending.append(contentsOf: ordered)
        }
        if pending.count > settings.maxPages * 3 {
            pending = Array(pending.prefix(settings.maxPages * 3))
        }
    }

    private mutating func dequeueNext() -> WebNavCandidate? {
        while !pending.isEmpty {
            let next: WebNavCandidate
            if pendingIsStack {
                next = pending.removeLast()
            } else {
                next = pending.removeFirst()
            }
            let key = next.visitKey
            if hasVisited(key) {
                lastRejection = "Already visited \(key)"
                continue
            }
            // Skip links that only point back at the current page.
            if let href = next.element.href {
                let normalized = URLNormalizer.normalize(href)
                if !normalized.isEmpty, normalized == currentURL {
                    markVisited(key)
                    lastRejection = "Same-page link skipped"
                    continue
                }
            }
            if next.depth > settings.maxDepth { continue }
            return next
        }
        return nil
    }
}
