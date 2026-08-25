import Domain
import Foundation

public enum ActionKindLabel {
    /// Content-free case name only (no paths, bundle IDs, or document content).
    public static func label(for action: ActionKind) -> String {
        switch action {
        case .activateApp: return "activateApp"
        case .switchWindow: return "switchWindow"
        case .switchTab: return "switchTab"
        case .scroll: return "scroll"
        case .pageNavigate: return "pageNavigate"
        case .arrowNavigate: return "arrowNavigate"
        case .highlightNavigate: return "highlightNavigate"
        case .contentClick: return "contentClick"
        case .explorerFileSwitch: return "explorerFileSwitch"
        case .inspectWebPage: return "inspectWebPage"
        case .activateWebNavTarget: return "activateWebNavTarget"
        case .browserBack: return "browserBack"
        case .openExistingFile: return "openExistingFile"
        case .wait: return "wait"
        case .returnToPrevious: return "returnToPrevious"
        }
    }
}
