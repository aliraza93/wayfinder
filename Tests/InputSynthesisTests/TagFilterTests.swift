import CoreEngine
import XCTest
@testable import InputSynthesis

final class TagFilterTests: XCTestCase {
    func testMonitorIgnoresTaggedEvents() async {
        let monitor = UserSovereigntyMonitor()
        let taggedScroll = IncomingInputEvent(carriesSelfTag: true, kind: .scroll)
        let taggedKey = IncomingInputEvent(carriesSelfTag: true, kind: .key)

        XCTAssertTrue(UserSovereigntyMonitor.shouldIgnore(taggedScroll))
        XCTAssertFalse(UserSovereigntyMonitor.shouldSignalIntervention(taggedScroll))

        await monitor.consider(taggedScroll)
        await monitor.consider(taggedKey)
        let halt = await monitor.shouldHalt()
        XCTAssertFalse(halt)
    }

    func testMonitorFiresOnUntaggedUserInput() async {
        let monitor = UserSovereigntyMonitor()
        let realScroll = IncomingInputEvent(carriesSelfTag: false, kind: .scroll)

        XCTAssertTrue(UserSovereigntyMonitor.shouldSignalIntervention(realScroll))
        await monitor.consider(realScroll)
        let halt = await monitor.shouldHalt()
        XCTAssertTrue(halt)
    }

    func testHotKeyStopViaRequestStop() async {
        let monitor = UserSovereigntyMonitor()
        await monitor.requestStop()
        let halt = await monitor.shouldHalt()
        XCTAssertTrue(halt)
    }

    func testSelfEventTagUserDataRoundTrip() {
        XCTAssertTrue(SelfEventTag.isTagged(userData: SelfEventTag.userDataValue))
        XCTAssertFalse(SelfEventTag.isTagged(userData: 0))
        XCTAssertFalse(SelfEventTag.isTagged(userData: 12345))
    }

    func testMapperClassifiesScrollAndKey() {
        // Construct lightweight CGEvents when possible; fall back to tag helpers.
        if let scroll = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ) {
            SelfEventTag.apply(to: scroll)
            let mapped = SovereigntyEventMapper.map(scroll)
            XCTAssertEqual(mapped?.carriesSelfTag, true)
            XCTAssertEqual(mapped?.kind, .scroll)
        }

        if let key = CGEvent(keyboardEventSource: nil, virtualKey: 125, keyDown: true) {
            let mapped = SovereigntyEventMapper.map(key)
            XCTAssertEqual(mapped?.carriesSelfTag, false)
            XCTAssertEqual(mapped?.kind, .key)
        }
    }
}
