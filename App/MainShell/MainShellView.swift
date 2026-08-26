import AppPresentation
import Domain
import SwiftUI

/// Primary application shell: sidebar + detail content.
struct MainShellView: View {
    @ObservedObject var session: AppSession
    @State private var section: AppSidebarSection = .dashboard
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section {
                    ForEach(AppSidebarSection.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                    }
                } header: {
                    HStack(spacing: 8) {
                        BrandMark(size: 22)
                        Text(ProductIdentity.displayName)
                            .font(.headline)
                    }
                    .textCase(nil)
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detail(for: section)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(section.title)
        .toolbar {
            if session.isRunning {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        if session.isPaused {
                            Button("Resume") { session.resume() }
                                .help("Resume workflow (⌃⌥R)")
                        } else {
                            Button("Pause") { session.pause() }
                                .help("Pause workflow (⌃⌥P)")
                        }
                        Button("Stop", role: .destructive) { session.stop() }
                            .help("Emergency Stop (⌃⌥.)")
                    }
                    .padding(.trailing, 8)
                }
            }
        }
        .onAppear {
            session.refreshPermissions()
            session.refreshWorkflowNames()
            applyPendingSection()
        }
        .onChange(of: session.pendingSidebarSection) { _ in
            applyPendingSection()
        }
    }

    private func applyPendingSection() {
        if let pending = session.consumePendingSidebarSection() {
            section = pending
        }
    }

    @ViewBuilder
    private func detail(for section: AppSidebarSection) -> some View {
        switch section {
        case .dashboard:
            DashboardView(session: session, openWindow: openWindow)
        case .workflows:
            WorkflowsSectionView(session: session, openWindow: openWindow)
        case .applications:
            ApplicationsSectionView(session: session)
        case .discovery:
            DiscoverySectionView(session: session)
        case .sessions:
            SessionsSectionView(session: session, openWindow: openWindow)
        case .logs:
            LogsSectionView(session: session, openWindow: openWindow)
        case .safety:
            SafetySectionView(session: session)
        case .settings:
            SettingsSectionView(session: session, openWindow: openWindow)
        }
    }
}
