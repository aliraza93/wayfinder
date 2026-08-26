import AppPresentation
import Domain
import SwiftUI

/// Shared layout / empty-state helpers for the main shell (native, low chrome).
enum AppChrome {
    static let contentMaxWidth: CGFloat = 720
    static let dashboardMaxWidth: CGFloat = 880
    static let pagePadding: CGFloat = 20
    static let stackSpacing: CGFloat = 14
}

/// Minimal trotting-gait mark — geometric strides, not a cartoon horse.
struct BrandMark: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(TiktikTheme.primary.opacity(0.12))
            Circle()
                .strokeBorder(TiktikTheme.primary.opacity(0.35), lineWidth: 1)
            TrottingGaitShape()
                .stroke(
                    TiktikTheme.primary,
                    style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)
                )
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Two forward arcs suggesting cadence / trot.
private struct TrottingGaitShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.12, y: h * 0.72))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.52, y: h * 0.28),
            control: CGPoint(x: w * 0.22, y: h * 0.18)
        )
        path.move(to: CGPoint(x: w * 0.38, y: h * 0.78))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.88, y: h * 0.32),
            control: CGPoint(x: w * 0.58, y: h * 0.12)
        )
        return path
    }
}

struct ShellPageHeader: View {
    var title: String
    var subtitle: String?
    var showBrand: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showBrand {
                BrandMark(size: 40)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct EmptyStateCard: View {
    var title: String
    var message: String
    var systemImage: String = "tray"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusPill: View {
    var title: String
    var color: Color

    var body: some View {
        StatusBadge(status: statusFromTitle(title), pulse: false)
            .accessibilityLabel(title)
    }

    private func statusFromTitle(_ title: String) -> DashboardWorkflowStatus {
        switch title.lowercased() {
        case "running": return .running
        case "paused": return .paused
        case "completed": return .completed
        case "failed": return .failed
        default: return .idle
        }
    }
}
