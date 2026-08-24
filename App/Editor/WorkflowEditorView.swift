import AppPresentation
import Domain
import SwiftUI

struct WorkflowEditorView: View {
    @ObservedObject var model: WorkflowEditorUIModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Action palette")
                    .font(.headline)
                Text("Only inert navigation — no typing, paste, save, or chords.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                List(ActionPaletteItem.allCases) { item in
                    Button(item.title) {
                        model.addPaletteItem(item)
                    }
                    .accessibilityIdentifier("editor.palette.\(item.rawValue)")
                }
            }
            .frame(minWidth: 180)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Workflow name", text: $model.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("editor.name")

                Text("Targets")
                    .font(.headline)
                HStack {
                    Picker("App", selection: $model.selectedRunningIndex) {
                        Text("Select running app").tag(-1)
                        ForEach(Array(model.runningApps.enumerated()), id: \.offset) { index, app in
                            Text("\(app.displayName) (\(app.bundleID))").tag(index)
                        }
                    }
                    Picker("Class", selection: $model.selectedClass) {
                        Text("Browser").tag(TargetAppClass.browser)
                        Text("Editor").tag(TargetAppClass.editor)
                        Text("Finder").tag(TargetAppClass.finder)
                        Text("Generic").tag(TargetAppClass.generic)
                    }
                    .frame(width: 120)
                    Button("Add target") { model.addSelectedTarget() }
                        .accessibilityIdentifier("editor.addTarget")
                }
                List {
                    ForEach(Array(model.targetLabels.enumerated()), id: \.offset) { index, label in
                        HStack {
                            Text(label)
                            Spacer()
                            Button("Remove") { model.removeTarget(at: index) }
                        }
                    }
                }
                .frame(minHeight: 80)

                Text("Steps")
                    .font(.headline)
                List {
                    ForEach(Array(model.stepLabels.enumerated()), id: \.offset) { index, label in
                        HStack {
                            Text(label)
                            Spacer()
                            Button("↑") { model.moveUp(index) }
                            Button("↓") { model.moveDown(index) }
                            Button("Remove") { model.removeStep(at: index) }
                        }
                    }
                }
                .accessibilityIdentifier("editor.steps")

                HStack {
                    Toggle("Loop", isOn: $model.loopEnabled)
                    Stepper("Max iterations: \(model.maxIterations)", value: $model.maxIterations, in: 1...100)
                }

                if let error = model.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("editor.error")
                }
                if let ok = model.successMessage {
                    Text(ok)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("editor.saved")
                }

                HStack {
                    Button("Refresh apps") { model.refreshApps() }
                    Spacer()
                    Button("Validate") { model.validateOnly() }
                        .accessibilityIdentifier("editor.validate")
                    Button("Save workflow") { model.save() }
                        .accessibilityIdentifier("editor.save")
                }
            }
            .padding()
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { model.refreshApps() }
        .onChange(of: model.name) { _ in model.pushName() }
        .onChange(of: model.loopEnabled) { _ in model.pushLoop() }
        .onChange(of: model.maxIterations) { _ in model.pushLoop() }
    }
}

@MainActor
final class WorkflowEditorUIModel: ObservableObject {
    @Published var name: String = "Untitled"
    @Published var loopEnabled = false
    @Published var maxIterations = 1
    @Published var selectedRunningIndex = -1
    @Published var selectedClass: TargetAppClass = .generic
    @Published private(set) var runningApps: [(bundleID: String, displayName: String)] = []
    @Published private(set) var targetLabels: [String] = []
    @Published private(set) var stepLabels: [String] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?

    private let viewModel: WorkflowEditorViewModel

    init(viewModel: WorkflowEditorViewModel) {
        self.viewModel = viewModel
        syncFromVM()
    }

    func refreshApps() {
        viewModel.refreshRunningApps()
        runningApps = viewModel.runningApps
    }

    func pushName() {
        viewModel.setName(name)
    }

    func pushLoop() {
        viewModel.setLoop(enabled: loopEnabled, maxIterations: maxIterations, maxDurationSeconds: nil)
    }

    func addPaletteItem(_ item: ActionPaletteItem) {
        let bundle: String
        if item == .activateApp, selectedRunningIndex >= 0, selectedRunningIndex < runningApps.count {
            bundle = runningApps[selectedRunningIndex].bundleID
        } else if item == .activateApp, let first = viewModel.draft.targets.first {
            bundle = first.bundleID
        } else {
            bundle = ""
        }
        viewModel.addStep(from: item, activateBundleID: bundle)
        syncFromVM()
        clearMessages()
    }

    func addSelectedTarget() {
        guard selectedRunningIndex >= 0, selectedRunningIndex < runningApps.count else { return }
        let app = runningApps[selectedRunningIndex]
        viewModel.addTarget(bundleID: app.bundleID, displayName: app.displayName, classification: selectedClass)
        syncFromVM()
        clearMessages()
    }

    func removeTarget(at index: Int) {
        viewModel.removeTarget(at: index)
        syncFromVM()
    }

    func removeStep(at index: Int) {
        viewModel.removeStep(at: index)
        syncFromVM()
    }

    func moveUp(_ index: Int) {
        guard index > 0 else { return }
        viewModel.moveStep(from: index, to: index - 1)
        syncFromVM()
    }

    func moveDown(_ index: Int) {
        viewModel.moveStep(from: index, to: index + 2)
        syncFromVM()
    }

    func validateOnly() {
        pushName()
        pushLoop()
        switch viewModel.validateDraft() {
        case .success:
            errorMessage = nil
            successMessage = "Valid — safe to save"
        case .failure(let error):
            successMessage = nil
            errorMessage = String(describing: error)
        }
    }

    func save() {
        pushName()
        pushLoop()
        switch viewModel.save() {
        case .success(let workflow):
            errorMessage = nil
            successMessage = "Saved “\(workflow.name)”"
            syncFromVM()
        case .failure(let error):
            successMessage = nil
            errorMessage = String(describing: error)
        }
    }

    private func syncFromVM() {
        name = viewModel.draft.name
        loopEnabled = viewModel.draft.loopEnabled
        maxIterations = viewModel.draft.maxIterations
        runningApps = viewModel.runningApps
        targetLabels = viewModel.draft.targets.map {
            "\($0.bundleID) [\($0.classification)]"
        }
        stepLabels = viewModel.draft.steps.map { RunSessionViewModel.label(for: $0.action) }
    }

    private func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}

// TargetAppClass already Hashable via enum synthesis.
