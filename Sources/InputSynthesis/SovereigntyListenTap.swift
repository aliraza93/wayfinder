import CoreEngine
import CoreGraphics
import Foundation

/// Listen-only session tap that forwards untagged scroll/key events to `UserSovereigntyMonitor`.
public final class SovereigntyListenTap: @unchecked Sendable {
    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let monitor: UserSovereigntyMonitor

    public init(monitor: UserSovereigntyMonitor) {
        self.monitor = monitor
    }

    public func start() {
        guard port == nil else { return }
        let mask =
            (1 << CGEventType.scrollWheel.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let tap = Unmanaged<SovereigntyListenTap>.fromOpaque(refcon).takeUnretainedValue()
                if let mapped = SovereigntyEventMapper.map(event) {
                    Task { await tap.monitor.consider(mapped) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return
        }

        port = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        if let tap = port {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        port = nil
    }

    deinit {
        stop()
    }
}
