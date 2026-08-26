import AppKit
import AppPresentation
import Domain
import SwiftUI

/// Menu bar companion — mirrors `AppSession` / dashboard state (no second engine).
struct RootMenu: View {
    @ObservedObject var session: AppSession
    @Environment(\.openWindow) private var openWindow

    private var snap: DashboardRunSnapshot { session.dashboard }

    var body: some View {
        Text(ProductIdentity.displayName)
            .font(.headline)
            .accessibilityIdentifier("menu.productTitle")

        Text(ProductIdentity.tagline)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)

        switch menuMode {
        case .idle:
            idleContent
        case .running:
            runningContent
        case .paused:
            pausedContent
        }

        Divider()
        Button("Quit \(ProductIdentity.displayName)") {
            NSApplication.shared.terminate(nil)
        }
        .accessibilityIdentifier("menu.quit")
        .onAppear {
            session.refreshPermissions()
            session.refreshWorkflowNames()
            if ProcessInfo.processInfo.arguments.contains("-uitesting") {
                WindowPresenter.open(openWindow, id: "uitest-host")
                WindowPresenter.open(openWindow, id: "onboarding")
            }
        }
    }

    private enum MenuMode {
        case idle
        case running
        case paused
    }

    private var menuMode: MenuMode {
        if session.isRunning {
            return session.isPaused ? .paused : .running
        }
        return .idle
    }

    // MARK: - Idle

    @ViewBuilder
    private var idleContent: some View {
        if let banner = session.saveConfirmationMessage {
            Text(banner)
                .foregroundStyle(.green)
                .font(.callout)
                .accessibilityIdentifier("menu.saveConfirmation")
        }

        Text(session.liveStatusLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("menu.liveStatus")

        if !session.accessibilityGranted {
            Text(session.permissionLabel)
                .font(.caption2)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("menu.permission")
        }

        Button("Open Dashboard") {
            openDashboard()
        }
        .accessibilityIdentifier("menu.openDashboard")

        startWorkflowControl

        Button("Settings") {
            openDashboard(section: .settings)
        }
        .accessibilityIdentifier("menu.settings")
    }

    @ViewBuilder
    private var startWorkflowControl: some View {
        if session.workflowNames.isEmpty {
            Button("Start Workflow") {}
                .disabled(true)
                .accessibilityIdentifier("menu.startStop")
            Text("No saved workflows — open Dashboard → Workflows")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if session.workflowNames.count == 1, let only = session.workflowNames.first {
            Button("Start Workflow") {
                session.selectWorkflow(only)
                session.startSelected()
            }
            .accessibilityIdentifier("menu.startStop")
        } else {
            Menu("Start Workflow") {
                ForEach(session.workflowNames, id: \.self) { name in
                    Button(session.selectedWorkflow == name ? "▶ \(name)" : name) {
                        session.selectWorkflow(name)
                        session.startSelected()
                    }
                }
            }
            .accessibilityIdentifier("menu.startStop")
        }
    }

    // MARK: - Running

    @ViewBuilder
    private var runningContent: some View {
        Text("Running")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.green)
            .accessibilityIdentifier("menu.liveStatus")

        if !snap.workflowName.isEmpty {
            Text(snap.workflowName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Text("App: \(snap.currentApplication)")
            .font(.caption)
            .lineLimit(1)
            .accessibilityIdentifier("menu.currentApplication")

        Text("Target: \(snap.currentFileOrTab)")
            .font(.caption)
            .lineLimit(1)
            .accessibilityIdentifier("menu.currentTarget")

        Text("Elapsed: \(RunLiveStatus.formatClock(snap.elapsedSeconds))")
            .font(.caption.monospacedDigit())
            .accessibilityIdentifier("menu.elapsed")

        Divider()

        Button("Pause (⌃⌥P)") {
            session.pause()
        }
        .accessibilityIdentifier("menu.pause")

        Button("Emergency Stop (⌃⌥.)") {
            session.stop()
        }
        .accessibilityIdentifier("menu.startStop")

        Button("Open Dashboard") {
            openDashboard()
        }
        .accessibilityIdentifier("menu.openDashboard")
    }

    // MARK: - Paused

    @ViewBuilder
    private var pausedContent: some View {
        Text("Paused")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
            .accessibilityIdentifier("menu.liveStatus")

        if !snap.workflowName.isEmpty {
            Text(snap.workflowName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if snap.currentApplication != "—" {
            Text("App: \(snap.currentApplication)")
                .font(.caption)
                .lineLimit(1)
        }

        Text("Elapsed: \(RunLiveStatus.formatClock(snap.elapsedSeconds))")
            .font(.caption.monospacedDigit())

        Divider()

        Button("Resume (⌃⌥R)") {
            session.resume()
        }
        .accessibilityIdentifier("menu.resume")

        Button("Emergency Stop (⌃⌥.)") {
            session.stop()
        }
        .accessibilityIdentifier("menu.startStop")

        Button("Open Dashboard") {
            openDashboard()
        }
        .accessibilityIdentifier("menu.openDashboard")
    }

    // MARK: - Dashboard

    private func openDashboard(section: AppSidebarSection = .dashboard) {
        session.requestOpenDashboard(section: section)
        WindowPresenter.open(openWindow, id: "main")
    }
}
