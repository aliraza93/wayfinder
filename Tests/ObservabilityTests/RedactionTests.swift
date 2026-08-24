import Foundation
import Observability
import XCTest

/// Enforces the content-free log contract: only timestamp, actionKind, targetBundleID, result.
final class RedactionTests: XCTestCase {
    func testRunEventHasOnlyAllowedFieldsInJSONL() {
        let recorder = RunRecorder()
        let event = RunEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            actionKind: "scroll",
            targetBundleID: "com.google.Chrome",
            result: .completed
        )
        recorder.append(event)

        let line = recorder.jsonl()
        XCTAssertFalse(line.isEmpty)

        let data = Data(line.utf8)
        let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let keys = Set(object.keys)
        XCTAssertTrue(keys.isSubset(of: Set(["timestamp", "actionKind", "targetBundleID", "result", "identity"])))
        XCTAssertTrue(keys.isSuperset(of: Set(["timestamp", "actionKind", "targetBundleID", "result"])))
    }

    func testJSONLRejectsEmbeddingDocumentContentAsActionKindShape() {
        // Recorder API has no content parameter — only structured fields.
        // Guard: actionKind must remain a short label, not free-form document text.
        let recorder = RunRecorder()
        recorder.append(
            RunEvent(
                timestamp: Date(),
                actionKind: "pageNavigate",
                targetBundleID: "com.microsoft.VSCode",
                result: .completed
            )
        )
        let line = recorder.jsonl()
        XCTAssertFalse(line.contains("\n"))
        XCTAssertFalse(line.lowercased().contains("password"))
        XCTAssertFalse(line.contains("func "))
        XCTAssertTrue(line.contains("\"actionKind\":\"pageNavigate\""))
        XCTAssertTrue(line.contains("\"targetBundleID\":\"com.microsoft.VSCode\""))
        XCTAssertTrue(line.contains("\"result\":\"completed\""))
    }

    func testSnapshotDoesNotExposeExtraPayload() {
        let recorder = RunRecorder()
        recorder.append(
            RunEvent(
                timestamp: Date(),
                actionKind: "wait",
                targetBundleID: "com.apple.finder",
                result: .skipped
            )
        )
        let snap = recorder.snapshot()
        XCTAssertEqual(snap.count, 1)
        XCTAssertEqual(snap[0].actionKind, "wait")
        XCTAssertEqual(snap[0].targetBundleID, "com.apple.finder")
        XCTAssertEqual(snap[0].result, .skipped)
    }
}
