import AppPresentation
import Permissions
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: OnboardingUIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Waypoint")
                .font(.title2)
                .accessibilityIdentifier("onboarding.title")
            Text(HonestCopy.tagline)
                .foregroundStyle(.secondary)
            Text("What it does")
                .font(.headline)
            Text(HonestCopy.does)
            Text("What it will never do")
                .font(.headline)
            Text(HonestCopy.neverDoes)
            Divider()
            Text(model.statusTitle)
                .font(.headline)
                .accessibilityIdentifier("onboarding.status")
            Text(model.statusDetail)
            HStack {
                Button("Request Accessibility…") {
                    model.request()
                }
                .accessibilityIdentifier("onboarding.request")
                Button("Open Accessibility Settings") {
                    model.openSettings()
                }
                .accessibilityIdentifier("onboarding.settings")
                Button("I’ve Enabled It — Recheck") {
                    model.refresh()
                }
                .accessibilityIdentifier("onboarding.recheck")
            }
            if model.isGranted {
                Text("Ready — close this window and use the menu bar.")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("onboarding.ready")
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { model.refresh() }
    }
}

@MainActor
final class OnboardingUIModel: ObservableObject {
    @Published private(set) var statusTitle = ""
    @Published private(set) var statusDetail = ""
    @Published private(set) var isGranted = false

    private let viewModel: OnboardingViewModel

    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
        sync()
    }

    func refresh() {
        viewModel.refresh()
        sync()
    }

    func request() {
        viewModel.request()
        sync()
    }

    func openSettings() {
        viewModel.openAccessibilitySettings()
        sync()
    }

    private func sync() {
        statusTitle = viewModel.statusTitle
        statusDetail = viewModel.statusDetail
        isGranted = viewModel.state == .granted
    }
}
