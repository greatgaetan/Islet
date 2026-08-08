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

    /// At rest: the notch widened by a glyph slot on each side.
    case resting

    /// A timer is running: progress ring on the right, active task on the left.
    case live

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

    public private(set) var state: NotchState = .resting
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
        if isTimerActive { return .live }
        if isChromeHidden && !isPointerInside { return .hidden }
        return .resting
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
            guard isPointerInside, state == .resting || state == .live else { break }
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
            if state == .hidden || state == .resting { state = restState }

        case .timerBecameIdle:
            isTimerActive = false
            if state == .live { state = restState }

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
            if state == .resting { state = restState }

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
