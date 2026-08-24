import Domain
import Foundation

public enum ActionKindLabel {
    /// Content-free case name only (no paths, bundle IDs, or document content).
    public static func label(for action: ActionKind) -> String {
        switch action {
        case .activateApp: return "activateApp"
        case .switchWindow: return "switchWindow"
        case .scroll: return "scroll"
        case .pageNavigate: return "pageNavigate"
        case .openExistingFile: return "openExistingFile"
        case .wait: return "wait"
        case .returnToPrevious: return "returnToPrevious"
        }
    }
}
