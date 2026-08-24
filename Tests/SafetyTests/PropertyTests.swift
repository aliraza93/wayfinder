import Domain
import Safety
import XCTest

final class PropertyTests: XCTestCase {
    func testMutatingOperationNeverAllowedForAnyTargetClass() {
        let mutatingPolicy = SafetyPolicy { action in
            var tags = action.capabilityTags
            tags = CapabilityTags(
                mutatesText: true,
                requiresFocusGuard: tags.requiresFocusGuard,
                verifiable: tags.verifiable,
                primitive: tags.primitive
            )
            return tags
        }

        let actions: [ActionKind] = [
            .activateApp(bundleID: "com.example.app"),
            .switchWindow(direction: .next),
            .scroll(direction: .down, amount: 1),
            .pageNavigate(.pageDown),
            .openExistingFile(path: "/tmp/x"),
            .wait(seconds: 1),
            .returnToPrevious,
        ]
        let classes: [TargetAppClass] = [.browser, .editor, .finder, .generic]

        for action in actions {
            for classification in classes {
                let target = TargetApp(bundleID: "id", classification: classification)
                let decision = mutatingPolicy.validate(action: action, target: target)
                guard case .deny(let reason) = decision else {
                    return XCTFail("mutating \(action) × \(classification) must not allow")
                }
                XCTAssertTrue(reason.contains("mutatesText"))
            }
        }
    }

    func testDeliberatelyAddedMutatingFixtureIsDenied() {
        let fixture = SafetyPolicy { _ in
            CapabilityTags(
                mutatesText: true,
                requiresFocusGuard: true,
                verifiable: false,
                primitive: .inertKey
            )
        }
        let target = TargetApp(bundleID: "com.microsoft.VSCode", classification: .editor)
        let decision = fixture.validate(action: .pageNavigate(.home), target: target)
        XCTAssertEqual(
            decision,
            .deny(reason: "mutatesText is forbidden for all targets (including editor)")
        )
    }

    func testOnlyScrollWheelAndInertKeyAreSyntheticInputPrimitives() {
        // Property: if an action is allowed and would emit synthetic input, its primitive
        // must be scrollWheel or inertKey. appControl/none are non-synthetic paths.
        let policy = SafetyPolicy()
        let actions: [ActionKind] = [
            .scroll(direction: .up, amount: 1),
            .pageNavigate(.end),
            .activateApp(bundleID: "x"),
            .wait(seconds: 0.1),
        ]
        let target = TargetApp(bundleID: "x", classification: .generic)

        for action in actions {
            let tags = action.capabilityTags
            let decision = policy.validate(action: action, target: target)
            XCTAssertEqual(decision, .allow)
            switch tags.primitive {
            case .scrollWheel, .inertKey:
                XCTAssertTrue(true)
            case .appControl:
                XCTAssertTrue(tags.verifiable)
            case .none:
                XCTAssertTrue(true)
            }
        }
    }
}
