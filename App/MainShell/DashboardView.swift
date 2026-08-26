import AppPresentation
import Domain
import SwiftUI

struct DashboardView: View {
    @ObservedObject var session: AppSession
    var openWindow: OpenWindowAction

    private var snap: DashboardRunSnapshot { session.dashboard }
    private var isLive: Bool { snap.status == .running || snap.status == .paused }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                workflowStatusCard
                if isLive {
                    metricsRow
                    currentTargetCard
                    if snap.chromeDebug.state != .idle || !snap.chromePreviewLines.isEmpty {
                        chromeIntelligencePanel
                    }
                    if let apps = session.discoverySnapshot?.apps, !apps.isEmpty {
                        workspaceProgressSection(apps: apps)
                    }
                } else {
                    if let snapshot = session.discoverySnapshot, !snapshot.apps.isEmpty {
                        discoveryResultsSection(snapshot)
                        applicationCardsSection(snapshot.apps)
                    } else {
                        emptyDiscoveryHint
                    }
                    controlsSection
                }
                if !session.lastMessage.isEmpty {
                    messageCard
                }
            }
            .padding(AppChrome.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.22), value: snap.status)
            .animation(.easeInOut(duration: 0.22), value: snap.currentFileOrTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TiktikTheme.elevatedBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandMark(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(ProductIdentity.displayName)
                    .font(.title.weight(.semibold))
                Text(ProductIdentity.dashboardSubtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TiktikTheme.primary.opacity(0.9))
                Text(ProductIdentity.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.title")
        .accessibilityLabel("\(ProductIdentity.displayName). \(ProductIdentity.dashboardSubtitle)")
    }

    // MARK: - Status

    private var workflowStatusCard: some View {
        DashboardPanel {
            VStack(alignment: .leading, spacing: 12) {
                StatusBadge(
                    status: displayStatus,
                    pulse: snap.status == .running
                )
                .accessibilityIdentifier("dashboard.status")

                statusBody

                statusActions
            }
        }
    }

    private var displayStatus: DashboardWorkflowStatus {
        if snap.status == .idle, session.accessibilityGranted {
            return .idle
        }
        return snap.status
    }

    @ViewBuilder
    private var statusBody: some View {
        switch snap.status {
        case .idle:
            VStack(alignment: .leading, spacing: 6) {
                Text("\(ProductIdentity.displayName) is ready")
                    .font(.title3.weight(.semibold))
                Text("Scan your workspace to discover targets, or start a saved workflow.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !session.accessibilityGranted {
                    Text("Grant Accessibility in Safety before starting a run.")
                        .font(.caption)
                        .foregroundStyle(TiktikTheme.warning)
                }
                if let workflow = session.selectedWorkflow ?? (snap.workflowName.isEmpty ? nil : snap.workflowName) {
                    Text("Selected: \(workflow)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .running, .paused:
            VStack(alignment: .leading, spacing: 8) {
                if !snap.workflowName.isEmpty {
                    Text(snap.workflowName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(snap.currentApplication)
                    .font(.title3.weight(.semibold))
                Text(snap.currentFileOrTab)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(RunLiveStatus.formatClock(snap.elapsedSeconds)) elapsed")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .completed:
            VStack(alignment: .leading, spacing: 6) {
                Text("Workflow completed")
                    .font(.title3.weight(.semibold))
                Text(snap.workflowName.isEmpty ? "Session finished successfully." : snap.workflowName)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Text("Workflow failed")
                    .font(.title3.weight(.semibold))
                Text(session.lastMessage.isEmpty ? "Check Logs for details." : session.lastMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusActions: some View {
        let actionWidth: CGFloat = 150
        HStack(spacing: 10) {
            switch snap.status {
            case .idle, .completed, .failed:
                TiktikButton(
                    title: session.isScanningWorkspace ? "Scanning…" : "Scan Workspace",
                    systemImage: session.isScanningWorkspace ? nil : "sparkles",
                    kind: .discovery,
                    isLoading: session.isScanningWorkspace,
                    minWidth: actionWidth
                ) {
                    session.scanWorkspace()
                    session.requestOpenDashboard(section: .discovery)
                }
                .disabled(session.isScanningWorkspace)
                .accessibilityIdentifier("dashboard.scan")

                if !session.isRunning {
                    TiktikButton(
                        title: "Start Workflow",
                        systemImage: "play.fill",
                        kind: .primary,
                        minWidth: actionWidth
                    ) {
                        session.startSelected()
                    }
                    .disabled(session.selectedWorkflow == nil || !session.canStart)
                    .keyboardShortcut("r", modifiers: [.command])
                    .accessibilityIdentifier("dashboard.start")
                    .help("Start the selected workflow (⌘R)")
                }

            case .running:
                TiktikButton(
                    title: "Pause",
                    systemImage: "pause.fill",
                    kind: .pause,
                    minWidth: actionWidth
                ) {
                    session.pause()
                }
                .accessibilityIdentifier("dashboard.pause")
                .help("Pause (⌃⌥P)")

                TiktikButton(
                    title: "Stop",
                    systemImage: "stop.fill",
                    kind: .stop,
                    minWidth: actionWidth
                ) {
                    session.stop()
                }
                .keyboardShortcut(".", modifiers: [.control, .option])
                .accessibilityIdentifier("dashboard.stop")
                .help("Emergency Stop (⌃⌥.)")

            case .paused:
                TiktikButton(
                    title: "Resume",
                    systemImage: "play.fill",
                    kind: .resume,
                    minWidth: actionWidth
                ) {
                    session.resume()
                }
                .accessibilityIdentifier("dashboard.resume")
                .help("Resume (⌃⌥R)")

                TiktikButton(
                    title: "Stop",
                    systemImage: "stop.fill",
                    kind: .stop,
                    minWidth: actionWidth
                ) {
                    session.stop()
                }
                .keyboardShortcut(".", modifiers: [.control, .option])
                .accessibilityIdentifier("dashboard.stop")
                .help("Emergency Stop (⌃⌥.)")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Metrics / live

    private var metricsRow: some View {
        let remainingTargets = snap.targetsRemaining
        let appsCount = session.discoverySnapshot?.apps.count
        return LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 12) {
            MetricCard(
                value: RunLiveStatus.formatClock(snap.elapsedSeconds),
                label: "Session",
                accent: TiktikTheme.info
            )
            MetricCard(
                value: "\(snap.targetsCompleted + (remainingTargets ?? 0))",
                label: "Targets",
                accent: TiktikTheme.neutral
            )
            MetricCard(
                value: "\(snap.targetsCompleted)",
                label: "Completed",
                accent: TiktikTheme.success
            )
            MetricCard(
                value: appsCount.map(String.init) ?? "—",
                label: "Applications",
                accent: TiktikTheme.primary
            )
        }
    }

    private var currentTargetCard: some View {
        let accent = TiktikTheme.appAccent(
            bundleID: snap.currentBundleID,
            displayName: snap.currentApplication
        )
        let dwellProgress: Double? = {
            guard let elapsed = snap.dwellElapsedSeconds,
                  let allocated = snap.dwellAllocatedSeconds,
                  allocated > 0
            else { return nil }
            return min(1, elapsed / allocated)
        }()

        return DashboardPanel(title: "CURRENT TARGET") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: TiktikTheme.appSymbol(
                        bundleID: snap.currentBundleID,
                        displayName: snap.currentApplication
                    ))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snap.currentApplication)
                            .font(.headline)
                        Text(snap.currentFileOrTab)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                    }
                }

                if let elapsed = snap.dwellElapsedSeconds, let allocated = snap.dwellAllocatedSeconds {
                    Text("\(RunLiveStatus.formatClock(elapsed)) / \(RunLiveStatus.formatClock(allocated))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let dwellProgress {
                        ProgressView(value: dwellProgress)
                            .tint(accent)
                    }
                } else if let remaining = snap.remainingSeconds {
                    Text("Remaining \(RunLiveStatus.formatClock(remaining))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current action")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(snap.currentAction)
                        .font(.body)
                }
            }
        }
        .accessibilityLabel("Current target")
    }

    private var chromeIntelligencePanel: some View {
        let debug = snap.chromeDebug
        return DashboardPanel(title: "CHROME INTELLIGENCE") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("State", value: debug.state.rawValue)
                LabeledContent("Page type", value: debug.pageType.rawValue)
                LabeledContent("Intent", value: debug.intent.rawValue)
                if !debug.currentURL.isEmpty {
                    LabeledContent("Page", value: debug.currentURL)
                        .lineLimit(2)
                }
                HStack(spacing: 16) {
                    Text("Targets \(debug.discoveredCount)")
                    Text("Safe \(debug.safeCount)")
                    Text("Blocked \(debug.blockedCount)")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                if !debug.nextTarget.isEmpty {
                    Text("Next: \(debug.nextTarget)")
                        .font(.callout)
                        .lineLimit(2)
                }
                if !snap.chromePreviewLines.isEmpty {
                    Text("Preview navigation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(Array(snap.chromePreviewLines.prefix(10).enumerated()), id: \.offset) { index, line in
                        Text("\(index + 1). \(line)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func workspaceProgressSection(apps: [DiscoveredAppDetail]) -> some View {
        let done = Double(snap.targetsCompleted)
        let rem = Double(snap.targetsRemaining ?? 0)
        let overall = (done + rem) > 0 ? done / (done + rem) : 0
        return VStack(alignment: .leading, spacing: 12) {
            DashboardPanel(title: "WORKSPACE PROGRESS") {
                ProgressRow(
                    title: snap.workflowName.isEmpty ? "Session" : snap.workflowName,
                    progress: overall,
                    accent: TiktikTheme.primary
                )
            }
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                ForEach(apps.prefix(9)) { app in
                    ApplicationCard(
                        name: app.displayName,
                        bundleID: app.bundleID,
                        targetCount: app.targets.count,
                        completedCount: app.bundleID == snap.currentBundleID ? snap.targetsCompleted : nil,
                        isActive: app.bundleID == snap.currentBundleID
                    )
                }
            }
        }
    }

    // MARK: - Discovery / idle

    private func discoveryResultsSection(_ snapshot: WorkspaceDiscoverySnapshot) -> some View {
        let files = snapshot.targets(ofKind: .file).count
        let tabs = snapshot.targets(ofKind: .tab).count
        let windows = snapshot.apps.reduce(0) { $0 + $1.windows.count }
        return DashboardPanel(title: "WORKSPACE DISCOVERED") {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 10) {
                DiscoveryStatChip(
                    title: "Applications",
                    value: snapshot.apps.count,
                    systemImage: "macwindow",
                    color: TiktikTheme.primary
                )
                DiscoveryStatChip(
                    title: "Windows",
                    value: windows,
                    systemImage: "rectangle.on.rectangle",
                    color: TiktikTheme.info
                )
                DiscoveryStatChip(
                    title: "Files",
                    value: files,
                    systemImage: "doc",
                    color: TiktikTheme.cursor
                )
                DiscoveryStatChip(
                    title: "Chrome Tabs",
                    value: tabs,
                    systemImage: "globe",
                    color: TiktikTheme.discovery
                )
                DiscoveryStatChip(
                    title: "Targets",
                    value: snapshot.allTargets.count,
                    systemImage: "sparkles",
                    color: TiktikTheme.discovery
                )
            }
        }
    }

    private func applicationCardsSection(_ apps: [DiscoveredAppDetail]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APPLICATIONS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                ForEach(apps.prefix(9)) { app in
                    ApplicationCard(
                        name: app.displayName,
                        bundleID: app.bundleID,
                        targetCount: app.targets.count,
                        completedCount: nil,
                        isActive: false
                    )
                }
            }
        }
    }

    private var emptyDiscoveryHint: some View {
        DashboardPanel {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(TiktikTheme.discovery)
                    .frame(width: 36, height: 36)
                    .background(TiktikTheme.discovery.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("No workspace scan yet")
                        .font(.body.weight(.semibold))
                    Text("Use Scan Workspace above to discover applications, files, tabs, and targets.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }

    private var controlsSection: some View {
        DashboardPanel(title: "WORKFLOW") {
            VStack(alignment: .leading, spacing: 14) {
                if session.workflowNames.isEmpty {
                    EmptyStateCard(
                        title: "No workflows yet",
                        message: "Use Discovery to confirm a Universal Workspace run, or open the editor to build one.",
                        systemImage: "list.bullet.rectangle"
                    )
                } else {
                    Picker("Selected workflow", selection: Binding(
                        get: { session.selectedWorkflow ?? "" },
                        set: { name in
                            if !name.isEmpty { session.selectWorkflow(name) }
                        }
                    )) {
                        Text("Select…").tag("")
                        ForEach(session.workflowNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 360, alignment: .leading)
                    .accessibilityLabel("Selected workflow")
                }

                HStack(spacing: 10) {
                    TiktikButton(
                        title: "Open Editor",
                        systemImage: "slider.horizontal.3",
                        kind: .secondary,
                        minWidth: 132
                    ) {
                        session.openEditor()
                        WindowPresenter.open(openWindow, id: "editor")
                    }
                    TiktikButton(
                        title: "Open Discovery",
                        systemImage: "magnifyingglass",
                        kind: .secondary,
                        minWidth: 132
                    ) {
                        session.requestOpenDashboard(section: .discovery)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var messageCard: some View {
        DashboardPanel {
            Text(session.lastMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Status message")
    }
}
