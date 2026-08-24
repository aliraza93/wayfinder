import Carbon
import Foundation

/// Global run-control hot-keys (Control+Option chord family).
/// Does not synthesize navigation input — only signals the session/engine.
///
/// - Stop:   Control+Option+`.`
/// - Pause:  Control+Option+`P`
/// - Resume: Control+Option+`R`
public final class RunControlHotKeys: @unchecked Sendable {
    public enum Action: Sendable {
        case stop
        case pause
        case resume
    }

    public static let signature: OSType = 0x5750_524B // 'WPRK'
    private static let stopID: UInt32 = 1
    private static let pauseID: UInt32 = 2
    private static let resumeID: UInt32 = 3

    private var stopRef: EventHotKeyRef?
    private var pauseRef: EventHotKeyRef?
    private var resumeRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onAction: @Sendable (Action) -> Void
    private var installed = false

    public init(onAction: @escaping @Sendable (Action) -> Void) {
        self.onAction = onAction
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
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return noErr }
                let owner = Unmanaged<RunControlHotKeys>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr, hotKeyID.signature == RunControlHotKeys.signature else {
                    return noErr
                }
                switch hotKeyID.id {
                case RunControlHotKeys.stopID:
                    owner.onAction(.stop)
                case RunControlHotKeys.pauseID:
                    owner.onAction(.pause)
                case RunControlHotKeys.resumeID:
                    owner.onAction(.resume)
                default:
                    break
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        guard status == noErr else { return }

        let mods = UInt32(controlKey | optionKey)
        let target = GetApplicationEventTarget()

        var stopOK = false
        var pauseOK = false
        var resumeOK = false

        stopOK = RegisterEventHotKey(
            UInt32(kVK_ANSI_Period),
            mods,
            EventHotKeyID(signature: Self.signature, id: Self.stopID),
            target,
            0,
            &stopRef
        ) == noErr

        pauseOK = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            mods,
            EventHotKeyID(signature: Self.signature, id: Self.pauseID),
            target,
            0,
            &pauseRef
        ) == noErr

        resumeOK = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            mods,
            EventHotKeyID(signature: Self.signature, id: Self.resumeID),
            target,
            0,
            &resumeRef
        ) == noErr

        if !(stopOK || pauseOK || resumeOK) {
            uninstall()
            return
        }
        installed = true
    }

    public func uninstall() {
        if let stopRef {
            UnregisterEventHotKey(stopRef)
            self.stopRef = nil
        }
        if let pauseRef {
            UnregisterEventHotKey(pauseRef)
            self.pauseRef = nil
        }
        if let resumeRef {
            UnregisterEventHotKey(resumeRef)
            self.resumeRef = nil
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
