import AppPresentation
import SwiftUI

/// Semantic colors for Tiktik Ghora — appearance-aware, native-first.
enum TiktikTheme {
    // MARK: - Core

    static var primary: Color { Color.accentColor }
    static var secondary: Color { Color.secondary }
    static var success: Color { Color.green }
    static var warning: Color { Color.orange }
    static var danger: Color { Color.red }
    static var info: Color { Color.cyan }

    /// Discovery / scan affordances.
    static var discovery: Color { Color.indigo }
    /// Chrome / browser accent (restrained).
    static var chrome: Color { Color.blue }
    /// Cursor / editor accent.
    static var cursor: Color { Color.teal }
    static var neutral: Color { Color(nsColor: .secondaryLabelColor) }

    // MARK: - Surfaces

    static var cardBackground: Color { Color(nsColor: .controlBackgroundColor) }
    static var elevatedBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }

    // MARK: - Status

    static func statusColor(for status: DashboardWorkflowStatus) -> Color {
        switch status {
        case .idle: return secondary
        case .running: return success
        case .paused: return warning
        case .completed: return success
        case .failed: return danger
        }
    }

    static func statusLabel(for status: DashboardWorkflowStatus) -> String {
        switch status {
        case .idle: return "READY"
        case .running: return "RUNNING"
        case .paused: return "PAUSED"
        case .completed: return "COMPLETED"
        case .failed: return "FAILED"
        }
    }

    // MARK: - App accents

    static func appAccent(bundleID: String, displayName: String = "") -> Color {
        let id = bundleID.lowercased()
        let name = displayName.lowercased()
        if id.hasPrefix("com.todesktop.") || name.contains("cursor") {
            return cursor
        }
        if id.hasPrefix("com.google.chrome") || name.contains("chrome") {
            return chrome
        }
        if id.contains("safari") || name.contains("safari") {
            return chrome
        }
        if id == "com.apple.finder" || name.contains("finder") {
            return Color(nsColor: .systemGray)
        }
        if id == "com.apple.preview" || name.contains("preview") {
            return Color(nsColor: .systemOrange)
        }
        return primary
    }

    static func appSymbol(bundleID: String, displayName: String = "") -> String {
        let id = bundleID.lowercased()
        let name = displayName.lowercased()
        if id.hasPrefix("com.todesktop.") || name.contains("cursor") {
            return "chevron.left.forwardslash.chevron.right"
        }
        if id.hasPrefix("com.google.chrome") || name.contains("chrome") || name.contains("safari") {
            return "globe"
        }
        if id == "com.apple.finder" || name.contains("finder") {
            return "folder"
        }
        if id == "com.apple.preview" || name.contains("preview") {
            return "doc.richtext"
        }
        return "macwindow"
    }
}
