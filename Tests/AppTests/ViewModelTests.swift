import AppPresentation
import Config
import Domain
import Observability
import Permissions
import Safety
import XCTest

final class ViewModelTests: XCTestCase {
    func testEditorRejectsEmptyName() {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaypointEditor-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = ConfigStore(baseDirectory: temp)
        let vm = WorkflowEditorViewModel(store: store)
        vm.setName("   ")
        vm.addTarget(bundleID: "com.google.Chrome", displayName: "Chrome", classification: .browser)
        vm.addStep(from: .scrollDown)
        XCTAssertEqual(vm.validateDraft(), .failure(.emptyName))
    }

    func testEditorRequiresTargetsAndSteps() {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaypointEditor2-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = ConfigStore(baseDirectory: temp)
        let vm = WorkflowEditorViewModel(store: store)
        vm.setName("Demo")
        XCTAssertEqual(vm.validateDraft(), .failure(.noTargets))
        vm.addTarget(bundleID: "com.google.Chrome", displayName: "Chrome", classification: .browser)
        XCTAssertEqual(vm.validateDraft(), .failure(.noSteps))
    }

    func testEditorSavesLegalWorkflowAndBlocksMutatingTags() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaypointEditor3-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = ConfigStore(baseDirectory: temp)
        let vm = WorkflowEditorViewModel(store: store)
        vm.setName("UI scroll")
        vm.addTarget(bundleID: "com.google.Chrome", displayName: "Chrome", classification: .browser)
        vm.addStep(from: .scrollDown)
        vm.addStep(from: .wait)
        vm.setLoop(enabled: true, maxIterations: 2, maxDurationSeconds: nil)

        let saved = vm.save()
        guard case .success(let workflow) = saved else {
            return XCTFail("expected save success, got \(saved)")
        }
        XCTAssertEqual(workflow.name, "UI scroll")
        XCTAssertEqual(workflow.steps.count, 2)

        let loaded = try store.load()
        XCTAssertEqual(loaded.workflows.count, 1)

        // Safety denial path: custom policy that denies everything.
        let denying = WorkflowEditorViewModel(
            store: store,
            draft: WorkflowDraft(workflow: workflow),
            safety: SafetyPolicy { _ in
                CapabilityTags(
                    mutatesText: true,
                    requiresFocusGuard: true,
                    verifiable: false,
                    primitive: .scrollWheel
                )
            }
        )
        let denied = denying.validateDraft()
        guard case .failure(.safety) = denied else {
            return XCTFail("expected safety failure, got \(denied)")
        }
    }

    func testActionPaletteItemsAreNonMutating() {
        for item in ActionPaletteItem.allCases {
            let action = item.makeAction(activateBundleID: "com.google.Chrome")
            XCTAssertFalse(action.capabilityTags.mutatesText, item.rawValue)
        }
    }

    func testOnboardingTransitions() {
        var state: PermissionState = .denied
        let vm = OnboardingViewModel(
            initial: .denied,
            refreshState: { state },
            requestAccess: {
                state = .denied
                return state
            },
            openSettings: {}
        )
        XCTAssertTrue(vm.showsOnboarding)
        XCTAssertEqual(vm.statusTitle, "Accessibility required")
        state = .granted
        vm.refresh()
        XCTAssertFalse(vm.showsOnboarding)
        XCTAssertEqual(vm.statusTitle, "Accessibility granted")
    }

    func testTimelineMapsRecorderEvents() {
        let recorder = RunRecorder()
        recorder.append(
            RunEvent(
                timestamp: Date(timeIntervalSince1970: 1),
                actionKind: "scroll",
                targetBundleID: "com.google.Chrome",
                result: .completed
            )
        )
        let vm = TimelineViewModel()
        vm.append(from: recorder)
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows[0].actionKind, "scroll")
        XCTAssertEqual(vm.rows[0].targetBundleID, "com.google.Chrome")
        XCTAssertEqual(vm.rows[0].result, "completed")
    }

    func testRunSessionCanStartGates() {
        let vm = RunSessionViewModel()
        vm.updateNames(["a"])
        XCTAssertFalse(vm.canStart)
        vm.updateAccessibilityGranted(true)
        XCTAssertTrue(vm.canStart)
        vm.markRunning(workflowName: "a", steps: [
            Step(
                action: .scroll(direction: .down, amount: 1),
                timeoutSeconds: 1,
                retryPolicy: RetryPolicy(maxRetries: 0),
                onError: .abort
            ),
        ])
        XCTAssertFalse(vm.canStart)
        XCTAssertTrue(vm.live.isRunning)
        XCTAssertTrue(vm.live.summaryLine.contains("Running"))
        vm.markIdle(eventCount: 3)
        XCTAssertTrue(vm.canStart)
    }

    func testHonestCopyPresent() {
        XCTAssertFalse(HonestCopy.tagline.isEmpty)
        XCTAssertTrue(HonestCopy.neverDoes.lowercased().contains("never"))
    }
}
