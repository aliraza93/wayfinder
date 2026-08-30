import AppPresentation
import Domain
import SwiftUI

struct WorkflowEditorView: View {
    @ObservedObject var model: WorkflowEditorUIModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HSplitView {
            if !model.durationPreset.isTimedReview {
                paletteColumn
                    .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
            }

            VStack(spacing: 0) {
                ScrollView {
                    editorForm
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                editorFooter
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .frame(minWidth: 520)
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            model.refreshApps()
            model.refreshSavedNames()
            if model.steps.isEmpty, model.durationPreset.isTimedReview {
                model.pushDuration()
            }
        }
        .onChange(of: model.name) { _ in
            guard !model.isSyncingFromStore else { return }
            model.pushName()
        }
        .onChange(of: model.loopEnabled) { _ in
            guard !model.isSyncingFromStore else { return }
            model.pushLoop()
        }
        .onChange(of: model.maxIterations) { _ in
            guard !model.isSyncingFromStore else { return }
            model.pushLoop()
        }
        .onChange(of: model.durationPreset) { _ in
            guard !model.isSyncingFromStore else { return }
            model.pushDuration()
        }
        .onChange(of: model.customDurationHours) { _ in
            guard !model.isSyncingFromStore else { return }
            model.pushDuration()
        }
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
            Text("Read-only navigation — no typing, paste, save, or delete.")
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

    private var editorForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text("Open")
                    .foregroundStyle(.secondary)
                Picker("", selection: $model.selectedSavedName) {
                    Text("New workflow").tag("")
                    ForEach(model.savedWorkflowNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 320, alignment: .leading)
                .accessibilityIdentifier("editor.openExisting")
                .onChange(of: model.selectedSavedName) { name in
                    guard !model.isSyncingFromStore else { return }
                    if name.isEmpty {
                        model.startNewWorkflow()
                    } else {
                        model.loadExisting(name)
                    }
                }

                Button("Refresh list") {
                    model.refreshSavedNames()
                }
                .help("Reload names from workflows.json")
                Spacer(minLength: 0)
            }

            TextField("Workflow name", text: $model.name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("editor.name")

            targetsCard
            durationCard

            if model.durationPreset.isTimedReview {
                reviewSessionCard
                reviewCursorCard
                reviewChromeCard
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What it does")
                            .font(.headline)
                        Text(HonestCopy.does)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(HonestCopy.tabFileLimits)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(HonestCopy.neverDoes)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                stepsCard
            }

            if let error = model.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .accessibilityIdentifier("editor.error")
            }
        }
    }

