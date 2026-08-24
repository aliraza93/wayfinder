import AppPresentation
import Permissions
import SwiftUI

@main
struct WaypointApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = AppSession()

    init() {
        SingleInstance.claim()
    }

    var body: some Scene {
        MenuBarExtra("Waypoint", systemImage: "location.north.line") {
            RootMenu(session: session)
                .onAppear {
                    appDelegate.onBecameActive = { [weak session] in
                        Task { @MainActor in
                            session?.refreshPermissions()
                        }
                    }
                    session.refreshPermissions()
                }
        }

        Window("Onboarding", id: "onboarding") {
            OnboardingView(model: session.onboardingUI)
                .accessibilityIdentifier("window.onboarding")
        }
        .defaultSize(width: 520, height: 400)

        Window("Workflow Editor", id: "editor") {
            WorkflowEditorView(model: session.editorUI)
                .accessibilityIdentifier("window.editor")
        }
        .defaultSize(width: 760, height: 520)

        Window("Run Timeline", id: "timeline") {
            RunTimelineView(model: session.timelineUI)
                .accessibilityIdentifier("window.timeline")
        }
        .defaultSize(width: 600, height: 360)

        // UITest host surface — openable without clicking the menu-bar extra.
        Window("Waypoint UITest Host", id: "uitest-host") {
            UITestHostView(session: session)
        }
        .defaultSize(width: 360, height: 240)
    }
}

/// Buttons that open the real windows — used by XCUITest instead of the menu-bar extra.
struct UITestHostView: View {
    @ObservedObject var session: AppSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Waypoint UITest Host")
                .accessibilityIdentifier("uitest.host.title")
            Text(session.permissionLabel)
                .accessibilityIdentifier("menu.permission")
            Text(session.liveStatusLine)
                .accessibilityIdentifier("menu.liveStatus")
            Button("Open Onboarding") {
                openWindow(id: "onboarding")
            }
            .accessibilityIdentifier("uitest.openOnboarding")
            Button("Open Editor") {
                openWindow(id: "editor")
            }
            .accessibilityIdentifier("uitest.openEditor")
            if let banner = session.saveConfirmationMessage {
                Text(banner)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("menu.saveConfirmation")
            }
            Button(session.isRunning ? "Stop" : "Start") {
                if session.isRunning { session.stop() } else { session.startSelected() }
            }
            .accessibilityIdentifier("menu.startStop")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            session.refreshPermissions()
            session.refreshWorkflowNames()
        }
    }
}
