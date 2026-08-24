import Domain
import Foundation

/// Honest product copy — what Waypoint does and will never do.
public enum HonestCopy {
    public static let tagline = "Hands-free navigation. Never touches your work."

    public static let does = """
    Waypoint runs read-only navigation workflows you define: switch apps/windows, \
    scroll, page, wait, and return. It only moves through already-open apps.
    """

    public static let neverDoes = """
    It never types characters, presses Return/Delete, pastes, saves, runs editor \
    commands, or uses Cmd/Ctrl chords. It does not fabricate activity or capture \
    document content.
    """

    public static let permissionWhy = """
    Accessibility permission lets Waypoint verify the frontmost app and send \
    inert scroll/page keys — nothing that can edit your files.
    """
}

/// Palette entries the editor may offer. Every entry has `mutatesText == false`.
public enum ActionPaletteItem: String, CaseIterable, Sendable, Identifiable {
    case scrollDown
    case scrollUp
    case pageDown
    case pageUp
    case home
    case end
    case wait
    case activateApp
    case returnToPrevious

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .scrollDown: return "Scroll down"
        case .scrollUp: return "Scroll up"
        case .pageDown: return "Page down"
        case .pageUp: return "Page up"
        case .home: return "Home"
        case .end: return "End"
        case .wait: return "Wait"
        case .activateApp: return "Activate app"
        case .returnToPrevious: return "Return to previous"
        }
    }

    public func makeAction(activateBundleID: String = "") -> ActionKind {
        switch self {
        case .scrollDown: return .scroll(direction: .down, amount: 40)
        case .scrollUp: return .scroll(direction: .up, amount: 40)
        case .pageDown: return .pageNavigate(.pageDown)
        case .pageUp: return .pageNavigate(.pageUp)
        case .home: return .pageNavigate(.home)
        case .end: return .pageNavigate(.end)
        case .wait: return .wait(seconds: 0.5)
        case .activateApp: return .activateApp(bundleID: activateBundleID)
        case .returnToPrevious: return .returnToPrevious
        }
    }

    /// Same human titles as the palette — used for step rows in the editor.
    public static func humanTitle(for action: ActionKind) -> String {
        switch action {
        case .scroll(let direction, _):
            switch direction {
            case .down: return ActionPaletteItem.scrollDown.title
            case .up: return ActionPaletteItem.scrollUp.title
            case .left, .right:
                return "Scroll \(direction)"
            }
        case .pageNavigate(let mode):
            switch mode {
            case .pageDown: return ActionPaletteItem.pageDown.title
            case .pageUp: return ActionPaletteItem.pageUp.title
            case .home: return ActionPaletteItem.home.title
            case .end: return ActionPaletteItem.end.title
            }
        case .wait:
            return ActionPaletteItem.wait.title
        case .activateApp:
            return ActionPaletteItem.activateApp.title
        case .returnToPrevious:
            return ActionPaletteItem.returnToPrevious.title
        case .switchWindow:
            return "Switch window"
        case .openExistingFile:
            return "Open existing file"
        }
    }
}
