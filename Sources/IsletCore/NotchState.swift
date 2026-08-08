import Foundation

/// The presentation states of the notch surface.
///
/// `hidden` does not mean "no window". It is the silhouette retracted to
/// exactly the physical notch, which makes it invisible against the bezel.
/// Every transition is therefore the morph of a shape that already exists —
/// nothing ever appears from nothing.
public enum NotchState: String, Sendable, CaseIterable {
    /// Retracted into the hardware. Used when the system hides its own chrome
    /// (full-screen space, auto-hidden menu bar).
    case hidden

    /// At rest. What it *shows* depends on whether a timer is running — glyphs
    /// when it is not, a ring and a countdown when it is — but that was never a
    /// distinction the machine acted on. Every rule treated the two identically,
    /// so it was a difference in appearance being carried as a difference in
    /// state. The appearance now lives with the view, where it belongs.
    case idle

    /// Pointer dwelled: controls become touchable.
    case peek

    /// Full panel: task list and timer, two columns.
    case expanded
}

/// The notch's presentation logic, as an explicit state machine.
///
/// Deliberately not a scatter of `isHovering` / `isExpanded` booleans across
/// views: interruptible motion is only tractable when the states and the
/// transitions between them are named.
public struct NotchStateMachine: Equatable, Sendable {
    public enum Event: Sendable, Equatable {
        case pointerEntered
        case pointerExited
        case dwellElapsed
        case graceElapsed
        case clicked
        case dismissRequested
        case timerBecameActive
        case timerBecameIdle
        case editingBegan
        case editingEnded
        case chromeHidden
        case chromeShown
        /// A segment changed: widen briefly, unprompted, then close again.
        case announcementBegan
        case announcementEnded
        /// Something needs an answer (a finished session). Stays open until
        /// resolved, like editing does.
        case decisionRequired
        case decisionResolved
        /// A drag was released. Unlike every other transition this one can land
        /// in *either* state, and nothing else could take Expanded back to Peek.
        case dragEnded(expanded: Bool)
        /// Summoned by ⌥Space. Stays open until the pointer arrives or Escape
        /// is pressed — the pointer was never near it, so the usual exit-plus-
        /// grace rule has nothing to work with.
        case presentedByKeyboard
    }

    public private(set) var state: NotchState = .idle
    public private(set) var isPointerInside = false
    public private(set) var isTimerActive = false
    public private(set) var isEditing = false
    public private(set) var isChromeHidden = false
    public private(set) var isAwaitingDecision = false
    public private(set) var isKeyboardPresented = false

    /// Anything that must not be closed behind the user's back.
    public var isLockedOpen: Bool { isEditing || isAwaitingDecision || isKeyboardPresented }

    public init() {}

    /// Where the surface falls back to when nothing is being interacted with.
    ///
    /// A running timer outranks hidden chrome: in a full-screen space the ring
    /// stays visible, because that is exactly when a quiet timer is worth most.
    public var restState: NotchState {
        // A running timer outranks hidden chrome: in a full-screen space the ring
        // stays visible, because that is exactly when a quiet timer is worth most.
        if isChromeHidden && !isPointerInside && !isTimerActive { return .hidden }
        return .idle
    }

    @discardableResult
    public mutating func handle(_ event: Event) -> NotchState {
        switch event {
        case .pointerEntered:
            isPointerInside = true
            // A keyboard-summoned panel hands control back to the pointer the
            // moment the pointer arrives. From then on, leaving collapses it
            // like anything else — no special case, no second rule to learn.
            //
            // Unless there is unsent text: losing what you typed because the
            // mouse brushed past is the worst defect a capture tool can have.
            // The rule stays sayable in one line — *once you are writing, only
            // the keyboard can close it.*
            if !isEditing { isKeyboardPresented = false }
            if state == .hidden { state = restState }

        case .pointerExited:
            isPointerInside = false

        case .dwellElapsed:
            guard isPointerInside, state == .idle else { break }
            state = .peek

        case .graceElapsed:
            // Editing locks the panel open: losing typed text to a stray
            // pointer movement is unforgivable. So does a pending decision.
            guard !isPointerInside, !isLockedOpen else { break }
            state = restState

        case .clicked:
            guard state != .hidden else { break }
            state = .expanded

        case .dismissRequested:
            isEditing = false
            isAwaitingDecision = false
            isKeyboardPresented = false
            state = restState

        case .timerBecameActive:
            isTimerActive = true
            // Only ever reveals a retracted surface; the idle state's *look*
            // follows the flag without the machine having to move anywhere.
            if state == .hidden { state = restState }

        case .timerBecameIdle:
            isTimerActive = false
            if state == .idle { state = restState }

        case .editingBegan:
            isEditing = true
            state = .expanded

        case .editingEnded:
            isEditing = false
            // The field is empty again, so the pointer may take over — otherwise
            // committing a task with the mouse resting on the panel would leave
            // it stuck open with nothing able to close it.
            if isPointerInside { isKeyboardPresented = false }

        case .chromeHidden:
            isChromeHidden = true
            if state == .idle { state = restState }

        case .chromeShown:
            isChromeHidden = false
            if state == .hidden { state = restState }

        case .announcementBegan:
            // Never yank an open panel shut, and never interrupt a full-screen
            // app — there, only the ring hue changes.
            guard state != .expanded, !isChromeHidden else { break }
            state = .peek

        case .announcementEnded:
            guard state == .peek, !isPointerInside, !isLockedOpen else { break }
            state = restState

        case .decisionRequired:
            isAwaitingDecision = true
            guard state != .expanded else { break }
            state = .peek

        case .decisionResolved:
            isAwaitingDecision = false

        case .presentedByKeyboard:
            isKeyboardPresented = true
            state = .expanded

        case .dragEnded(let expanded):
            // The pointer is by definition still on the panel, so Peek — not the
            // rest state — is where a downward-cancelled drag belongs.
            state = expanded ? .expanded : .peek
        }
        return state
    }
}
