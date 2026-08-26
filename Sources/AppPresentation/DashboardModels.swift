import Domain
import Foundation

/// Sidebar destinations for the main application shell.
public enum AppSidebarSection: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case workflows
    case applications
    case discovery
    case sessions
    case logs
    case safety
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .workflows: return "Workflows"
        case .applications: return "Applications"
        case .discovery: return "Discovery"
        case .sessions: return "Sessions"
        case .logs: return "Logs"
        case .safety: return "Safety"
        case .settings: return "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .workflows: return "list.bullet.rectangle"
        case .applications: return "app.badge"
        case .discovery: return "magnifyingglass"
        case .sessions: return "clock.arrow.circlepath"
        case .logs: return "doc.text"
        case .safety: return "checkmark.shield"
        case .settings: return "gearshape"
        }
    }
}

/// High-level workflow run status for the dashboard.
public enum DashboardWorkflowStatus: String, Equatable, Sendable {
    case idle
    case running
    case paused
    case completed
    case failed

    public var title: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}

/// Live snapshot for the main dashboard (identity only — never document body).
public struct DashboardRunSnapshot: Equatable, Sendable {
    public var status: DashboardWorkflowStatus
    public var workflowName: String
    public var elapsedSeconds: Double
    public var remainingSeconds: Double?
    public var durationSeconds: Double?
    public var currentApplication: String
    public var currentWindow: String
    public var currentFileOrTab: String
    public var currentAction: String
    public var targetsCompleted: Int
    public var targetsRemaining: Int?
    public var discoverySummary: String
    public var enginePhase: String
    /// Active target bundle id when known (UI accent only).
    public var currentBundleID: String
    public var dwellElapsedSeconds: Double?
    public var dwellAllocatedSeconds: Double?
    /// Chrome Intelligence debug (empty when not in a browser crawl).
    public var chromeDebug: ChromeExplorerDebugSnapshot
    public var chromePreviewLines: [String]

    public init(
        status: DashboardWorkflowStatus = .idle,
        workflowName: String = "",
        elapsedSeconds: Double = 0,
        remainingSeconds: Double? = nil,
        durationSeconds: Double? = nil,
        currentApplication: String = "—",
        currentWindow: String = "—",
        currentFileOrTab: String = "—",
        currentAction: String = "—",
        targetsCompleted: Int = 0,
        targetsRemaining: Int? = nil,
        discoverySummary: String = "",
        enginePhase: String = "",
        currentBundleID: String = "",
        dwellElapsedSeconds: Double? = nil,
        dwellAllocatedSeconds: Double? = nil,
        chromeDebug: ChromeExplorerDebugSnapshot = .empty,
        chromePreviewLines: [String] = []
    ) {
        self.status = status
        self.workflowName = workflowName
        self.elapsedSeconds = elapsedSeconds
        self.remainingSeconds = remainingSeconds
        self.durationSeconds = durationSeconds
        self.currentApplication = currentApplication
        self.currentWindow = currentWindow
        self.currentFileOrTab = currentFileOrTab
        self.currentAction = currentAction
        self.targetsCompleted = targetsCompleted
        self.targetsRemaining = targetsRemaining
        self.discoverySummary = discoverySummary
        self.enginePhase = enginePhase
        self.currentBundleID = currentBundleID
        self.dwellElapsedSeconds = dwellElapsedSeconds
        self.dwellAllocatedSeconds = dwellAllocatedSeconds
        self.chromeDebug = chromeDebug
        self.chromePreviewLines = chromePreviewLines
    }

    public static let idle = DashboardRunSnapshot()
}
