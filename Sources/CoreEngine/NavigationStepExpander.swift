import Domain
import Foundation

/// Expands compact navigation actions into single-emit steps + waits (FakeClock-friendly).
/// Arrow multi-press stays as one step when `keepArrowBlocks` is true so shuffle can
/// reorder whole blocks (e.g. “Arrow up ×20” vs “Arrow left ×10”).
public enum NavigationStepExpander {
    public static func expand(_ steps: [Step], keepArrowBlocks: Bool = true) -> [Step] {
        var out: [Step] = []
        for step in steps {
            switch step.action {
            case .arrowNavigate(let direction, let presses, let intervalSeconds):
                if keepArrowBlocks {
                    out.append(
                        Step(
                            action: .arrowNavigate(
                                direction: direction,
                                presses: min(max(1, presses), NavigationLimits.maxArrowPresses),
                                intervalSeconds: clampInterval(intervalSeconds)
                            ),
                            timeoutSeconds: step.timeoutSeconds,
                            retryPolicy: step.retryPolicy,
                            onError: step.onError
                        )
                    )
                    continue
                }
                let count = min(max(1, presses), NavigationLimits.maxArrowPresses)
                let interval = clampInterval(intervalSeconds)
                for index in 0..<count {
                    out.append(
                        Step(
                            action: .arrowNavigate(
                                direction: direction,
                                presses: 1,
                                intervalSeconds: 0
                            ),
                            timeoutSeconds: step.timeoutSeconds,
                            retryPolicy: step.retryPolicy,
                            onError: step.onError
                        )
                    )
                    if index + 1 < count, interval > 0 {
                        out.append(
                            Step(
                                action: .wait(seconds: interval),
                                timeoutSeconds: max(step.timeoutSeconds, interval + 0.5),
                                retryPolicy: RetryPolicy(maxRetries: 0),
                                onError: .abort
                            )
                        )
                    }
                }

            case .scroll(let direction, let amount):
                out.append(
                    Step(
                        action: .scroll(
                            direction: direction,
                            amount: min(max(1, amount), NavigationLimits.maxScrollAmount)
                        ),
                        timeoutSeconds: step.timeoutSeconds,
                        retryPolicy: step.retryPolicy,
                        onError: step.onError
                    )
                )

            default:
                out.append(step)
            }
        }
        return out
    }

    private static func clampInterval(_ seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return min(max(seconds, NavigationLimits.minIntervalSeconds), NavigationLimits.maxIntervalSeconds)
    }
}
