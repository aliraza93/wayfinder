import AppControl
import CoreEngine
import Domain
import Foundation
import InputSynthesis
import Safety
import WaypointAccessibility

public enum RealExecutorError: Error, Equatable, Sendable {
    case unsupportedAction
    case invalidScroll
    case invalidInertKey
    case activateFailed(String)
    case returnStackEmpty
}

/// Real `ActionExecutor`: Safety → (FocusGuard for input) → InputSynthesis / AppControl.
public actor RealExecutor: ActionExecutor {
    private let synth: EventSynth
    private let activator: AppActivator
    private let fileOpener: ExistingFileOpener
    private let clickResolver: FocusedContentClickResolver
    private let explorerResolver: ExplorerSidebarClickResolver
    private var explorerHop: Int = 0

    public init(
        synth: EventSynth,
        activator: AppActivator = AppActivator(),
        fileOpener: ExistingFileOpener = ExistingFileOpener(),
        clickResolver: FocusedContentClickResolver = FocusedContentClickResolver(),
        explorerResolver: ExplorerSidebarClickResolver = ExplorerSidebarClickResolver()
    ) {
        self.synth = synth
        self.activator = activator
        self.fileOpener = fileOpener
        self.clickResolver = clickResolver
        self.explorerResolver = explorerResolver
    }

    public func execute(action: ActionKind, target: TargetApp) async throws {
        switch action {
        case .scroll(let direction, let amount):
            let capped = min(max(1, amount), NavigationLimits.maxScrollAmount)
            let scaled = min(capped * 12, NavigationLimits.maxScrollAmount * 12)
            let delta = ScrollAction.deltaY(direction: direction, amount: scaled)
            guard let primitive = ScrollPrimitive.make(deltaY: delta) else {
                throw ActionError("invalid scroll delta")
            }
            try await synth.emitScroll(primitive, action: action, target: target)

        case .pageNavigate(let move):
            let keyCode: UInt16
            switch move {
            case .pageUp: keyCode = 116
            case .pageDown: keyCode = 121
            case .home: keyCode = 115
            case .end: keyCode = 119
            }
            guard let primitive = InertKeyPrimitive.make(keyCode: keyCode) else {
                throw ActionError("invalid inert key for pageNavigate")
            }
            try await synth.emitInertKey(primitive, action: action, target: target)

        case .arrowNavigate(let direction, _, _):
            let keyCode: UInt16
            switch direction {
            case .left: keyCode = 123
            case .right: keyCode = 124
            case .down: keyCode = 125
            case .up: keyCode = 126
            }
            guard let primitive = InertKeyPrimitive.make(keyCode: keyCode) else {
                throw ActionError("invalid inert key for arrowNavigate")
            }
            try await synth.emitInertKey(primitive, action: action, target: target)

        case .switchTab(let direction):
            guard let primitive = NavigationChordPrimitive.tabSwitch(direction: direction) else {
                throw ActionError("tab switch chord not allowlisted")
            }
            try await synth.emitNavigationChord(primitive, action: action, target: target)

        case .highlightNavigate(let direction):
            guard let primitive = NavigationChordPrimitive.highlight(direction: direction) else {
                throw ActionError("highlight chord not allowlisted")
            }
            try await synth.emitNavigationChord(primitive, action: action, target: target)

        case .contentClick:
            // Prefer upper/mid editor (not bottom). Double-click selects a word/line highlight.
            guard let point = clickResolver.resolvePoint(
                bundleID: target.bundleID,
                randomize: true,
                verticalBand: .upperMid
            ),
                let primitive = ClickPrimitive.make(x: point.x, y: point.y)
            else {
                throw ActionError("could not resolve content click target")
            }
            try await synth.emitDoubleClick(primitive, action: action, target: target)

        case .activateWebNavTarget(_, let x, let y):
            guard let primitive = ClickPrimitive.make(x: CGFloat(x), y: CGFloat(y)) else {
                throw ActionError("invalid web nav click point")
            }
            // Single click follows links; double-click is for editor highlight only.
            try await synth.emitClick(primitive, action: action, target: target)
            try await Task.sleep(nanoseconds: 350_000_000)

        case .browserBack:
            guard let primitive = NavigationChordPrimitive.browserBack() else {
                throw ActionError("browser back chord not allowlisted")
            }
            try await synth.emitNavigationChord(primitive, action: action, target: target)
            try await Task.sleep(nanoseconds: 400_000_000)

        case .inspectWebPage:
            // Engine refreshes the snapshot via WebPageInspectionSource; no input.
            return

        case .explorerFileSwitch(let direction):
            // Open another project file from the LEFT SIDEBAR only.
            // NEVER press Return — if focus is still in the editor, Return mutates source.
            try await openFileFromExplorerSidebar(direction: direction, target: target, action: action)

        case .wait:
            return

        case .activateApp(let bundleID):
            let id = bundleID.isEmpty ? target.bundleID : bundleID
            var ok = false
            for _ in 0..<3 {
                ok = await activator.activateOrLaunch(bundleID: id, timeoutSeconds: 6.0)
                if ok { break }
                try await Task.sleep(nanoseconds: 400_000_000)
            }
            guard ok else {
                throw ActionError("could not activate or launch \(id)")
            }
            try await Task.sleep(nanoseconds: 500_000_000)

        case .openExistingFile(let path):
            try await fileOpener.open(path: path, withBundleID: target.bundleID)
            _ = await activator.activateOrLaunch(bundleID: target.bundleID, timeoutSeconds: 3.0)
            // Start at top of the file — do not jump to bottom.
            if let home = InertKeyPrimitive.make(keyCode: 115) {
                try await synth.emitInertKey(home, action: .pageNavigate(.home), target: target)
            }

        case .returnToPrevious:
            throw ActionError("returnToPrevious must be rewritten by the engine")

        case .switchWindow:
            throw ActionError("unsupported action for RealExecutor")
        }
    }

    /// Double-click a file row in the sidebar, then land at top/mid of the editor (no End).
    private func openFileFromExplorerSidebar(
        direction: WindowDirection,
        target: TargetApp,
        action: ActionKind
    ) async throws {
        guard target.classification == .editor else {
            throw ActionError("explorer file switch is editor-only")
        }

        try await synth.emitModifierRelease(action: action, target: target)
        try await Task.sleep(nanoseconds: 80_000_000)

        explorerHop += 1
        guard let point = explorerResolver.resolveFileRowClick(
            bundleID: target.bundleID,
            direction: direction,
            hop: explorerHop
        ),
            let click = ClickPrimitive.make(x: point.x, y: point.y)
        else {
            throw ActionError("could not resolve explorer sidebar click")
        }

        try await synth.emitModifierRelease(action: action, target: target)
        // Double-click opens the file reliably without Return.
        try await synth.emitDoubleClick(click, action: action, target: target)
        try await Task.sleep(nanoseconds: 400_000_000)

        try await synth.emitModifierRelease(action: action, target: target)
        // Go to top, then double-click mid/upper content so a line/word is highlighted.
        if let home = InertKeyPrimitive.make(keyCode: 115) {
            try await synth.emitInertKey(home, action: .pageNavigate(.home), target: target)
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if let content = clickResolver.resolvePoint(
            bundleID: target.bundleID,
            randomize: true,
            verticalBand: .upperMid
        ),
            let contentClick = ClickPrimitive.make(x: content.x, y: content.y)
        {
            try await synth.emitDoubleClick(contentClick, action: .contentClick, target: target)
        }
    }
}
