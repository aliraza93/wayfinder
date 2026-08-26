import Foundation

/// Builds the universal navigation queue from Targets allowlist + optional open-app extras.
public enum NavigationPlanner: Sendable {
    /// Queue = configured files/tabs + explicit Targets (+ optional discovered Finder/Preview/Other).
    public static func buildQueue(
        settings: ReviewWorkspaceSettings,
        discovered: [DiscoveredApplication],
        workflowTargets: [TargetApp],
        visited: VisitedTargetTracker = .empty
    ) -> [ReviewTarget] {
        var settings = settings
        settings.normalize()

        var queue: [ReviewTarget] = []
        var seenKeys = Set<String>()
        let allowlist = Set(workflowTargets.map(\.bundleID))

        func append(_ target: ReviewTarget) {
            let key = identityKey(target)
            guard !seenKeys.contains(key) else { return }
            seenKeys.insert(key)
            queue.append(target)
        }

        // 1. Configured workspace files (only meaningful with an editor target).
        for path in settings.filePaths {
            let resolved = settings.resolvedFilePath(path)
            let name = (resolved as NSString).lastPathComponent
            append(.editorFile(path: resolved, displayName: name.isEmpty ? path : name))
        }

        // 2. Configured Chrome tab identities.
        for (index, label) in settings.chromeTabLabels.enumerated() {
            append(.chromeTab(label: label, index: index))
        }

        let hasConfiguredFiles = !settings.filePaths.isEmpty
        let hasConfiguredTabs = !settings.chromeTabLabels.isEmpty

        // 3. Explicit Targets allowlist (Cursor, Chrome, …) — primary crawl set.
        for target in workflowTargets {
            if NavigationAppPolicy.isForbidden(target.bundleID) { continue }
            if target.classification == .editor, hasConfiguredFiles { continue }
            if target.classification == .browser, hasConfiguredTabs { continue }
            let display = discovered.first(where: { $0.bundleID == target.bundleID })?.displayName
                ?? target.bundleID
            append(
                .discoveredApp(
                    bundleID: target.bundleID,
                    displayName: display,
                    classification: target.classification
                )
            )
        }

        // 4. Optional: other open apps (Finder / Preview / Other only — never random IDEs).
        if settings.discoverRunningApps {
            for app in discovered {
                guard NavigationAppPolicy.allowsDiscovered(
                    app,
                    settings: settings,
                    workflowTargets: workflowTargets
                ) else { continue }
                if allowlist.contains(app.bundleID) { continue }
                if app.classification == .editor, hasConfiguredFiles { continue }
                if app.classification == .browser, hasConfiguredTabs { continue }
                append(
                    .discoveredApp(
                        bundleID: app.bundleID,
                        displayName: app.displayName,
                        classification: app.classification
                    )
                )
            }
        }

        if queue.isEmpty {
            for target in workflowTargets where !NavigationAppPolicy.isForbidden(target.bundleID) {
                append(
                    .discoveredApp(
                        bundleID: target.bundleID,
                        displayName: target.bundleID,
                        classification: target.classification
                    )
                )
            }
        }

        return orderQueue(queue, settings: settings, visited: visited)
    }

    /// Apply target-order mode without rebuilding membership.
    public static func orderQueue(
        _ queue: [ReviewTarget],
        settings: ReviewWorkspaceSettings,
        visited: VisitedTargetTracker = .empty
    ) -> [ReviewTarget] {
        switch settings.targetOrder {
        case .sequential:
            return interleaveByAppClass(queue)
        case .random:
            return interleaveByAppClass(queue.shuffled())
        case .configuredPriority:
            return queue
        case .applicationPriority:
            return orderByApplicationPriority(queue)
        case .targetRotation:
            return orderForRotation(queue, visited: visited)
        }
    }

    /// Prefer Cursor → Chrome → Finder → Preview → Safari → others, then display name.
    public static func orderByApplicationPriority(_ queue: [ReviewTarget]) -> [ReviewTarget] {
        queue.sorted { a, b in
            let pa = applicationPriority(of: a)
            let pb = applicationPriority(of: b)
            if pa != pb { return pa < pb }
            return a.identity.localizedCaseInsensitiveCompare(b.identity) == .orderedAscending
        }
    }

    /// Least-visited first, then application priority — enables rotation across long sessions.
    public static func orderForRotation(
        _ queue: [ReviewTarget],
        visited: VisitedTargetTracker
    ) -> [ReviewTarget] {
        queue.sorted { a, b in
            let ka = identityKey(a)
            let kb = identityKey(b)
            let va = visited.visitCount(for: ka)
            let vb = visited.visitCount(for: kb)
            if va != vb { return va < vb }
            let pa = applicationPriority(of: a)
            let pb = applicationPriority(of: b)
            if pa != pb { return pa < pb }
            return a.identity.localizedCaseInsensitiveCompare(b.identity) == .orderedAscending
        }
    }

