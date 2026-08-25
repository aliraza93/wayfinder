import Domain
import Safety
import XCTest

final class PolicyMatrixTests: XCTestCase {
    private let policy = SafetyPolicy()

    private var allActions: [ActionKind] {
        [
            .activateApp(bundleID: "com.example.app"),
            .switchWindow(direction: .next),
            .switchTab(direction: .next),
            .scroll(direction: .down, amount: 1),
            .pageNavigate(.pageDown),
            .arrowNavigate(direction: .down, presses: 1, intervalSeconds: 0.5),
            .highlightNavigate(direction: .down),
            .contentClick,
            .explorerFileSwitch(direction: .next),
            .inspectWebPage,
            .activateWebNavTarget(identity: "https://example.com", x: 1, y: 2),
            .browserBack,
            .openExistingFile(path: "/tmp/doc.txt"),
            .wait(seconds: 1),
            .returnToPrevious,
        ]
    }

    private var allClasses: [TargetAppClass] {
        [.browser, .editor, .finder, .generic]
    }

    func testMatrixEveryActionAllowedForEveryTargetClass() {
        for action in allActions {
            for classification in allClasses {
                let target = TargetApp(bundleID: "com.example.\(classification)", classification: classification)
                let decision = policy.validate(action: action, target: target)
                XCTAssertEqual(
                    decision,
                    .allow,
                    "expected allow for \(action) × \(classification), got \(decision)"
                )
            }
        }
    }

    func testRequireAllowedThrowsForbiddenActionErrorOnDeny() {
        let mutatingPolicy = SafetyPolicy { _ in
            CapabilityTags(
                mutatesText: true,
                requiresFocusGuard: false,
                verifiable: false,
                primitive: .none
            )
        }
        let target = TargetApp(bundleID: "com.microsoft.VSCode", classification: .editor)
        let action = ActionKind.wait(seconds: 1)

        XCTAssertThrowsError(try mutatingPolicy.requireAllowed(action: action, target: target)) { error in
            guard let forbidden = error as? ForbiddenActionError else {
                return XCTFail("expected ForbiddenActionError, got \(error)")
            }
            XCTAssertEqual(forbidden.action, action)
            XCTAssertEqual(forbidden.target, target)
            XCTAssertTrue(forbidden.reason.contains("mutatesText"))
        }
    }

    func testUnverifiableAppControlDenied() {
        let policy = SafetyPolicy { _ in
            CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: false,
                verifiable: false,
                primitive: .appControl
            )
        }
        let target = TargetApp(bundleID: "com.example.app", classification: .generic)
        let decision = policy.validate(action: .activateApp(bundleID: "x"), target: target)
        XCTAssertEqual(decision, .deny(reason: "appControl actions must be verifiable"))
    }
}
