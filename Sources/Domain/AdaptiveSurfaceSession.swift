import Foundation

/// Heuristic reading window for one file/tab — never reads document body.
/// Short content → leave sooner; sustained downward navigation → stay longer.
public struct AdaptiveSurfaceSession: Equatable, Sendable {
    public var startedAt: Date
    public var endsAt: Date
    public var downwardCount: Int
    public var boundaryCount: Int
    public var extensionsUsed: Int

    public init(now: Date, durationSeconds: Double) {
        self.startedAt = now
        self.endsAt = now.addingTimeInterval(durationSeconds)
        self.downwardCount = 0
        self.boundaryCount = 0
        self.extensionsUsed = 0
    }

    public func isExpired(at now: Date) -> Bool {
        now >= endsAt
    }

    public var elapsedSeconds: Double {
        Date().timeIntervalSince(startedAt)
    }

    /// Update length estimate from navigation signals (not file bytes).
    public mutating func observe(action: ActionKind, markedBoundary: Bool, settings: ReviewWorkspaceSettings, now: Date) {
        if markedBoundary {
            boundaryCount += 1
        }
        if Self.isDownward(action) {
            downwardCount += 1
        }

        // Short: reached end after little scrolling → wrap up soon.
        if boundaryCount > 0, downwardCount < 7 {
            let remaining = endsAt.timeIntervalSince(now)
            if remaining > 2.5 {
                endsAt = now.addingTimeInterval(Double.random(in: 0.6...2.2))
            }
        }

        // Long: lots of downward motion, still no end → grant more time (capped).
        if downwardCount >= 8, boundaryCount == 0, extensionsUsed < 2 {
            endsAt = endsAt.addingTimeInterval(settings.randomFileDwellExtensionSeconds())
            extensionsUsed += 1
        }

        // Very long skim: second extension if still going deep.
        if downwardCount >= 16, boundaryCount == 0, extensionsUsed < 3 {
            endsAt = endsAt.addingTimeInterval(settings.randomFileDwellExtensionSeconds() * 0.85)
            extensionsUsed += 1
        }
    }

    public static func isDownward(_ action: ActionKind) -> Bool {
        switch action {
        case .scroll(let direction, _):
            return direction == .down
        case .pageNavigate(let mode):
            return mode == .pageDown || mode == .end
        case .arrowNavigate(let direction, _, _):
            return direction == .down
        default:
            return false
        }
    }
}

/// Hint for the crawl planner based on adaptive session.
public enum ContentPaceHint: Equatable, Sendable {
    case reading
    case shortContent
    case longContent
    case atEnd

    public static func from(session: AdaptiveSurfaceSession, atBoundary: Bool) -> ContentPaceHint {
        if atBoundary || session.boundaryCount > 0 && session.downwardCount < 7 {
            return session.downwardCount < 7 ? .shortContent : .atEnd
        }
        if session.downwardCount >= 8, session.boundaryCount == 0 {
            return .longContent
        }
        return .reading
    }
}