    public static func applicationPriority(of target: ReviewTarget) -> Int {
        switch target {
        case .editorFile:
            return 0
        case .chromeTab:
            return 1
        case .discoveredApp(let bundleID, _, let classification):
            return WorkspaceDiscoveryPlanner.priority(
                bundleID: bundleID,
                classification: classification
            )
        }
    }

    /// Merge a refreshed discovery into an existing queue without dropping the current target.
    public static func refreshQueue(
        current: ReviewTarget?,
        remainingFromIndex index: Int,
        previous: [ReviewTarget],
        settings: ReviewWorkspaceSettings,
        discovered: [DiscoveredApplication],
        workflowTargets: [TargetApp],
        visited: VisitedTargetTracker = .empty
    ) -> [ReviewTarget] {
        let rebuilt = buildQueue(
            settings: settings,
            discovered: discovered,
            workflowTargets: workflowTargets,
            visited: visited
        )
        var result: [ReviewTarget] = []
        if let current {
            result.append(current)
        }
        let currentKey = current.map(identityKey)
        let runningBundleIDs = Set(discovered.map(\.bundleID))
        let allowlist = Set(workflowTargets.map(\.bundleID))

        for target in rebuilt {
            let key = identityKey(target)
            if key == currentKey { continue }
            // Drop discovered-only apps that are no longer running.
            if case .discoveredApp(let bundleID, _, _) = target,
               !allowlist.contains(bundleID),
               !runningBundleIDs.contains(bundleID)
            {
                continue
            }
            result.append(target)
        }
        if index + 1 < previous.count {
            for leftover in previous[(index + 1)...] {
                let key = identityKey(leftover)
                if result.contains(where: { identityKey($0) == key }) { continue }
                switch leftover {
                case .editorFile, .chromeTab:
                    result.append(leftover)
                case .discoveredApp(let bundleID, _, _):
                    // Keep allowlisted apps; drop unavailable discovery extras.
                    if allowlist.contains(bundleID) || runningBundleIDs.contains(bundleID) {
                        result.append(leftover)
                    }
                }
            }
        }
        return result.isEmpty ? rebuilt : result
    }

    public static func identityKey(_ target: ReviewTarget) -> String {
        switch target {
        case .editorFile(let path, _):
            return "file:\(path)"
        case .chromeTab(let label, let index):
            return "tab:\(index):\(label)"
        case .discoveredApp(let bundleID, _, _):
            return "app:\(bundleID)"
        }
    }

    /// Result of one crawl tick (randomized; recovers after End instead of sitting there).
    public struct CrawlTick: Equatable, Sendable {
        public var action: ActionKind
        /// True when this action is End — next ticks recover or switch.
        public var markedBoundary: Bool
        /// Leave this target early (open/switch another file or next queue item).
        public var endDwellEarly: Bool
        public var resetsDownStreak: Bool

        public init(
            action: ActionKind,
            markedBoundary: Bool = false,
            endDwellEarly: Bool = false,
            resetsDownStreak: Bool = false
        ) {
            self.action = action
            self.markedBoundary = markedBoundary
            self.endDwellEarly = endDwellEarly
            self.resetsDownStreak = resetsDownStreak
        }
    }

