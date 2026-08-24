import XCTest
@testable import Domain

final class SmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertTrue(true)
        XCTAssertEqual(DomainModule.name, "Domain")
    }
}
