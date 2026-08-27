import AppPresentation
import Domain
import Observability
import Safety
import SwiftUI

// MARK: - Workflows

struct WorkflowsSectionView: View {
    @ObservedObject var session: AppSession
    var openWindow: OpenWindowAction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppChrome.stackSpacing) {
                ShellPageHeader(
                    title: "Workflows",
                    subtitle: "Saved navigation workflows. Select one to run from the Dashboard or menu bar."
                )

                GroupBox {
                    if session.workflowNames.isEmpty {
                        EmptyStateCard(
                            title: "No workflows yet",
                            message: "Use Discovery to scan open apps, or open the editor to build a Universal Workspace workflow.",
                            systemImage: "list.bullet.rectangle"
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(session.workflowNames.enumerated()), id: \.element) { index, name in
                                if index > 0 { Divider() }
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name)
                                            .font(.body.weight(session.selectedWorkflow == name ? .semibold : .regular))
                                        if session.selectedWorkflow == name {
                                            Text("Selected")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Button("Select") { session.selectWorkflow(name) }
                                        .disabled(session.selectedWorkflow == name)
                                }
                                .padding(.vertical, 10)
                            }
                        }
                        .padding(4)
                    }
                }

                HStack {
                    Button("Refresh") { session.refreshWorkflowNames() }
                    Button("Edit workflows…") {
                        session.openEditor()
                        WindowPresenter.open(openWindow, id: "editor")
                    }
                }
            }
            .padding(AppChrome.pagePadding)
            .frame(maxWidth: AppChrome.contentMaxWidth, alignment: .leading)
        }
    }
}

// MARK: - Applications

struct ApplicationsSectionView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppChrome.stackSpacing) {
                ShellPageHeader(
                    title: "Applications",
                    subtitle: "Running apps available for Targets. Configure Targets in the workflow editor."
                )

                GroupBox {
                    let apps = session.editorUI.runningApps
                    if apps.isEmpty {
                        EmptyStateCard(
                            title: "No apps listed",
                            message: "Click Refresh to enumerate visible user-facing apps. System Settings is never a Target.",
                            systemImage: "app.badge"
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                                if index > 0 { Divider() }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.displayName)
                                    Text(app.bundleID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(4)
                    }
                }

                Button("Refresh apps") { session.editorUI.refreshApps() }
            }
            .padding(AppChrome.pagePadding)
            .frame(maxWidth: AppChrome.contentMaxWidth, alignment: .leading)
        }
        .onAppear { session.editorUI.refreshApps() }
    }
}

// MARK: - Discovery wizard

enum DiscoveryWizardStep: Int, CaseIterable, Identifiable, Equatable {
    case scan
    case review
    case configure
    case preview
    case confirm

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .scan: return "Scan"
        case .review: return "Review"
        case .configure: return "Configure"
        case .preview: return "Preview"
        case .confirm: return "Start"
        }
    }

    var next: DiscoveryWizardStep? { DiscoveryWizardStep(rawValue: rawValue + 1) }
    var previous: DiscoveryWizardStep? { DiscoveryWizardStep(rawValue: rawValue - 1) }
}

enum DiscoveryFlowError: Error {
    case noSnapshot
    case noApprovals
}

// MARK: - Discovery

struct DiscoverySectionView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppChrome.stackSpacing) {
                ShellPageHeader(
                    title: "Discovery",
                    subtitle: "Scan → Review → Configure → Preview → Start. Nothing is automated until you confirm Start Workflow."
                )

                DashboardPanel {
                    DiscoveryWizardStepBar(step: session.discoveryWizardStep)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Discovery step \(session.discoveryWizardStep.title)")
                }

                if !session.discoveryMessage.isEmpty {
                    Text(session.discoveryMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Group {
                    switch session.discoveryWizardStep {
                    case .scan:
                        DiscoveryScanStepView(session: session)
                    case .review:
                        DiscoveryReviewStepView(session: session)
                    case .configure:
                        DiscoveryConfigureStepView(session: session)
                    case .preview:
                        DiscoveryPreviewStepView(session: session)
                    case .confirm:
                        DiscoveryConfirmStepView(session: session)
                    }
                }

                DiscoveryWizardNavBar(session: session)
            }
            .padding(AppChrome.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TiktikTheme.elevatedBackground)
    }
}

