import AppPresentation
import Domain
import Permissions
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: OnboardingUIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to \(ProductIdentity.displayName)")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("onboarding.title")
                    Text(HonestCopy.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("What it does")
                .font(.headline)
            Text(HonestCopy.does)
                .font(.callout)

            Text("What it will never do")
                .font(.headline)
            Text(HonestCopy.neverDoes)
                .font(.callout)

            Divider()

            Text(model.statusTitle)
                .font(.headline)
                .accessibilityIdentifier("onboarding.status")
            Text(model.statusDetail)
                .font(.callout)
                .foregroundStyle(.secondary)

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
                Text("Ready — close this window and use the Dashboard or menu bar.")
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
