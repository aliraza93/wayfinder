import Actions
import Adapters
import AppControl
import AppPresentation
import Config
import CoreEngine
import Domain
import InputSynthesis
import Observability
import Permissions
import Safety
import SwiftUI
import WaypointAccessibility

/// Shared app session: onboarding, editor, run control, timeline — engine off main.
@MainActor
final class AppSession: ObservableObject {
    @Published var showOnboarding = false
    @Published var showEditor = false
    @Published var showTimeline = false

    @Published private(set) var permissionLabel = "Accessibility: Unknown"
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var liveStatusLine = "Idle"
    @Published private(set) var workflowNames: [String] = []
    @Published var selectedWorkflow: String?
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var canStart = false
    @Published private(set) var lastMessage = ""
    @Published private(set) var saveConfirmationMessage: String?
    @Published private(set) var progressLines: [String] = []
    @Published private(set) var dashboard: DashboardRunSnapshot = .idle
    /// When set, the main shell selects this sidebar section (menu bar → Open Dashboard / Settings).
    @Published var pendingSidebarSection: AppSidebarSection?

    /// Latest read-only Scan Workspace result. Nil until the user scans.
    @Published private(set) var discoverySnapshot: WorkspaceDiscoverySnapshot?
    @Published private(set) var isScanningWorkspace = false
    @Published private(set) var discoveryMessage = ""
    /// Scan → Review → Configure → Preview → Start wizard (no automation until Start).
    @Published var discoveryWizardStep: DiscoveryWizardStep = .scan
    @Published var discoveryDurationPreset: RunDurationPreset = .oneHour
    @Published var discoveryCustomHours: Int = 2
    @Published var discoveryDwellMinSeconds: Double = 30
    @Published var discoveryDwellMaxSeconds: Double = 180
    @Published var discoveryPacing: NavigationPacingProfile = .relaxed
    @Published var discoveryTargetOrder: ReviewTargetOrder = .applicationPriority
    @Published var discoveryAllowedDomainsText = ""
    @Published var discoveryBlockedDomainsText = ""
    /// Local session history (Application Support — no screenshots / no body text).
    @Published private(set) var sessionHistory: [SessionHistoryRecord] = []
    @Published var selectedSessionID: String?
    @Published private(set) var sessionHistoryMessage = ""

    let onboardingUI: OnboardingUIModel
    let editorUI: WorkflowEditorUIModel
    let timelineUI = TimelineUIModel()
    private let workspaceScanner = WorkspaceScanner()
    private let sessionHistoryStore = SessionHistoryStore()

    private let store: ConfigStore
    private let permission = AccessibilityPermission()
    private let onboardingVM: OnboardingViewModel
    private let runVM = RunSessionViewModel()
    private let timelineVM = TimelineViewModel()
    private let saveConfirmation: TransientConfirmation

    private var runTask: Task<Void, Never>?
    private var monitor: UserSovereigntyMonitor?
    private var listenTap: SovereigntyListenTap?
    private var runHotKeys: RunControlHotKeys?
    private var activeRecorder: RunRecorder?
    private var activeEngine: WorkflowEngine?
    private var saveBannerTask: Task<Void, Never>?
    private var activeRunStartedAt: Date?
    private var activeRunWorkflowName: String?

    init(
        store: ConfigStore = ConfigStore(),
        saveConfirmation: TransientConfirmation = TransientConfirmation()
    ) {
        self.store = store
        self.saveConfirmation = saveConfirmation
        let onboarding = OnboardingViewModel(
            refreshState: { [permission] in permission.refresh() },
            requestAccess: { [permission] in permission.requestAccess() },
            openSettings: { [permission] in permission.openSystemSettings() }
        )
        self.onboardingVM = onboarding
        self.onboardingUI = OnboardingUIModel(viewModel: onboarding)

        let editorVM = WorkflowEditorViewModel(
            store: store,
            listRunning: {
                AppEnumerator().userFacingApps().compactMap { app in
                    guard let id = app.bundleID else { return nil }
                    return (id, app.displayName ?? id)
                }
            }
        )
        let editor = WorkflowEditorUIModel(viewModel: editorVM)
        self.editorUI = editor
        refreshPermissions()
        refreshWorkflowNames()
        refreshSessionHistory()
        showOnboarding = onboarding.showsOnboarding

        editor.onSuccessfulSave = { [weak self] name in
            self?.presentSaveConfirmation(name)
        }
    }

