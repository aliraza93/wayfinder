import AppKit
import SwiftUI

struct RootMenu: View {
    @ObservedObject var session: AppSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(session.permissionLabel)
            .accessibilityIdentifier("menu.permission")
        Text(session.liveStatusLine)
            .font(.caption)
            .accessibilityIdentifier("menu.liveStatus")

        Button("Request Accessibility…") {
            session.requestAccessibility()
        }
        .accessibilityIdentifier("menu.requestAccessibility")
        Button("Open Accessibility Settings") {
            session.openAccessibilitySettings()
        }
        Button("Permission onboarding…") {
            session.openOnboarding()
            openWindow(id: "onboarding")
        }
        .accessibilityIdentifier("menu.onboarding")

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
        }

        Button(session.isRunning ? "Stop" : "Start") {
            if session.isRunning {
                session.stop()
            } else {
                session.startSelected()
            }
        }
        .disabled(!session.canStart && !session.isRunning)
        .accessibilityIdentifier("menu.startStop")

        Divider()
        Button("Workflow Editor…") {
            session.openEditor()
            openWindow(id: "editor")
        }
        .accessibilityIdentifier("menu.editor")
        Button("Run Timeline…") {
            session.openTimeline()
            openWindow(id: "timeline")
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
                openWindow(id: "uitest-host")
                openWindow(id: "onboarding")
            } else if session.showOnboarding {
                openWindow(id: "onboarding")
            }
        }
    }
}
