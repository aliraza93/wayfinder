import XCTest
@testable import Domain

final class ActionTagTests: XCTestCase {
    /// One sample of every `ActionKind` case (associated values don't change tags).
    private var allActions: [ActionKind] {
        [
            .activateApp(bundleID: "com.example.app"),
            .switchWindow(direction: .next),
            .scroll(direction: .down, amount: 3),
            .pageNavigate(.pageDown),
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
        // Calling capabilityTags exercises the exhaustive switch; missing cases won't compile.
        for action in allActions {
            let tags = action.capabilityTags
            XCTAssertFalse(tags.mutatesText)
            _ = tags.requiresFocusGuard
            _ = tags.verifiable
            _ = tags.primitive
        }
        XCTAssertEqual(allActions.count, 7, "v1 ActionKind has exactly seven cases")
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
            ActionKind.scroll(direction: .up, amount: 1).capabilityTags.primitive,
            .scrollWheel
        )
        XCTAssertEqual(
            ActionKind.pageNavigate(.home).capabilityTags.primitive,
            .inertKey
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

        XCTAssertTrue(ActionKind.switchWindow(direction: .next).capabilityTags.requiresFocusGuard)
        XCTAssertTrue(ActionKind.switchWindow(direction: .next).capabilityTags.verifiable)

        XCTAssertTrue(ActionKind.scroll(direction: .down, amount: 1).capabilityTags.requiresFocusGuard)
        XCTAssertFalse(ActionKind.scroll(direction: .down, amount: 1).capabilityTags.verifiable)

        XCTAssertTrue(ActionKind.pageNavigate(.pageUp).capabilityTags.requiresFocusGuard)
        XCTAssertFalse(ActionKind.pageNavigate(.pageUp).capabilityTags.verifiable)

        XCTAssertFalse(ActionKind.openExistingFile(path: "/a").capabilityTags.requiresFocusGuard)
        XCTAssertTrue(ActionKind.openExistingFile(path: "/a").capabilityTags.verifiable)

        XCTAssertFalse(ActionKind.wait(seconds: 1).capabilityTags.requiresFocusGuard)
        XCTAssertFalse(ActionKind.wait(seconds: 1).capabilityTags.verifiable)

        XCTAssertFalse(ActionKind.returnToPrevious.capabilityTags.requiresFocusGuard)
        XCTAssertTrue(ActionKind.returnToPrevious.capabilityTags.verifiable)
    }
}
