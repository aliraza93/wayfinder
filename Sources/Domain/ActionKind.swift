/// Closed set of actions Waypoint can perform. No text/paste/delete/save cases exist.
public enum ActionKind: Equatable, Sendable {
    case activateApp(bundleID: String)
    case switchWindow(direction: WindowDirection)
    /// Cycle among already-open tabs (Ctrl+Tab / Ctrl+Shift+Tab via adapter chord).
    case switchTab(direction: WindowDirection)
    case scroll(direction: ScrollDirection, amount: Int)
    case pageNavigate(PageMove)
    /// Allowlisted arrow keys only. `presses` / `intervalSeconds` are expanded before run.
    case arrowNavigate(direction: ArrowDirection, presses: Int, intervalSeconds: Double)
    /// Shift+arrow selection motion — highlights lines/ranges without editing text.
    case highlightNavigate(direction: ArrowDirection)
    /// Adapter-resolved click inside the focused target’s content area.
    case contentClick
    /// Focus project explorer, move selection, open existing file (no path typing).
    case explorerFileSwitch(direction: WindowDirection)
    case openExistingFile(path: String)
    /// Best-effort refresh of accessible page structure (no synthetic input).
    case inspectWebPage
    /// Targeted click on a safety-filtered navigation target (screen coords from inspector).
    case activateWebNavTarget(identity: String, x: Double, y: Double)
    /// Browser history back (allowlisted Cmd+[).
    case browserBack
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

/// Inert arrow navigation only — never character keys.
public enum ArrowDirection: Equatable, Sendable {
    case up
    case down
    case left
    case right
}
