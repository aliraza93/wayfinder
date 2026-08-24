import Actions
import Adapters
import AppControl
import Config
import CoreEngine
import Domain
import InputSynthesis
import Observability
import Permissions
import Safety
import SwiftUI
import WaypointAccessibility

/// Minimal workflow picker — load JSON via ConfigStore / WorkflowRunner (no rich editor).
struct WorkflowControls: View {
    @ObservedObject var controller: WorkflowMenuController

    var body: some View {
        Text(controller.statusLine)
        if controller.workflowNames.isEmpty {
            Text("No workflows.json — seed sample first")
                .font(.caption)
        } else {
            ForEach(controller.workflowNames, id: \.self) { name in
                Button(controller.selectedName == name ? "▶ \(name)" : name) {
                    controller.selectedName = name
                }
            }
        }
        Button("Seed Sample Workflows") {
            controller.seedSample()
        }
        Button(controller.isRunning ? "Stop Workflow" : "Run Selected Workflow") {
            if controller.isRunning {
                controller.stop()
            } else {
                controller.startSelected()
            }
        }
        .disabled((!controller.canStart && !controller.isRunning) || controller.selectedName == nil)
    }
}

@MainActor
final class WorkflowMenuController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusLine = "Workflows: Idle"
    @Published private(set) var lastLogSummary = ""
    @Published private(set) var workflowNames: [String] = []
    @Published var selectedName: String?
    @Published var accessibilityGranted = false

    private var runTask: Task<Void, Never>?
    private var monitor: UserSovereigntyMonitor?
    private var listenTap: SovereigntyListenTap?
    private var stopHotKey: GlobalStopHotKey?
    private let store = ConfigStore()

    var canStart: Bool { accessibilityGranted && !isRunning && selectedName != nil }

    func updateAccessibility(_ state: PermissionState) {
        accessibilityGranted = (state == .granted)
        refreshNames()
        if !isRunning {
            statusLine = accessibilityGranted ? "Workflows: Idle" : "Workflows: Needs Accessibility"
        }
    }

    func refreshNames() {
        do {
            if !FileManager.default.fileExists(atPath: store.workflowsFileURL.path) {
                workflowNames = []
                return
            }
            let doc = try store.load()
            workflowNames = doc.workflows.map(\.name)
            if selectedName == nil || !(workflowNames.contains(selectedName ?? "")) {
                selectedName = workflowNames.first
            }
        } catch {
            workflowNames = []
            statusLine = "Workflows: Load error"
        }
    }

    func seedSample() {
        do {
            try store.save(WorkflowRunner.sampleMultiTargetDocument())
            refreshNames()
            statusLine = "Workflows: Sample saved"
        } catch {
            statusLine = "Workflows: Seed failed"
        }
    }

    func startSelected() {
        guard canStart, let name = selectedName else {
            statusLine = "Workflows: Grant Accessibility + pick a workflow"
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
        let resolver = EnumeratorTargetResolver()

        self.monitor = sovereignty
        self.listenTap = tap
        self.stopHotKey = hotKey
        isRunning = true
        statusLine = "Workflows: Running \(name)"

        runTask = Task { [weak self] in
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
                    self?.finish(events: summary.events, adapters: summary.adapters)
                }
            } catch {
                await MainActor.run {
                    self?.finishFailure(String(describing: error))
                }
            }
        }
    }

    func stop() {
        Task { [monitor] in
            await monitor?.requestStop()
        }
        statusLine = "Workflows: Stopping…"
    }

    private func finish(events: [RunEvent], adapters: [String: ResolvedAdapter]) {
        teardownInput()
        lastLogSummary = events
            .map { "\($0.actionKind):\($0.result.rawValue)" }
            .joined(separator: ", ")
        let adapterNote = adapters
            .map { "\($0.value)" }
            .sorted()
            .joined(separator: ",")
        statusLine = "Workflows: Done (\(events.count) ev; \(adapterNote))"
    }

    private func finishFailure(_ message: String) {
        teardownInput()
        statusLine = "Workflows: \(message)"
        lastLogSummary = ""
    }

    private func teardownInput() {
        listenTap?.stop()
        listenTap = nil
        stopHotKey?.uninstall()
        stopHotKey = nil
        monitor = nil
        runTask = nil
        isRunning = false
    }
}

/// Bridges AppEnumerator into WorkflowTargetResolver.
struct EnumeratorTargetResolver: WorkflowTargetResolver {
    private let enumerator = AppEnumerator()

    func isAvailable(bundleID: String) -> Bool {
        enumerator.isRunning(bundleID: bundleID)
    }
}
