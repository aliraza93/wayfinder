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
    @Published private(set) var liveStatusLine = "Idle"
    @Published private(set) var workflowNames: [String] = []
    @Published var selectedWorkflow: String?
    @Published private(set) var isRunning = false
    @Published private(set) var canStart = false
    @Published private(set) var lastMessage = ""

    let onboardingUI: OnboardingUIModel
    let editorUI: WorkflowEditorUIModel
    let timelineUI = TimelineUIModel()

    private let store: ConfigStore
    private let permission = AccessibilityPermission()
    private let onboardingVM: OnboardingViewModel
    private let runVM = RunSessionViewModel()
    private let timelineVM = TimelineViewModel()

    private var runTask: Task<Void, Never>?
    private var monitor: UserSovereigntyMonitor?
    private var listenTap: SovereigntyListenTap?
    private var stopHotKey: GlobalStopHotKey?
    private var activeRecorder: RunRecorder?

    init(store: ConfigStore = ConfigStore()) {
        self.store = store
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
        self.editorUI = WorkflowEditorUIModel(viewModel: editorVM)
        refreshPermissions()
        refreshWorkflowNames()
        showOnboarding = onboarding.showsOnboarding
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
        guard runVM.canStart, let name = selectedWorkflow ?? runVM.selectedName else {
            lastMessage = "Grant Accessibility and pick a workflow"
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
        tap.start()
        let hotKey = GlobalStopHotKey(monitor: sovereignty)
        hotKey.install()

        let clock = SystemClock()
        let timing = TimingPolicy(clock: clock)
        let focus = FocusGuard(probe: SystemAXProbe(), timing: timing)
        let synth = EventSynth(
            focusGuard: focus,
            poster: CGEventPoster(),
            sovereignty: sovereignty
        )
        let executor = RealExecutor(synth: synth)
        let recorder = RunRecorder()
        let runner = WorkflowRunner(store: store)
        let resolver = AppEnumeratorTargetResolver()

        monitor = sovereignty
        listenTap = tap
        stopHotKey = hotKey
        activeRecorder = recorder
        isRunning = true
        runVM.markRunning(workflowName: name, steps: workflow.steps)
        syncRunUI()
        lastMessage = ""

        let started = Date()
        runTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let summary = try await runner.run(
                    workflowName: name,
                    executor: executor,
                    sovereignty: sovereignty,
                    timing: timing,
                    recorder: recorder,
                    resolver: resolver
                )
                await MainActor.run {
                    self?.finishRun(events: summary.events, started: started)
                }
            } catch {
                await MainActor.run {
                    self?.finishFailure(String(describing: error))
                }
            }
        }

        // Poll recorder for live status / timeline while running (main-actor UI updates).
        Task { [weak self] in
            while let self, self.isRunning {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    guard self.isRunning else { return }
                    let events = recorder.snapshot()
                    self.timelineVM.replace(with: events)
                    self.timelineUI.apply(self.timelineVM)
                    let elapsed = Date().timeIntervalSince(started)
                    let idx = max(0, events.count - 1)
                    self.runVM.updateProgress(
                        stepIndex: min(idx, max(0, workflow.steps.count - 1)),
                        steps: workflow.steps,
                        elapsed: elapsed,
                        eventCount: events.count
                    )
                    self.syncRunUI()
                }
            }
        }
    }

    func stop() {
        Task {
            await monitor?.requestStop()
        }
        liveStatusLine = "Stopping…"
    }

    private func finishRun(events: [RunEvent], started: Date) {
        teardownInput()
        timelineVM.replace(with: events)
        timelineUI.apply(timelineVM)
        let elapsed = Date().timeIntervalSince(started)
        runVM.markIdle(eventCount: events.count, elapsedSeconds: elapsed)
        lastMessage = events
            .map { "\($0.actionKind):\($0.result.rawValue)" }
            .joined(separator: ", ")
        syncRunUI()
        refreshWorkflowNames()
    }

    private func finishFailure(_ message: String) {
        teardownInput()
        runVM.markIdle(eventCount: 0)
        lastMessage = message
        syncRunUI()
    }

    private func teardownInput() {
        listenTap?.stop()
        listenTap = nil
        stopHotKey?.uninstall()
        stopHotKey = nil
        monitor = nil
        runTask = nil
        activeRecorder = nil
        isRunning = false
    }

    private func syncRunUI() {
        canStart = runVM.canStart
        liveStatusLine = runVM.live.summaryLine
        workflowNames = runVM.workflowNames
        selectedWorkflow = runVM.selectedName
    }
}

struct AppEnumeratorTargetResolver: WorkflowTargetResolver {
    private let enumerator = AppEnumerator()
    func isAvailable(bundleID: String) -> Bool {
        enumerator.isRunning(bundleID: bundleID)
    }
}
