import Domain
import Safety
import XCTest

final class NavigationChordAllowlistTests: XCTestCase {
    func testTabSwitchChordsAreAllowlisted() {
        let next = NavigationChordAllowlist.tabSwitch(direction: .next)
        let prev = NavigationChordAllowlist.tabSwitch(direction: .previous)
        XCTAssertTrue(NavigationChordAllowlist.contains(next))
        XCTAssertTrue(NavigationChordAllowlist.contains(prev))
        XCTAssertTrue(next.control)
        XCTAssertFalse(next.shift)
        XCTAssertTrue(prev.control)
        XCTAssertTrue(prev.shift)
    }

    func testHighlightChordsAreAllowlisted() {
        for direction: ArrowDirection in [.up, .down, .left, .right] {
            let chord = NavigationChordAllowlist.highlight(direction: direction)
            XCTAssertTrue(NavigationChordAllowlist.contains(chord))
            XCTAssertTrue(chord.shift)
            XCTAssertFalse(chord.control)
            XCTAssertFalse(chord.command)
        }
    }

    func testArbitraryChordsDenied() {
        // Cmd+S must never be constructible via allowlist.
        let save = NavigationChord(keyCode: 1, command: true)
        XCTAssertFalse(NavigationChordAllowlist.contains(save))
        // Return with shift
        let ret = NavigationChord(keyCode: 36, shift: true)
        XCTAssertFalse(NavigationChordAllowlist.contains(ret))
    }

    func testExplorerFocusAndOpenAreAllowlisted() {
        XCTAssertTrue(NavigationChordAllowlist.contains(NavigationChordAllowlist.focusExplorer))
        XCTAssertTrue(NavigationChordAllowlist.contains(NavigationChordAllowlist.explorerOpenSelection))
        XCTAssertTrue(NavigationChordAllowlist.focusExplorer.command)
        XCTAssertTrue(NavigationChordAllowlist.focusExplorer.shift)
        XCTAssertEqual(NavigationChordAllowlist.explorerOpenSelection.keyCode, 36)
    }
}
