import AppKit
import Foundation

/// Accessibility TCC handling: detect, prompt once, deep-link on denial, re-check on foreground.
/// Does not read any AX content.
public final class AccessibilityPermission: @unchecked Sendable {
    /// System Settings → Privacy & Security → Accessibility.
    public static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    private let probe: any TrustProbe
    private let openURL: @Sendable (URL) -> Void
    private var didPrompt = false

    public private(set) var state: PermissionState = .unknown

    public init(
        probe: any TrustProbe = SystemTrustProbe(),
        openURL: @escaping @Sendable (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        }
    ) {
        self.probe = probe
        self.openURL = openURL
    }

    /// Re-check without prompting. Call on app foreground so a Settings toggle flips to granted without relaunch.
    @discardableResult
    public func refresh() -> PermissionState {
        if probe.isTrusted(prompt: false) {
            state = .granted
        } else if didPrompt {
            state = .denied
        } else if state == .unknown {
            state = .denied
        } else {
            state = .denied
        }
        return state
    }

    /// Prompt at most once. On denial (or if already prompted), deep-link to Accessibility settings — never re-prompt.
    /// If the process is already trusted, returns `.granted` without prompting or opening Settings.
    @discardableResult
    public func requestAccess() -> PermissionState {
        if probe.isTrusted(prompt: false) {
            state = .granted
            return state
        }

        if didPrompt {
            openSystemSettings()
            return refresh()
        }

        didPrompt = true
        let trusted = probe.isTrusted(prompt: true)
        if trusted {
            state = .granted
        } else {
            state = .denied
            openSystemSettings()
        }
        return state
    }

    public func openSystemSettings() {
        openURL(Self.accessibilitySettingsURL)
    }

    /// Test/helper: whether a system prompt has already been attempted this session.
    public var hasPrompted: Bool { didPrompt }
}
