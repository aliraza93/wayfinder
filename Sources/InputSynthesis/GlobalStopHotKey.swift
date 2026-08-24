import Carbon
import CoreEngine
import Foundation

/// Global stop hot-key: Control+Option+Period (`.`).
/// Calls `UserSovereigntyMonitor.requestStop` — does not synthesize input.
public final class GlobalStopHotKey: @unchecked Sendable {
    public static let signature: OSType = 0x5750_5354 // 'WPST'
    public static let hotKeyID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let monitor: UserSovereigntyMonitor
    private var installed = false

    public init(monitor: UserSovereigntyMonitor) {
        self.monitor = monitor
    }

    public func install() {
        guard !installed else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData else { return noErr }
                let owner = Unmanaged<GlobalStopHotKey>.fromOpaque(userData).takeUnretainedValue()
                Task { await owner.monitor.requestStop() }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        guard status == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        // Control+Option+Period — key code 47 (ANSI_Period).
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_Period),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let handler = handlerRef {
                RemoveEventHandler(handler)
                handlerRef = nil
            }
            return
        }
        installed = true
    }

    public func uninstall() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        installed = false
    }

    deinit {
        uninstall()
    }
}
