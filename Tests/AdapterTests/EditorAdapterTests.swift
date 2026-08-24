import Adapters
import Domain
import Safety
import XCTest

final class EditorAdapterTests: XCTestCase {
    func testOnlyEmitsInertScrollAndAllowlistedKeys() {
        var adapter = EditorAdapter(probe: FixedEditorProbe(result: .dependable))
        adapter.prepare(target: editorTarget)

        let primitives = adapter.navigationLoopPrimitives()
        XCTAssertFalse(primitives.isEmpty)
        for p in primitives {
            XCTAssertTrue(EditorAdapter.isStrictlyInert(p), "non-inert primitive: \(p)")
        }

        // Explicit allowlist membership for every key.
        for case .inertKey(let code) in primitives {
            XCTAssertTrue(InertKeyAllowlist.contains(code))
            XCTAssertTrue(EditorAdapter.allowedKeyCodes.contains(code))
        }
    }

    func testScrollAndPageSelection() {
        var adapter = EditorAdapter(probe: FixedEditorProbe(result: .dependable))
        adapter.prepare(target: editorTarget)

        XCTAssertEqual(
            adapter.selectPrimitive(for: .scroll(direction: .down, amount: 40)),
            .scrollWheel(deltaY: -40)
        )
        XCTAssertEqual(
            adapter.selectPrimitive(for: .pageNavigate(.pageUp)),
            .inertKey(keyCode: 116)
        )
        XCTAssertEqual(adapter.selectArrow(direction: .left), .inertKey(keyCode: 123))
        XCTAssertEqual(adapter.selectArrow(direction: .right), .inertKey(keyCode: 124))
    }

    func testScrollViaArrowsWhenWheelDisabled() {
        var adapter = EditorAdapter(
            probe: FixedEditorProbe(result: EditorCapabilities(scrollViaWheel: false))
        )
        adapter.prepare(target: editorTarget)
        XCTAssertEqual(
            adapter.selectPrimitive(for: .scroll(direction: .up, amount: 10)),
            .inertKey(keyCode: 126)
        )
    }

    func testProbeFailureDegradesWithoutError() {
        var adapter = EditorAdapter(probe: FixedEditorProbe(result: nil))
        adapter.prepare(target: editorTarget)
        XCTAssertTrue(adapter.usedDegradedFallback)
        XCTAssertEqual(adapter.capabilities, .dependable)
        XCTAssertNotNil(adapter.selectPrimitive(for: .scroll(direction: .down, amount: 5)))
    }

    func testRejectsNonNavigationActions() {
        var adapter = EditorAdapter(probe: FixedEditorProbe(result: .dependable))
        adapter.prepare(target: editorTarget)
        XCTAssertNil(adapter.selectPrimitive(for: .wait(seconds: 1)))
        XCTAssertNil(adapter.selectPrimitive(for: .activateApp(bundleID: "x")))
        XCTAssertNil(adapter.selectPrimitive(for: .openExistingFile(path: "/tmp/a.swift")))
        XCTAssertNil(adapter.selectPrimitive(for: .returnToPrevious))
        XCTAssertNil(adapter.rewrite(.switchWindow(direction: .next)))
    }

    func testScrollAmountCapped() {
        var adapter = EditorAdapter(probe: FixedEditorProbe(result: .dependable))
        adapter.prepare(target: editorTarget)
        let over = EditorAdapter.maxScrollAmount + 99
        XCTAssertEqual(
            adapter.selectPrimitive(for: .scroll(direction: .down, amount: over)),
            .scrollWheel(deltaY: -Int32(EditorAdapter.maxScrollAmount))
        )
    }

    func testAllowedKeysAreSubsetOfSafetyAllowlist() {
        XCTAssertTrue(EditorAdapter.allowedKeyCodes.isSubset(of: InertKeyAllowlist.keyCodes))
    }

    func testNavigationActionsHaveMutatesTextFalse() {
        let actions: [ActionKind] = [
            .scroll(direction: .down, amount: 1),
            .scroll(direction: .up, amount: 1),
            .pageNavigate(.pageDown),
            .pageNavigate(.pageUp),
            .pageNavigate(.home),
            .pageNavigate(.end),
        ]
        for action in actions {
            XCTAssertFalse(action.capabilityTags.mutatesText)
        }
    }

    func testNoCommandChordKeyCodesInAdapterSet() {
        // Cmd/Ctrl chords are not key codes alone — ensure we never emit Return/Delete/letters.
        let forbidden: Set<UInt16> = [
            36, // Return
            51, // Delete
            0, 1, 2, // A/S/D sample character keys
            8, 9, // C/V paste-ish
        ]
        XCTAssertTrue(EditorAdapter.allowedKeyCodes.isDisjoint(with: forbidden))
    }

    private var editorTarget: TargetApp {
        TargetApp(bundleID: "com.microsoft.VSCode", classification: .editor)
    }
}
