import Foundation

public struct TimedReviewPick: Equatable, Sendable {
    public var action: ActionKind
    public var gapSeconds: Double
    /// Structured log label (e.g. targetSelected, fileOpened) — never document body.
    public var metaKind: String?
    /// User-configured identity (file name / tab label).
    public var identity: String?

    public init(
        action: ActionKind,
        gapSeconds: Double,
        metaKind: String? = nil,
        identity: String? = nil
    ) {
        self.action = action
        self.gapSeconds = gapSeconds
        self.metaKind = metaKind
        self.identity = identity
    }
}

/// Builds and walks the universal navigation queue (config + optional live discovery).
public struct ReviewTargetSelector: Sendable {
    public var settings: ReviewWorkspaceSettings
    public var editorBundleID: String?
    public var browserBundleID: String?
    public var discovered: [DiscoveredApplication]
    public var workflowTargets: [TargetApp]

    public init(
        settings: ReviewWorkspaceSettings,
        editorBundleID: String? = nil,
        browserBundleID: String? = nil,
        discovered: [DiscoveredApplication] = [],
        workflowTargets: [TargetApp] = []
    ) {
        self.settings = settings
        self.editorBundleID = editorBundleID
        self.browserBundleID = browserBundleID
        self.discovered = discovered
        self.workflowTargets = workflowTargets
    }

    public func makeQueue() -> [ReviewTarget] {
        var targets = workflowTargets
        if targets.isEmpty {
            if let editorBundleID {
                targets.append(TargetApp(bundleID: editorBundleID, classification: .editor))
            }
            if let browserBundleID {
                targets.append(TargetApp(bundleID: browserBundleID, classification: .browser))
            }
        }

        var queue = NavigationPlanner.buildQueue(
            settings: settings,
            discovered: discovered,
            workflowTargets: targets
        )

        // If still empty (no files, tabs, discovery), fall back to current surfaces.
        if queue.isEmpty {
            if editorBundleID != nil {
                queue.append(.editorFile(path: "", displayName: "(current editor)"))
            }
            if browserBundleID != nil {
                queue.append(.chromeTab(label: "(current tab)", index: 0))
            }
        }
        return queue
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
    /// Counts of discovered targets by classification label (dashboard).
    public var discoveryCounts: [String: Int]
    /// Identity of the target whose dwell just ended (for logging).
    public var completedIdentity: String?
    private var enterPhase: ReviewEnterPhase
    private var pendingRefresh: Bool
    private var pendingAdvanceAfterRefresh: Bool
    /// After Home/End (or long downward streak), bias toward up / switch / next target.
    private var atBoundary: Bool
    private var consecutiveDown: Int
    /// Per-file/tab reading window (adaptive length).
    private var surfaceSession: AdaptiveSurfaceSession?
    /// File/tab switches on the current app before forcing the next Target.
    private var surfaceSwitchesOnApp: Int
    /// After this many surface switches, leave for another app (when ≥2 apps in queue).
    private var maxSurfaceSwitchesBeforeAppChange: Int
    /// After open/switch, force a settle pause before review keys.
    private var pendingPageSettle: Bool
    /// Consecutive non-wait actions (feeds PacingController force-pause).
    private var consecutiveActions: Int
    /// Smart Chrome crawl (nil when disabled or not on a browser target).
    public var chromeCrawl: ChromeCrawlSession?
    /// Session visit counts + lifecycle by identity key.
    public var visited: VisitedTargetTracker
    /// Ordered lifecycle history for the dashboard / logs.
    public var history: NavigationHistory

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
        // nil forces the first `nextPick` through `startTarget` (dwell + lifecycle).
        self.current = nil
        self.targetsCompleted = 0
        self.nextPreview = queue.first
        self.crawlStepsOnTarget = 0
        self.enterPhase = .focusApp
        self.discoveryCounts = Self.countByKind(queue)
        self.pendingRefresh = false
        self.pendingAdvanceAfterRefresh = false
        self.completedIdentity = nil
        self.atBoundary = false
        self.consecutiveDown = 0
        self.surfaceSession = nil
        self.surfaceSwitchesOnApp = 0
        self.maxSurfaceSwitchesBeforeAppChange = Self.plannedSurfaceSwitches(for: queue)
        self.pendingPageSettle = false
        self.consecutiveActions = 0
        self.chromeCrawl = nil
        self.visited = .empty
        self.history = NavigationHistory()
        for target in queue {
            let key = NavigationPlanner.identityKey(target)
            visited.markPending(key)
            history.record(
                identityKey: key,
                displayName: target.identity,
                lifecycle: .pending
            )
        }
    }

