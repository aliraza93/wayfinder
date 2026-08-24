import Adapters
import Domain
import XCTest

final class ResolutionTests: XCTestCase {
    func testTargetClassMapsToExpectedAdapter() {
        XCTAssertEqual(AdapterResolver.resolve(.browser), .browser)
        XCTAssertEqual(AdapterResolver.resolve(.editor), .editor)
        XCTAssertEqual(AdapterResolver.resolve(.finder), .generic)
        XCTAssertEqual(AdapterResolver.resolve(.generic), .generic)
    }

    func testTargetAppResolutionUsesClassification() {
        let chrome = TargetApp(bundleID: "com.google.Chrome", classification: .browser)
        let code = TargetApp(bundleID: "com.microsoft.VSCode", classification: .editor)
        let finder = TargetApp(bundleID: "com.apple.finder", classification: .finder)
        XCTAssertEqual(AdapterResolver.resolve(chrome), .browser)
        XCTAssertEqual(AdapterResolver.resolve(code), .editor)
        XCTAssertEqual(AdapterResolver.resolve(finder), .generic)
    }

    func testGenericAdapterOnlyEmitsInertPrimitives() {
        let adapter = GenericAdapter()
        let scroll = adapter.selectPrimitive(for: .scroll(direction: .down, amount: 10))
        XCTAssertEqual(scroll, .scrollWheel(deltaY: -10))
        let page = adapter.selectPrimitive(for: .pageNavigate(.home))
        XCTAssertEqual(page, .inertKey(keyCode: 115))
        XCTAssertNil(adapter.selectPrimitive(for: .activateApp(bundleID: "x")))
        XCTAssertNil(adapter.rewrite(.returnToPrevious))
    }

    func testActionMapperCapsScrollForEachAdapter() {
        let target = TargetApp(bundleID: "com.apple.finder", classification: .finder)
        let rewritten = AdapterActionMapper.rewrite(
            .scroll(direction: .down, amount: 500),
            target: target,
            adapter: .generic
        )
        XCTAssertEqual(rewritten, .scroll(direction: .down, amount: GenericAdapter.maxScrollAmount))
    }
}