    private var editorFooter: some View {
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

    private var durationCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("How long?")
                    .font(.headline)
                Picker("Duration", selection: $model.durationPreset) {
                    ForEach(RunDurationPreset.timedOnly) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("editor.duration")

                if model.durationPreset == .custom {
                    Stepper(
                        "Hours: \(model.customDurationHours)",
                        value: $model.customDurationHours,
                        in: 1...72
                    )
                }

                Text("Session length for Universal Workspace Navigation. Dwell and discovery are configured below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reviewSessionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Allowed apps")
                    .font(.headline)
                Text("Only apps in Targets above are crawled. Turn on optional open-app extras below if you want Finder/Preview/others too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Also crawl other open apps", isOn: $model.discoverRunningApps)
                if model.discoverRunningApps {
                    Toggle("Finder", isOn: $model.includeFinder)
                    Toggle("Preview", isOn: $model.includePreview)
                    Toggle("Other applications (never Settings)", isOn: $model.includeOther)
                    Toggle("Refresh open apps between dwells", isOn: $model.refreshTargetsBetweenDwells)
                    Text("Does not auto-add Xcode or other editors/browsers — add those as Targets if you want them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Extras use conservative Page/Arrow keys only. Never clicks random coordinates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text("Target dwell & navigation")
                    .font(.headline)
                HStack {
                    Text("Min dwell (sec)")
                    Spacer()
                    Stepper(
                        "\(Int(model.dwellMinSeconds))",
                        value: $model.dwellMinSeconds,
                        in: 5...600,
                        step: 5
                    )
                }
                HStack {
                    Text("Max dwell (sec)")
                    Spacer()
                    Stepper(
                        "\(Int(model.dwellMaxSeconds))",
                        value: $model.dwellMaxSeconds,
                        in: 10...900,
                        step: 5
                    )
                }
                Picker("Navigation Pacing", selection: $model.pacingProfile) {
                    ForEach(NavigationPacingProfile.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                if model.pacingProfile == .custom {
                    Group {
                        HStack {
                            Text("Min review (sec)")
                            Spacer()
                            Stepper(
                                "\(Int(model.pacingCustom.minReviewSeconds))",
                                value: $model.pacingCustom.minReviewSeconds,
                                in: 5...600,
                                step: 5
                            )
                        }
                        HStack {
                            Text("Max review (sec)")
                            Spacer()
                            Stepper(
                                "\(Int(model.pacingCustom.maxReviewSeconds))",
                                value: $model.pacingCustom.maxReviewSeconds,
                                in: 10...1_800,
                                step: 10
                            )
                        }
                        HStack {
                            Text("Scroll interval (sec)")
                            Spacer()
                            TextField(
                                "1.4",
                                value: $model.pacingCustom.scrollIntervalSeconds,
                                format: .number.precision(.fractionLength(2))
                            )
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Navigation pause (sec)")
                            Spacer()
                            TextField(
                                "1.8",
                                value: $model.pacingCustom.navigationPauseSeconds,
                                format: .number.precision(.fractionLength(2))
                            )
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Page transition (sec)")
                            Spacer()
                            TextField(
                                "2.0",
                                value: $model.pacingCustom.pageTransitionPauseSeconds,
                                format: .number.precision(.fractionLength(2))
                            )
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Max consecutive actions")
                            Spacer()
                            Stepper(
                                "\(model.pacingCustom.maxConsecutiveActions)",
                                value: $model.pacingCustom.maxConsecutiveActions,
                                in: 1...12
                            )
                        }
                    }
                }
                Picker("Target order", selection: $model.targetOrder) {
                    ForEach(ReviewTargetOrder.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
                Toggle("Loop targets until session ends", isOn: $model.loopTargets)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: model.discoverRunningApps) { _ in model.pushReviewSettings() }
            .onChange(of: model.includeFinder) { _ in model.pushReviewSettings() }
            .onChange(of: model.includePreview) { _ in model.pushReviewSettings() }
            .onChange(of: model.includeOther) { _ in model.pushReviewSettings() }
            .onChange(of: model.refreshTargetsBetweenDwells) { _ in model.pushReviewSettings() }
            .onChange(of: model.dwellMinSeconds) { _ in model.pushReviewSettings() }
            .onChange(of: model.dwellMaxSeconds) { _ in model.pushReviewSettings() }
            .onChange(of: model.pacingProfile) { _ in model.pushReviewSettings() }
            .onChange(of: model.pacingCustom) { _ in model.pushReviewSettings() }
            .onChange(of: model.targetOrder) { _ in model.pushReviewSettings() }
            .onChange(of: model.loopTargets) { _ in model.pushReviewSettings() }
        }
    }

    private var reviewCursorCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cursor files")
                    .font(.headline)
                TextField("Workspace (~/Projects/…)", text: $model.workspacePath)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.workspacePath) { _ in model.pushReviewSettings() }
                HStack {
                    TextField("Relative or absolute file path", text: $model.fileDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Add file") { model.addFile() }
                }
                if model.filePaths.isEmpty {
                    Text("Add existing project files to open and crawl in order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.filePaths.enumerated()), id: \.offset) { index, path in
                        HStack {
                            Text("\(index + 1). \(path)")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) { model.removeFile(at: index) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reviewChromeCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Chrome")
                    .font(.headline)

                Toggle("Enable smart web navigation", isOn: $model.chromeEnabled)
                    .onChange(of: model.chromeEnabled) { _ in model.pushReviewSettings() }

                Picker("Navigation profile", selection: $model.chromeProfile) {
                    Text("Documentation").tag(ChromeNavigationProfile.documentation)
                    Text("GitHub Repository").tag(ChromeNavigationProfile.githubRepository)
                    Text("General Website").tag(ChromeNavigationProfile.generalWebsite)
                    Text("Custom").tag(ChromeNavigationProfile.custom)
                }
                .onChange(of: model.chromeProfile) { _ in model.pushReviewSettings() }

                Text("Allowed domains (one per line)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.chromeAllowedDomainsText)
                    .font(.body)
                    .frame(minHeight: 52, maxHeight: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    )
                    .onChange(of: model.chromeAllowedDomainsText) { _ in model.pushReviewSettings() }

                Text("Blocked domains (one per line)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.chromeBlockedDomainsText)
                    .font(.body)
                    .frame(minHeight: 40, maxHeight: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    )
                    .onChange(of: model.chromeBlockedDomainsText) { _ in model.pushReviewSettings() }

                Picker("External domains", selection: $model.chromeExternalPolicy) {
                    Text("Blocked").tag(ChromeExternalDomainPolicy.blocked)
                    Text("Allowlist only").tag(ChromeExternalDomainPolicy.allowlist)
                }
                .onChange(of: model.chromeExternalPolicy) { _ in model.pushReviewSettings() }

                HStack {
                    Stepper("Max depth: \(model.chromeMaxDepth)", value: $model.chromeMaxDepth, in: 1...25)
                        .onChange(of: model.chromeMaxDepth) { _ in model.pushReviewSettings() }
                    Stepper("Max pages: \(model.chromeMaxPages)", value: $model.chromeMaxPages, in: 1...200)
                        .onChange(of: model.chromeMaxPages) { _ in model.pushReviewSettings() }
                }
                Text("Reading uses Page/Arrow keys (top ↔ bottom). Stay length scales with page structure automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Documentation", isOn: $model.chromeCrawlDocumentation)
                    .onChange(of: model.chromeCrawlDocumentation) { _ in model.pushReviewSettings() }
                Toggle("Source files", isOn: $model.chromeCrawlSourceFiles)
                    .onChange(of: model.chromeCrawlSourceFiles) { _ in model.pushReviewSettings() }
                Toggle("Repository directories", isOn: $model.chromeCrawlDirectories)
                    .onChange(of: model.chromeCrawlDirectories) { _ in model.pushReviewSettings() }
                Toggle("Issues (off by default)", isOn: $model.chromeCrawlIssues)
                    .onChange(of: model.chromeCrawlIssues) { _ in model.pushReviewSettings() }

                Picker("GitHub crawl", selection: $model.chromeGithubStrategy) {
                    Text("Breadth-first").tag(GitHubCrawlStrategy.breadthFirst)
                    Text("Depth-first").tag(GitHubCrawlStrategy.depthFirst)
                    Text("Selected directories").tag(GitHubCrawlStrategy.selectedDirectories)
                }
                .onChange(of: model.chromeGithubStrategy) { _ in model.pushReviewSettings() }

                if model.chromeGithubStrategy == .selectedDirectories {
                    Text("Selected directories (one per line, e.g. app/)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $model.chromeSelectedDirectoriesText)
                        .font(.body)
                        .frame(minHeight: 40, maxHeight: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25))
                        )
                        .onChange(of: model.chromeSelectedDirectoriesText) { _ in model.pushReviewSettings() }
                }

                Text("Preferred link keywords (one per line)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.chromePreferredKeywordsText)
                    .font(.body)
                    .frame(minHeight: 40, maxHeight: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    )
                    .onChange(of: model.chromePreferredKeywordsText) { _ in model.pushReviewSettings() }

                Text("Excluded path prefixes (one per line)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.chromeExcludedPathsText)
                    .font(.body)
                    .frame(minHeight: 40, maxHeight: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    )
                    .onChange(of: model.chromeExcludedPathsText) { _ in model.pushReviewSettings() }

                Divider()
                Text("Chrome tabs")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    TextField("Tab label (for status / logs)", text: $model.tabDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Add tab") { model.addTab() }
                }
                Text("Labels identify tabs in the dashboard. Smart navigation inspects the active page; Ctrl+Tab remains a fallback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(model.tabLabels.enumerated()), id: \.offset) { index, label in
                    HStack {
                        Text("\(index + 1). \(label)")
                        Spacer()
                        Button(role: .destructive) { model.removeTab(at: index) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Steps")
                    .font(.headline)

                if model.steps.isEmpty {
                    Text("Add navigation steps from the palette")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .accessibilityIdentifier("editor.stepsEmpty")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.steps.enumerated()), id: \.offset) { index, title in
                            if index > 0 {
                                Divider()
                            }
                            HStack(alignment: .center, spacing: 8) {
                                Text("\(index + 1).")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title)
                                        .lineLimit(1)
                                    stepEditors(for: index)
                                }
                                Spacer(minLength: 8)
                                Button("↑") { model.moveUp(index) }
                                    .disabled(index == 0)
                                Button("↓") { model.moveDown(index) }
                                    .disabled(index == model.steps.count - 1)
                                Button("Remove") { model.removeStep(at: index) }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .accessibilityIdentifier("editor.steps")
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private func stepEditors(for index: Int) -> some View {
        switch model.stepKind(at: index) {
        case .scroll:
            Stepper(
                "Amount: \(model.scrollAmount(at: index))",
                value: Binding(
                    get: { model.scrollAmount(at: index) },
                    set: { model.setScrollAmount(at: index, amount: $0) }
                ),
                in: 1...100
            )
            .font(.caption)
            .controlSize(.small)
        case .arrow:
            HStack(spacing: 12) {
                Stepper(
                    "×\(model.arrowPresses(at: index))",
                    value: Binding(
                        get: { model.arrowPresses(at: index) },
                        set: { model.setArrow(at: index, presses: $0, interval: model.arrowInterval(at: index)) }
                    ),
                    in: 1...20
                )
                .font(.caption)
                Stepper(
                    "\(String(format: "%.1f", model.arrowInterval(at: index)))s",
                    value: Binding(
                        get: { model.arrowInterval(at: index) },
                        set: { model.setArrow(at: index, presses: model.arrowPresses(at: index), interval: $0) }
                    ),
                    in: 0...5,
                    step: 0.05
                )
                .font(.caption)
            }
        case .wait:
            Stepper(
                "\(String(format: "%.1f", model.waitSeconds(at: index)))s",
                value: Binding(
                    get: { model.waitSeconds(at: index) },
                    set: { model.setWait(at: index, seconds: $0) }
                ),
                in: 0.1...60,
                step: 0.5
            )
            .font(.caption)
        case .other:
            EmptyView()
        }
    }
}

struct EditorTargetRow: Equatable {
    var displayName: String
    var bundleID: String
    var classification: String
}

enum EditorStepKind {
    case scroll
    case arrow
    case wait
    case other
}

@MainActor
final class WorkflowEditorUIModel: ObservableObject {
    @Published var name: String = "Untitled"
    @Published var loopEnabled = false
    @Published var maxIterations = 1
    @Published var durationPreset: RunDurationPreset = .oneHour
    @Published var customDurationHours = 2
    @Published var shuffleSteps = true
    @Published var dwellMinSeconds: Double = 30
    @Published var dwellMaxSeconds: Double = 180
    @Published var pacingProfile: NavigationPacingProfile = .relaxed
    @Published var pacingCustom: NavigationPacingCustom = .default
    @Published var targetOrder: ReviewTargetOrder = .sequential
    @Published var loopTargets = true
    @Published var discoverRunningApps = true
    @Published var includeEditors = true
    @Published var includeBrowsers = true
    @Published var includeFinder = true
    @Published var includePreview = true
    @Published var includeOther = false
    @Published var refreshTargetsBetweenDwells = true
    @Published var workspacePath = ""
    @Published var fileDraft = ""
    @Published var tabDraft = ""
    @Published private(set) var filePaths: [String] = []
    @Published private(set) var tabLabels: [String] = []
    @Published var chromeEnabled = true
    @Published var chromeProfile: ChromeNavigationProfile = .generalWebsite
    @Published var chromeAllowedDomainsText = ""
    @Published var chromeBlockedDomainsText = ""
    @Published var chromeExternalPolicy: ChromeExternalDomainPolicy = .blocked
    @Published var chromeMaxDepth = 5
    @Published var chromeMaxPages = 20
    @Published var chromeMaxTimePerPageMinutes = 3
    @Published var chromeMaxScrollsPerPage = 40
    @Published var chromeCrawlDocumentation = true
    @Published var chromeCrawlSourceFiles = true
    @Published var chromeCrawlDirectories = true
    @Published var chromeCrawlIssues = false
    @Published var chromeGithubStrategy: GitHubCrawlStrategy = .breadthFirst
    @Published var chromeSelectedDirectoriesText = "app/\nsrc/\nroutes/\ntests/"
    @Published var chromePreferredKeywordsText = ""
    @Published var chromeExcludedPathsText = ""
    @Published var selectedRunningIndex = -1
    @Published var selectedClass: TargetAppClass = .generic
    @Published var selectedSavedName: String = ""
    @Published private(set) var savedWorkflowNames: [String] = []
    @Published private(set) var runningApps: [(bundleID: String, displayName: String)] = []
    @Published private(set) var targets: [EditorTargetRow] = []
    @Published private(set) var steps: [String] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var shouldDismiss = false
    /// True while copying store → UI so `onChange` handlers don’t rewrite the draft.
    @Published private(set) var isSyncingFromStore = false

    /// Called after a successful persist (parent shows transient confirmation).
    var onSuccessfulSave: ((String) -> Void)?

    private let viewModel: WorkflowEditorViewModel

    init(viewModel: WorkflowEditorViewModel) {
        self.viewModel = viewModel
        // Align new-editor defaults with Universal Workspace Navigation.
        targetOrder = .applicationPriority
        syncFromVM()
    }

    func refreshApps() {
        viewModel.refreshRunningApps()
        runningApps = viewModel.runningApps
        syncFromVM()
    }

    func refreshSavedNames() {
        savedWorkflowNames = viewModel.savedWorkflowNames()
        // Don’t clear selection here — that would fire Open→New and wipe the form.
        if !selectedSavedName.isEmpty, !savedWorkflowNames.contains(selectedSavedName) {
            isSyncingFromStore = true
            selectedSavedName = ""
            isSyncingFromStore = false
        }
    }

    func loadExisting(_ name: String) {
        guard viewModel.loadNamed(name) else {
            errorMessage = "Couldn’t load “\(name)”"
            refreshSavedNames()
            return
        }
        // Timed workflows always use the built-in fast random pool (ignore old slow steps).
        if viewModel.draft.maxDurationSeconds != nil || viewModel.draft.untilStopped {
            viewModel.applyTimedReviewSteps()
            viewModel.setShuffleSteps(true)
        }
        syncFromVM(selectedName: name)
        errorMessage = nil
    }

    func startNewWorkflow() {
        viewModel.resetDraft()
        syncFromVM(selectedName: "")
        errorMessage = nil
    }

    func pushName() {
        viewModel.setName(name)
    }

    func pushLoop() {
        pushDuration()
    }

    func pushDuration() {
        let customSeconds = Double(customDurationHours) * 3_600
        viewModel.setDurationPreset(durationPreset, customSeconds: customSeconds)
        pushReviewSettings()
        syncFromVM(selectedName: selectedSavedName)
    }

    func pushReviewSettings() {
        guard !isSyncingFromStore else { return }
        var settings = viewModel.draft.review
        settings.workspacePath = workspacePath
        settings.filePaths = filePaths
        settings.chromeTabLabels = tabLabels
        settings.dwellMinSeconds = dwellMinSeconds
        settings.dwellMaxSeconds = dwellMaxSeconds
        settings.pacing = pacingProfile
        settings.pacingCustom = pacingCustom
        settings.customIntervalSeconds = pacingCustom.scrollIntervalSeconds
        settings.targetOrder = targetOrder
        settings.loopTargets = loopTargets
        settings.discoverRunningApps = discoverRunningApps
        settings.discovery = DiscoveryScope(
            includeEditors: true,
            includeBrowsers: true,
            includeFinder: includeFinder,
            includePreview: includePreview,
            includeOther: includeOther
        )
        settings.refreshTargetsBetweenDwells = refreshTargetsBetweenDwells
        var chrome = settings.chrome
        chrome.enabled = chromeEnabled
        chrome.profile = chromeProfile
        chrome.allowedDomains = chromeAllowedDomainsText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        chrome.blockedDomains = chromeBlockedDomainsText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        chrome.externalDomainPolicy = chromeExternalPolicy
        chrome.maxDepth = chromeMaxDepth
        chrome.maxPages = chromeMaxPages
        chrome.maxTimePerPageSeconds = 600
        chrome.maxScrollsPerPage = 80
        chrome.crawlDocumentation = chromeCrawlDocumentation
        chrome.crawlSourceFiles = chromeCrawlSourceFiles
        chrome.crawlRepositoryDirectories = chromeCrawlDirectories
        chrome.crawlIssues = chromeCrawlIssues
        chrome.githubStrategy = chromeGithubStrategy
        chrome.selectedDirectories = chromeSelectedDirectoriesText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        chrome.preferredLinkKeywords = chromePreferredKeywordsText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        chrome.excludedPathPrefixes = chromeExcludedPathsText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        chrome.normalize()
        settings.chrome = chrome
        viewModel.setReviewSettings(settings)
        syncFromVM(selectedName: selectedSavedName)
    }

    func addFile() {
        viewModel.addReviewFilePath(fileDraft)
        fileDraft = ""
        syncFromVM()
    }

    func removeFile(at index: Int) {
        viewModel.removeReviewFilePath(at: index)
        syncFromVM()
    }

    func addTab() {
        viewModel.addChromeTabLabel(tabDraft)
        tabDraft = ""
        syncFromVM()
    }

    func removeTab(at index: Int) {
        viewModel.removeChromeTabLabel(at: index)
        syncFromVM()
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
        if durationPreset.isTimedReview {
            viewModel.applyTimedReviewSteps()
        }
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

    func stepKind(at index: Int) -> EditorStepKind {
        guard viewModel.draft.steps.indices.contains(index) else { return .other }
        switch viewModel.draft.steps[index].action {
        case .scroll: return .scroll
        case .arrowNavigate: return .arrow
        case .wait: return .wait
        default: return .other
        }
    }

    func scrollAmount(at index: Int) -> Int {
        guard viewModel.draft.steps.indices.contains(index),
              case .scroll(_, let amount) = viewModel.draft.steps[index].action
        else { return 1 }
        return amount
    }

    func setScrollAmount(at index: Int, amount: Int) {
        viewModel.setScrollAmount(at: index, amount: amount)
        syncFromVM()
    }

    func arrowPresses(at index: Int) -> Int {
        guard viewModel.draft.steps.indices.contains(index),
              case .arrowNavigate(_, let presses, _) = viewModel.draft.steps[index].action
        else { return 1 }
        return presses
    }

    func arrowInterval(at index: Int) -> Double {
        guard viewModel.draft.steps.indices.contains(index),
              case .arrowNavigate(_, _, let interval) = viewModel.draft.steps[index].action
        else { return 0.5 }
        return interval
    }

    func setArrow(at index: Int, presses: Int, interval: Double) {
        viewModel.setArrowNavigate(at: index, presses: presses, intervalSeconds: interval)
        syncFromVM()
    }

    func waitSeconds(at index: Int) -> Double {
        guard viewModel.draft.steps.indices.contains(index),
              case .wait(let seconds) = viewModel.draft.steps[index].action
        else { return 1 }
        return seconds
    }

    func setWait(at index: Int, seconds: Double) {
        viewModel.setWaitSeconds(at: index, seconds: seconds)
        syncFromVM()
    }

    func validateOnly() {
        pushName()
        pushDuration()
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
        pushDuration()
        var flow = WorkflowEditorSaveFlow()
        flow.apply(result: viewModel.save())
        errorMessage = flow.errorMessage
        if let name = flow.confirmationName {
            syncFromVM(selectedName: name)
            refreshSavedNames()
            onSuccessfulSave?(name)
        }
        shouldDismiss = flow.shouldDismiss
    }

    func acknowledgeDismissed() {
        shouldDismiss = false
    }

    private func syncFromVM(selectedName: String? = nil) {
        isSyncingFromStore = true
        defer { isSyncingFromStore = false }

        name = viewModel.draft.name
        loopEnabled = viewModel.draft.loopEnabled
        maxIterations = viewModel.draft.maxIterations
        durationPreset = RunDurationPreset.infer(
            maxDurationSeconds: viewModel.draft.maxDurationSeconds,
            untilStopped: viewModel.draft.untilStopped,
            loopEnabled: viewModel.draft.loopEnabled
        )
        shuffleSteps = viewModel.draft.shuffleSteps
        dwellMinSeconds = viewModel.draft.review.dwellMinSeconds
        dwellMaxSeconds = viewModel.draft.review.dwellMaxSeconds
        pacingProfile = viewModel.draft.review.pacing
        pacingCustom = viewModel.draft.review.pacingCustom
        targetOrder = viewModel.draft.review.targetOrder
        loopTargets = viewModel.draft.review.loopTargets
        discoverRunningApps = viewModel.draft.review.discoverRunningApps
        includeEditors = viewModel.draft.review.discovery.includeEditors
        includeBrowsers = viewModel.draft.review.discovery.includeBrowsers
        includeFinder = viewModel.draft.review.discovery.includeFinder
        includePreview = viewModel.draft.review.discovery.includePreview
        includeOther = viewModel.draft.review.discovery.includeOther
        refreshTargetsBetweenDwells = viewModel.draft.review.refreshTargetsBetweenDwells
        workspacePath = viewModel.draft.review.workspacePath
        filePaths = viewModel.draft.review.filePaths
        tabLabels = viewModel.draft.review.chromeTabLabels
        chromeEnabled = viewModel.draft.review.chrome.enabled
        chromeProfile = viewModel.draft.review.chrome.profile
        chromeAllowedDomainsText = viewModel.draft.review.chrome.allowedDomains.joined(separator: "\n")
        chromeBlockedDomainsText = viewModel.draft.review.chrome.blockedDomains.joined(separator: "\n")
        chromeExternalPolicy = viewModel.draft.review.chrome.externalDomainPolicy
        chromeMaxDepth = viewModel.draft.review.chrome.maxDepth
        chromeMaxPages = viewModel.draft.review.chrome.maxPages
        chromeMaxTimePerPageMinutes = max(
            1,
            Int((viewModel.draft.review.chrome.maxTimePerPageSeconds / 60).rounded())
        )
        chromeMaxScrollsPerPage = viewModel.draft.review.chrome.maxScrollsPerPage
        chromeCrawlDocumentation = viewModel.draft.review.chrome.crawlDocumentation
        chromeCrawlSourceFiles = viewModel.draft.review.chrome.crawlSourceFiles
        chromeCrawlDirectories = viewModel.draft.review.chrome.crawlRepositoryDirectories
        chromeCrawlIssues = viewModel.draft.review.chrome.crawlIssues
        chromeGithubStrategy = viewModel.draft.review.chrome.githubStrategy
        chromeSelectedDirectoriesText = viewModel.draft.review.chrome.selectedDirectories.joined(separator: "\n")
        chromePreferredKeywordsText = viewModel.draft.review.chrome.preferredLinkKeywords.joined(separator: "\n")
        chromeExcludedPathsText = viewModel.draft.review.chrome.excludedPathPrefixes.joined(separator: "\n")
        if durationPreset == .custom, let seconds = viewModel.draft.maxDurationSeconds {
            customDurationHours = max(1, Int((seconds / 3_600).rounded()))
        }
        if let selectedName {
            selectedSavedName = selectedName
        }
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