    private func makeChromeCrawl(now: Date) -> ChromeCrawlSession {
        ChromeCrawlSession(
            settings: settings.chrome,
            pacing: settings.pacing,
            pacingCustom: settings.pacingCustom,
            now: now
        )
    }

    private func paceGap(_ context: PacingContext) -> Double {
        settings.gapSeconds(for: context)
    }

    /// True when the engine should refresh the accessible page snapshot before the next pick.
    public var needsWebInspect: Bool {
        guard settings.chrome.enabled, currentAppClass() == .browser else { return false }
        return chromeCrawl?.needsInspect ?? true
    }

    /// Apply a best-effort page snapshot from Accessibility.
    public mutating func applyWebSnapshot(_ snapshot: WebPageSnapshot, now: Date = Date()) {
        if chromeCrawl == nil, settings.chrome.enabled {
            chromeCrawl = makeChromeCrawl(now: now)
        }
        guard var session = chromeCrawl else { return }
        session.applySnapshot(snapshot, now: now)
        let groups = snapshot.tabs.compactMap { tab -> ChromeTabGroup? in
            guard tab.name.hasPrefix("Tab group: ") else { return nil }
            let title = String(tab.name.dropFirst("Tab group: ".count))
            return ChromeTabGroup(id: tab.identity, title: title)
        }
        if !groups.isEmpty {
            session.tabGroups = groups
        }
        chromeCrawl = session
        // Long GitHub/docs pages: stretch the current surface + app dwell.
        if session.pageReadWeight >= 0.7 {
            extendDwellForPageWeight(now: now)
            if surfaceSession == nil {
                beginSurfaceSession(now: now)
            } else if var surface = surfaceSession {
                let extra = settings.randomFileDwellSeconds(distinctAppCount: distinctAppCount())
                    * (session.pageReadWeight - 0.4)
                surface.endsAt = surface.endsAt.addingTimeInterval(max(2, extra))
                surfaceSession = surface
            }
        }
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

        if pendingAdvanceAfterRefresh {
            pendingAdvanceAfterRefresh = false
            guard let next = nextQueueIndex(after: index) else { return nil }
            return startTarget(at: next, now: now)
        }

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

        if pendingPageSettle {
            pendingPageSettle = false
            consecutiveActions = 0
            return TimedReviewPick(
                action: .wait(seconds: 0.05),
                gapSeconds: paceGap(.pageSettle),
                metaKind: "pageSettle",
                identity: current?.identity
            )
        }

        if let end = dwellEndsAt, now >= end {
            markCurrentCompleted(at: now)
            targetsCompleted += 1
            completedIdentity = current?.identity
            recordMetaCompleted = true
            if settings.refreshTargetsBetweenDwells && settings.discoverRunningApps {
                pendingRefresh = true
                pendingAdvanceAfterRefresh = true
                dwellEndsAt = nil
                return TimedReviewPick(
                    action: .wait(seconds: 0.05),
                    gapSeconds: 0.01,
                    metaKind: "awaitingRefresh",
                    identity: completedIdentity
                )
            }
            let nextIndex = index + 1
            if nextIndex >= queue.count {
                if settings.loopTargets {
                    reorderQueueForLoop()
                    return startTarget(at: 0, now: now)
                }
                return nil
            }
            if let preferred = preferredAlternateIndex(after: index) {
                return startTarget(at: preferred, now: now)
            }
            return startTarget(at: nextIndex, now: now)
        }

        crawlStepsOnTarget += 1

        // Smart Chrome / browser crawl when enabled.
        if settings.chrome.enabled, currentAppClass() == .browser {
            if chromeCrawl == nil {
                chromeCrawl = makeChromeCrawl(now: now)
            }
            if var session = chromeCrawl {
                session.pacing = settings.pacing
                session.pacingCustom = settings.pacingCustom
                let decision = session.nextDecision(now: now)
                chromeCrawl = session
                if let pick = mapChromeDecision(decision, now: now) {
                    return pick
                }
            }
        }

        // Per-file dwell expired → another file/tab, or rotate to the next Target app.
        if let session = surfaceSession, session.isExpired(at: now) {
            surfaceSwitchesOnApp += 1
            if shouldRotateToAlternateApp() {
                return completeTargetEarly(now: now, reasonAction: .wait(seconds: 0.05))
            }
            return switchSurfaceWithinApp(now: now)
        }

        let tick = makeCrawlTick(now: now)
        if tick.endDwellEarly {
            return completeTargetEarly(now: now, reasonAction: tick.action)
        }
        if isSurfaceSwitch(tick.action) {
            surfaceSwitchesOnApp += 1
            if shouldRotateToAlternateApp() {
                return completeTargetEarly(now: now, reasonAction: tick.action)
            }
            beginSurfaceSession(now: now)
            pendingPageSettle = true
            consecutiveActions = 0
            return TimedReviewPick(
                action: tick.action,
                gapSeconds: paceGap(.surfaceSwitch),
                metaKind: "surfaceSwitched",
                identity: current?.identity
            )
        }
        consecutiveActions += 1
        let weight = chromeCrawl?.pageReadWeight ?? max(0.4, Double(consecutiveDown) / 16.0)
        return TimedReviewPick(
            action: tick.action,
            gapSeconds: paceGap(.review(weight: weight, scrolls: crawlStepsOnTarget, atEnd: atBoundary)),
            metaKind: tick.markedBoundary ? "reachedContentBoundary" : "navigationExecuted",
            identity: current?.identity
        )
    }

