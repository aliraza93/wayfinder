import CoreEngine
import Domain
import XCTest

final class NavigationExpanderTests: XCTestCase {
    func testArrowBlocksStayIntactByDefault() {
        let steps = [
            Step(
                action: .arrowNavigate(direction: .down, presses: 3, intervalSeconds: 2),
                timeoutSeconds: 2,
                retryPolicy: RetryPolicy(maxRetries: 0),
                onError: .abort
            ),
        ]
        let expanded = NavigationStepExpander.expand(steps)
        XCTAssertEqual(expanded.count, 1)
        XCTAssertEqual(
            expanded[0].action,
            .arrowNavigate(direction: .down, presses: 3, intervalSeconds: 2)
        )
    }

    func testArrowNavigateCanExpandPressesWithIntervals() {
        let steps = [
            Step(
                action: .arrowNavigate(direction: .down, presses: 3, intervalSeconds: 2),
                timeoutSeconds: 2,
                retryPolicy: RetryPolicy(maxRetries: 0),
                onError: .abort
            ),
        ]
        let expanded = NavigationStepExpander.expand(steps, keepArrowBlocks: false)
        XCTAssertEqual(expanded.count, 5) // arrow, wait, arrow, wait, arrow
        XCTAssertEqual(expanded[0].action, .arrowNavigate(direction: .down, presses: 1, intervalSeconds: 0))
        XCTAssertEqual(expanded[1].action, .wait(seconds: 2))
    }

    func testDurationIgnoresLowIterationCeiling() {
        let loop = LoopSettings(
            enabled: true,
            maxIterations: 1,
            maxDurationSeconds: 60,
            untilStopped: false
        )
        XCTAssertEqual(
            WorkflowEngine.resolvedMaxIterations(for: loop),
            NavigationLimits.absoluteMaxIterations
        )
    }

    func testUntilStoppedUsesAbsoluteCeiling() {
        let loop = LoopSettings(enabled: true, maxIterations: 2, untilStopped: true)
        XCTAssertEqual(
            WorkflowEngine.resolvedMaxIterations(for: loop),
            NavigationLimits.absoluteMaxIterations
        )
    }
}