private struct DiscoveryWizardStepBar: View {
    let step: DiscoveryWizardStep

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DiscoveryWizardStep.allCases) { item in
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(circleFill(for: item))
                            .frame(width: 28, height: 28)
                        Text("\(item.rawValue + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(item.rawValue <= step.rawValue ? Color.white : Color.secondary)
                    }
                    Text(item.title)
                        .font(.caption.weight(item == step ? .semibold : .regular))
                        .foregroundStyle(item == step ? Color.primary : Color.secondary)
                }
                .frame(maxWidth: .infinity)

                if item != DiscoveryWizardStep.allCases.last {
                    Rectangle()
                        .fill(item.rawValue < step.rawValue ? TiktikTheme.primary.opacity(0.7) : TiktikTheme.separator)
                        .frame(height: 2)
                        .frame(maxWidth: 48)
                        .padding(.bottom, 18)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func circleFill(for item: DiscoveryWizardStep) -> Color {
        item.rawValue <= step.rawValue ? TiktikTheme.primary : Color.secondary.opacity(0.22)
    }
}

private struct DiscoveryWizardNavBar: View {
    @ObservedObject var session: AppSession

    var body: some View {
        HStack {
            if session.discoveryWizardStep != .scan {
                TiktikButton(title: "Back", systemImage: "chevron.left", kind: .secondary, minWidth: 100) {
                    session.retreatDiscoveryWizard()
                }
            }
            Spacer()
            if session.discoveryWizardStep != .confirm {
                TiktikButton(
                    title: session.discoveryWizardStep == .scan && session.discoverySnapshot == nil
                        ? "Scan first"
                        : "Continue",
                    systemImage: "chevron.right",
                    kind: .primary,
                    minWidth: 120
                ) {
                    if session.discoveryWizardStep == .scan, session.discoverySnapshot == nil {
                        session.scanWorkspace()
                    } else {
                        session.advanceDiscoveryWizard()
                    }
                }
                .disabled(
                    session.discoveryWizardStep == .scan
                        ? session.isScanningWorkspace
                        : !session.discoveryWizardCanAdvance(from: session.discoveryWizardStep)
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: Scan

private struct DiscoveryScanStepView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TiktikButton(
                title: session.isScanningWorkspace ? "Scanning…" : "Scan Workspace",
                systemImage: session.isScanningWorkspace ? nil : "sparkles",
                kind: .discovery,
                isLoading: session.isScanningWorkspace,
                minWidth: 150
            ) {
                session.scanWorkspace()
            }
            .disabled(session.isScanningWorkspace)
            .accessibilityIdentifier("discovery.scan")

            if let snapshot = session.discoverySnapshot {
                let windows = snapshot.apps.reduce(0) { $0 + $1.windows.count }
                let files = snapshot.targets(ofKind: .file).count
                let tabs = snapshot.targets(ofKind: .tab).count
                DashboardPanel(title: "WORKSPACE FOUND") {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ], spacing: 10) {
                        DiscoveryStatChip(title: "Applications", value: snapshot.apps.count, systemImage: "macwindow", color: TiktikTheme.primary)
                        DiscoveryStatChip(title: "Windows", value: windows, systemImage: "rectangle.on.rectangle", color: TiktikTheme.info)
                        DiscoveryStatChip(title: "Files", value: files, systemImage: "doc", color: TiktikTheme.cursor)
                        DiscoveryStatChip(title: "Tabs", value: tabs, systemImage: "globe", color: TiktikTheme.discovery)
                        DiscoveryStatChip(title: "Targets", value: snapshot.allTargets.count, systemImage: "sparkles", color: TiktikTheme.discovery)
                    }
                }
            } else if session.isScanningWorkspace {
                DashboardPanel {
                    EmptyStateCard(
                        title: "Scanning workspace…",
                        message: "Enumerating open apps and windows. No automation runs during discovery.",
                        systemImage: "magnifyingglass"
                    )
                }
            } else {
                DashboardPanel {
                    EmptyStateCard(
                        title: "Ready to scan",
                        message: "Discover open apps, windows, files, tabs, and documents. Discovery is read-only and never starts a workflow.",
                        systemImage: "sparkles"
                    )
                }
            }
        }
    }
}