    func presentSaveConfirmation(_ name: String) {
        refreshWorkflowNames()
        selectWorkflow(name)
        saveConfirmation.showSaved(workflowName: name)
        saveConfirmationMessage = saveConfirmation.message
        lastMessage = saveConfirmation.message ?? ""
        saveBannerTask?.cancel()
        saveBannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self.saveConfirmation.clear()
            self.saveConfirmationMessage = nil
        }
    }

    func refreshPermissions() {
        let state = permission.refresh()
        onboardingVM.refresh()
        onboardingUI.refresh()
        switch state {
        case .unknown: permissionLabel = "Accessibility: Unknown"
        case .denied: permissionLabel = "Accessibility: Denied"
        case .granted: permissionLabel = "Accessibility: Granted"
        }
        accessibilityGranted = (state == .granted)
        runVM.updateAccessibilityGranted(state == .granted)
        showOnboarding = state != .granted
        syncRunUI()
    }

    func requestAccessibility() {
        _ = permission.requestAccess()
        refreshPermissions()
    }

    func openAccessibilitySettings() {
        permission.openSystemSettings()
        refreshPermissions()
    }

    func refreshWorkflowNames() {
        do {
            if FileManager.default.fileExists(atPath: store.workflowsFileURL.path) {
                let doc = try store.load()
                workflowNames = doc.workflows.map(\.name)
            } else {
                workflowNames = []
            }
        } catch {
            workflowNames = []
        }
        runVM.updateNames(workflowNames)
        selectedWorkflow = runVM.selectedName
        syncRunUI()
    }

    func selectWorkflow(_ name: String) {
        selectedWorkflow = name
        runVM.select(name)
        syncRunUI()
        if accessibilityGranted {
            lastMessage = "Selected “\(name)”. Click Start (bring Cursor frontmost first)."
        } else {
            lastMessage = "Selected “\(name)”. Grant Accessibility, then click Start."
        }
    }

    func openEditor() {
        showEditor = true
    }

    func openTimeline() {
        showTimeline = true
    }

    func openOnboarding() {
        showOnboarding = true
    }

    /// Menu bar / external request to focus the main window on a sidebar section.
    func requestOpenDashboard(section: AppSidebarSection = .dashboard) {
        pendingSidebarSection = section
    }

    func consumePendingSidebarSection() -> AppSidebarSection? {
        let value = pendingSidebarSection
        pendingSidebarSection = nil
        return value
    }

    /// Read-only workspace scan — never activates apps or emits input.
    func scanWorkspace() {
        guard !isScanningWorkspace else { return }
        isScanningWorkspace = true
        discoveryMessage = "Scanning…"
        discoveryWizardStep = .scan
        Task { @MainActor in
            let snapshot = workspaceScanner.scan()
            self.discoverySnapshot = snapshot
            self.isScanningWorkspace = false
            let appCount = snapshot.apps.count
            let targetCount = snapshot.allTargets.count
            self.discoveryMessage =
                "Found \(appCount) app\(appCount == 1 ? "" : "s"), \(targetCount) target\(targetCount == 1 ? "" : "s"). Review and select targets next."
            var snap = self.dashboard
            snap.discoverySummary =
                "Scan \(Self.discoveryTimeFormatter.string(from: snapshot.scannedAt)): \(appCount) apps"
            self.dashboard = snap
            if !snapshot.apps.isEmpty {
                self.discoveryWizardStep = .review
            }
        }
    }

    func setDiscoveryWizardStep(_ step: DiscoveryWizardStep) {
        discoveryWizardStep = step
    }

    func discoveryWizardCanAdvance(from step: DiscoveryWizardStep) -> Bool {
        switch step {
        case .scan:
            return discoverySnapshot != nil && !(discoverySnapshot?.apps.isEmpty ?? true)
        case .review:
            return (discoverySnapshot?.approvedTargets.isEmpty == false)
        case .configure:
            return discoveryDwellMinSeconds < discoveryDwellMaxSeconds
        case .preview:
            return !(discoverySnapshot?.approvedTargets.isEmpty ?? true)
        case .confirm:
            return false
        }
    }

    func advanceDiscoveryWizard() {
        guard let next = discoveryWizardStep.next else { return }
        guard discoveryWizardCanAdvance(from: discoveryWizardStep) else {
            switch discoveryWizardStep {
            case .review:
                discoveryMessage = "Select at least one target to continue."
            case .configure:
                discoveryMessage = "Minimum target time must be less than maximum."
            default:
                discoveryMessage = "Complete this step before continuing."
            }
            return
        }
        discoveryWizardStep = next
        discoveryMessage = ""
    }

    func retreatDiscoveryWizard() {
        if let previous = discoveryWizardStep.previous {
            discoveryWizardStep = previous
            discoveryMessage = ""
        }
    }

    func setDiscoveryTargetApproved(id: String, approved: Bool) {
        guard var snapshot = discoverySnapshot else { return }
        snapshot.setApproved(id, approved: approved)
        discoverySnapshot = snapshot
    }

    func setDiscoveryAppApproved(bundleID: String, approved: Bool) {
        guard var snapshot = discoverySnapshot else { return }
        snapshot.setAppApproved(bundleID: bundleID, approved: approved)
        discoverySnapshot = snapshot
    }

    func setAllDiscoveryTargetsApproved(_ approved: Bool) {
        guard var snapshot = discoverySnapshot else { return }
        snapshot.setAllApproved(approved)
        discoverySnapshot = snapshot
        discoveryMessage = approved
            ? "All targets selected."
            : "Selections cleared."
    }

    var discoveryPlanSteps: [DiscoveryPlanStep] {
        guard let snapshot = discoverySnapshot else { return [] }
        return DiscoveryNavigationPlan.buildPlan(from: snapshot)
    }

    var discoverySessionEstimate: DiscoverySessionEstimate {
        let count = discoverySnapshot?.approvedTargets.count ?? 0
        let untilStopped = discoveryDurationPreset == .untilStopped
        let cap: Double?
        switch discoveryDurationPreset {
        case .custom:
            cap = Double(max(1, discoveryCustomHours)) * 3_600
        case .untilStopped, .iterationsOnly:
            cap = nil
        default:
            cap = discoveryDurationPreset.seconds
        }
        return DiscoveryNavigationPlan.estimate(
            approvedCount: count,
            dwellMinSeconds: discoveryDwellMinSeconds,
            dwellMaxSeconds: discoveryDwellMaxSeconds,
            maxDurationSeconds: cap,
            untilStopped: untilStopped
        )
    }

    /// Merges approved discovery into the selected workflow. Does not start a run.
    func applyApprovedDiscoveryToSelectedWorkflow() {
        do {
            _ = try persistDiscoverySelections(starting: false)
        } catch {
            discoveryMessage = "Couldn’t apply: \(error.localizedDescription)"
        }
    }

    /// Persist selections + config into Universal Workspace Navigation, then Start.
    /// Does not run automation until `startSelected()` is invoked.
    func confirmAndStartDiscoveryWorkflow() {
        refreshPermissions()
        guard accessibilityGranted else {
            discoveryMessage = "Grant Accessibility before starting."
            openAccessibilitySettings()
            return
        }
        guard let snapshot = discoverySnapshot, !snapshot.approvedTargets.isEmpty else {
            discoveryMessage = "Select at least one target before starting."
            discoveryWizardStep = .review
            return
        }
        do {
            let name = try persistDiscoverySelections(starting: true)
            selectWorkflow(name)
            discoveryMessage = "Starting Universal Workspace Navigation…"
            lastMessage = discoveryMessage
            startSelected()
        } catch {
            discoveryMessage = "Couldn’t prepare workflow: \(error.localizedDescription)"
        }
    }

    /// Writes approved targets + discovery config. Returns workflow name. Never starts a run.
    @discardableResult
    private func persistDiscoverySelections(starting: Bool) throws -> String {
        guard let snapshot = discoverySnapshot else {
            discoveryMessage = "Scan the workspace first."
            throw DiscoveryFlowError.noSnapshot
        }
        let approved = snapshot.approvedTargets
        guard !approved.isEmpty else {
            discoveryMessage = "Select at least one target before continuing."
            throw DiscoveryFlowError.noApprovals
        }

        var document: WorkflowConfigDocument
        if FileManager.default.fileExists(atPath: store.workflowsFileURL.path) {
            document = try store.load()
        } else {
            document = WorkflowConfigDocument(workflows: [])
        }

        let name = UniversalWorkspaceNavigation.workflowName
        let index: Int
        if let existing = document.workflows.firstIndex(where: { $0.name == name }) {
            index = existing
        } else {
            var fresh = Workflow(
                name: name,
                targets: [],
                steps: [],
                loop: LoopSettings(
                    enabled: true,
                    maxIterations: NavigationLimits.absoluteMaxIterations,
                    maxDurationSeconds: 600,
                    untilStopped: false,
                    shuffleSteps: true
                ),
                review: .universalDefault
            )
            fresh.steps = TimedReviewNavigation.steps(targets: fresh.targets, settings: fresh.review)
            document.workflows.append(fresh)
            index = document.workflows.count - 1
        }

        var workflow = document.workflows[index]
        UniversalWorkflowBridge.mergeApprovedTargets(into: &workflow, approved: approved)
        applyDiscoveryDraftConfig(to: &workflow)
        workflow.steps = TimedReviewNavigation.steps(targets: workflow.targets, settings: workflow.review)
        document.workflows[index] = workflow
        try store.save(document)

        refreshWorkflowNames()
        selectWorkflow(name)
        editorUI.refreshSavedNames()
        editorUI.loadExisting(name)

        let count = approved.count
        if starting {
            discoveryMessage = "Prepared \(count) targets for “\(name)”."
        } else {
            discoveryMessage =
                "Saved \(count) selected target\(count == 1 ? "" : "s") to “\(name)”."
        }
        lastMessage = discoveryMessage
        return name
    }

    private func applyDiscoveryDraftConfig(to workflow: inout Workflow) {
        var review = workflow.review
        UniversalWorkflowBridge.applyUniversalRuntimeFlags(&review)
        review.dwellMinSeconds = discoveryDwellMinSeconds
        review.dwellMaxSeconds = discoveryDwellMaxSeconds
        review.pacing = discoveryPacing
        review.targetOrder = discoveryTargetOrder
        review.chrome.allowedDomains = discoveryAllowedDomainsText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        review.chrome.blockedDomains = discoveryBlockedDomainsText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        review.normalize()
        workflow.review = review

        switch discoveryDurationPreset {
        case .untilStopped:
            workflow.loop.enabled = true
            workflow.loop.untilStopped = true
            workflow.loop.maxDurationSeconds = nil
            workflow.loop.shuffleSteps = true
            workflow.loop.maxIterations = NavigationLimits.absoluteMaxIterations
        case .custom:
            workflow.loop.enabled = true
            workflow.loop.untilStopped = false
            workflow.loop.maxDurationSeconds = Double(max(1, discoveryCustomHours)) * 3_600
            workflow.loop.shuffleSteps = true
            workflow.loop.maxIterations = NavigationLimits.absoluteMaxIterations
        case .iterationsOnly:
            workflow.loop.enabled = true
            workflow.loop.untilStopped = false
            workflow.loop.maxDurationSeconds = nil
            workflow.loop.shuffleSteps = false
        default:
            workflow.loop.enabled = true
            workflow.loop.untilStopped = false
            workflow.loop.maxDurationSeconds = discoveryDurationPreset.seconds ?? 600
            workflow.loop.shuffleSteps = true
            workflow.loop.maxIterations = NavigationLimits.absoluteMaxIterations
        }
    }

    private static let discoveryTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    func startSelected() {
        refreshPermissions()
        guard let name = selectedWorkflow ?? runVM.selectedName else {
            lastMessage = "Pick a workflow in the menu first"
            return
        }
        guard accessibilityGranted else {
            lastMessage = "Accessibility Denied — enable \(ProductIdentity.displayName) in System Settings, then Refresh Accessibility status"
            openAccessibilitySettings()
            return
        }
        guard runVM.canStart else {
            lastMessage = "Cannot start — pick a workflow and grant Accessibility"
            return
        }

        let document: WorkflowConfigDocument
        do {
            document = try store.load()
        } catch {
            lastMessage = "Load failed"
            return
        }
        guard let workflow = document.workflows.first(where: { $0.name == name }) else {
            lastMessage = "Workflow not found"
            return
        }

        let sovereignty = UserSovereigntyMonitor(secureInput: SystemSecureInputProbe())
        let tap = SovereigntyListenTap(monitor: sovereignty)
        // Start the listen tap *after* activate settles — menu-click / focus noise must not halt the run.
        let hotKeys = RunControlHotKeys { [weak self] action in
            Task { @MainActor in
                guard let self else { return }
                switch action {
                case .stop:
                    self.stop()
                case .pause:
                    self.pause()
                case .resume:
                    self.resume()
                }
            }
        }
        hotKeys.install()

        let clock = SystemClock()
        let timing = TimingPolicy(clock: clock)
        let axProbe = SystemAXProbe()
        let focus = FocusGuard(probe: axProbe, timing: timing)
        let synth = EventSynth(
            focusGuard: focus,
            poster: CGEventPoster(),
            sovereignty: sovereignty
        )
        let executor = RealExecutor(synth: synth)
        let recorder = RunRecorder()
        let runner = WorkflowRunner(store: store)
        let resolver = AppEnumeratorTargetResolver()
        let precondition = FocusTargetPreconditionProbe(probe: axProbe) { bundleID in
            AppEnumerator().isRunning(bundleID: bundleID)
        }

        monitor = sovereignty
        listenTap = tap
        runHotKeys = hotKeys
        activeRecorder = recorder
        isRunning = true
        isPaused = false
        activeRunStartedAt = Date()
        activeRunWorkflowName = name
        runVM.markRunning(
            workflowName: name,
            steps: workflow.steps,
            durationSeconds: workflow.loop.maxDurationSeconds
        )
        let primaryBundleID = workflow.targets[0].bundleID
        lastMessage = "Starting… launching / focusing targets"
        syncRunUI()

        let started = Date()
        let activator = AppActivator()
        runTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Launch every configured target (e.g. Chrome) so multi-app runs aren't stuck
            // when the browser wasn't already open. Primary gets final focus.
            for target in workflow.targets where target.bundleID != primaryBundleID {
                _ = await activator.activateOrLaunch(bundleID: target.bundleID, timeoutSeconds: 6.0)
            }

            let activated = await activator.activateOrLaunch(
                bundleID: primaryBundleID,
                timeoutSeconds: 8.0
            )
            if !activated {
                self.finishFailure(
                    "Couldn’t open \(primaryBundleID) — install it or check the bundle ID on the target"
                )
                return
            }

            let focusReady = await Self.waitUntilFrontmost(
                bundleID: primaryBundleID,
                probe: axProbe,
                timeoutSeconds: 3.0
            )
            if !focusReady {
                self.finishFailure(
                    "Opened \(primaryBundleID) but it never became frontmost — click its window, then Start again"
                )
                return
            }

            await sovereignty.reset()
            tap.start()

            do {
                let summary = try await runner.run(
                    workflowName: name,
                    executor: executor,
                    sovereignty: sovereignty,
                    timing: timing,
                    recorder: recorder,
                    resolver: resolver,
                    preconditionProbe: precondition,
                    discoverySource: LiveApplicationDiscoverySource(),
                    pageInspectionSource: LiveWebPageInspectionSource(),
                    engineHandler: { [weak self] engine in
                        await MainActor.run {
                            self?.activeEngine = engine
                        }
                    }
                )
                self.finishRun(
                    events: summary.events,
                    started: started,
                    targetBundleID: primaryBundleID,
                    endReason: summary.endReason
                )
            } catch {
                self.finishFailure(String(describing: error))
            }
        }

        // Poll recorder for live status / timeline while running (main-actor UI updates).
        Task { [weak self] in
            while true {
                guard let session = self else { return }
                let stillRunning = await MainActor.run { session.isRunning }
                guard stillRunning else { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run { [weak self] in
                    guard let self, self.isRunning else { return }
                    let events = recorder.snapshot()
                    self.timelineVM.replace(with: events)
                    self.timelineUI.apply(self.timelineVM)
                    let elapsed = Date().timeIntervalSince(started)
                    let navEvents = events.filter {
                        [
                            "scroll",
                            "pageNavigate",
                            "arrowNavigate",
                            "switchTab",
                            "highlightNavigate",
                            "contentClick",
                            "explorerFileSwitch",
                            "activateApp",
                            "openExistingFile",
                            "wait",
                        ].contains($0.actionKind)
                    }
                    let idx = max(0, navEvents.count - 1)
                    self.runVM.updateProgress(
                        stepIndex: min(idx, max(0, workflow.steps.count - 1)),
                        steps: workflow.steps,
                        elapsed: elapsed,
                        events: events
                    )
                    self.syncRunUI()
                }

                if let engine = await MainActor.run(body: { self?.activeEngine }) {
                    let identity = await engine.currentReviewIdentity
                    let next = await engine.nextReviewIdentity
                    let completed = await engine.reviewTargetsCompleted
                    let dwellElapsed = await engine.currentDwellElapsedSeconds
                    let dwellAlloc = await engine.currentDwellAllocatedSeconds
                    let phase = await engine.reviewUIPhase
                    let action = await engine.currentActionKind
                    let discovery = await engine.discoverySummary
                    let appBundle = await engine.activeTargetBundleID
                    let queueCount = await engine.reviewQueueCount
                    let chromeDebug = await engine.chromeExplorerDebug
                    let chromePreview = await engine.chromeNavigationPreview
                    await MainActor.run { [weak self] in
                        guard let self, self.isRunning else { return }
                        self.progressLines = self.reviewDashboardLines(
                            workflowName: workflow.name,
                            phase: phase,
                            identity: identity,
                            next: next,
                            completed: completed,
                            dwellElapsed: dwellElapsed,
                            dwellAlloc: dwellAlloc,
                            action: action,
                            discovery: discovery,
                            live: self.runVM.live
                        )
                        self.updateDashboardSnapshot(
                            workflowName: workflow.name,
                            enginePhase: phase,
                            identity: identity,
                            next: next,
                            completed: completed,
                            action: action,
                            discovery: discovery,
                            appBundle: appBundle,
                            queueCount: queueCount,
                            dwellElapsed: dwellElapsed,
                            dwellAlloc: dwellAlloc,
                            live: self.runVM.live,
                            chromeDebug: chromeDebug,
                            chromePreview: chromePreview
                        )
                    }
                }
            }
        }
    }

    /// Polls until `bundleID` is frontmost or timeout.
    private static func waitUntilFrontmost(
        bundleID: String,
        probe: SystemAXProbe,
        timeoutSeconds: Double
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var stableHits = 0
        while Date() < deadline {
            if probe.frontmostAppBundleID() == bundleID {
                stableHits += 1
                // ~150ms stable (3 × 50ms) before proceeding.
                if stableHits >= 3 { return true }
            } else {
                stableHits = 0
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return probe.frontmostAppBundleID() == bundleID
    }

    func pause() {
        Task {
            await activeEngine?.pause()
            await MainActor.run {
                self.isPaused = true
                self.runVM.markPaused()
                self.lastMessage = "Paused"
                self.syncRunUI()
            }
        }
    }

    func resume() {
        Task {
            await activeEngine?.resume()
            await MainActor.run {
                self.isPaused = false
                self.runVM.markResumed()
                self.lastMessage = "Resumed"
                self.syncRunUI()
            }
        }
    }

    func stop() {
        Task {
            await monitor?.requestStop()
            await activeEngine?.requestStop()
        }
        liveStatusLine = "Stopping…"
    }

    private func finishRun(
        events: [RunEvent],
        started: Date,
        targetBundleID: String,
        endReason: RunEndReason?
    ) {
        teardownInput()
        timelineVM.replace(with: events)
        timelineUI.apply(timelineVM)
        let elapsed = Date().timeIntervalSince(started)
        let phase: RunUIPhase
        let historyStatus: SessionEndStatus
        switch endReason {
        case .completed:
            phase = .completed
            historyStatus = .completed
        case .stopped:
            phase = .stopped
            historyStatus = .stopped
        case .failed:
            phase = .failed
            historyStatus = .failed
        case nil:
            let failed = events.contains(where: { $0.result == .failed })
            phase = failed ? .failed : .completed
            historyStatus = failed ? .failed : .completed
        }
        recordFinishedSession(
            events: events,
            started: started,
            endStatus: historyStatus
        )
        let counts = RunLiveStatus.counts(from: events)
        runVM.markIdle(eventCount: events.count, elapsedSeconds: elapsed, phase: phase)
        let failedNav = events.contains {
            ["scroll", "pageNavigate", "arrowNavigate"].contains($0.actionKind) && $0.result == .failed
        }
        let didNavigate = counts.scroll + counts.keyboard > 0
        if !didNavigate, failedNav || phase == .failed {
            lastMessage =
                "\(phase.title) — no navigation landed. Keep Cursor frontmost (don’t click away after Start)."
        } else if failedNav {
            lastMessage =
                "\(phase.title) · scroll \(counts.scroll) · keys \(counts.keyboard) · \(RunLiveStatus.formatClock(elapsed)) — keep \(targetBundleID) frontmost"
        } else {
            lastMessage =
                "\(phase.title) · scroll \(counts.scroll) · keys \(counts.keyboard) · \(RunLiveStatus.formatClock(elapsed))"
        }
        syncRunUI()
        refreshWorkflowNames()
    }

    private func finishFailure(_ message: String) {
        if let started = activeRunStartedAt {
            recordFinishedSession(events: [], started: started, endStatus: .failed)
        } else {
            activeRunStartedAt = nil
            activeRunWorkflowName = nil
        }
        teardownInput()
        runVM.markIdle(eventCount: 0, phase: .failed)
        lastMessage = message
        syncRunUI()
    }

    func refreshSessionHistory() {
        do {
            sessionHistory = try sessionHistoryStore.load().sessions
                .sorted { $0.startedAt > $1.startedAt }
            sessionHistoryMessage = ""
        } catch {
            sessionHistory = []
            sessionHistoryMessage = "Couldn’t load session history."
        }
    }

    var sessionHistorySections: [SessionHistorySection] {
        sessionHistory.groupedByDay()
    }

    var selectedSessionRecord: SessionHistoryRecord? {
        guard let selectedSessionID else { return nil }
        return sessionHistory.first { $0.id == selectedSessionID }
    }

    func selectSession(_ id: String?) {
        selectedSessionID = id
    }

    func clearSessionHistory() {
        do {
            try sessionHistoryStore.clear()
            sessionHistory = []
            selectedSessionID = nil
            sessionHistoryMessage = "Session history cleared."
        } catch {
            sessionHistoryMessage = "Couldn’t clear history."
        }
    }

    private func recordFinishedSession(
        events: [RunEvent],
        started: Date,
        endStatus: SessionEndStatus
    ) {
        let name = activeRunWorkflowName
            ?? selectedWorkflow
            ?? {
                let live = runVM.live.workflowName
                return live.isEmpty ? nil : live
            }()
            ?? "Untitled"
        let record = SessionHistorySummarizer.record(
            workflowName: name,
            startedAt: started,
            endedAt: Date(),
            endStatus: endStatus,
            events: events
        )
        do {
            try sessionHistoryStore.append(record)
            refreshSessionHistory()
            selectedSessionID = record.id
        } catch {
            sessionHistoryMessage = "Couldn’t save session history."
        }
        activeRunStartedAt = nil
        activeRunWorkflowName = nil
    }

    private func teardownInput() {
        listenTap?.stop()
        listenTap = nil
        runHotKeys?.uninstall()
        runHotKeys = nil
        monitor = nil
        runTask = nil
        activeRecorder = nil
        activeEngine = nil
        isRunning = false
        isPaused = false
    }

    private func syncRunUI() {
        canStart = runVM.canStart
        liveStatusLine = runVM.live.summaryLine
        progressLines = progressLines(from: runVM.live)
        workflowNames = runVM.workflowNames
        selectedWorkflow = runVM.selectedName
        refreshDashboardFromLiveStatus()
    }

    private func refreshDashboardFromLiveStatus() {
        let live = runVM.live
        let status: DashboardWorkflowStatus
        switch live.phase {
        case .idle: status = .idle
        case .running: status = .running
        case .paused: status = .paused
        case .completed, .stopped: status = .completed
        case .failed: status = .failed
        }
        if status == .running || status == .paused {
            // Keep engine-fed fields; only refresh clocks from live when poll hasn't run yet.
            var snap = dashboard
            snap.status = status
            snap.workflowName = live.workflowName.isEmpty ? (selectedWorkflow ?? "") : live.workflowName
            snap.elapsedSeconds = live.elapsedSeconds
            snap.remainingSeconds = live.remainingSeconds
            snap.durationSeconds = live.durationSeconds
            if snap.currentAction == "—" || snap.currentAction.isEmpty {
                snap.currentAction = live.currentStepLabel
            }
            dashboard = snap
        } else {
            dashboard = DashboardRunSnapshot(
                status: status,
                workflowName: live.workflowName.isEmpty ? (selectedWorkflow ?? "") : live.workflowName,
                elapsedSeconds: live.elapsedSeconds,
                remainingSeconds: live.remainingSeconds,
                durationSeconds: live.durationSeconds,
                currentAction: live.currentStepLabel == "—" ? "—" : live.currentStepLabel
            )
        }
    }

    private func updateDashboardSnapshot(
        workflowName: String,
        enginePhase: String,
        identity: String?,
        next: String?,
        completed: Int,
        action: String?,
        discovery: String,
        appBundle: String,
        queueCount: Int,
        dwellElapsed: Double?,
        dwellAlloc: Double?,
        live: RunLiveStatus,
        chromeDebug: ChromeExplorerDebugSnapshot = .empty,
        chromePreview: [String] = []
    ) {
        let status: DashboardWorkflowStatus = isPaused ? .paused : .running
        let appLabel: String
        if appBundle.isEmpty {
            appLabel = "—"
        } else if let named = editorUI.runningApps.first(where: { $0.bundleID == appBundle })?.displayName {
            appLabel = named
        } else {
            appLabel = appBundle
        }
        let remaining: Int? = queueCount > 0 ? max(0, queueCount - completed) : nil
        let windowLabel: String
        switch enginePhase {
        case "switchingTarget": windowLabel = "Switching target"
        case "paused": windowLabel = "Paused"
        case "discovering", "refreshing": windowLabel = "Discovering"
        case "failed": windowLabel = "Failed"
        default: windowLabel = enginePhase.isEmpty ? "Active" : enginePhase.capitalized
        }
        dashboard = DashboardRunSnapshot(
            status: status,
            workflowName: workflowName,
            elapsedSeconds: live.elapsedSeconds,
            remainingSeconds: live.remainingSeconds,
            durationSeconds: live.durationSeconds,
            currentApplication: appLabel,
            currentWindow: windowLabel,
            currentFileOrTab: (identity?.isEmpty == false) ? identity! : "—",
            currentAction: (action?.isEmpty == false) ? action! : live.currentStepLabel,
            targetsCompleted: completed,
            targetsRemaining: remaining,
            discoverySummary: discovery,
            enginePhase: enginePhase,
            currentBundleID: appBundle,
            dwellElapsedSeconds: dwellElapsed,
            dwellAllocatedSeconds: dwellAlloc,
            chromeDebug: chromeDebug,
            chromePreviewLines: chromePreview
        )
        _ = next
    }

    private func progressLines(from live: RunLiveStatus) -> [String] {
        guard live.isRunning || live.phase == .paused else { return [] }
        var lines = [live.phase.title]
        if let duration = live.durationSeconds {
            lines.append("Duration: \(RunLiveStatus.formatClock(duration))")
        } else {
            lines.append("Duration: until stopped")
        }
        lines.append("Elapsed: \(RunLiveStatus.formatClock(live.elapsedSeconds))")
        if let remaining = live.remainingSeconds {
            lines.append("Remaining: \(RunLiveStatus.formatClock(remaining))")
        }
        lines.append("Current action: \(live.currentStepLabel)")
        lines.append("Scroll actions: \(live.scrollActionCount)")
        lines.append("Keyboard actions: \(live.keyboardActionCount)")
        return lines
    }

    private func reviewDashboardLines(
        workflowName: String,
        phase: String,
        identity: String?,
        next: String?,
        completed: Int,
        dwellElapsed: Double?,
        dwellAlloc: Double?,
        action: String?,
        discovery: String,
        live: RunLiveStatus
    ) -> [String] {
        var lines: [String] = [
            "Workflow: \(workflowName)",
            "Status: \(phase)",
        ]
        if let identity, !identity.isEmpty {
            lines.append("Current: \(identity)")
        }
        if let next, !next.isEmpty {
            lines.append("Next: \(next)")
        }
        if let dwellElapsed, let dwellAlloc {
            lines.append(
                "Time on target: \(RunLiveStatus.formatClock(dwellElapsed)) / \(RunLiveStatus.formatClock(dwellAlloc))"
            )
        }
        if let duration = live.durationSeconds {
            lines.append(
                "Session: \(RunLiveStatus.formatClock(live.elapsedSeconds)) / \(RunLiveStatus.formatClock(duration))"
            )
        } else {
            lines.append("Session: \(RunLiveStatus.formatClock(live.elapsedSeconds)) / until stopped")
        }
        lines.append("Targets completed: \(completed)")
        if !discovery.isEmpty {
            lines.append("Discovered: \(discovery)")
        }
        if let action, !action.isEmpty {
            lines.append("Current action: \(action)")
        }
        return lines
    }
}

struct AppEnumeratorTargetResolver: WorkflowTargetResolver {
    private let enumerator = AppEnumerator()
    private let activator = AppActivator()

    func isAvailable(bundleID: String) -> Bool {
        // Allow Start when the app is installed even if it isn't running yet —
        // AppSession / RealExecutor will launch it.
        enumerator.isRunning(bundleID: bundleID) || activator.isInstalled(bundleID: bundleID)
    }
}