    /// Set when a target dwell just completed (engine records TargetCompleted).
    public var recordMetaCompleted: Bool = false

    /// True after a dwell ends when the engine should re-discover apps.
    public var needsDiscoveryRefresh: Bool {
        pendingRefresh && settings.refreshTargetsBetweenDwells && settings.discoverRunningApps
    }

    /// Apply a mid-run discovery refresh (engine calls between targets).
    public mutating func applyDiscoveryRefresh(
        discovered: [DiscoveredApplication],
        workflowTargets: [TargetApp]
    ) {
        pendingRefresh = false
        let previousKeys = Set(queue.map(NavigationPlanner.identityKey))
        queue = NavigationPlanner.refreshQueue(
            current: current,
            remainingFromIndex: index,
            previous: queue,
            settings: settings,
            discovered: discovered,
            workflowTargets: workflowTargets,
            visited: visited
        )
        discoveryCounts = Self.countByKind(queue)
        let nextKeys = Set(queue.map(NavigationPlanner.identityKey))
        for key in previousKeys.subtracting(nextKeys) {
            if key == current.map(NavigationPlanner.identityKey) { continue }
            visited.markSkipped(key)
            history.record(
                identityKey: key,
                displayName: key,
                lifecycle: .skipped
            )
        }
        for target in queue {
            let key = NavigationPlanner.identityKey(target)
            if !previousKeys.contains(key) {
                visited.markPending(key)
                history.record(
                    identityKey: key,
                    displayName: target.identity,
                    lifecycle: .pending
                )
            }
        }
        if let current, let newIndex = queue.firstIndex(of: current) {
            index = newIndex
        }
        let upcoming = index + 1
        nextPreview = upcoming < queue.count ? queue[upcoming] : (queue.count > 1 ? queue[0] : nil)
    }

