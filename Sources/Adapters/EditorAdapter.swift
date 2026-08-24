import Domain
import Foundation
import Safety

/// Editor navigation uses only the dependable inert set — never chords or characters.
public struct EditorCapabilities: Equatable, Sendable {
    /// Prefer scroll-wheel for `.scroll`; when false, use arrow inert keys.
    public var scrollViaWheel: Bool

    public init(scrollViaWheel: Bool = true) {
        self.scrollViaWheel = scrollViaWheel
    }

    public static let dependable = EditorCapabilities(scrollViaWheel: true)
}

public protocol EditorCapabilityProbe: Sendable {
    func probe(target: TargetApp) -> EditorCapabilities?
}

public struct FixedEditorProbe: EditorCapabilityProbe {
    public var result: EditorCapabilities?

    public init(result: EditorCapabilities?) {
        self.result = result
    }

    public func probe(target: TargetApp) -> EditorCapabilities? {
        _ = target
        return result
    }
}

/// Coarse editor probe: known editor bundle / `.editor` class + window exists.
/// Does not read document text or editor AX trees.
public struct EditorCoarseProbe: EditorCapabilityProbe {
    private let windowExists: @Sendable () -> Bool

    public init(windowExists: @escaping @Sendable () -> Bool = { true }) {
        self.windowExists = windowExists
    }

    public func probe(target: TargetApp) -> EditorCapabilities? {
        guard EditorAdapter.isEditorFamily(bundleID: target.bundleID)
            || target.classification == .editor
        else {
            return nil
        }
        guard windowExists() else { return nil }
        return .dependable
    }
}

/// Inert primitives only — scroll-wheel or allowlisted arrows/Page/Home/End.
public enum EditorPrimitive: Equatable, Sendable {
    case scrollWheel(deltaY: Int32)
    case inertKey(keyCode: UInt16)
}

/// Read-only editor adapter (VS Code / editor-class): scroll + arrows/Page/Home/End only.
/// No character keys, Return, Delete, paste, save, or Cmd/Ctrl chords — ever.
public struct EditorAdapter: Sendable {
    public static let maxScrollAmount: Int = 100

    public static let editorFamilyBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
    ]

    /// Virtual key codes the adapter may emit (must stay ⊆ `InertKeyAllowlist`).
    public static let allowedKeyCodes: Set<UInt16> = [
        123, 124, 125, 126, // arrows
        116, 121, // page up / down
        115, 119, // home / end
    ]

    private let probe: any EditorCapabilityProbe
    public private(set) var capabilities: EditorCapabilities
    public private(set) var usedDegradedFallback: Bool

    public init(probe: any EditorCapabilityProbe = EditorCoarseProbe()) {
        self.probe = probe
        self.capabilities = .dependable
        self.usedDegradedFallback = false
    }

    public static func isEditorFamily(bundleID: String) -> Bool {
        if editorFamilyBundleIDs.contains(bundleID) { return true }
        // Cursor ships under com.todesktop.* hashes — treat classification as authority there.
        return bundleID.hasPrefix("com.microsoft.VSCode")
            || bundleID.hasPrefix("com.visualstudio.code")
    }

    /// Run-start prepare. Probe failure degrades to `.dependable` (never errors).
    public mutating func prepare(target: TargetApp) {
        if let caps = probe.probe(target: target) {
            capabilities = caps
            usedDegradedFallback = false
        } else {
            capabilities = .dependable
            usedDegradedFallback = true
        }
    }

    /// Selects an inert primitive. Unsupported / non-navigation actions → `nil`.
    public func selectPrimitive(for action: ActionKind) -> EditorPrimitive? {
        switch action {
        case .scroll(let direction, let amount):
            return selectScroll(direction: direction, amount: amount)
        case .pageNavigate(let move):
            return selectPage(move)
        case .wait, .activateApp, .switchWindow, .openExistingFile, .returnToPrevious:
            return nil
        }
    }

    /// Explicit caret move via arrow keys only (read-only).
    public func selectArrow(direction: ScrollDirection) -> EditorPrimitive? {
        let key = Self.arrowKeyCode(direction)
        guard Self.allowedKeyCodes.contains(key), InertKeyAllowlist.contains(key) else {
            return nil
        }
        return .inertKey(keyCode: key)
    }

    /// Rewrites to executor-facing `ActionKind` (capped scroll / page only).
    public func rewrite(_ action: ActionKind) -> ActionKind? {
        switch action {
        case .scroll(let direction, let amount):
            guard direction == .up || direction == .down else { return nil }
            return .scroll(direction: direction, amount: cappedScrollAmount(amount))
        case .pageNavigate(let move):
            return .pageNavigate(move)
        default:
            return nil
        }
    }

    /// Every primitive this adapter can produce for a navigation loop — all inert.
    public func navigationLoopPrimitives(
        scrollAmount: Int = 40,
        includeArrows: Bool = true
    ) -> [EditorPrimitive] {
        var out: [EditorPrimitive] = []
        if let d = selectPrimitive(for: .scroll(direction: .down, amount: scrollAmount)) {
            out.append(d)
        }
        if let u = selectPrimitive(for: .scroll(direction: .up, amount: scrollAmount)) {
            out.append(u)
        }
        for move: PageMove in [.pageDown, .pageUp, .end, .home] {
            if let p = selectPrimitive(for: .pageNavigate(move)) {
                out.append(p)
            }
        }
        if includeArrows {
            for dir: ScrollDirection in [.down, .up, .left, .right] {
                if let a = selectArrow(direction: dir) {
                    out.append(a)
                }
            }
        }
        return out
    }

    /// True iff the primitive is scroll-wheel or an allowlisted inert key (no chords).
    public static func isStrictlyInert(_ primitive: EditorPrimitive) -> Bool {
        switch primitive {
        case .scrollWheel(let delta):
            return delta != 0
        case .inertKey(let keyCode):
            return allowedKeyCodes.contains(keyCode) && InertKeyAllowlist.contains(keyCode)
        }
    }

    public static func arrowKeyCode(_ direction: ScrollDirection) -> UInt16 {
        switch direction {
        case .left: return 123
        case .right: return 124
        case .down: return 125
        case .up: return 126
        }
    }

    public static func pageKeyCode(_ move: PageMove) -> UInt16 {
        switch move {
        case .pageUp: return 116
        case .pageDown: return 121
        case .home: return 115
        case .end: return 119
        }
    }

    private func selectScroll(direction: ScrollDirection, amount: Int) -> EditorPrimitive? {
        let capped = cappedScrollAmount(amount)
        if capabilities.scrollViaWheel {
            let delta = scrollDeltaY(direction: direction, amount: capped)
            guard delta != 0 else { return nil }
            return .scrollWheel(deltaY: delta)
        }
        return selectArrow(direction: direction)
    }

    private func selectPage(_ move: PageMove) -> EditorPrimitive? {
        let key = Self.pageKeyCode(move)
        guard Self.allowedKeyCodes.contains(key), InertKeyAllowlist.contains(key) else {
            return nil
        }
        return .inertKey(keyCode: key)
    }

    private func cappedScrollAmount(_ amount: Int) -> Int {
        min(max(1, amount), Self.maxScrollAmount)
    }

    private func scrollDeltaY(direction: ScrollDirection, amount: Int) -> Int32 {
        let magnitude = Int32(amount)
        switch direction {
        case .up: return magnitude
        case .down: return -magnitude
        case .left, .right: return 0
        }
    }
}