// MARK: Review

private struct DiscoveryReviewStepView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TiktikButton(title: "Select all", systemImage: "checkmark.circle", kind: .secondary, minWidth: 110) {
                    session.setAllDiscoveryTargetsApproved(true)
                }
                TiktikButton(title: "Clear all", systemImage: "xmark.circle", kind: .secondary, minWidth: 110) {
                    session.setAllDiscoveryTargetsApproved(false)
                }
                Spacer()
                Text("\(session.discoverySnapshot?.approvedTargets.count ?? 0) selected")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(TiktikTheme.cardBackground, in: Capsule())
            }

            if let snapshot = session.discoverySnapshot {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ], spacing: 12) {
                    ForEach(snapshot.apps) { app in
                        DiscoveryReviewAppBox(app: app, session: session)
                    }
                }

                DashboardPanel(title: "TOTALS") {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 10) {
                        ForEach(DiscoveryNavigationPlan.appTargetCounts(from: snapshot), id: \.name) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(.callout.weight(.medium))
                                Text("\(row.count) target\(row.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Divider()
                    HStack {
                        Text("Total approved")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(snapshot.approvedTargets.count)")
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                }
            }
        }
    }
}

private struct DiscoveryReviewAppBox: View {
    let app: DiscoveredAppDetail
    @ObservedObject var session: AppSession

    private var approvedCount: Int { app.targets.filter(\.approved).count }
    private var allSelected: Bool { !app.targets.isEmpty && approvedCount == app.targets.count }
    private var accent: Color {
        TiktikTheme.appAccent(bundleID: app.bundleID, displayName: app.displayName)
    }

