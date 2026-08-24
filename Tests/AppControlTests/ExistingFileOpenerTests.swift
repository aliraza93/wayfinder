import AppControl
import XCTest

final class ExistingFileOpenerTests: XCTestCase {
    func testEmptyPathRejected() {
        XCTAssertThrowsError(try ExistingFileOpener.resolvedExistingFileURL(path: "  ")) { error in
            XCTAssertEqual(error as? ExistingFileOpenerError, .emptyPath)
        }
    }

    func testMissingFileRejected() {
        XCTAssertThrowsError(
            try ExistingFileOpener.resolvedExistingFileURL(path: "/tmp/waypoint-no-such-file-\(UUID().uuidString).txt")
        ) { error in
            guard case .fileNotFound = error as? ExistingFileOpenerError else {
                return XCTFail("expected fileNotFound")
            }
        }
    }

    func testExistingFileResolves() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("waypoint-existing-\(UUID().uuidString).txt")
            .path
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let url = try ExistingFileOpener.resolvedExistingFileURL(path: path)
        XCTAssertEqual(url.path, path)
    }
}
