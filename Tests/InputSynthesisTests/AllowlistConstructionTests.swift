import CoreEngine
import Domain
import Foundation
import Safety
import WaypointAccessibility
import XCTest
@testable import InputSynthesis

final class AllowlistConstructionTests: XCTestCase {
    func testOnlyAllowlistedKeysCanBeBuilt() {
        for code in InertKeyAllowlist.keyCodes {
            XCTAssertNotNil(InertKeyPrimitive.make(keyCode: code), "key \(code) should build")
        }

        let denied: [UInt16] = [0, 36, 51, 53, 49, 55, 59, 48] // A, Return, Delete, Esc, Space, Cmd, Ctrl, Tab
        for code in denied {
            XCTAssertNil(InertKeyPrimitive.make(keyCode: code), "key \(code) must not build")
        }
    }

    func testScrollPrimitiveRejectsZeroDelta() {
        XCTAssertNil(ScrollPrimitive.make(deltaY: 0))
        XCTAssertNotNil(ScrollPrimitive.make(deltaY: 3))
        XCTAssertNotNil(ScrollPrimitive.make(deltaY: -2))
    }

    func testEventSynthEmitsOnlyAfterSafetyAndFocus() async throws {
        let probe = StaticAXProbe(bundleID: "com.google.Chrome")
        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.05) }
        let focus = FocusGuard(probe: probe, timing: timing, debounceSeconds: 0.1)
        let poster = RecordingEventPoster()
        let monitor = UserSovereigntyMonitor(secureInput: NullSecureInputProbe())
        let synth = EventSynth(
            focusGuard: focus,
            poster: poster,
            sovereignty: monitor
        )
        let target = TargetApp(bundleID: "com.google.Chrome", classification: .browser)
        let scroll = ScrollPrimitive.make(deltaY: 5)!

        try await synth.emitScroll(scroll, action: .scroll(direction: .down, amount: 5), target: target)

        XCTAssertEqual(poster.events.count, 1)
        XCTAssertEqual(poster.events[0], SynthesizedEvent(kind: .scroll(deltaY: 5), tagged: true))
    }

    func testEventSynthBlocksWhenFocusChanged() async {
        let probe = StaticAXProbe(bundleID: "com.apple.finder")
        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.05) }
        let focus = FocusGuard(probe: probe, timing: timing, debounceSeconds: 0.1)
        let poster = RecordingEventPoster()
        let monitor = UserSovereigntyMonitor()
        let synth = EventSynth(focusGuard: focus, poster: poster, sovereignty: monitor)
        let target = TargetApp(bundleID: "com.google.Chrome", classification: .browser)

        do {
            try await synth.emitScroll(
                ScrollPrimitive.make(deltaY: 1)!,
                action: .scroll(direction: .down, amount: 1),
                target: target
            )
            XCTFail("expected focus failure")
        } catch let error as EventSynthError {
            XCTAssertEqual(error, .focusNotOk(.changed))
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(poster.events.isEmpty)
    }

    func testSecureInputSurfacesPrecondition() async {
        let probe = StaticAXProbe(bundleID: "com.google.Chrome")
        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.05) }
        let focus = FocusGuard(probe: probe, timing: timing, debounceSeconds: 0.1)
        let poster = RecordingEventPoster()
        let monitor = UserSovereigntyMonitor(secureInput: AlwaysSecureInputProbe())
        let synth = EventSynth(focusGuard: focus, poster: poster, sovereignty: monitor)
        let target = TargetApp(bundleID: "com.google.Chrome", classification: .browser)

        do {
            try await synth.emitScroll(
                ScrollPrimitive.make(deltaY: 1)!,
                action: .scroll(direction: .down, amount: 1),
                target: target
            )
            XCTFail("expected secure input error")
        } catch {
            XCTAssertEqual(error as? EventSynthError, .secureInputEnabled)
        }
        XCTAssertTrue(poster.events.isEmpty)
    }
}

private struct StaticAXProbe: AXProbe {
    var bundleID: String?
    func frontmostAppBundleID() -> String? { bundleID }
    func focusedWindowExists() -> Bool { true }
    func focusedElementBundleID() -> String? { bundleID }
}

private struct AlwaysSecureInputProbe: SecureInputProbe {
    func isSecureEventInputEnabled() -> Bool { true }
}