    var body: some View {
        DashboardPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: TiktikTheme.appSymbol(bundleID: app.bundleID, displayName: app.displayName))
                        .foregroundStyle(accent)
                        .frame(width: 28, height: 28)
                        .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Toggle(isOn: Binding(
                        get: { allSelected },
                        set: { session.setDiscoveryAppApproved(bundleID: app.bundleID, approved: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.displayName)
                                .font(.headline)
                            Text("\(approvedCount) / \(app.targets.count) targets")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    Spacer(minLength: 0)
                }

                ForEach(DiscoveryNavigationPlan.reviewKinds, id: \.self) { kind in
                    let items = app.targets.filter { $0.kind == kind }
                    if !items.isEmpty {
                        Text(DiscoveryNavigationPlan.reviewTitle(for: kind))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        ForEach(items) { target in
                            Toggle(isOn: Binding(
                                get: { target.approved },
                                set: { session.setDiscoveryTargetApproved(id: target.id, approved: $0) }
                            )) {
                                Text(target.displayName)
                                    .lineLimit(1)
                            }
                            .toggleStyle(.checkbox)
                        }
                        if kind == .tab, ApplicationClassifier.classify(bundleID: app.bundleID) == .browser {
                            Text("Existing tabs stay open — page content only.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Configure

private struct DiscoveryConfigureStepView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            DashboardPanel(title: "SESSION") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Session duration", selection: $session.discoveryDurationPreset) {
                        ForEach(RunDurationPreset.timedOnly + [.untilStopped], id: \.self) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    if session.discoveryDurationPreset == .custom {
                        Stepper(
                            "Custom: \(session.discoveryCustomHours) hr",
                            value: $session.discoveryCustomHours,
                            in: 1...72
                        )
                    }

                    Stepper(
                        "Minimum target time: \(Int(session.discoveryDwellMinSeconds))s",
                        value: $session.discoveryDwellMinSeconds,
                        in: 5...600,
                        step: 5
                    )
                    Stepper(
                        "Maximum target time: \(Int(session.discoveryDwellMaxSeconds))s",
                        value: $session.discoveryDwellMaxSeconds,
                        in: 10...900,
                        step: 5
                    )

                    Picker("Navigation speed", selection: $session.discoverySpeed) {
                        ForEach(NavigationSpeedPreset.allCases) { speed in
                            Text(speed.title).tag(speed)
                        }
                    }

                    Picker("Target order", selection: $session.discoveryTargetOrder) {
                        ForEach(ReviewTargetOrder.allCases, id: \.self) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    Text(session.discoveryTargetOrder == .applicationPriority
                          ? "Application priority prefers Cursor → Chrome → Finder → Preview."
                          : "Controls how approved targets are sequenced.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            DashboardPanel(title: "CHROME PAGE CRAWL") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Existing tabs stay open. Exploration uses page content only — never Chrome Back, Close, Omnibox, or toolbar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Inspect → understand → navigate (links / GitHub files / docs) → Page/Arrow keys to read (no scroll-wheel). Longer pages stay open longer.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Default: same-domain · depth \(ChromeNavigationSettings.default.maxDepth) · max \(ChromeNavigationSettings.default.maxPages) pages per tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Allowed domains (one per line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $session.discoveryAllowedDomainsText)
                        .font(.body)
                        .frame(minHeight: 64, maxHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(TiktikTheme.separator))

                    Text("Blocked domains (one per line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $session.discoveryBlockedDomainsText)
                        .font(.body)
                        .frame(minHeight: 48, maxHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(TiktikTheme.separator))
                }
            }
        }
    }
}

// MARK: Preview

private struct DiscoveryPreviewStepView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        let steps = session.discoveryPlanSteps
        DashboardPanel(title: "ESTIMATED NAVIGATION PLAN") {
            if steps.isEmpty {
                Text("No approved targets yet.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ], spacing: 6) {
                    ForEach(steps.prefix(40)) { step in
                        Text("\(step.index). \(step.displayLine)")
                            .font(.callout)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if steps.count > 40 {
                    Text("…and \(steps.count - 40) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: Confirm / Start

private struct DiscoveryConfirmStepView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        let estimate = session.discoverySessionEstimate
        DashboardPanel(title: "CONFIRM") {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    MetricCard(value: "\(estimate.approvedCount)", label: "Targets", accent: TiktikTheme.discovery)
                    MetricCard(value: estimate.formattedDuration, label: "Estimated session", accent: TiktikTheme.info)
                    MetricCard(value: UniversalWorkspaceNavigation.workflowName, label: "Workflow", accent: TiktikTheme.primary)
                }

                TiktikButton(
                    title: "Start Workflow",
                    systemImage: "play.fill",
                    kind: .primary,
                    minWidth: 150
                ) {
                    session.confirmAndStartDiscoveryWorkflow()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(session.isRunning || estimate.approvedCount == 0)

                Text("Automation begins only after Start Workflow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Sessions

struct SessionsSectionView: View {
    @ObservedObject var session: AppSession
    var openWindow: OpenWindowAction
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppChrome.stackSpacing) {
                ShellPageHeader(
                    title: "Sessions",
                    subtitle: "Local history of completed and stopped runs. Identity metadata only — never page content or screenshots."
                )

                GroupBox("Current session") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Status", value: session.dashboard.status.title)
                        LabeledContent("Workflow", value: session.dashboard.workflowName.isEmpty ? "—" : session.dashboard.workflowName)
                        LabeledContent("Elapsed", value: RunLiveStatus.formatClock(session.dashboard.elapsedSeconds))
                        LabeledContent("Targets completed", value: "\(session.dashboard.targetsCompleted)")
                    }
                    .padding(4)
                }

                HStack {
                    Button("Refresh") { session.refreshSessionHistory() }
                    Button("Open run timeline…") {
                        session.openTimeline()
                        WindowPresenter.open(openWindow, id: "timeline")
                    }
                    Spacer()
                    Button("Clear history…", role: .destructive) {
                        confirmClear = true
                    }
                    .disabled(session.sessionHistory.isEmpty)
                }

                if !session.sessionHistoryMessage.isEmpty {
                    Text(session.sessionHistoryMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if session.sessionHistory.isEmpty {
                    GroupBox {
                        EmptyStateCard(
                            title: "No saved sessions",
                            message: "Finished or stopped workflows appear here with duration, apps visited, and action counts.",
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                } else {
                    ForEach(session.sessionHistorySections) { section in
                        GroupBox(section.group.title) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(section.sessions.enumerated()), id: \.element.id) { index, record in
                                    if index > 0 { Divider() }
                                    Button {
                                        session.selectSession(record.id)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(record.workflowName)
                                                .font(.body.weight(session.selectedSessionID == record.id ? .semibold : .regular))
                                                .foregroundStyle(.primary)
                                            Text(record.formattedDuration)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                            Text("\(max(record.targetsVisited.count, record.targetsTouched)) targets · \(record.endStatus.title)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(4)
                        }
                    }
                }

                if let detail = session.selectedSessionRecord {
                    SessionHistoryDetailView(record: detail)
                }
            }
            .padding(AppChrome.pagePadding)
            .frame(maxWidth: AppChrome.contentMaxWidth, alignment: .leading)
        }
        .onAppear { session.refreshSessionHistory() }
        .alert("Clear session history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { session.clearSessionHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes local session history on this Mac. Workflows are not affected.")
        }
    }
}

private struct SessionHistoryDetailView: View {
    let record: SessionHistoryRecord

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        GroupBox("Session details") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Workflow", value: record.workflowName)
                LabeledContent("Status", value: record.endStatus.title)
                LabeledContent("Started", value: timeFormatter.string(from: record.startedAt))
                LabeledContent("Ended", value: timeFormatter.string(from: record.endedAt))
                LabeledContent("Duration", value: record.formattedDuration)
                LabeledContent("Actions performed", value: "\(record.actionsPerformed)")
                LabeledContent("Failures", value: "\(record.failureCount)")

                detailList(title: "Applications visited", items: record.applicationsVisited)
                detailList(title: "Targets visited", items: record.targetsVisited)
                detailList(title: "Targets skipped", items: record.targetsSkipped)

                if !record.actionCounts.isEmpty {
                    Text("Actions")
                        .font(.subheadline.weight(.semibold))
                    ForEach(record.actionCounts.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.caption.monospaced())
                            Spacer()
                            Text("\(record.actionCounts[key] ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private func detailList(title: String, items: [String]) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
        if items.isEmpty {
            Text("None")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.callout)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Logs

struct LogsSectionView: View {
    @ObservedObject var session: AppSession
    var openWindow: OpenWindowAction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppChrome.stackSpacing) {
                ShellPageHeader(
                    title: "Logs",
                    subtitle: "Privacy-respecting run events: action kind, target app, result — never document body text."
                )

                GroupBox {
                    if session.timelineUI.rows.isEmpty {
                        EmptyStateCard(
                            title: "No events yet",
                            message: "Start a workflow to populate the timeline. Entries stay on this Mac only.",
                            systemImage: "doc.text"
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(session.timelineUI.rows.prefix(40)) { row in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.timeText)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 72, alignment: .leading)
                                    Text(row.actionKind)
                                        .font(.callout.monospaced())
                                    Spacer()
                                    Text(row.result)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(4)
                    }
                }

                Button("Open full timeline…") {
                    session.openTimeline()
                    WindowPresenter.open(openWindow, id: "timeline")
                }
            }
            .padding(AppChrome.pagePadding)
            .frame(maxWidth: 800, alignment: .leading)
        }
    }
}

// MARK: - Safety

struct SafetySectionView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppChrome.stackSpacing) {
                ShellPageHeader(
                    title: "Safety Center",
                    subtitle: SafetyCenterCatalog.permissionGateCopy
                )

                emergencyStopCard
                permissionsCard
                allowlistCard
                blocklistCard

                GroupBox("Product invariants") {
                    Text(HonestCopy.neverDoes)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
            }
            .padding(AppChrome.pagePadding)
            .frame(maxWidth: AppChrome.contentMaxWidth, alignment: .leading)
        }
        .onAppear { session.refreshPermissions() }
    }

    private var emergencyStopCard: some View {
        GroupBox("Emergency Stop") {
            VStack(alignment: .leading, spacing: 12) {
                Text(SafetyCenterCatalog.emergencyStopCopy)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Stop Workflow", role: .destructive) {
                        session.stop()
                    }
                    .controlSize(.large)
                    .disabled(!session.isRunning)
                    .accessibilityIdentifier("safety.emergencyStop")

                    if session.isRunning {
                        Text(session.isPaused ? "Workflow is paused — Stop still ends the run." : "Workflow is running.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No active workflow.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Also available: Dashboard · Menu bar · Toolbar · ⌃⌥.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var permissionsCard: some View {
        GroupBox("macOS permissions") {
            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    title: "Accessibility Permission",
                    status: session.accessibilityGranted ? "Available" : "Required",
                    ready: session.accessibilityGranted,
                    detail: HonestCopy.permissionWhy
                )
                Divider()
                permissionRow(
                    title: "Automation Permission",
                    status: "Not required",
                    ready: true,
                    detail: "Apple Events / Automation is not used to drive Target apps. An usage string exists only if macOS asks when opening System Settings."
                )
                Divider()
                permissionRow(
                    title: "Application Access",
                    status: applicationAccessStatus,
                    ready: session.accessibilityGranted,
                    detail: applicationAccessDetail
                )

                HStack {
                    Button("Refresh") { session.refreshPermissions() }
                    Button("Request Accessibility…") { session.requestAccessibility() }
                    Button("Open Accessibility Settings") { session.openAccessibilitySettings() }
                }
            }
            .padding(4)
        }
    }

    private var applicationAccessStatus: String {
        if !session.accessibilityGranted { return "Waiting on Accessibility" }
        if session.isRunning { return "Active for running Targets" }
        return "Limited to configured Targets"
    }

    private var applicationAccessDetail: String {
        "Only apps you add as workflow Targets (plus optional Finder/Preview discovery you enable) may be focused or navigated. System Settings and other forbidden bundles are blocked."
    }

    private func permissionRow(title: String, status: String, ready: Bool, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(status)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(ready ? Color.primary : Color.orange)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var allowlistCard: some View {
        GroupBox("Action allowlist") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Every action still passes through SafetyPolicy.validate before execution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(SafetyCenterCatalog.allowedActions) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(entry.title, systemImage: "checkmark.circle")
                            .font(.callout.weight(.medium))
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var blocklistCard: some View {
        GroupBox("Blocked") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(SafetyCenterCatalog.blockedActions) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(entry.title, systemImage: "xmark.octagon")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.red.opacity(0.9))
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}

// MARK: - Settings

struct SettingsSectionView: View {
    @ObservedObject var session: AppSession
    var openWindow: OpenWindowAction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppChrome.stackSpacing) {
                ShellPageHeader(
                    title: "Settings",
                    subtitle: ProductIdentity.shortDescription,
                    showBrand: true
                )

                GroupBox("Product") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Name", value: ProductIdentity.displayName)
                        LabeledContent("Tagline", value: ProductIdentity.tagline)
                        LabeledContent("Bundle ID", value: ProductIdentity.bundleIdentifier)
                        Text("Bundle ID is kept stable so Accessibility grants persist across updates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }

                GroupBox("Hot-keys") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stop  ⌃⌥.")
                        Text("Pause  ⌃⌥P")
                        Text("Resume  ⌃⌥R")
                        Text("Start (Dashboard)  ⌘R")
                    }
                    .font(.body.monospaced())
                    .padding(4)
                }

                GroupBox("Permissions") {
                    HStack {
                        Button("Permission onboarding…") {
                            session.openOnboarding()
                            WindowPresenter.open(openWindow, id: "onboarding")
                        }
                        Button("Workflow editor…") {
                            session.openEditor()
                            WindowPresenter.open(openWindow, id: "editor")
                        }
                        Button("Safety Center") {
                            session.requestOpenDashboard(section: .safety)
                        }
                    }
                    .padding(4)
                }
            }
            .padding(AppChrome.pagePadding)
            .frame(maxWidth: AppChrome.contentMaxWidth, alignment: .leading)
        }
    }
}
