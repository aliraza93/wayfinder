import AppKit
import SwiftUI

struct RootMenu: View {
    @ObservedObject var session: AppSession
    @Environment(\.openWindow) private var openWindow

    private var isGranted: Bool {
        session.accessibilityGranted
    }

    var body: some View {
        if let banner = session.saveConfirmationMessage {
            Text(banner)
                .foregroundStyle(.green)
                .font(.callout)
                .accessibilityIdentifier("menu.saveConfirmation")
        }

        Text(session.permissionLabel)
            .accessibilityIdentifier("menu.permission")
        Text(session.liveStatusLine)
            .font(.caption)
            .accessibilityIdentifier("menu.liveStatus")

        if isGranted {
            Text("Accessibility OK — no prompt needed")
                .font(.caption2)
        } else {
            Text("Accessibility Denied — Start won’t run until Granted. Remove Waypoint (−) in Settings if toggle is stale, Run again, enable the new entry.")
                .font(.caption2)
                .lineLimit(4)
            Button("Request Accessibility…") {
                session.requestAccessibility()
            }
            .accessibilityIdentifier("menu.requestAccessibility")
        }

        Button("Refresh Accessibility status") {
            session.refreshPermissions()
        }
        Button("Open Accessibility Settings") {
            session.openAccessibilitySettings()
        }
        if !isGranted {
            Button("Permission onboarding…") {
                session.openOnboarding()
                WindowPresenter.open(openWindow, id: "onboarding")
            }
            .accessibilityIdentifier("menu.onboarding")
        }

        Divider()

        Text("Workflows")
            .font(.caption)
        if session.workflowNames.isEmpty {
            Text("No saved workflows — open the editor")
                .font(.caption)
        } else {
            ForEach(session.workflowNames, id: \.self) { name in
                Button(session.selectedWorkflow == name ? "▶ \(name)" : name) {
                    session.selectWorkflow(name)
                }
            }
            Text("▶ = selected. Then click Start (does not run on name tap).")
                .font(.caption2)
        }

        Button(session.isRunning ? "Stop" : "Start") {
            if session.isRunning {
                session.stop()
            } else {
                session.startSelected()
            }
        }
        // Allow Start click even when Denied so we can show why it won’t run.
        .disabled(session.isRunning ? false : session.selectedWorkflow == nil)
        .accessibilityIdentifier("menu.startStop")

        Divider()
        Button("Workflow Editor…") {
            session.openEditor()
            WindowPresenter.open(openWindow, id: "editor")
        }
        .accessibilityIdentifier("menu.editor")
        Button("Run Timeline…") {
            session.openTimeline()
            WindowPresenter.open(openWindow, id: "timeline")
        }
        .accessibilityIdentifier("menu.timeline")
        Button("Refresh workflows") {
            session.refreshWorkflowNames()
        }

        if !session.lastMessage.isEmpty {
            Text(session.lastMessage)
                .font(.caption)
                .lineLimit(3)
        }

        Divider()
        Text("Stop hot-key: Ctrl+Opt+.")
            .font(.caption2)
        Button("Quit Waypoint") {
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
            // Do not auto-pop onboarding on every menu open — only open when user asks.
        }
    }
}
