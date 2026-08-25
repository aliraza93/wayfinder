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

    let onboardingUI: OnboardingUIModel
    let editorUI: WorkflowEditorUIModel
    let timelineUI = TimelineUIModel()

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

    func startSelected() {
        refreshPermissions()
        guard let name = selectedWorkflow ?? runVM.selectedName else {
            lastMessage = "Pick a workflow in the menu first"
            return
        }
        guard accessibilityGranted else {
            lastMessage = "Accessibility Denied — enable Waypoint in System Settings, then Refresh Accessibility status"
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
        switch endReason {
        case .completed: phase = .completed
        case .stopped: phase = .stopped
        case .failed: phase = .failed
        case nil: phase = events.contains(where: { $0.result == .failed }) ? .failed : .completed
        }
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
        teardownInput()
        runVM.markIdle(eventCount: 0, phase: .failed)
        lastMessage = message
        syncRunUI()
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
