import WaypointAccessibility
import CoreEngine
import Domain
import XCTest

private final class FakeAXProbe: AXProbe, @unchecked Sendable {
    var frontmost: String?
    var windowExists: Bool = true
    var focusedElement: String?
    /// Optional sequence consumed on each frontmost read (for mid-debounce changes).
    var frontmostSequence: [String?] = []

    func frontmostAppBundleID() -> String? {
        if !frontmostSequence.isEmpty {
            let next = frontmostSequence.removeFirst()
            frontmost = next
            return next
        }
        return frontmost
    }

    func focusedWindowExists() -> Bool { windowExists }

    func focusedElementBundleID() -> String? {
        focusedElement ?? frontmost
    }
}

final class FocusGuardTests: XCTestCase {
    private let target = TargetApp(bundleID: "com.google.Chrome", classification: .browser)

    func testStableFrontmostReturnsOk() async {
        let probe = FakeAXProbe()
        probe.frontmost = "com.google.Chrome"
        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.05) }
        let guard_ = FocusGuard(probe: probe, timing: timing, debounceSeconds: 0.15)

        let result = await guard_.assert(target: target)
        XCTAssertEqual(result, .ok)
    }

    func testDifferentAppReturnsChanged() async {
        let probe = FakeAXProbe()
        probe.frontmost = "com.apple.finder"
        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.05) }
        let guard_ = FocusGuard(probe: probe, timing: timing, debounceSeconds: 0.15)

        let result = await guard_.assert(target: target)
        XCTAssertEqual(result, .changed)
    }

    func testMissingFrontmostReturnsLost() async {
        let probe = FakeAXProbe()
        probe.frontmost = nil
        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.05) }
        let guard_ = FocusGuard(probe: probe, timing: timing, debounceSeconds: 0.15)

        let result = await guard_.assert(target: target)
        XCTAssertEqual(result, .lost)
    }

    func testChangeDuringDebounceReturnsChanged() async {
        let probe = FakeAXProbe()
        probe.frontmost = "com.google.Chrome"
        // Later reads switch away before debounce completes.
        probe.frontmostSequence = [
            "com.google.Chrome",
            "com.microsoft.VSCode",
            "com.microsoft.VSCode",
            "com.microsoft.VSCode",
        ]
        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.05) }
        let guard_ = FocusGuard(probe: probe, timing: timing, debounceSeconds: 0.15)

        let result = await guard_.assert(target: target)
        XCTAssertEqual(result, .changed)
    }

    func testCoarseAXForwardsProbeWithoutExtraReads() {
        let probe = FakeAXProbe()
        probe.frontmost = "com.apple.finder"
        probe.windowExists = true
        probe.focusedElement = "com.apple.finder"
        let coarse = CoarseAX(probe: probe)

        XCTAssertEqual(coarse.frontmostAppBundleID(), "com.apple.finder")
        XCTAssertTrue(coarse.focusedWindowExists())
        XCTAssertEqual(coarse.focusedElementBundleID(), "com.apple.finder")
    }
}
