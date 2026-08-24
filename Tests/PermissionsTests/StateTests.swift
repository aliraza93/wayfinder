import Permissions
import XCTest

private final class FakeTrustProbe: TrustProbe, @unchecked Sendable {
    var trusted: Bool
    private(set) var promptCalls = 0
    private(set) var silentCalls = 0

    init(trusted: Bool) {
        self.trusted = trusted
    }

    func isTrusted(prompt: Bool) -> Bool {
        if prompt {
            promptCalls += 1
        } else {
            silentCalls += 1
        }
        return trusted
    }
}

final class StateTests: XCTestCase {
    func testStartsUnknownThenRefreshDenied() {
        let probe = FakeTrustProbe(trusted: false)
        var opened: [URL] = []
        let permission = AccessibilityPermission(probe: probe) { opened.append($0) }

        XCTAssertEqual(permission.state, .unknown)
        XCTAssertEqual(permission.refresh(), .denied)
        XCTAssertEqual(permission.state, .denied)
        XCTAssertEqual(probe.promptCalls, 0)
        XCTAssertEqual(probe.silentCalls, 1)
        XCTAssertTrue(opened.isEmpty)
    }

    func testRefreshGrantedWithoutPrompt() {
        let probe = FakeTrustProbe(trusted: true)
        let permission = AccessibilityPermission(probe: probe) { _ in }
        XCTAssertEqual(permission.refresh(), .granted)
        XCTAssertEqual(probe.promptCalls, 0)
    }

    func testRequestPromptsOnceThenDeepLinksOnDenial() {
        let probe = FakeTrustProbe(trusted: false)
        var opened: [URL] = []
        let permission = AccessibilityPermission(probe: probe) { opened.append($0) }

        XCTAssertEqual(permission.requestAccess(), .denied)
        XCTAssertEqual(probe.promptCalls, 1)
        XCTAssertEqual(opened, [AccessibilityPermission.accessibilitySettingsURL])
        XCTAssertTrue(permission.hasPrompted)

        opened.removeAll()
        probe.trusted = false
        XCTAssertEqual(permission.requestAccess(), .denied)
        // Second call must not re-prompt — only deep-link + silent refresh.
        XCTAssertEqual(probe.promptCalls, 1)
        XCTAssertEqual(opened, [AccessibilityPermission.accessibilitySettingsURL])
        XCTAssertGreaterThanOrEqual(probe.silentCalls, 1)
    }

    func testRequestGrantedDoesNotOpenSettings() {
        let probe = FakeTrustProbe(trusted: true)
        var opened: [URL] = []
        let permission = AccessibilityPermission(probe: probe) { opened.append($0) }

        XCTAssertEqual(permission.requestAccess(), .granted)
        XCTAssertEqual(probe.promptCalls, 1)
        XCTAssertTrue(opened.isEmpty)
    }

    func testForegroundRecheckFlipsToGrantedWithoutRelaunch() {
        let probe = FakeTrustProbe(trusted: false)
        var opened: [URL] = []
        let permission = AccessibilityPermission(probe: probe) { opened.append($0) }

        _ = permission.requestAccess()
        XCTAssertEqual(permission.state, .denied)

        // User toggles in System Settings; app becomes active and re-checks.
        probe.trusted = true
        XCTAssertEqual(permission.refresh(), .granted)
        XCTAssertEqual(permission.state, .granted)
        // Still only one prompt attempt overall.
        XCTAssertEqual(probe.promptCalls, 1)
    }

    func testSettingsURLPointsAtAccessibilityPrivacyPane() {
        let url = AccessibilityPermission.accessibilitySettingsURL.absoluteString
        XCTAssertTrue(url.contains("Privacy_Accessibility"))
        XCTAssertTrue(url.hasPrefix("x-apple.systempreferences:"))
    }
}
