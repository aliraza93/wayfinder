import XCTest
@testable import Domain

final class ActionTagTests: XCTestCase {
    /// One sample of every `ActionKind` case (associated values don't change tags).
    private var allActions: [ActionKind] {
        [
            .activateApp(bundleID: "com.example.app"),
            .switchWindow(direction: .next),
            .switchTab(direction: .next),
            .scroll(direction: .down, amount: 3),
            .pageNavigate(.pageDown),
            .arrowNavigate(direction: .down, presses: 1, intervalSeconds: 0.5),
            .highlightNavigate(direction: .down),
            .contentClick,
            .explorerFileSwitch(direction: .next),
            .openExistingFile(path: "/tmp/doc.txt"),
            .wait(seconds: 1.0),
            .returnToPrevious,
        ]
    }

    func testEveryActionHasMutatesTextFalse() {
        for action in allActions {
            XCTAssertFalse(
                action.capabilityTags.mutatesText,
                "\(action) must not mutate text"
            )
        }
    }

    func testTagLookupCoversEveryAction() {
        for action in allActions {
            let tags = action.capabilityTags
            XCTAssertFalse(tags.mutatesText)
            _ = tags.requiresFocusGuard
            _ = tags.verifiable
            _ = tags.primitive
        }
        XCTAssertEqual(allActions.count, 12, "ActionKind cases including explorerFileSwitch")
    }

    func testPrimitivesMatchIntent() {
        XCTAssertEqual(
            ActionKind.activateApp(bundleID: "x").capabilityTags.primitive,
            .appControl
        )
        XCTAssertEqual(
            ActionKind.switchWindow(direction: .previous).capabilityTags.primitive,
            .appControl
        )
        XCTAssertEqual(
            ActionKind.switchTab(direction: .next).capabilityTags.primitive,
            .navigationChord
        )
        XCTAssertEqual(
            ActionKind.scroll(direction: .up, amount: 1).capabilityTags.primitive,
            .scrollWheel
        )
        XCTAssertEqual(
            ActionKind.pageNavigate(.home).capabilityTags.primitive,
            .inertKey
        )
        XCTAssertEqual(
            ActionKind.arrowNavigate(direction: .up, presses: 1, intervalSeconds: 0)
                .capabilityTags.primitive,
            .inertKey
        )
        XCTAssertEqual(
            ActionKind.highlightNavigate(direction: .up).capabilityTags.primitive,
            .navigationChord
        )
        XCTAssertEqual(
            ActionKind.contentClick.capabilityTags.primitive,
            .targetedClick
        )
        XCTAssertEqual(
            ActionKind.explorerFileSwitch(direction: .next).capabilityTags.primitive,
            .targetedClick
        )
        XCTAssertEqual(
            ActionKind.openExistingFile(path: "/a").capabilityTags.primitive,
            .appControl
        )
        XCTAssertEqual(
            ActionKind.wait(seconds: 0.5).capabilityTags.primitive,
            .none
        )
        XCTAssertEqual(
            ActionKind.returnToPrevious.capabilityTags.primitive,
            .appControl
        )
    }

    func testFocusGuardAndVerifiableFlags() {
        XCTAssertFalse(ActionKind.activateApp(bundleID: "x").capabilityTags.requiresFocusGuard)
        XCTAssertTrue(ActionKind.activateApp(bundleID: "x").capabilityTags.verifiable)

        XCTAssertTrue(ActionKind.switchTab(direction: .next).capabilityTags.requiresFocusGuard)
        XCTAssertFalse(ActionKind.switchTab(direction: .next).capabilityTags.verifiable)

        XCTAssertTrue(ActionKind.highlightNavigate(direction: .down).capabilityTags.requiresFocusGuard)
        XCTAssertTrue(ActionKind.contentClick.capabilityTags.requiresFocusGuard)

        XCTAssertTrue(ActionKind.scroll(direction: .down, amount: 1).capabilityTags.requiresFocusGuard)
        XCTAssertFalse(ActionKind.scroll(direction: .down, amount: 1).capabilityTags.verifiable)

        XCTAssertFalse(ActionKind.openExistingFile(path: "/a").capabilityTags.requiresFocusGuard)
        XCTAssertTrue(ActionKind.openExistingFile(path: "/a").capabilityTags.verifiable)

        XCTAssertFalse(ActionKind.wait(seconds: 1).capabilityTags.requiresFocusGuard)
        XCTAssertFalse(ActionKind.wait(seconds: 1).capabilityTags.verifiable)

        XCTAssertFalse(ActionKind.returnToPrevious.capabilityTags.requiresFocusGuard)
        XCTAssertTrue(ActionKind.returnToPrevious.capabilityTags.verifiable)
    }
}
