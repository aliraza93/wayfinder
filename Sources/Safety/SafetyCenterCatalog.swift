import Foundation

/// Explicit navigation allowlist / blocklist shown in Safety Center (and enforced by SafetyPolicy).
public enum SafetyCenterCatalog: Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: String { title }
        public var title: String
        public var detail: String

        public init(title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    /// Actions the product may perform when Accessibility is granted and SafetyPolicy allows.
    public static let allowedActions: [Entry] = [
        Entry(title: "Focus application", detail: "Activate a configured Target app via AppKit / NSWorkspace."),
        Entry(title: "Focus window", detail: "Bring an already-open window of a Target app forward when adapters can resolve it."),
        Entry(title: "Switch tab", detail: "Allowlisted Ctrl+Tab / Ctrl+Shift+Tab chords only."),
        Entry(title: "Switch file", detail: "Explorer sidebar click or open-existing-file for configured paths."),
        Entry(title: "Open existing file", detail: "Open a URL/path the user already configured — never create new files."),
        Entry(title: "Scroll", detail: "Optional scroll-wheel primitive (allowed by Safety). Default Universal workflow prefers Page/Arrow keys instead."),
        Entry(title: "Page Up", detail: "Inert Page Up key — no modifiers that edit text."),
        Entry(title: "Page Down", detail: "Inert Page Down key — no modifiers that edit text."),
        Entry(title: "Arrow navigation", detail: "Inert arrow keys for reading, not selection-with-Shift editing."),
        Entry(title: "Home", detail: "Inert Home key for navigation."),
        Entry(title: "End", detail: "Inert End key for navigation."),
        Entry(
            title: "Click known page navigation element",
            detail: "Targeted click on scored web-page content inside AXWebArea — never Chrome toolbar, tabs, omnibox, or window controls."
        ),
        Entry(title: "Follow documentation / sidebar links", detail: "Same-domain docs and TOC links scored for read-only exploration."),
        Entry(title: "Open GitHub directory or source file", detail: "Repository tree / blob links only — never edit mode or PR actions."),
        Entry(title: "Page scrolling", detail: "Page Up/Down and arrow keys inside the focused page or file — scroll-wheel is not used in the default workflow. Longer pages stay open longer."),
    ]

    /// Capabilities that must never be implemented or executed.
    public static let blockedActions: [Entry] = [
        Entry(title: "Arbitrary text input", detail: "No typeText API; no character keystreams into editors or pages."),
        Entry(title: "Source modification", detail: "No format, refactor, or editor mutate commands."),
        Entry(title: "Delete", detail: "Delete / Backspace as editing are denied."),
        Entry(title: "Save", detail: "Cmd+S and save commands are not allowlisted."),
        Entry(title: "Paste", detail: "Paste / cut / replace text are forbidden."),
        Entry(title: "Submit", detail: "Return as submit/send and form submission are blocked."),
        Entry(title: "Purchase", detail: "Checkout, payment, and buy controls are skipped by safety filters."),
        Entry(title: "Send", detail: "Send message / email / post actions are denied."),
        Entry(title: "Arbitrary shell commands", detail: "No shell execution from the automation path."),
        Entry(
            title: "Chrome browser UI",
            detail: "Back, Forward, Reload, Close Tab/Window, Omnibox, Profile, Extensions, menus, and window controls are refused."
        ),
        Entry(
            title: "Arbitrary screen-coordinate clicks",
            detail: "Browser clicks require page-content targets validated inside the web area — blind desktop clicking is forbidden."
        ),
    ]

    public static let emergencyStopCopy = """
    Emergency Stop immediately requests the engine to halt and ignores further synthetic navigation. \
    Use the Dashboard, menu bar, Safety Center, or ⌃⌥. while a workflow is running.
    """

    public static let permissionGateCopy = """
    Tiktik Ghora does not bypass macOS permission systems. Accessibility must be granted in System Settings. \
    Apple Events / Automation is not used to drive Target apps. Application access is limited to Targets you configure.
    """
}
