import Domain
import Foundation
import Safety

/// Kind of navigation adapter selected for a target class.
public enum ResolvedAdapter: Equatable, Sendable, CustomStringConvertible {
    case browser
    case editor
    case generic

    public var description: String {
        switch self {
        case .browser: return "browser"
        case .editor: return "editor"
        case .generic: return "generic"
        }
    }
}

/// Pure target-class → adapter resolution (testable, no AppKit).
public enum AdapterResolver {
    /// Finder and generic fall back to `GenericAdapter`. Every v1 class resolves.
    public static func resolve(_ classification: TargetAppClass) -> ResolvedAdapter {
        switch classification {
        case .browser: return .browser
        case .editor: return .editor
        case .finder, .generic: return .generic
        }
    }

    public static func resolve(_ target: TargetApp) -> ResolvedAdapter {
        resolve(target.classification)
    }
}

/// Inert-only adapter for finder / generic targets (scroll-wheel + page keys).
public struct GenericAdapter: Sendable {
    public static let maxScrollAmount: Int = 100

    public init() {}

    public func prepare(target: TargetApp) {
        _ = target
        // No probe surface — always dependable inert primitives.
    }

    public func selectPrimitive(for action: ActionKind) -> BrowserPrimitive? {
        // Reuse browser primitive shape (scroll wheel / inert key) without Chrome probing.
        switch action {
        case .scroll(let direction, let amount):
            let capped = min(max(1, amount), Self.maxScrollAmount)
            let magnitude = Int32(capped)
            switch direction {
            case .up: return .scrollWheel(deltaY: magnitude)
            case .down: return .scrollWheel(deltaY: -magnitude)
            case .left, .right: return nil
            }
        case .pageNavigate(let move):
            let key: UInt16
            switch move {
            case .pageUp: key = 116
            case .pageDown: key = 121
            case .home: key = 115
            case .end: key = 119
            }
            guard InertKeyAllowlist.contains(key) else { return nil }
            return .inertKey(keyCode: key)
        default:
            return nil
        }
    }

    public func rewrite(_ action: ActionKind) -> ActionKind? {
        switch action {
        case .scroll(let direction, let amount):
            guard direction == .up || direction == .down else { return nil }
            return .scroll(direction: direction, amount: min(max(1, amount), Self.maxScrollAmount))
        case .pageNavigate(let move):
            return .pageNavigate(move)
        default:
            return nil
        }
    }
}

/// Maps domain actions through the adapter chosen for a target.
public enum AdapterActionMapper {
    public static func rewrite(
        _ action: ActionKind,
        target: TargetApp,
        adapter: ResolvedAdapter
    ) -> ActionKind {
        switch action {
        case .wait:
            return action
        default:
            break
        }

        switch adapter {
        case .browser:
            var browser = BrowserAdapter(probe: FixedBrowserProbe(result: .dependable))
            browser.prepare(target: target)
            return browser.rewrite(action) ?? action
        case .editor:
            var editor = EditorAdapter(probe: FixedEditorProbe(result: .dependable))
            editor.prepare(target: target)
            return editor.rewrite(action) ?? action
        case .generic:
            let generic = GenericAdapter()
            generic.prepare(target: target)
            return generic.rewrite(action) ?? action
        }
    }
}
