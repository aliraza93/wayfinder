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

    public init(
        synth: EventSynth,
        activator: AppActivator = AppActivator(),
        fileOpener: ExistingFileOpener = ExistingFileOpener(),
        clickResolver: FocusedContentClickResolver = FocusedContentClickResolver()
    ) {
        self.synth = synth
        self.activator = activator
        self.fileOpener = fileOpener
        self.clickResolver = clickResolver
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
            guard let point = clickResolver.resolvePoint(bundleID: target.bundleID, randomize: true),
                  let primitive = ClickPrimitive.make(x: point.x, y: point.y)
            else {
                throw ActionError("could not resolve content click target")
            }
            try await synth.emitClick(primitive, action: action, target: target)

        case .explorerFileSwitch(let direction):
            // Ctrl+Tab among already-open project files is the reliable path in Cursor.
            // Explorer tree walk is a secondary path when we intentionally branch there.
            let useExplorer = Double.random(in: 0...1) < 0.35
            if !useExplorer {
                guard let tab = NavigationChordPrimitive.tabSwitch(direction: direction) else {
                    throw ActionError("tab switch chord not allowlisted")
                }
                try await synth.emitNavigationChord(tab, action: action, target: target)
                try await Task.sleep(nanoseconds: 300_000_000)
                break
            }

            guard let focus = NavigationChordPrimitive.make(NavigationChordAllowlist.focusExplorer) else {
                throw ActionError("focus explorer chord not allowlisted")
            }
            try await synth.emitNavigationChord(focus, action: action, target: target)
            try await Task.sleep(nanoseconds: 300_000_000)

            let arrowCode: UInt16 = (direction == .next) ? 125 : 126
            let hops = Int.random(in: 1...5)
            for _ in 0..<hops {
                guard let arrow = InertKeyPrimitive.make(keyCode: arrowCode) else {
                    throw ActionError("invalid explorer arrow")
                }
                try await synth.emitInertKey(arrow, action: action, target: target)
                try await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.1...0.28) * 1_000_000_000))
            }

            guard let open = NavigationChordPrimitive.make(NavigationChordAllowlist.explorerOpenSelection) else {
                throw ActionError("explorer open chord not allowlisted")
            }
            try await synth.emitNavigationChord(open, action: action, target: target)
            try await Task.sleep(nanoseconds: 350_000_000)

            // Click into the editor content so later arrows don't stay trapped in the tree.
            if let point = clickResolver.resolvePoint(bundleID: target.bundleID, randomize: false),
               let click = ClickPrimitive.make(x: point.x, y: point.y)
            {
                try await synth.emitClick(click, action: .contentClick, target: target)
            }

        case .wait:
            return

        case .activateApp(let bundleID):
            let id = bundleID.isEmpty ? target.bundleID : bundleID
            let ok = await activator.activateOrLaunch(bundleID: id)
            guard ok else {
                throw ActionError("could not activate or launch \(id)")
            }

        case .openExistingFile(let path):
            try await fileOpener.open(path: path, withBundleID: target.bundleID)
            _ = await activator.activateOrLaunch(bundleID: target.bundleID, timeoutSeconds: 3.0)

        case .returnToPrevious:
            throw ActionError("returnToPrevious must be rewritten by the engine")

        case .switchWindow:
            throw ActionError("unsupported action for RealExecutor")
        }
    }
}