    private mutating func startTarget(at i: Int, now: Date) -> TimedReviewPick {
        let safe = ((i % queue.count) + queue.count) % queue.count
        index = safe
        current = queue[safe]
        enterPhase = .focusApp
        crawlStepsOnTarget = 0
        atBoundary = false
        consecutiveDown = 0
        surfaceSession = nil
        surfaceSwitchesOnApp = 0
        maxSurfaceSwitchesBeforeAppChange = Self.plannedSurfaceSwitches(for: queue)
        let dwell = settings.smartAppDwellSeconds(distinctAppCount: distinctAppCount())
        dwellStartedAt = now
        dwellEndsAt = now.addingTimeInterval(dwell)
        let upcoming = (safe + 1) % queue.count
        nextPreview = queue.count > 1 ? queue[upcoming] : nil
        if settings.chrome.enabled, appClass(of: queue[safe]) == .browser {
            // Preserve visited files/tabs across Chrome dwells in the same run.
            if var existing = chromeCrawl {
                existing.prepareForNewBrowserDwell(now: now)
                chromeCrawl = existing
            } else {
                chromeCrawl = makeChromeCrawl(now: now)
            }
        }
        // Keep chromeCrawl memory when rotating to Cursor/etc. so return visits stay fresh.
        markCurrentActive(at: now)
        return focusAppPick()
    }

    /// Leave the current target immediately (e.g. Chrome activate failed — don't keep crawling Cursor).
    public mutating func abandonCurrentTarget(now: Date) {
        markCurrentSkipped(at: now)
        targetsCompleted += 1
        completedIdentity = current?.identity
        recordMetaCompleted = true
        atBoundary = false
        consecutiveDown = 0
        crawlStepsOnTarget = 0
        surfaceSession = nil

        let nextIdx: Int?
        if let preferred = preferredAlternateIndex(after: index) {
            nextIdx = preferred
        } else if index + 1 < queue.count {
            nextIdx = index + 1
        } else if settings.loopTargets {
            reorderQueueForLoop()
            nextIdx = 0
        } else {
            nextIdx = nil
        }

        guard let nextIdx, queue.indices.contains(nextIdx) else {
            current = nil
            dwellEndsAt = nil
            return
        }
        _ = startTarget(at: nextIdx, now: now)
    }

    /// Leave current dwell early (e.g. after End) and move to another target/file.
    private mutating func completeTargetEarly(now: Date, reasonAction: ActionKind) -> TimedReviewPick {
        markCurrentCompleted(at: now)
        targetsCompleted += 1
        completedIdentity = current?.identity
        recordMetaCompleted = true
        atBoundary = false
        consecutiveDown = 0
        if settings.refreshTargetsBetweenDwells && settings.discoverRunningApps {
            pendingRefresh = true
            pendingAdvanceAfterRefresh = true
            dwellEndsAt = nil
            return TimedReviewPick(
                action: reasonAction,
                gapSeconds: paceGap(.surfaceSwitch),
                metaKind: "boundarySwitchTarget",
                identity: completedIdentity
            )
        }
        let nextIndex = index + 1
        if nextIndex >= queue.count {
            if settings.loopTargets {
                reorderQueueForLoop()
                return startTarget(at: 0, now: now)
            }
            return TimedReviewPick(
                action: reasonAction,
                gapSeconds: paceGap(.surfaceSwitch),
                metaKind: "boundarySwitchTarget",
                identity: completedIdentity
            )
        }
        if let preferred = preferredAlternateIndex(after: index) {
            return startTarget(at: preferred, now: now)
        }
        return startTarget(at: nextIndex, now: now)
    }

    private mutating func markCurrentCompleted(at now: Date) {
        guard let current else { return }
        let key = NavigationPlanner.identityKey(current)
        visited.markCompleted(key, at: now)
        history.record(
            identityKey: key,
            displayName: current.identity,
            lifecycle: .completed,
            at: now
        )
    }

    private mutating func markCurrentSkipped(at now: Date) {
        guard let current else { return }
        let key = NavigationPlanner.identityKey(current)
        visited.markSkipped(key)
        history.record(
            identityKey: key,
            displayName: current.identity,
            lifecycle: .skipped,
            at: now
        )
    }

    private mutating func markCurrentActive(at now: Date) {
        guard let current else { return }
        let key = NavigationPlanner.identityKey(current)
        visited.markActive(key, at: now)
        history.record(
            identityKey: key,
            displayName: current.identity,
            lifecycle: .active,
            at: now
        )
    }

    private mutating func reorderQueueForLoop() {
        queue = NavigationPlanner.orderQueue(queue, settings: settings, visited: visited)
        if let current, let newIndex = queue.firstIndex(of: current) {
            index = newIndex
        }
    }

