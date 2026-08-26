import Adapters
import Domain
import XCTest

final class BrowserProbeTests: XCTestCase {
    func testProbeSuccessSelectsScrollWheelAndPageKeys() {
        var adapter = BrowserAdapter(
            probe: FixedBrowserProbe(result: .dependable)
        )
        adapter.prepare(target: chromeTarget)
        XCTAssertFalse(adapter.usedDegradedFallback)
        XCTAssertEqual(adapter.capabilities, .dependable)

        let scroll = adapter.selectPrimitive(for: .scroll(direction: .down, amount: 40))
        XCTAssertEqual(scroll, .scrollWheel(deltaY: -40))

        let page = adapter.selectPrimitive(for: .pageNavigate(.pageDown))
        XCTAssertEqual(page, .inertKey(keyCode: 121))

        let home = adapter.selectPrimitive(for: .pageNavigate(.home))
        XCTAssertEqual(home, .inertKey(keyCode: 115))
    }

    func testProbeFailureDegradesToDependableWithoutError() {
        var adapter = BrowserAdapter(probe: FixedBrowserProbe(result: nil))
        adapter.prepare(target: chromeTarget)
        XCTAssertTrue(adapter.usedDegradedFallback)
        XCTAssertEqual(adapter.capabilities, .dependable)

        // Degraded path still selects inert primitives — never throws / never tabs.
        XCTAssertEqual(
            adapter.selectPrimitive(for: .scroll(direction: .up, amount: 10)),
            .scrollWheel(deltaY: 10)
        )
        XCTAssertEqual(
            adapter.selectPrimitive(for: .pageNavigate(.end)),
            .inertKey(keyCode: 119)
        )
    }

    func testPageKeysUnreliableDegradesPageToScrollWheel() {
        var adapter = BrowserAdapter(
            probe: FixedBrowserProbe(
                result: BrowserCapabilities(scrollViaWheel: true, pageViaKeys: false)
            )
        )
        adapter.prepare(target: chromeTarget)
        XCTAssertFalse(adapter.usedDegradedFallback)

        XCTAssertEqual(
            adapter.selectPrimitive(for: .pageNavigate(.pageDown)),
            .scrollWheel(deltaY: -Int32(BrowserAdapter.pageAsScrollAmount))
        )
        XCTAssertEqual(
            adapter.rewrite(.pageNavigate(.pageUp)),
            .scroll(direction: .up, amount: BrowserAdapter.pageAsScrollAmount)
        )
    }

    func testScrollWheelUnreliableDegradesToArrowKeys() {
        var adapter = BrowserAdapter(
            probe: FixedBrowserProbe(
                result: BrowserCapabilities(scrollViaWheel: false, pageViaKeys: true)
            )
        )
        adapter.prepare(target: chromeTarget)

        XCTAssertEqual(
            adapter.selectPrimitive(for: .scroll(direction: .down, amount: 5)),
            .inertKey(keyCode: 125)
        )
        XCTAssertEqual(
            adapter.selectPrimitive(for: .scroll(direction: .up, amount: 5)),
            .inertKey(keyCode: 126)
        )
    }

    func testScrollAmountIsCapped() {
        var adapter = BrowserAdapter(probe: FixedBrowserProbe(result: .dependable))
        adapter.prepare(target: chromeTarget)

        let over = BrowserAdapter.maxScrollAmount + 50
        XCTAssertEqual(
            adapter.selectPrimitive(for: .scroll(direction: .down, amount: over)),
            .scrollWheel(deltaY: -Int32(BrowserAdapter.maxScrollAmount))
        )
        XCTAssertEqual(
            adapter.rewrite(.scroll(direction: .down, amount: over)),
            .scroll(direction: .down, amount: BrowserAdapter.maxScrollAmount)
        )
    }

    func testChromeCoarseProbeFailsWithoutWindowThenDegrades() {
        let probe = ChromeCoarseProbe(windowExists: { false })
        var adapter = BrowserAdapter(probe: probe)
        adapter.prepare(target: chromeTarget)
        XCTAssertTrue(adapter.usedDegradedFallback)
        XCTAssertEqual(adapter.capabilities, .dependable)
    }

    func testChromeCoarseProbeSucceedsForChromeWithWindow() {
        let probe = ChromeCoarseProbe(windowExists: { true })
        var adapter = BrowserAdapter(probe: probe)
        adapter.prepare(target: chromeTarget)
        XCTAssertFalse(adapter.usedDegradedFallback)
        XCTAssertEqual(adapter.capabilities, .dependable)
    }

    func testNoTabSwitchPrimitiveExists() {
        var adapter = BrowserAdapter(probe: FixedBrowserProbe(result: .dependable))
        adapter.prepare(target: chromeTarget)
        // Tab switch is a navigation chord rewritten for RealExecutor — not an inert BrowserPrimitive.
        XCTAssertNil(adapter.selectPrimitive(for: .switchTab(direction: .next)))
        XCTAssertEqual(adapter.rewrite(.switchTab(direction: .next)), .switchTab(direction: .next))
        XCTAssertNil(adapter.selectPrimitive(for: .wait(seconds: 1)))
        XCTAssertNil(adapter.selectPrimitive(for: .activateApp(bundleID: "com.google.Chrome")))
        XCTAssertNil(adapter.rewrite(.switchWindow(direction: .next)))
    }

    func testRewriteRefusesBrowserUIActions() {
        var adapter = BrowserAdapter(probe: FixedBrowserProbe(result: .dependable))
        adapter.prepare(target: chromeTarget)
        XCTAssertEqual(adapter.rewrite(.contentClick), .wait(seconds: 0.05))
        XCTAssertEqual(adapter.rewrite(.browserBack), .wait(seconds: 0.05))
        if case .activateWebNavTarget = adapter.rewrite(
            .activateWebNavTarget(identity: "https://example.com/docs", x: 10, y: 20)
        ) {
            // allowed through — RealExecutor still validates WebArea
        } else {
            XCTFail("activateWebNavTarget should remain for page-content clicks")
        }
    }

    private var chromeTarget: TargetApp {
        TargetApp(bundleID: "com.google.Chrome", classification: .browser)
    }
}
