import Foundation

/// Decision from the Chrome crawl engine for one tick (Domain-pure).
public enum ChromeCrawlDecision: Equatable, Sendable {
    case inspect
    case activate(identity: String, x: Double, y: Double)
    case scroll(direction: ScrollDirection, amount: Int)
    case browserBack
    case switchTab(direction: WindowDirection)
    case wait(seconds: Double)
    /// Hand control back to the universal progressive crawler / next app.
    case yieldToUniversal
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
    public var currentDepth: Int
    public var pagesVisited: Int
    public var scrollsOnPage: Int
    public var pageStartedAt: Date?
    public var lastSnapshot: WebPageSnapshot?
    public var needsInspect: Bool
    public var readingSource: Bool
    /// BFS queue vs DFS stack controlled by strategy when enqueueing.
    private var pendingIsStack: Bool

    public init(settings: ChromeNavigationSettings, now: Date = Date()) {
        var normalized = settings
        normalized.normalize()
        self.settings = normalized
        self.visitedURLs = []
        self.history = []
        self.pending = []
        self.currentURL = ""
        self.currentDepth = 0
        self.pagesVisited = 0
        self.scrollsOnPage = 0
        self.pageStartedAt = now
        self.lastSnapshot = nil
        self.needsInspect = true
        self.readingSource = false
        self.pendingIsStack = normalized.githubStrategy == .depthFirst
    }

    public mutating func markNeedsInspect() {
        needsInspect = true
    }

    public mutating func applySnapshot(_ snapshot: WebPageSnapshot, now: Date) {
        needsInspect = false
        var snap = snapshot
        if snap.kind == .generic {
            snap.kind = GitHubURLParser.pageKind(for: snap.url)
        }
        lastSnapshot = snap
        let normalizedURL = URLNormalizer.normalize(snap.url)
        if !normalizedURL.isEmpty, normalizedURL != currentURL {
            if !currentURL.isEmpty {
                history.append(currentURL)
            }
            currentURL = normalizedURL
            currentDepth = history.count
            pagesVisited += 1
            scrollsOnPage = 0
            pageStartedAt = now
            if !normalizedURL.isEmpty {
                visitedURLs.insert(normalizedURL)
            }
            readingSource = snap.kind == .githubBlob
                || GitHubURLParser.isSourceFilePath(normalizedURL)
        }

        let ranked = WebLinkScorer.rankedCandidates(
            snapshot: snap,
            settings: settings,
            visited: visitedURLs,
            depth: currentDepth + 1
        )
        enqueue(ranked)
    }

    public mutating func nextDecision(now: Date) -> ChromeCrawlDecision {
        if needsInspect || lastSnapshot == nil {
            return .inspect
        }

        if pagesVisited > settings.maxPages {
            return .yieldToUniversal
        }

        if let started = pageStartedAt,
           now.timeIntervalSince(started) >= settings.maxTimePerPageSeconds
        {
            return advanceAfterPageBudget()
        }

        if scrollsOnPage >= settings.maxScrollsPerPage {
            return advanceAfterPageBudget()
        }

        // Source / long article: prefer reading before hopping.
        if readingSource, scrollsOnPage < min(12, settings.maxScrollsPerPage / 2) {
            scrollsOnPage += 1
            return .scroll(direction: .down, amount: Int.random(in: 3...6))
        }

        if let snap = lastSnapshot, !snap.isEmpty {
            // Prefer pagination when reading docs and pending is thin.
            if settings.crawlDocumentation || settings.profile == .documentation {
                if let nextPage = snap.pagination.first(where: {
                    WebLinkSafetyFilter.isSafe(name: $0.name, href: $0.href)
                        && ($0.name.lowercased().contains("next") || $0.name.lowercased().contains("more"))
                }) {
                    let id = URLNormalizer.normalize(nextPage.href ?? nextPage.identity)
                    if !id.isEmpty, !visitedURLs.contains(id), currentDepth < settings.maxDepth {
                        visitedURLs.insert(id)
                        return .activate(identity: id, x: nextPage.centerX, y: nextPage.centerY)
                    }
                }
            }

            if let next = dequeueNext() {
                visitedURLs.insert(URLNormalizer.normalize(next.element.href ?? next.element.identity))
                return .activate(
                    identity: next.element.identity,
                    x: next.element.centerX,
                    y: next.element.centerY
                )
            }
        }

        // Keep scrolling to reveal infinite-scroll / more links, then reinspect.
        if scrollsOnPage < settings.maxScrollsPerPage {
            scrollsOnPage += 1
            if scrollsOnPage % 5 == 0 {
                needsInspect = true
                return .wait(seconds: 0.45)
            }
            return .scroll(direction: .down, amount: Int.random(in: 2...5))
        }

        return advanceAfterPageBudget()
    }

    public mutating func noteActivationCompleted() {
        needsInspect = true
        readingSource = false
        scrollsOnPage = 0
        pageStartedAt = Date()
    }

    private mutating func advanceAfterPageBudget() -> ChromeCrawlDecision {
        if let next = dequeueNext() {
            visitedURLs.insert(URLNormalizer.normalize(next.element.href ?? next.element.identity))
            return .activate(
                identity: next.element.identity,
                x: next.element.centerX,
                y: next.element.centerY
            )
        }
        if history.count >= 1, currentDepth > 0 {
            if let last = history.popLast() {
                currentURL = last
                currentDepth = max(0, currentDepth - 1)
                needsInspect = true
                readingSource = false
                scrollsOnPage = 0
                return .browserBack
            }
        }
        return .yieldToUniversal
    }

    private mutating func enqueue(_ candidates: [WebNavCandidate]) {
        let filtered = candidates.filter { candidate in
            if !settings.crawlIssues, candidate.typeLabel == "link",
               (candidate.element.href ?? "").contains("/issues")
            {
                return settings.crawlIssues
            }
            if candidate.typeLabel == "sourceFile", !settings.crawlSourceFiles { return false }
            if candidate.typeLabel == "directory", !settings.crawlRepositoryDirectories { return false }
            return true
        }
        let existing = Set(pending.map(\.element.identity))
        let fresh = filtered.filter { !existing.contains($0.element.identity) }
        if pendingIsStack {
            // DFS: high priority first onto stack (append = top).
            pending.append(contentsOf: fresh.reversed())
        } else {
            // BFS: append to queue.
            pending.append(contentsOf: fresh)
        }
        // Cap pending to avoid unbounded growth.
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
            let id = URLNormalizer.normalize(next.element.href ?? next.element.identity)
            if visitedURLs.contains(id) || visitedURLs.contains(next.element.identity) {
                continue
            }
            if next.depth > settings.maxDepth { continue }
            return next
        }
        return nil
    }
}
