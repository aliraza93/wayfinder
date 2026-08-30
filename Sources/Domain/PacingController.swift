import Foundation

/// Navigation vs content-review phases for deliberate pacing.
public enum PacingPhase: String, Equatable, Sendable {
    case navigation
    case review
    case pageSettle
    case surfaceSwitch
}

/// Structure-only signals used to scale gaps and review budgets (never document body).
public struct PacingContext: Equatable, Sendable {
    public var phase: PacingPhase
    public var estimatedReadWeight: Double
    public var headingCount: Int
    public var candidateCount: Int
    public var scrollsOnSurface: Int
    public var atContentEnd: Bool
    public var newlyDiscoveredTargets: Int
    public var consecutiveActions: Int

    public init(
        phase: PacingPhase,
        estimatedReadWeight: Double = 0.5,
        headingCount: Int = 0,
        candidateCount: Int = 0,
        scrollsOnSurface: Int = 0,
        atContentEnd: Bool = false,
        newlyDiscoveredTargets: Int = 0,
        consecutiveActions: Int = 0
    ) {
        self.phase = phase
        self.estimatedReadWeight = estimatedReadWeight
        self.headingCount = headingCount
        self.candidateCount = candidateCount
        self.scrollsOnSurface = scrollsOnSurface
        self.atContentEnd = atContentEnd
        self.newlyDiscoveredTargets = newlyDiscoveredTargets
        self.consecutiveActions = consecutiveActions
    }

    public static func navigation(
        weight: Double = 0.5,
        candidates: Int = 0,
        consecutive: Int = 0
    ) -> PacingContext {
        PacingContext(
            phase: .navigation,
            estimatedReadWeight: weight,
            candidateCount: candidates,
            consecutiveActions: consecutive
        )
    }

    public static func review(
        weight: Double,
        headings: Int = 0,
        scrolls: Int = 0,
        atEnd: Bool = false
    ) -> PacingContext {
        PacingContext(
            phase: .review,
            estimatedReadWeight: weight,
            headingCount: headings,
            scrollsOnSurface: scrolls,
            atContentEnd: atEnd
        )
    }

    public static var pageSettle: PacingContext {
        PacingContext(phase: .pageSettle)
    }

    public static var surfaceSwitch: PacingContext {
        PacingContext(phase: .surfaceSwitch)
    }
}

/// Deliberate pacing for Universal Workspace Navigation (not activity-monitor timing).
public enum PacingController: Sendable {
    public static func gapSeconds(
        profile: NavigationPacingProfile,
        custom: NavigationPacingCustom,
        context: PacingContext
    ) -> Double {
        let base = baseGap(profile: profile, custom: custom, phase: context.phase)
        var gap = base

        let weight = min(1.4, max(0.2, context.estimatedReadWeight))
        if profile != .custom {
            switch context.phase {
            case .review:
                gap *= 0.85 + weight * 0.35
                if context.headingCount >= 6 { gap *= 1.12 }
                if context.atContentEnd { gap *= 0.85 }
                if context.scrollsOnSurface > 12 { gap *= 1.08 }
            case .navigation:
                if context.candidateCount >= 8 { gap *= 1.1 }
                if context.newlyDiscoveredTargets > 0 { gap *= 1.15 }
            case .pageSettle:
                gap *= 0.9 + weight * 0.25
            case .surfaceSwitch:
                break
            }
        }

        if shouldForcePause(
            consecutiveActions: context.consecutiveActions,
            maxConsecutive: maxConsecutiveActions(profile: profile, custom: custom)
        ) {
            gap = max(gap, base * 1.6)
        }

        return min(8.0, max(0.2, gap))
    }

