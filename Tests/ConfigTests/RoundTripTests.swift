import Config
import Domain
import XCTest

final class RoundTripTests: XCTestCase {
    func testScrollActionPinnedJSONShape() throws {
        let action = ActionKind.scroll(direction: .down, amount: 3)
        let data = try JSONEncoder().encode(action)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(object["type"] as? String, "scroll")
        XCTAssertEqual(object["direction"] as? String, "down")
        XCTAssertEqual(object["amount"] as? Int, 3)
        XCTAssertEqual(object.count, 3)

        let decoded = try JSONDecoder().decode(ActionKind.self, from: data)
        XCTAssertEqual(decoded, action)
    }

    func testDocumentRoundTripEquality() throws {
        let document = sampleDocument()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        let decoded = try JSONDecoder().decode(WorkflowConfigDocument.self, from: data)
        XCTAssertEqual(decoded, document)
    }

    func testConfigStoreRoundTripUsesTempDirectory() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaypointConfigTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = ConfigStore(baseDirectory: temp)
        let document = sampleDocument()
        try store.save(document)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.workflowsFileURL.path))
        XCTAssertFalse(store.workflowsFileURL.path.contains("Application Support"))

        let loaded = try store.load()
        XCTAssertEqual(loaded, document)
        XCTAssertEqual(loaded.schemaVersion, SchemaVersion.current)
    }

    func testUnknownKeyRejected() throws {
        let json = """
        {
          "schemaVersion": 2,
          "workflows": [],
          "extra": true
        }
        """
        let store = ConfigStore(baseDirectory: FileManager.default.temporaryDirectory)
        XCTAssertThrowsError(try store.decodeDocument(from: Data(json.utf8))) { error in
            guard case ConfigError.unknownKey(let path, let key) = error else {
                return XCTFail("expected unknownKey, got \(error)")
            }
            XCTAssertEqual(path, "$")
            XCTAssertEqual(key, "extra")
        }
    }

    func testUnknownActionKeyRejected() throws {
        let json = """
        {
          "schemaVersion": 2,
          "workflows": [{
            "name": "w",
            "targets": [{"bundleID": "com.apple.finder", "classification": "finder"}],
            "steps": [{
              "action": {"type": "scroll", "direction": "down", "amount": 1, "speed": "fast"},
              "timeoutSeconds": 1,
              "retryPolicy": {"maxRetries": 0},
              "onError": "abort"
            }],
            "loop": {"enabled": false, "maxIterations": 1}
          }]
        }
        """
        let store = ConfigStore(baseDirectory: FileManager.default.temporaryDirectory)
        XCTAssertThrowsError(try store.decodeDocument(from: Data(json.utf8))) { error in
            guard case ConfigError.unknownKey(_, let key) = error else {
                return XCTFail("expected unknownKey, got \(error)")
            }
            XCTAssertEqual(key, "speed")
        }
    }

    private func sampleDocument() -> WorkflowConfigDocument {
        WorkflowConfigDocument(
            schemaVersion: SchemaVersion.current,
            workflows: [
                Workflow(
                    name: "Browse docs",
                    targets: [
                        TargetApp(bundleID: "com.google.Chrome", classification: .browser),
                        TargetApp(bundleID: "com.microsoft.VSCode", classification: .editor),
                    ],
                    steps: [
                        Step(
                            action: .activateApp(bundleID: "com.google.Chrome"),
                            timeoutSeconds: 5,
                            retryPolicy: RetryPolicy(maxRetries: 1),
                            onError: .abort
                        ),
                        Step(
                            action: .scroll(direction: .down, amount: 3),
                            timeoutSeconds: 2,
                            retryPolicy: RetryPolicy(maxRetries: 0),
                            onError: .skip
                        ),
                        Step(
                            action: .pageNavigate(.pageDown),
                            timeoutSeconds: 2,
                            retryPolicy: RetryPolicy(maxRetries: 0),
                            onError: .abort
                        ),
                        Step(
                            action: .wait(seconds: 0.5),
                            timeoutSeconds: 1,
                            retryPolicy: RetryPolicy(maxRetries: 0),
                            onError: .abort
                        ),
                        Step(
                            action: .returnToPrevious,
                            timeoutSeconds: 5,
                            retryPolicy: RetryPolicy(maxRetries: 0),
                            onError: .abort
                        ),
                    ],
                    loop: LoopSettings(enabled: true, maxIterations: 3, maxDurationSeconds: 60)
                ),
            ]
        )
    }
}