    /// Randomized progressive crawl. Prefers top/middle; avoids racing to End.
    public static func progressiveCrawlTick(
        step: Int,
        classification: TargetAppClass,
        atBoundary: Bool,
        consecutiveDown: Int,
        pace: ContentPaceHint = .reading
    ) -> CrawlTick {
        let conservative = (classification == .generic || classification == .finder)
        let roll = Int.random(in: 0..<100)

        // Fresh file: settle at top / upper mid — highlight, small moves (no End/PageDown spam).
        if step <= 4 {
            if step == 1 {
                return CrawlTick(action: .pageNavigate(.home), resetsDownStreak: true)
            }
            // Browsers never use geometric contentClick (hits Chrome chrome).
            if classification != .browser, !conservative, roll < 55 {
                return CrawlTick(action: .contentClick, resetsDownStreak: true)
            }
            if classification != .browser, !conservative, roll < 80 {
                return CrawlTick(action: .highlightNavigate(direction: .down), resetsDownStreak: true)
            }
            return CrawlTick(
                action: .arrowNavigate(direction: .down, presses: 1, intervalSeconds: 0)
            )
        }

        // Short content or stuck at bottom: switch file — do not keep End-keying.
        if pace == .shortContent || atBoundary {
            if classification == .editor {
                return CrawlTick(
                    action: .explorerFileSwitch(direction: Bool.random() ? .next : .previous),
                    resetsDownStreak: true
                )
            }
            if classification == .browser {
                return CrawlTick(
                    action: .switchTab(direction: Bool.random() ? .next : .previous),
                    endDwellEarly: roll < 25,
                    resetsDownStreak: true
                )
            }
            return CrawlTick(action: .pageNavigate(.home), resetsDownStreak: true)
        }

        // Too much downward motion: pull back to top/middle instead of End.
        if consecutiveDown >= 10 {
            if roll < 45 {
                return CrawlTick(action: .pageNavigate(.home), resetsDownStreak: true)
            }
            if roll < 75 {
                return CrawlTick(action: .pageNavigate(.pageUp), resetsDownStreak: true)
            }
            return CrawlTick(
                action: .arrowNavigate(direction: .up, presses: Int.random(in: 3...6), intervalSeconds: 0),
                resetsDownStreak: true
            )
        }

        // Mid-file variety: highlight lines, page/arrow keys — never scroll-wheel in default crawl.
        // Never geometric contentClick in browsers (Chrome toolbar / tab strip risk).
        if classification != .browser, !conservative, roll < 18 {
            return CrawlTick(action: .contentClick, resetsDownStreak: true)
        }
        if classification != .browser, !conservative, roll < 32 {
            let dir: ArrowDirection = Bool.random() ? .down : .up
            return CrawlTick(action: .highlightNavigate(direction: dir), resetsDownStreak: dir == .up)
        }
        if roll < 42 {
            return CrawlTick(
                action: .arrowNavigate(direction: .up, presses: Int.random(in: 1...3), intervalSeconds: 0),
                resetsDownStreak: true
            )
        }
        if roll < 55 {
            return CrawlTick(
                action: .arrowNavigate(direction: .up, presses: Int.random(in: 2...4), intervalSeconds: 0),
                resetsDownStreak: true
            )
        }
        // Prefer Page Down for longer progress; arrows for fine movement.
        if pace == .longContent {
            if roll < 78 {
                return CrawlTick(action: .pageNavigate(.pageDown))
            }
            return CrawlTick(
                action: .arrowNavigate(direction: .down, presses: Int.random(in: 2...4), intervalSeconds: 0)
            )
        }
        if roll < 72, consecutiveDown < 8 {
            return CrawlTick(action: .pageNavigate(.pageDown))
        }
        if roll < 88 {
            return CrawlTick(
                action: .arrowNavigate(direction: .down, presses: Int.random(in: 1...3), intervalSeconds: 0)
            )
        }
        if !conservative, step > 14, roll < 94 {
            return CrawlTick(
                action: surfaceSwitchAction(classification: classification),
                resetsDownStreak: true
            )
        }
        return CrawlTick(
            action: .arrowNavigate(
                direction: .down,
                presses: 1,
                intervalSeconds: 0
            )
        )
    }

    /// Backward-compatible helper (tests / seeds). Prefer `progressiveCrawlTick`.
    public static func progressiveCrawlAction(
        step: Int,
        classification: TargetAppClass
    ) -> ActionKind {
        progressiveCrawlTick(
            step: step,
            classification: classification,
            atBoundary: false,
            consecutiveDown: min(step, 9)
        ).action
    }

    private static func surfaceSwitchAction(classification: TargetAppClass) -> ActionKind {
        let direction: WindowDirection = Bool.random() ? .next : .previous
        switch classification {
        case .editor:
            // Always sidebar explorer — never Ctrl+Tab among already-open tabs.
            return .explorerFileSwitch(direction: direction)
        case .browser:
            return .switchTab(direction: direction)
        case .finder, .generic:
            return .pageNavigate(.home)
        }
    }

    /// Alternate editor/browser (and other) targets so Chrome is not starved after Cursor.
    public static func interleaveByAppClass(_ targets: [ReviewTarget]) -> [ReviewTarget] {
        var editors: [ReviewTarget] = []
        var browsers: [ReviewTarget] = []
        var others: [ReviewTarget] = []
        for target in targets {
            switch targetAppClass(target) {
            case .editor: editors.append(target)
            case .browser: browsers.append(target)
            case .finder, .generic: others.append(target)
            }
        }
        var result: [ReviewTarget] = []
        result.reserveCapacity(targets.count)
        while !editors.isEmpty || !browsers.isEmpty {
            if let e = editors.first {
                result.append(e)
                editors.removeFirst()
            }
            if let b = browsers.first {
                result.append(b)
                browsers.removeFirst()
            }
        }
        result.append(contentsOf: others)
        return result
    }

    private static func targetAppClass(_ target: ReviewTarget) -> TargetAppClass {
        switch target {
        case .editorFile: return .editor
        case .chromeTab: return .browser
        case .discoveredApp(_, _, let classification): return classification
        }
    }
}
