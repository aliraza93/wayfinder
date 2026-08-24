import Safety
import XCTest

final class AllowlistTests: XCTestCase {
    private let policy = SafetyPolicy()

    func testAllowlistedKeysAreAllowed() {
        for keyCode in InertKeyAllowlist.keyCodes {
            XCTAssertEqual(
                policy.validateKey(keyCode),
                .allow,
                "expected allow for key \(keyCode)"
            )
            XCTAssertNoThrow(try policy.requireAllowedKey(keyCode))
        }
    }

    func testAllowlistContentsMatchInertNavigationSet() {
        let expected: Set<UInt16> = [123, 124, 125, 126, 116, 121, 115, 119]
        XCTAssertEqual(InertKeyAllowlist.keyCodes, expected)
        XCTAssertEqual(InertKeyAllowlist.keyCodes.count, 8)
    }

    func testNonAllowlistedKeysDenied() {
        // Character / editing / chord-related codes that must never be synthesized.
        let denied: [UInt16] = [
            0, // A
            1, // S
            36, // Return
            51, // Delete
            53, // Escape
            49, // Space
            55, // Command
            56, // Shift
            59, // Control
            58, // Option
            48, // Tab
        ]

        for keyCode in denied {
            XCTAssertFalse(InertKeyAllowlist.contains(keyCode))
            let decision = policy.validateKey(keyCode)
            guard case .deny = decision else {
                return XCTFail("expected deny for key \(keyCode), got \(decision)")
            }
        }
    }

    func testRequireAllowedKeySurfacesForbiddenActionError() {
        XCTAssertThrowsError(try policy.requireAllowedKey(36)) { error in
            guard let forbidden = error as? ForbiddenActionError else {
                return XCTFail("expected ForbiddenActionError, got \(error)")
            }
            XCTAssertEqual(forbidden.keyCode, 36)
            XCTAssertTrue(forbidden.reason.contains("allowlist"))
        }
    }
}
