import AppKit
import Carbon.HIToolbox

/// A process-global hotkey via Carbon's `RegisterEventHotKey`.
///
/// Deliberately *not* `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`:
/// a global keyboard monitor demands Accessibility permission, and Islet must
/// never open with a permission prompt in front of it. Carbon hotkeys need
/// nothing, at the cost of only supporting simple combinations — a trade worth
/// taking.
@MainActor
final class HotKey {
    /// ⌥Space. Free on a stock Mac; ⌃Space collides with input switching.
    static let optionSpace = (keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handler: EventHandlerRef?

    private let id: UInt32
    private var reference: EventHotKeyRef?

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        Self.installHandlerIfNeeded()

        id = Self.nextID
        Self.nextID += 1
        Self.actions[id] = action

        let hotKeyID = EventHotKeyID(signature: OSType(0x49_53_4C_54), id: id) // 'ISLT'
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference
        )

        guard status == noErr, reference != nil else {
            Self.actions[id] = nil
            log("could not register hotkey (status \(status)) — is it already taken?")
            return nil
        }
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.actions[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard handler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressed
                )
                guard status == noErr else { return status }
                MainActor.assumeIsolated { HotKey.actions[pressed.id]?() }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handler
        )
    }
}