    public static func reviewDurationSeconds(
        profile: NavigationPacingProfile,
        custom: NavigationPacingCustom,
        weight: Double,
        dwellMaxSeconds: Double
    ) -> Double {
        let w = min(1.4, max(0.2, weight))
        let bias = reviewDurationBias(profile: profile)
        let raw = (20 + w * 240) * bias
        switch profile {
        case .custom:
            return min(custom.maxReviewSeconds, max(custom.minReviewSeconds, raw))
        case .relaxed, .deliberate, .normal:
            return min(min(1_800, dwellMaxSeconds * 1.2), max(25, raw))
        }
    }

    public static func keyBudget(
        profile: NavigationPacingProfile,
        custom: NavigationPacingCustom,
        weight: Double,
        readingSource: Bool,
        maxScrollsCeiling: Int
    ) -> Int {
        let w = min(1.4, max(0.2, weight))
        let bias = reviewDurationBias(profile: profile)
        let auto = Int((8 + w * 40 * bias).rounded())
        let minKeys = readingSource ? 8 : 4
        let maxKeys = readingSource ? 48 : 24
        var budget = min(max(minKeys, auto), maxKeys)
        if profile == .custom {
            // Custom scroll interval doesn't change key count directly; clamp by review span heuristic.
            let span = max(1, custom.maxReviewSeconds / max(0.5, custom.scrollIntervalSeconds))
            budget = min(budget, max(minKeys, Int(span.rounded())))
        }
        return min(max(1, maxScrollsCeiling), budget)
    }

    public static func maxConsecutiveActions(
        profile: NavigationPacingProfile,
        custom: NavigationPacingCustom
    ) -> Int {
        switch profile {
        case .relaxed: return 2
        case .deliberate: return 3
        case .normal: return 5
        case .custom: return max(1, min(12, custom.maxConsecutiveActions))
        }
    }

    public static func shouldForcePause(consecutiveActions: Int, maxConsecutive: Int) -> Bool {
        consecutiveActions >= max(1, maxConsecutive)
    }

    /// Soften opportunistic mid-dwell file/tab hops under careful profiles.
    public static func allowOpportunisticSurfaceHop(
        profile: NavigationPacingProfile,
        crawlSteps: Int,
        consecutiveDown: Int
    ) -> Bool {
        switch profile {
        case .relaxed:
            return crawlSteps > 22 && consecutiveDown >= 4
        case .deliberate:
            return crawlSteps > 18 && consecutiveDown >= 3
        case .normal, .custom:
            return crawlSteps > 14
        }
    }

    public static func reviewDurationBias(profile: NavigationPacingProfile) -> Double {
        switch profile {
        case .relaxed: return 1.4
        case .deliberate: return 1.6
        case .normal: return 1.0
        case .custom: return 1.0
        }
    }

    private static func baseGap(
        profile: NavigationPacingProfile,
        custom: NavigationPacingCustom,
        phase: PacingPhase
    ) -> Double {
        switch profile {
        case .custom:
            switch phase {
            case .review: return custom.scrollIntervalSeconds
            case .navigation: return custom.navigationPauseSeconds
            case .pageSettle: return custom.pageTransitionPauseSeconds
            case .surfaceSwitch: return custom.pageTransitionPauseSeconds
            }
        case .relaxed:
            switch phase {
            case .navigation: return Double.random(in: 1.6...2.4)
            case .review: return Double.random(in: 1.2...1.8)
            case .pageSettle: return Double.random(in: 1.5...2.5)
            case .surfaceSwitch: return Double.random(in: 1.4...2.2)
            }
        case .deliberate:
            switch phase {
            case .navigation: return Double.random(in: 1.2...1.8)
            case .review: return Double.random(in: 1.0...1.5)
            case .pageSettle: return Double.random(in: 1.2...2.0)
            case .surfaceSwitch: return Double.random(in: 1.0...1.8)
            }
        case .normal:
            switch phase {
            case .navigation: return Double.random(in: 0.6...1.0)
            case .review: return Double.random(in: 0.45...0.7)
            case .pageSettle: return Double.random(in: 0.6...1.2)
            case .surfaceSwitch: return Double.random(in: 0.5...1.0)
            }
        }
    }
}
