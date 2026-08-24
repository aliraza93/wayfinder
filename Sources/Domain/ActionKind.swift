/// Closed set of actions Waypoint can perform. No text/paste/delete/save cases exist.
public enum ActionKind: Equatable, Sendable {
    case activateApp(bundleID: String)
    case switchWindow(direction: WindowDirection)
    case scroll(direction: ScrollDirection, amount: Int)
    case pageNavigate(PageMove)
    case openExistingFile(path: String)
    case wait(seconds: Double)
    case returnToPrevious
}

public enum WindowDirection: Equatable, Sendable {
    case next
    case previous
}

public enum ScrollDirection: Equatable, Sendable {
    case up
    case down
    case left
    case right
}

/// Inert document paging keys only — never character or chorded shortcuts.
public enum PageMove: Equatable, Sendable {
    case pageUp
    case pageDown
    case home
    case end
}
