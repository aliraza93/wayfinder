import AppPresentation
import Domain
import SwiftUI

struct WorkflowEditorView: View {
    @ObservedObject var model: WorkflowEditorUIModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HSplitView {
            paletteColumn
                .frame(minWidth: 200, idealWidth: 220)

            editorColumn
                .frame(minWidth: 480)
                .padding(16)
        }
        .frame(minWidth: 780, minHeight: 520)
        .onAppear { model.refreshApps() }
        .onChange(of: model.name) { _ in model.pushName() }
        .onChange(of: model.loopEnabled) { _ in model.pushLoop() }
        .onChange(of: model.maxIterations) { _ in model.pushLoop() }
        .onChange(of: model.shouldDismiss) { should in
            if should {
                dismiss()
                model.acknowledgeDismissed()
            }
        }
    }

    private var paletteColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Action palette")
                .font(.headline)
            Text("Only inert navigation — no typing, paste, save, or chords.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(ActionPaletteItem.allCases) { item in
                Button {
                    model.addPaletteItem(item)
                } label: {
                    Label(item.title, systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add “\(item.title)” step")
                .accessibilityIdentifier("editor.palette.\(item.rawValue)")
            }
        }
        .padding(12)
    }

    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Workflow name", text: $model.name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("editor.name")

            targetsCard
            stepsCard

            HStack(alignment: .center, spacing: 12) {
                Toggle("Loop", isOn: $model.loopEnabled)
                Stepper(
                    "Max iterations: \(model.maxIterations)",
                    value: $model.maxIterations,
                    in: 1...50
                )
                .disabled(!model.loopEnabled)
                .opacity(model.loopEnabled ? 1 : 0.45)
                .help(model.loopEnabled ? "Maximum loop count" : "Enable Loop to set iterations")
            }

            if let error = model.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .accessibilityIdentifier("editor.error")
            }

            HStack {
                Spacer()
                Button("Validate") { model.validateOnly() }
                    .accessibilityIdentifier("editor.validate")
                Button("Save workflow") { model.save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("editor.save")
                    .help("Save workflow (Return / ⌘S)")
            }
        }
    }

    private var targetsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Targets")
                        .font(.headline)
                    Spacer()
                    Button("Refresh apps") { model.refreshApps() }
                        .accessibilityIdentifier("editor.refreshApps")
                }

                HStack {
                    Picker("App", selection: $model.selectedRunningIndex) {
                        Text("Select running app").tag(-1)
                        ForEach(Array(model.runningApps.enumerated()), id: \.offset) { index, app in
                            Text(app.displayName).tag(index)
                                .help(app.bundleID)
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

                if model.targets.isEmpty {
                    Text("Add a running app as a target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.targets.enumerated()), id: \.offset) { index, row in
                            if index > 0 {
                                Divider()
                            }
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(row.displayName) [\(row.classification)]")
                                        .font(.body)
                                    Text(row.bundleID)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .help(row.bundleID)
                                }
                                Spacer()
                                Button("Remove") { model.removeTarget(at: index) }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    private var stepsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Steps")
                    .font(.headline)

                if model.steps.isEmpty {
                    Text("Add navigation steps from the palette")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("editor.stepsEmpty")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.steps.enumerated()), id: \.offset) { index, title in
                            if index > 0 {
                                Divider()
                            }
                            HStack {
                                Text("\(index + 1).")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                                Text(title)
                                Spacer()
                                Button("↑") { model.moveUp(index) }
                                    .disabled(index == 0)
                                Button("↓") { model.moveDown(index) }
                                    .disabled(index == model.steps.count - 1)
                                Button("Remove") { model.removeStep(at: index) }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .accessibilityIdentifier("editor.steps")
                }
            }
            .padding(4)
        }
    }
}

struct EditorTargetRow: Equatable {
    var displayName: String
    var bundleID: String
    var classification: String
}

@MainActor
final class WorkflowEditorUIModel: ObservableObject {
    @Published var name: String = "Untitled"
    @Published var loopEnabled = false
    @Published var maxIterations = 1
    @Published var selectedRunningIndex = -1
    @Published var selectedClass: TargetAppClass = .generic
    @Published private(set) var runningApps: [(bundleID: String, displayName: String)] = []
    @Published private(set) var targets: [EditorTargetRow] = []
    @Published private(set) var steps: [String] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var shouldDismiss = false

    /// Called after a successful persist (parent shows transient confirmation).
    var onSuccessfulSave: ((String) -> Void)?

    private let viewModel: WorkflowEditorViewModel

    init(viewModel: WorkflowEditorViewModel) {
        self.viewModel = viewModel
        syncFromVM()
    }

    func refreshApps() {
        viewModel.refreshRunningApps()
        runningApps = viewModel.runningApps
        syncFromVM()
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
        errorMessage = nil
    }

    func addSelectedTarget() {
        guard selectedRunningIndex >= 0, selectedRunningIndex < runningApps.count else { return }
        let app = runningApps[selectedRunningIndex]
        viewModel.addTarget(bundleID: app.bundleID, displayName: app.displayName, classification: selectedClass)
        syncFromVM()
        errorMessage = nil
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
        guard index < viewModel.draft.steps.count - 1 else { return }
        viewModel.moveStep(from: index, to: index + 2)
        syncFromVM()
    }

    func validateOnly() {
        pushName()
        pushLoop()
        switch viewModel.validateDraft() {
        case .success:
            errorMessage = nil
        case .failure(let error):
            errorMessage = WorkflowEditorSaveFlow.describe(error)
        }
    }

    /// Validates then persists. Invalid → keep open with red error. Valid → persist, dismiss, notify parent.
    func save() {
        pushName()
        pushLoop()
        var flow = WorkflowEditorSaveFlow()
        flow.apply(result: viewModel.save())
        errorMessage = flow.errorMessage
        if let name = flow.confirmationName {
            syncFromVM()
            onSuccessfulSave?(name)
        }
        shouldDismiss = flow.shouldDismiss
    }

    func acknowledgeDismissed() {
        shouldDismiss = false
    }

    private func syncFromVM() {
        name = viewModel.draft.name
        loopEnabled = viewModel.draft.loopEnabled
        maxIterations = viewModel.draft.maxIterations
        runningApps = viewModel.runningApps
        targets = viewModel.draft.targets.map { target in
            EditorTargetRow(
                displayName: viewModel.displayName(forBundleID: target.bundleID),
                bundleID: target.bundleID,
                classification: String(describing: target.classification)
            )
        }
        steps = viewModel.draft.steps.map { ActionPaletteItem.humanTitle(for: $0.action) }
    }
}
