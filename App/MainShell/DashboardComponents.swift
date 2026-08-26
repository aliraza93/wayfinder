import AppPresentation
import Domain
import SwiftUI

// MARK: - Buttons

enum TiktikButtonStyleKind {
    case primary
    case secondary
    case discovery
    case pause
    case resume
    case stop
}

struct TiktikButton: View {
    var title: String
    var systemImage: String?
    var kind: TiktikButtonStyleKind
    var isLoading: Bool = false
    /// When set, enforces a shared control width (equal-sized action rows).
    var minWidth: CGFloat? = nil
    var action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    private var isProminent: Bool {
        switch kind {
        case .primary, .discovery, .pause, .resume, .stop: return true
        case .secondary: return false
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .frame(width: 12, height: 12)
                }
                Text(title)
                    .font(.callout.weight(isProminent ? .semibold : .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: minWidth != nil ? .infinity : nil, minHeight: 14, alignment: .center)
            .padding(.horizontal, isProminent ? 12 : 10)
            .padding(.vertical, isProminent ? 6 : 5)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: minWidth, height: isProminent ? 30 : 28, alignment: .center)
        .background(background, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .foregroundStyle(foreground)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: kind == .secondary ? 1 : 0)
        )
        .shadow(color: shadowColor, radius: isHovered && isEnabled ? 3 : 0, y: isHovered ? 1 : 0)
        .opacity(isEnabled ? 1 : 0.45)
        .brightness(isHovered && isEnabled ? 0.03 : 0)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var cornerRadius: CGFloat { 7 }

    private var foreground: Color {
        switch kind {
        case .primary, .discovery, .resume, .stop:
            return .white
        case .secondary:
            return .primary
        case .pause:
            return Color(nsColor: .labelColor)
        }
    }

    private var background: Color {
        let base: Color
        switch kind {
        case .primary: base = TiktikTheme.primary
        case .secondary: base = TiktikTheme.cardBackground
        case .discovery: base = TiktikTheme.discovery
        case .pause: base = TiktikTheme.warning.opacity(0.85)
        case .resume: base = TiktikTheme.success
        case .stop: base = TiktikTheme.danger
        }
        if isHovered && isEnabled {
            return base.opacity(kind == .secondary ? 0.9 : 0.92)
        }
        return base
    }

    private var borderColor: Color {
        kind == .secondary ? TiktikTheme.separator : .clear
    }

    private var shadowColor: Color {
        switch kind {
        case .primary: return TiktikTheme.primary.opacity(0.25)
        case .discovery: return TiktikTheme.discovery.opacity(0.22)
        case .stop: return TiktikTheme.danger.opacity(0.2)
        default: return .clear
        }
    }
}

// MARK: - Status

struct StatusBadge: View {
    var status: DashboardWorkflowStatus
    var pulse: Bool = false

    @State private var pulseOn = false

    private var color: Color { TiktikTheme.statusColor(for: status) }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.25))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulse && pulseOn ? 1.35 : 1)
                    .opacity(pulse && pulseOn ? 0.35 : 0)
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(TiktikTheme.statusLabel(for: status))
                .font(.subheadline.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(color)
            if status == .completed {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
            } else if status == .failed {
                Image(systemName: "exclamationmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .onAppear {
            guard pulse else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulseOn = true
            }
        }
    }
}

// MARK: - Cards

struct DashboardPanel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TiktikTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(TiktikTheme.separator.opacity(0.55), lineWidth: 1)
        )
    }
}

struct MetricCard: View {
    var value: String
    var label: String
    var accent: Color = TiktikTheme.neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TiktikTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent.opacity(0.7))
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(TiktikTheme.separator.opacity(0.5), lineWidth: 1)
        )
    }
}

struct ApplicationCard: View {
    var name: String
    var bundleID: String
    var targetCount: Int
    var completedCount: Int?
    var isActive: Bool = false

    private var accent: Color { TiktikTheme.appAccent(bundleID: bundleID, displayName: name) }
    private var progress: Double {
        guard let completedCount, targetCount > 0 else { return 0 }
        return min(1, Double(completedCount) / Double(targetCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: TiktikTheme.appSymbol(bundleID: bundleID, displayName: name))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(name)
                    .font(.headline)
                Spacer(minLength: 0)
                if isActive {
                    Text("Active")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accent.opacity(0.12), in: Capsule())
                }
            }
            Text("\(targetCount) target\(targetCount == 1 ? "" : "s")")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let completedCount {
                Text("\(completedCount) completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .tint(accent)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TiktikTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isActive ? accent.opacity(0.45) : TiktikTheme.separator.opacity(0.5), lineWidth: 1)
        )
    }
}

struct ProgressRow: View {
    var title: String
    var progress: Double
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.callout)
                Spacer()
                Text("\(Int((min(1, max(0, progress)) * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, max(0, progress)))
                .tint(accent)
        }
    }
}

struct DiscoveryStatChip: View {
    var title: String
    var value: Int
    var systemImage: String
    var color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.body.weight(.semibold).monospacedDigit())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
