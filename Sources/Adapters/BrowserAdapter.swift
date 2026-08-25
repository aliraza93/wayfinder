import Domain
import Foundation
import Safety

/// Capability snapshot from a browser probe. Never includes page content or AX web-tree data.
public struct BrowserCapabilities: Equatable, Sendable {
    /// When true, `.scroll` uses the scroll-wheel primitive.
    /// When false, degrade to arrow inert keys.
    public var scrollViaWheel: Bool
    /// When true, `.pageNavigate` uses Page/Home/End inert keys.
    /// When false, degrade to capped scroll-wheel deltas.
    public var pageViaKeys: Bool

    public init(scrollViaWheel: Bool, pageViaKeys: Bool) {
        self.scrollViaWheel = scrollViaWheel
        self.pageViaKeys = pageViaKeys
    }

    /// Dependable app-agnostic path: scroll-wheel + inert page keys.
    public static let dependable = BrowserCapabilities(scrollViaWheel: true, pageViaKeys: true)
}

/// Injectable Chrome/browser capability probe. Returns `nil` on failure → adapter degrades.
public protocol BrowserCapabilityProbe: Sendable {
    func probe(target: TargetApp) -> BrowserCapabilities?
}

/// Fixed probe result for unit tests.
public struct FixedBrowserProbe: BrowserCapabilityProbe {
    public var result: BrowserCapabilities?

    public init(result: BrowserCapabilities?) {
        self.result = result
    }

    public func probe(target: TargetApp) -> BrowserCapabilities? {
        _ = target
        return result
    }
}

/// Coarse probe only: known Chrome-family bundle + injected window-exists.
/// Does **not** read Chrome's web AX tree.
public struct ChromeCoarseProbe: BrowserCapabilityProbe {
    private let windowExists: @Sendable () -> Bool

    public init(windowExists: @escaping @Sendable () -> Bool = { true }) {
        self.windowExists = windowExists
    }

    public func probe(target: TargetApp) -> BrowserCapabilities? {
        guard BrowserAdapter.isChromeFamily(bundleID: target.bundleID)
            || target.classification == .browser
        else {
            return nil
        }
        guard windowExists() else {
            return nil
        }
        // Confirmed frontmost-capable browser window — prefer inert primitives.
        return .dependable
    }
}

/// Selected inert primitive for browser navigation (no chords, no tab switching).
public enum BrowserPrimitive: Equatable, Sendable {
    case scrollWheel(deltaY: Int32)
    case inertKey(keyCode: UInt16)
}

/// Chrome navigation adapter: probe at run start, select scroll/page primitives, degrade on failure.
/// Tab cycling uses allowlisted Ctrl+Tab chords via `rewrite` → RealExecutor.
public struct BrowserAdapter: Sendable {
    public static let maxScrollAmount: Int = 100
    public static let pageAsScrollAmount: Int = 80

