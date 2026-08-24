import Config
import Domain
import XCTest

final class ValidatorTests: XCTestCase {
    func testAcceptsLegalEditorWorkflow() throws {
        let workflow = Workflow(
            name: "Editor scroll",
            targets: [TargetApp(bundleID: "com.microsoft.VSCode", classification: .editor)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 2,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        XCTAssertNoThrow(try WorkflowValidator().validate(workflow))
    }

    func testRejectsMutatingActionOnEditorTarget() {
        let workflow = Workflow(
            name: "Bad editor",
            targets: [TargetApp(bundleID: "com.microsoft.VSCode", classification: .editor)],
            steps: [
                Step(
                    action: .wait(seconds: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        // No real ActionKind mutates text; inject tags to prove the validator gate.
        let validator = WorkflowValidator { action in
            var tags = action.capabilityTags
            if case .wait = action {
                tags = CapabilityTags(
                    mutatesText: true,
                    requiresFocusGuard: false,
                    verifiable: false,
                    primitive: .none
                )
            }
            return tags
        }

        XCTAssertThrowsError(try validator.validate(workflow)) { error in
            guard case ConfigError.validation(let validation) = error else {
                return XCTFail("expected validation error, got \(error)")
            }
            guard case let .illegalActionForTarget(name, targetClass, reason) = validation else {
                return XCTFail("expected illegalActionForTarget, got \(validation)")
            }
            XCTAssertEqual(name, "Bad editor")
            XCTAssertEqual(targetClass, .editor)
            XCTAssertTrue(reason.contains("mutatesText"))
        }
    }
}