    /// Prefer the next target of a different app class (e.g. Chrome after Cursor).
    private func preferredAlternateIndex(after i: Int) -> Int? {
        guard queue.indices.contains(i) else { return nil }
        let currentClass = appClass(of: queue[i])
        let range: [Int]
        if settings.loopTargets {
            range = Array((i + 1)..<queue.count) + Array(0..<i)
        } else {
            range = Array((i + 1)..<queue.count)
        }
        return range.first { appClass(of: queue[$0]) != currentClass }
    }

    private func nextQueueIndex(after i: Int) -> Int? {
        if let preferred = preferredAlternateIndex(after: i) {
            return preferred
        }
        let next = i + 1
        if next < queue.count { return next }
        if settings.loopTargets { return 0 }
        return nil
    }

    private func appClass(of target: ReviewTarget) -> TargetAppClass {
        switch target {
        case .editorFile: return .editor
        case .chromeTab: return .browser
        case .discoveredApp(_, _, let classification): return classification
        }
    }

    private mutating func makeCrawlTick(now: Date) -> NavigationPlanner.CrawlTick {
        let classification = currentAppClass()
        let pace: ContentPaceHint
        if let session = surfaceSession {
            pace = ContentPaceHint.from(session: session, atBoundary: atBoundary)
        } else {
            pace = .reading
        }
        let tick = NavigationPlanner.progressiveCrawlTick(
            step: crawlStepsOnTarget,
            classification: classification,
            atBoundary: atBoundary,
            consecutiveDown: consecutiveDown,
            pace: pace
        )
        var resolved = tick
        if isSurfaceSwitch(tick.action),
           !PacingController.allowOpportunisticSurfaceHop(
               profile: settings.pacing,
               crawlSteps: crawlStepsOnTarget,
               consecutiveDown: consecutiveDown
           )
        {
            // Prefer finishing review over mid-dwell hops under Relaxed/Deliberate.
            resolved = NavigationPlanner.CrawlTick(
                action: consecutiveDown >= 4
                    ? .pageNavigate(.pageUp)
                    : .pageNavigate(.pageDown),
                resetsDownStreak: consecutiveDown >= 4
            )
        }
        if resolved.markedBoundary {
            atBoundary = true
        } else if resolved.resetsDownStreak {
            atBoundary = false
            consecutiveDown = 0
        } else if isDownward(resolved.action) {
            consecutiveDown += 1
        } else {
            consecutiveDown = max(0, consecutiveDown - 1)
        }
        surfaceSession?.observe(
            action: resolved.action,
            markedBoundary: resolved.markedBoundary,
            settings: settings,
            now: now
        )
        return resolved
    }

