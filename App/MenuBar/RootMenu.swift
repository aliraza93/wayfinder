import AppKit
import Permissions
import SwiftUI

/// Menu-bar: Accessibility + skeleton + minimal workflow selector.
struct RootMenu: View {
    @StateObject private var permissions = MenuPermissionModel()
    @StateObject private var skeleton = SkeletonRunner()
    @StateObject private var workflows = WorkflowMenuController()

    var body: some View {
        Text(permissions.label)
        Button("Request Accessibility…") {
            permissions.requestAccess()
            skeleton.updateAccessibility(permissions.state)
            workflows.updateAccessibility(permissions.state)
        }
        Button("Open Accessibility Settings") {
            permissions.openSettings()
            skeleton.updateAccessibility(permissions.state)
            workflows.updateAccessibility(permissions.state)
        }
        Divider()
        SkeletonControls(runner: skeleton)
        if !skeleton.lastLogSummary.isEmpty {
            Text("Skeleton log: \(skeleton.lastLogSummary)")
                .font(.caption)
        }
        Divider()
        WorkflowControls(controller: workflows)
        if !workflows.lastLogSummary.isEmpty {
            Text("Workflow log: \(workflows.lastLogSummary)")
                .font(.caption)
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .onAppear {
            permissions.refresh()
            skeleton.updateAccessibility(permissions.state)
            workflows.updateAccessibility(permissions.state)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            skeleton.updateAccessibility(permissions.state)
            workflows.updateAccessibility(permissions.state)
        }
    }
}

@MainActor
final class MenuPermissionModel: ObservableObject {
    @Published private(set) var state: PermissionState = .unknown
    private let permission = AccessibilityPermission()

    var label: String {
        switch state {
        case .unknown: return "Accessibility: Unknown"
        case .denied: return "Accessibility: Denied"
        case .granted: return "Accessibility: Granted"
        }
    }

    func refresh() {
        state = permission.refresh()
    }

    func requestAccess() {
        state = permission.requestAccess()
    }

    func openSettings() {
        permission.openSystemSettings()
        state = permission.refresh()
    }
}
