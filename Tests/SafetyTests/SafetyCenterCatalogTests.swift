import Safety
import XCTest

final class SafetyCenterCatalogTests: XCTestCase {
    func testAllowlistCoversRequiredNavigationActions() {
        let titles = Set(SafetyCenterCatalog.allowedActions.map(\.title))
        for required in [
            "Focus application",
            "Focus window",
            "Switch tab",
            "Switch file",
            "Open existing file",
            "Scroll",
            "Page Up",
            "Page Down",
            "Arrow navigation",
            "Home",
            "End",
            "Click known page navigation element",
            "Page scrolling",
        ] {
            XCTAssertTrue(titles.contains(required), required)
        }
    }

    func testBlocklistCoversForbiddenCapabilities() {
        let titles = Set(SafetyCenterCatalog.blockedActions.map(\.title))
        for blocked in [
            "Arbitrary text input",
            "Source modification",
            "Delete",
            "Save",
            "Paste",
            "Submit",
            "Purchase",
            "Send",
            "Arbitrary shell commands",
            "Chrome browser UI",
            "Arbitrary screen-coordinate clicks",
        ] {
            XCTAssertTrue(titles.contains(blocked), blocked)
        }
    }

    func testPermissionGateDoesNotClaimBypass() {
        let copy = SafetyCenterCatalog.permissionGateCopy.lowercased()
        XCTAssertTrue(copy.contains("does not bypass"))
        XCTAssertFalse(copy.contains("bypasses macos"))
    }
}