    private func isDownward(_ action: ActionKind) -> Bool {
        AdaptiveSurfaceSession.isDownward(action)
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
                gapSeconds: paceGap(.navigation(weight: 0.5, consecutive: consecutiveActions)),
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
                gapSeconds: paceGap(.navigation(weight: 0.5, consecutive: consecutiveActions)),
                metaKind: "applicationFocused",
                identity: current?.identity
            )
        case .discoveredApp(let bundleID, _, _):
            return TimedReviewPick(
                action: .activateApp(bundleID: bundleID),
                gapSeconds: paceGap(.navigation(weight: 0.5, consecutive: consecutiveActions)),
                metaKind: "applicationFocused",
                identity: current?.identity
            )
        }
    }

    private mutating func selectSurfacePick() -> TimedReviewPick {
        enterPhase = .crawl
        beginSurfaceSession(now: Date())
        pendingPageSettle = true
        consecutiveActions = 0
        switch current! {
        case .editorFile(let path, _):
            if path.isEmpty {
                return TimedReviewPick(
                    action: .explorerFileSwitch(direction: Bool.random() ? .next : .previous),
                    gapSeconds: paceGap(.surfaceSwitch),
                    metaKind: "fileSelected",
                    identity: current?.identity
                )
            }
            return TimedReviewPick(
                action: .openExistingFile(path: path),
                gapSeconds: paceGap(.navigation(weight: 0.55)),
                metaKind: "fileOpened",
                identity: current?.identity
            )
        case .chromeTab(_, let tabIndex):
            let direction: WindowDirection = (tabIndex % 2 == 0) ? .next : .previous
            return TimedReviewPick(
                action: .switchTab(direction: direction),
                gapSeconds: paceGap(.surfaceSwitch),
                metaKind: "tabSelected",
                identity: current?.identity
            )
        case .discoveredApp(_, _, let classification):
            switch classification {
            case .editor:
                return TimedReviewPick(
                    action: .explorerFileSwitch(direction: Bool.random() ? .next : .previous),
                    gapSeconds: paceGap(.surfaceSwitch),
                    metaKind: "surfaceSelected",
                    identity: current?.identity
                )
            case .browser:
                return TimedReviewPick(
                    action: .switchTab(direction: Bool.random() ? .next : .previous),
                    gapSeconds: paceGap(.surfaceSwitch),
                    metaKind: "surfaceSelected",
                    identity: current?.identity
                )
            case .finder, .generic:
                return TimedReviewPick(
                    action: .wait(seconds: paceGap(.pageSettle)),
                    gapSeconds: 0.05,
                    metaKind: "surfaceSelected",
                    identity: current?.identity
                )
            }
        }
    }

    private mutating func mapChromeDecision(_ decision: ChromeCrawlDecision, now: Date) -> TimedReviewPick? {
        switch decision {
        case .inspect:
            consecutiveActions = 0
            return TimedReviewPick(
                action: .inspectWebPage,
                gapSeconds: paceGap(.pageSettle),
                metaKind: "pageInspectRequested",
                identity: current?.identity
            )
        case .activate(let identity, let x, let y):
            if var session = chromeCrawl {
                session.noteActivationCompleted()
                chromeCrawl = session
            }
            consecutiveActions += 1
            pendingPageSettle = true
            return TimedReviewPick(
                action: .activateWebNavTarget(identity: identity, x: x, y: y),
                gapSeconds: paceGap(.navigation(
                    weight: chromeCrawl?.pageReadWeight ?? 0.5,
                    candidates: chromeCrawl?.pending.count ?? 0,
                    consecutive: consecutiveActions
                )),
                metaKind: "webNavActivated",
                identity: identity
            )
        case .keyTraverse(let motion):
            let action = motion.asAction
            if motion.isDownward {
                consecutiveDown += 1
            } else {
                consecutiveDown = max(0, consecutiveDown - 1)
            }
            surfaceSession?.observe(
                action: action,
                markedBoundary: false,
                settings: settings,
                now: now
            )
            extendDwellForPageWeight(now: now)
            consecutiveActions = 0
            return TimedReviewPick(
                action: action,
                gapSeconds: paceGap(.review(
                    weight: chromeCrawl?.pageReadWeight ?? 0.5,
                    scrolls: chromeCrawl?.scrollsOnPage ?? crawlStepsOnTarget,
                    atEnd: atBoundary
                )),
                metaKind: "webKeyTraverse",
                identity: chromeCrawl?.currentURL
            )
        case .browserBack:
            // Architectural refusal: never drive Chrome history Back.
            return TimedReviewPick(
                action: .wait(seconds: 0.2),
                gapSeconds: 0.05,
                metaKind: "browserBackRefused",
                identity: chromeCrawl?.currentURL
            )
        case .switchTab(let direction):
            surfaceSwitchesOnApp += 1
            if shouldRotateToAlternateApp() {
                return completeTargetEarly(now: now, reasonAction: .switchTab(direction: direction))
            }
            beginSurfaceSession(now: now)
            pendingPageSettle = true
            consecutiveActions = 0
            return TimedReviewPick(
                action: .switchTab(direction: direction),
                gapSeconds: paceGap(.surfaceSwitch),
                metaKind: "surfaceSwitched",
                identity: current?.identity
            )
        case .wait(let seconds):
            consecutiveActions = 0
            return TimedReviewPick(
                action: .wait(seconds: seconds),
                gapSeconds: 0.05,
                metaKind: "webWait",
                identity: chromeCrawl?.currentURL
            )
        case .yieldToUniversal:
            return nil
        }
    }

    private mutating func beginSurfaceSession(now: Date) {
        atBoundary = false
        consecutiveDown = 0
        let weight = chromeCrawl?.pageReadWeight ?? max(0.45, Double(consecutiveDown) / 20.0)
        let scaled = settings.weightedFileDwellSeconds(
            weight: weight,
            distinctAppCount: distinctAppCount()
        )
        surfaceSession = AdaptiveSurfaceSession(now: now, durationSeconds: scaled)
    }

    /// Longer pages/files keep the app dwell open intelligently (capped).
    private mutating func extendDwellForPageWeight(now: Date) {
        let weight = chromeCrawl?.pageReadWeight ?? 0.4
        guard weight >= 0.55, let end = dwellEndsAt else { return }
        let remaining = end.timeIntervalSince(now)
        guard remaining > 0 else { return }
        let extra = settings.randomFileDwellExtensionSeconds() * min(1.5, weight)
        let cappedEnd = (dwellStartedAt ?? now).addingTimeInterval(settings.dwellMaxSeconds)
        let proposed = end.addingTimeInterval(extra)
        dwellEndsAt = min(proposed, cappedEnd)
        if var session = surfaceSession {
            session.endsAt = max(session.endsAt, now.addingTimeInterval(extra * 0.85))
            surfaceSession = session
        }
    }

    private func shouldRotateToAlternateApp() -> Bool {
        distinctAppCount() >= 2
            && surfaceSwitchesOnApp >= maxSurfaceSwitchesBeforeAppChange
            && preferredAlternateIndex(after: index) != nil
    }

    private func distinctAppCount() -> Int {
        Set(queue.map { Self.appClassKey(of: $0) }).count
    }

    private static func plannedSurfaceSwitches(for queue: [ReviewTarget]) -> Int {
        let apps = Set(queue.map { appClassKey(of: $0) }).count
        guard apps >= 2 else { return Int.max }
        // More within-app hops for variety before rotating to the other Target.
        return Int.random(in: 3...6)
    }

    private static func appClassKey(of target: ReviewTarget) -> String {
        switch target {
        case .editorFile: return "editor"
        case .chromeTab: return "browser"
        case .discoveredApp(let bundleID, _, let classification):
            switch classification {
            case .editor: return "editor:\(bundleID)"
            case .browser: return "browser:\(bundleID)"
            case .finder: return "finder:\(bundleID)"
            case .generic: return "generic:\(bundleID)"
            }
        }
    }

    private mutating func switchSurfaceWithinApp(now: Date) -> TimedReviewPick {
        beginSurfaceSession(now: now)
        pendingPageSettle = true
        consecutiveActions = 0
        let classification = currentAppClass()
        // Prefer next when this surface has been hopped more than previous (simple variety).
        let preferNext = (surfaceSwitchesOnApp % 2 == 0) || Bool.random()
        let direction: WindowDirection = preferNext ? .next : .previous
        let action: ActionKind
        switch classification {
        case .editor:
            action = .explorerFileSwitch(direction: direction)
        case .browser:
            action = .switchTab(direction: direction)
        case .finder, .generic:
            action = .pageNavigate(.home)
        }
        // Record hop against chrome page key when known so revisit tracking can prefer novelty.
        if classification == .browser, let url = chromeCrawl?.currentURL, !url.isEmpty {
            visited.markCompleted("surface:\(url)", at: now)
        } else if classification == .editor {
            visited.markCompleted("surface:editor:\(surfaceSwitchesOnApp)", at: now)
        }
        return TimedReviewPick(
            action: action,
            gapSeconds: paceGap(.surfaceSwitch),
            metaKind: "fileDwellComplete",
            identity: current?.identity
        )
    }

    private func isSurfaceSwitch(_ action: ActionKind) -> Bool {
        switch action {
        case .explorerFileSwitch, .switchTab:
            return true
        default:
            return false
        }
    }

    private func currentAppClass() -> TargetAppClass {
        switch current {
        case .editorFile: return .editor
        case .chromeTab: return .browser
        case .discoveredApp(_, _, let c): return c
        case .none: return .generic
        }
    }

    private static func countByKind(_ queue: [ReviewTarget]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for target in queue {
            counts[target.kindLabel, default: 0] += 1
        }
        return counts
    }
}
