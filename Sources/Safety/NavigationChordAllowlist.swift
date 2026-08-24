import Domain
import Foundation

/// Allowlisted navigation chords (tabs, highlight, explorer focus/open).
/// Separate from `InertKeyAllowlist` — modifiers are never permitted on inert keys.
public struct NavigationChord: Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    public var control: Bool
    public var shift: Bool
    public var option: Bool
    public var command: Bool

    public init(
        keyCode: UInt16,
        control: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        command: Bool = false
    ) {
        self.keyCode = keyCode
        self.control = control
        self.shift = shift
        self.option = option
        self.command = command
    }
}

public enum NavigationChordAllowlist: Sendable {
    public static let tabKeyCode: UInt16 = 48
    /// Virtual key `E` — used with Cmd+Shift for Focus on Explorer View (VS Code / Cursor).
    public static let eKeyCode: UInt16 = 14
    /// Return — only allowlisted for explorer “open selection” (never generic typing).
    public static let returnKeyCode: UInt16 = 36

    public static let allowed: Set<NavigationChord> = [
        NavigationChord(keyCode: tabKeyCode, control: true, shift: false),
        NavigationChord(keyCode: tabKeyCode, control: true, shift: true),
        NavigationChord(keyCode: 126, shift: true),
        NavigationChord(keyCode: 125, shift: true),
        NavigationChord(keyCode: 123, shift: true),
        NavigationChord(keyCode: 124, shift: true),
        // Focus Explorer (Cmd+Shift+E)
        NavigationChord(keyCode: eKeyCode, shift: true, command: true),
        // Open explorer selection (Return) — only emitted by explorerFileSwitch
        NavigationChord(keyCode: returnKeyCode),
    ]

    public static func contains(_ chord: NavigationChord) -> Bool {
        allowed.contains(chord)
    }

    public static func tabSwitch(direction: WindowDirection) -> NavigationChord {
        switch direction {
        case .next:
            return NavigationChord(keyCode: tabKeyCode, control: true, shift: false)
        case .previous:
            return NavigationChord(keyCode: tabKeyCode, control: true, shift: true)
        }
    }

    public static func highlight(direction: ArrowDirection) -> NavigationChord {
        let key: UInt16
        switch direction {
        case .left: key = 123
        case .right: key = 124
        case .down: key = 125
        case .up: key = 126
        }
        return NavigationChord(keyCode: key, shift: true)
    }

    public static var focusExplorer: NavigationChord {
        NavigationChord(keyCode: eKeyCode, shift: true, command: true)
    }

    public static var explorerOpenSelection: NavigationChord {
        NavigationChord(keyCode: returnKeyCode)
    }
}
