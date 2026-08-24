import Domain
import Foundation

/// Honest product copy — what Waypoint does and will never do.
public enum HonestCopy {
    public static let tagline = "Hands-free navigation. Never touches your work."

    public static let does = """
    Read & Review Workspace is one workflow that walks configured Cursor files and Chrome tabs: \
    focus app → open/select surface → crawl content for a configured dwell → next target — \
    until the session duration ends.
    """

    public static let neverDoes = """
    It never types into your files, presses Return/Delete to edit, pastes, saves, formats, \
    refactors, or runs destructive editor commands. It does not fabricate activity or capture \
    document body content.
    """

    public static let permissionWhy = """
    Accessibility permission lets Waypoint verify the frontmost app and perform read-only \
    navigation (scroll, page/arrow keys, allowlisted tab/explorer navigation, content clicks) — \
    nothing that rewrites your source.
    """

    public static let tabFileLimits = """
    Configure workspace files and Chrome tab labels, dwell min/max (default 30s–3m), and navigation \
    speed. Target order can be sequential or random. Opening files is allowed; editing is not. \
    Chrome tabs use allowlisted Ctrl+Tab (labels are for identity/UI).
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
    case arrowDown
    case arrowUp
    case arrowLeft
    case arrowRight
    case highlightDown
    case highlightUp
    case switchTabNext
    case switchTabPrevious
    case contentClick
    case explorerFileNext
    case explorerFilePrevious
    case wait
    case activateApp
    case returnToPrevious
    case openExistingFile

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .scrollDown: return "Scroll down"
        case .scrollUp: return "Scroll up"
        case .pageDown: return "Page down"
        case .pageUp: return "Page up"
        case .home: return "Home"
        case .end: return "End"
        case .arrowDown: return "Arrow down"
        case .arrowUp: return "Arrow up"
        case .arrowLeft: return "Arrow left"
        case .arrowRight: return "Arrow right"
        case .highlightDown: return "Highlight down"
        case .highlightUp: return "Highlight up"
        case .switchTabNext: return "Next tab"
        case .switchTabPrevious: return "Previous tab"
        case .contentClick: return "Content click"
        case .explorerFileNext: return "Explorer next file"
        case .explorerFilePrevious: return "Explorer previous file"
        case .wait: return "Wait"
        case .activateApp: return "Activate app"
        case .returnToPrevious: return "Return to previous"
        case .openExistingFile: return "Open existing file"
        }
    }

    public func makeAction(activateBundleID: String = "", filePath: String = "") -> ActionKind {
        switch self {
        case .scrollDown: return .scroll(direction: .down, amount: 4)
        case .scrollUp: return .scroll(direction: .up, amount: 4)
        case .pageDown: return .pageNavigate(.pageDown)
        case .pageUp: return .pageNavigate(.pageUp)
        case .home: return .pageNavigate(.home)
        case .end: return .pageNavigate(.end)
        case .arrowDown:
            return .arrowNavigate(direction: .down, presses: 1, intervalSeconds: 0.05)
        case .arrowUp:
            return .arrowNavigate(direction: .up, presses: 1, intervalSeconds: 0.05)
        case .arrowLeft:
            return .arrowNavigate(direction: .left, presses: 1, intervalSeconds: 0.05)
        case .arrowRight:
            return .arrowNavigate(direction: .right, presses: 1, intervalSeconds: 0.05)
        case .highlightDown: return .highlightNavigate(direction: .down)
        case .highlightUp: return .highlightNavigate(direction: .up)
        case .switchTabNext: return .switchTab(direction: .next)
        case .switchTabPrevious: return .switchTab(direction: .previous)
        case .contentClick: return .contentClick
        case .explorerFileNext: return .explorerFileSwitch(direction: .next)
        case .explorerFilePrevious: return .explorerFileSwitch(direction: .previous)
        case .wait: return .wait(seconds: 0.25)
        case .activateApp: return .activateApp(bundleID: activateBundleID)
        case .returnToPrevious: return .returnToPrevious
        case .openExistingFile: return .openExistingFile(path: filePath)
        }
    }

    /// Same human titles as the palette — used for step rows in the editor.
    public static func humanTitle(for action: ActionKind) -> String {
        switch action {
        case .scroll(let direction, let amount):
            switch direction {
            case .down: return "\(ActionPaletteItem.scrollDown.title) (\(amount))"
            case .up: return "\(ActionPaletteItem.scrollUp.title) (\(amount))"
            case .left, .right:
                return "Scroll \(direction) (\(amount))"
            }
        case .pageNavigate(let mode):
            switch mode {
            case .pageDown: return ActionPaletteItem.pageDown.title
            case .pageUp: return ActionPaletteItem.pageUp.title
            case .home: return ActionPaletteItem.home.title
            case .end: return ActionPaletteItem.end.title
            }
        case .arrowNavigate(let direction, let presses, let interval):
            let base: String
            switch direction {
            case .down: base = ActionPaletteItem.arrowDown.title
            case .up: base = ActionPaletteItem.arrowUp.title
            case .left: base = ActionPaletteItem.arrowLeft.title
            case .right: base = ActionPaletteItem.arrowRight.title
            }
            if presses > 1 || interval > 0 {
                return "\(base) ×\(presses) @\(String(format: "%.1f", interval))s"
            }
            return base
        case .highlightNavigate(let direction):
            switch direction {
            case .down: return ActionPaletteItem.highlightDown.title
            case .up: return ActionPaletteItem.highlightUp.title
            case .left: return "Highlight left"
            case .right: return "Highlight right"
            }
        case .switchTab(let direction):
            switch direction {
            case .next: return ActionPaletteItem.switchTabNext.title
            case .previous: return ActionPaletteItem.switchTabPrevious.title
            }
        case .contentClick:
            return ActionPaletteItem.contentClick.title
        case .explorerFileSwitch(let direction):
            switch direction {
            case .next: return ActionPaletteItem.explorerFileNext.title
            case .previous: return ActionPaletteItem.explorerFilePrevious.title
            }
        case .wait(let seconds):
            return "\(ActionPaletteItem.wait.title) (\(String(format: "%.1f", seconds))s)"
        case .activateApp:
            return ActionPaletteItem.activateApp.title
        case .returnToPrevious:
            return ActionPaletteItem.returnToPrevious.title
        case .switchWindow:
            return "Switch window"
        case .openExistingFile(let path):
            let name = (path as NSString).lastPathComponent
            return name.isEmpty ? ActionPaletteItem.openExistingFile.title : "Open \(name)"
        }
    }
}
