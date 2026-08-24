import Config
import Domain
import XCTest

final class MigrationTests: XCTestCase {
    func testV1ToV2UpgradesClassKeyToClassification() throws {
        let v1JSON = """
        {
          "schemaVersion": 1,
          "workflows": [
            {
              "name": "Legacy",
              "targets": [
                {"bundleID": "com.google.Chrome", "class": "browser"}
              ],
              "steps": [
                {
                  "action": {"type": "scroll", "direction": "up", "amount": 2},
                  "timeoutSeconds": 1,
                  "retryPolicy": {"maxRetries": 0},
                  "onError": "abort"
                }
              ],
              "loop": {"enabled": false, "maxIterations": 1}
            }
          ]
        }
        """

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaypointMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = ConfigStore(baseDirectory: temp)
        let document = try store.decodeDocument(from: Data(v1JSON.utf8))

        XCTAssertEqual(document.schemaVersion, SchemaVersion.current)
        XCTAssertEqual(document.workflows.count, 1)
        XCTAssertEqual(document.workflows[0].targets[0].classification, .browser)
        XCTAssertEqual(document.workflows[0].targets[0].bundleID, "com.google.Chrome")
        XCTAssertEqual(
            document.workflows[0].steps[0].action,
            .scroll(direction: .up, amount: 2)
        )
    }

    func testUnsupportedFutureVersionRejected() {
        var root: [String: Any] = [
            "schemaVersion": SchemaVersion.current + 1,
            "workflows": [],
        ]
        XCTAssertThrowsError(try Migration.migrateToCurrent(&root)) { error in
            guard case ConfigError.unsupportedSchemaVersion(let version) = error else {
                return XCTFail("expected unsupportedSchemaVersion, got \(error)")
            }
            XCTAssertEqual(version, SchemaVersion.current + 1)
        }
    }
}