    public static let chromeFamilyBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev",
    ]

    private let probe: any BrowserCapabilityProbe
    public private(set) var capabilities: BrowserCapabilities
    /// `true` when the last `prepare` fell back because probe returned nil.
    public private(set) var usedDegradedFallback: Bool

    public init(probe: any BrowserCapabilityProbe = ChromeCoarseProbe()) {
        self.probe = probe
        self.capabilities = .dependable
        self.usedDegradedFallback = false
    }

    public static func isChromeFamily(bundleID: String) -> Bool {
        if chromeFamilyBundleIDs.contains(bundleID) { return true }
        // Chromium-based browsers still use inert primitives; treat as browser family by prefix.
        return bundleID.hasPrefix("com.google.Chrome")
    }

    /// Call once at run start. Probe failure **degrades** to `.dependable` — never throws.
    public mutating func prepare(target: TargetApp) {
        if let caps = probe.probe(target: target) {
            capabilities = caps
            usedDegradedFallback = false
        } else {
            capabilities = .dependable
            usedDegradedFallback = true
        }
    }

    /// Maps a domain action to an inert primitive (capped). Unsupported actions → `nil`.
    /// Never returns a tab-switch or mutating primitive.
    public func selectPrimitive(for action: ActionKind) -> BrowserPrimitive? {
        switch action {
        case .scroll(let direction, let amount):
            return selectScroll(direction: direction, amount: amount)
        case .pageNavigate(let move):
            return selectPage(move)
        case .arrowNavigate(let direction, _, _):
            let key: UInt16
            switch direction {
            case .left: key = 123
            case .right: key = 124
            case .down: key = 125
            case .up: key = 126
            }
            guard InertKeyAllowlist.contains(key) else { return nil }
            return .inertKey(keyCode: key)
        case .switchTab, .highlightNavigate, .contentClick, .explorerFileSwitch,
             .activateWebNavTarget, .browserBack:
            return nil
        case .wait, .activateApp, .switchWindow, .openExistingFile, .returnToPrevious, .inspectWebPage:
            return nil
        }
    }

    /// Rewrites to an `ActionKind` the real executor can emit (capped / degraded).
    public func rewrite(_ action: ActionKind) -> ActionKind? {
        switch action {
        case .scroll(let direction, let amount):
            guard direction == .up || direction == .down else { return nil }
            return .scroll(direction: direction, amount: cappedScrollAmount(amount))

        case .pageNavigate(let move):
            if capabilities.pageViaKeys {
                return .pageNavigate(move)
            }
            switch move {
            case .pageUp, .home:
                return .scroll(direction: .up, amount: Self.pageAsScrollAmount)
            case .pageDown, .end:
                return .scroll(direction: .down, amount: Self.pageAsScrollAmount)
            }

        case .arrowNavigate(let direction, let presses, let intervalSeconds):
            return .arrowNavigate(
                direction: direction,
                presses: min(max(1, presses), NavigationLimits.maxArrowPresses),
                intervalSeconds: intervalSeconds
            )

        case .switchTab(let direction):
            return .switchTab(direction: direction)

        case .highlightNavigate(let direction):
            return .highlightNavigate(direction: direction)

        case .contentClick:
            return .contentClick

        case .activateWebNavTarget, .browserBack, .inspectWebPage:
            return action

        case .explorerFileSwitch:
            // Explorer is an editor concern; browsers use tab switch instead.
            return nil

        default:
            return nil
        }
    }

    private func selectScroll(direction: ScrollDirection, amount: Int) -> BrowserPrimitive? {
        let capped = cappedScrollAmount(amount)
        if capabilities.scrollViaWheel {
            let delta = scrollDeltaY(direction: direction, amount: capped)
            guard delta != 0 else { return nil }
            return .scrollWheel(deltaY: delta)
        }
        // Degrade to arrows.
        let key: UInt16?
        switch direction {
        case .up: key = 126
        case .down: key = 125
        case .left: key = 123
        case .right: key = 124
        }
        guard let key, InertKeyAllowlist.contains(key) else { return nil }
        return .inertKey(keyCode: key)
    }

    private func selectPage(_ move: PageMove) -> BrowserPrimitive? {
        if capabilities.pageViaKeys {
            let key = Self.keyCode(for: move)
            guard InertKeyAllowlist.contains(key) else { return nil }
            return .inertKey(keyCode: key)
        }
        // Degrade to capped scroll-wheel.
        let direction: ScrollDirection
        switch move {
        case .pageUp, .home: direction = .up
        case .pageDown, .end: direction = .down
        }
        let delta = scrollDeltaY(direction: direction, amount: Self.pageAsScrollAmount)
        return .scrollWheel(deltaY: delta)
    }

    public static func keyCode(for move: PageMove) -> UInt16 {
        switch move {
        case .pageUp: return 116
        case .pageDown: return 121
        case .home: return 115
        case .end: return 119
        }
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
