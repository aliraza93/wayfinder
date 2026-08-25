import Domain
import Foundation
import Safety

/// Constructible navigation-chord primitive — allowlist only.
public struct NavigationChordPrimitive: Equatable, Sendable {
    public var chord: NavigationChord

    private init(chord: NavigationChord) {
        self.chord = chord
    }

    public static func make(_ chord: NavigationChord) -> NavigationChordPrimitive? {
        guard NavigationChordAllowlist.contains(chord) else { return nil }
        return NavigationChordPrimitive(chord: chord)
    }

    public static func tabSwitch(direction: WindowDirection) -> NavigationChordPrimitive? {
        make(NavigationChordAllowlist.tabSwitch(direction: direction))
    }

    public static func highlight(direction: ArrowDirection) -> NavigationChordPrimitive? {
        make(NavigationChordAllowlist.highlight(direction: direction))
    }

    public static func browserBack() -> NavigationChordPrimitive? {
        make(NavigationChordAllowlist.browserBack)
    }
}
