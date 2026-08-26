import AppKit
import Domain
import SwiftUI

/// Forwards activation so Accessibility can flip Denied → Granted after the Settings toggle without relaunch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onBecameActive: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Main window + menu bar companion: regular activation (Dock icon).
        _ = NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        onBecameActive?()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        onBecameActive?()
        return true
    }

    @objc private func windowDidClose(_ notification: Notification) {
        DispatchQueue.main.async {
            WindowPresenter.restoreAccessoryIfNeeded()
        }
    }
}

/// Opens SwiftUI `Window` scenes from a `MenuBarExtra` / LSUIElement agent.
/// Without activation, `openWindow` often appears to do nothing (window stays behind or never keys).
enum WindowPresenter {
    static func open(_ openWindow: OpenWindowAction, id: String) {
        if NSApp.activationPolicy() != .regular {
            _ = NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where Self.matches(window, id: id) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where Self.matches(window, id: id) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    static func restoreAccessoryIfNeeded() {
        // With a main WindowGroup, stay regular so the Dock icon remains available.
        // Helper-only close no longer forces accessory mode.
    }

    private static func matches(_ window: NSWindow, id: String) -> Bool {
        if let raw = window.identifier?.rawValue, raw.contains(id) {
            return true
        }
        let titles: [String: String] = [
            "main": ProductIdentity.displayName,
            "editor": "Workflow Editor",
            "timeline": "Run Timeline",
            "onboarding": "Onboarding",
            "uitest-host": "\(ProductIdentity.displayName) UITest Host",
        ]
        if let expected = titles[id], window.title == expected {
            return true
        }
        return false
    }
}
