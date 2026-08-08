import AppKit

/// Pointer and click observation.
///
/// Global monitors for *mouse* events require no Accessibility permission —
/// only keyboard monitors do. That is why hover detection goes through here
/// and the quick-add hotkey will go through `RegisterEventHotKey` instead:
/// Islet must never open with a permission prompt.
final class EventMonitor {
    private var tokens: [Any] = []

    /// `onKeyDown` returns true when it consumed the key, so a keystroke is only
    /// swallowed when Islet actually had a use for it.
    /// Primitives, not the `NSEvent`: an event is not `Sendable`, and handing one
    /// across an isolation boundary is a data race the compiler is right to
    /// refuse.
    init(onMove: @escaping @MainActor (CGPoint) -> Void,
         onOptionClick: @escaping @MainActor () -> Void,
         onKeyDown: @escaping @MainActor (UInt16, String?, Bool, Bool) -> Bool) {
        let move: (NSEvent) -> Void = { _ in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated { onMove(location) }
        }

        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged], handler: move
        ) {
            tokens.append(global)
        }

        let localMove: (NSEvent) -> NSEvent? = { event in
            move(event)
            return event
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged],
            handler: localMove
        ) {
            tokens.append(local)
        }

        // ⌥-click cycles the slow-motion factor. No permission, no hotkey
        // registration, and it is the single most useful debug affordance
        // in the project.
        let optionClickHandler: (NSEvent) -> NSEvent? = { event in
            guard event.modifierFlags.contains(.option) else { return event }
            MainActor.assumeIsolated { onOptionClick() }
            return nil
        }
        if let optionClick = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown],
            handler: optionClickHandler
        ) {
            tokens.append(optionClick)
        }

        // Local, not global: a global key monitor would demand Accessibility
        // permission. This only fires while Islet is the active app, which is
        // exactly the window in which Escape means "close the panel".
        let keyHandler: (NSEvent) -> NSEvent? = { event in
            let keyCode = event.keyCode
            let characters = event.charactersIgnoringModifiers
            let hasCommand = event.modifierFlags.contains(.command)
            let hasShift = event.modifierFlags.contains(.shift)
            let consumed = MainActor.assumeIsolated {
                onKeyDown(keyCode, characters, hasCommand, hasShift)
            }
            return consumed ? nil : event
        }
        if let keys = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown],
            handler: keyHandler
        ) {
            tokens.append(keys)
        }
    }
}
