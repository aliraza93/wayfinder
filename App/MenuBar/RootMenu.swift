import AppKit
import Permissions
import SwiftUI

/// Menu-bar debug affordance for Accessibility TCC state.
struct RootMenu: View {
    @StateObject private var model = MenuPermissionModel()

    var body: some View {
        Text(model.label)
        Button("Request Accessibility…") {
            model.requestAccess()
        }
        Button("Open Accessibility Settings") {
            model.openSettings()
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
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
