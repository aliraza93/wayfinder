import ApplicationServices
import Domain
import Foundation

/// Read-only window title enumeration via Accessibility.
/// Never activates apps, never emits input, never reads document body text.
public struct WindowTitleEnumerator: Sendable {
    public var maxWindowsPerApp: Int

    public init(maxWindowsPerApp: Int = 24) {
        self.maxWindowsPerApp = maxWindowsPerApp
    }

    public func windows(processID: Int32) -> (status: DiscoveryAccessibilityStatus, windows: [DiscoveredWindowInfo]) {
        let appElement = AXUIElementCreateApplication(processID)
        var windowsRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )
        guard status == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            // App exists but AX windows unavailable — limited discovery.
            return (.unavailable, [])
        }

        var result: [DiscoveredWindowInfo] = []
        for (index, window) in windows.prefix(maxWindowsPerApp).enumerated() {
            let title = stringAttribute(window, kAXTitleAttribute as String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Skip empty titles; keep short chrome titles only (identity).
            guard !title.isEmpty else { continue }
            result.append(
                DiscoveredWindowInfo(
                    title: String(title.prefix(160)),
                    index: index
                )
            )
        }

        if result.isEmpty {
            return (.limited, [])
        }
        return (.readable, result)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref as? String
        else {
            return nil
        }
        return value
    }
}
