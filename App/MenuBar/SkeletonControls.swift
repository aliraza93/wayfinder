import Actions
import AppKit
import AppControl
import CoreEngine
import Domain
import InputSynthesis
import Observability
import Permissions
import Safety
import SwiftUI
import WaypointAccessibility

/// Menu-bar Start/Stop for the hardcoded frontmost-app scroll loop.
struct SkeletonControls: View {
    @ObservedObject var runner: SkeletonRunner

    var body: some View {
        Text(runner.statusLine)
        Button(runner.isRunning ? "Stop Skeleton" : "Start Skeleton") {
            if runner.isRunning {
                runner.stop()
            } else {
                runner.start()
            }
        }
        .disabled(!runner.canStart && !runner.isRunning)
        if runner.isRunning {
            Text("Stop: Ctrl+Opt+. or any key/scroll")
                .font(.caption)
        }
    }
}

@MainActor
final class SkeletonRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusLine = "Skeleton: Idle"
    @Published private(set) var lastLogSummary = ""
    @Published var accessibilityGranted = false

    private var runTask: Task<Void, Never>?
    private var monitor: UserSovereigntyMonitor?
    private var listenTap: SovereigntyListenTap?
    private var stopHotKey: GlobalStopHotKey?
    private var engine: WorkflowEngine?
    private var targetBundleID: String?

    var canStart: Bool { accessibilityGranted && !isRunning }

    func updateAccessibility(_ state: PermissionState) {
        accessibilityGranted = (state == .granted)
        if !accessibilityGranted && !isRunning {
            statusLine = "Skeleton: Needs Accessibility"
        } else if !isRunning {
            statusLine = "Skeleton: Idle"
        }
    }

    func start() {
        guard canStart else {
            statusLine = "Skeleton: Grant Accessibility first"
            return
        }

        guard let front = resolveFrontmostTarget() else {
            statusLine = "Skeleton: No frontmost app"
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
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: sovereignty,
            timing: timing,
            recorder: recorder
        )

        self.monitor = sovereignty
        self.listenTap = tap
        self.stopHotKey = hotKey
        self.engine = engine
        self.targetBundleID = front.bundleID
        isRunning = true
        statusLine = "Skeleton: Running on \(front.displayName)"

        let workflow = SkeletonWorkflow.make(frontmostBundleID: front.bundleID)

        runTask = Task { [weak self] in
            await engine.run(workflow)
            await MainActor.run {
                self?.finishRun(recorder: recorder)
            }
        }
    }

    func stop() {
        Task { [monitor] in
            await monitor?.requestStop()
        }
        statusLine = "Skeleton: Stopping…"
    }

    private func resolveFrontmostTarget() -> FrontmostApp? {
        let selfID = Bundle.main.bundleIdentifier
        if let front = FrontmostAppResolver().frontmostApp(),
           front.bundleID != selfID
        {
            return front
        }
        if let id = CoarseAX().frontmostAppBundleID(), id != selfID {
            return FrontmostApp(bundleID: id, displayName: id)
        }
        return nil
    }

    private func finishRun(recorder: RunRecorder) {
        listenTap?.stop()
        listenTap = nil
        stopHotKey?.uninstall()
        stopHotKey = nil
        monitor = nil
        engine = nil
        runTask = nil
        isRunning = false

        let events = recorder.snapshot()
        lastLogSummary = events
            .map { "\($0.actionKind):\($0.result.rawValue)" }
            .joined(separator: ", ")

        // Verified focus at stop (honest if lost) — full restore is a later milestone.
        if let target = targetBundleID {
            let current = CoarseAX().frontmostAppBundleID()
            if current == target {
                statusLine = events.isEmpty
                    ? "Skeleton: Stopped (focus ok)"
                    : "Skeleton: Done (\(events.count) events; focus ok)"
            } else {
                statusLine = "Skeleton: Done; couldn't restore focus (front=\(current ?? "nil"))"
            }
        } else {
            statusLine = events.isEmpty ? "Skeleton: Stopped (no events)" : "Skeleton: Done (\(events.count) events)"
        }
        targetBundleID = nil
    }
}
