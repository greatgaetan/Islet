import AppKit
import Carbon.HIToolbox
import IsletCore
import SwiftUI

/// Single root of truth for the surface. One observable object, so every
/// animation fires at a moment this code chose.
@MainActor
@Observable
final class NotchModel {
    private(set) var machine = NotchStateMachine()
    var notch: NotchDimensions
    let pomodoro = PomodoroModel()
    let tasks: TaskModel
    let history: SessionHistoryModel
    let recap: RecapModel

    private(set) var slowFactor: Double = Motion.slowFactor
    /// Set while a segment change is being announced. The Peek layer renders it
    /// instead of its usual contents.
    private(set) var announcement: String?
    /// One gentle fade at launch — the only appearance animation a permanent
    /// element is allowed, and it does the job of confirming Islet started.
    private(set) var hasAppeared = false

    /// False when there is no notched display to draw on (lid closed at the
    /// office). The timer keeps running; the announcement has to go elsewhere.
    var isSurfaceAvailable = true
    /// Fired for every segment change, whether or not the notch can show it.
    /// The controller uses it for the notification fallback.
    var onSegmentBegan: ((PomodoroSegment) -> Void)?
    var onSessionEnded: (() -> Void)?
    /// Fires when the panel takes or gives up keyboard focus. The controller
    /// activates Islet on the way in and hands focus back on the way out.
    var onKeyboardFocusChanged: ((Bool) -> Void)?
    /// The panel is the only surface Islet has. Without these, there is no way to
    /// reach settings — and, worse, no way to quit it at all.
    var onShowTasks: (() -> Void)?
    var onShowSettings: (() -> Void)?

    /// `ISLET_KEY_LOG=1` prints every keystroke Islet is offered, with its code
    /// and its characters — the fastest way to settle a keyboard-layout argument.
    static let logsKeys = ProcessInfo.processInfo.environment["ISLET_KEY_LOG"] != nil

    /// The crossing floor. A settled pointer gets there sooner — see `DwellGate`.
    static let dwell = Duration.seconds(DwellGate.crossing)
    static let grace = Duration.milliseconds(400)
    static let announcementHold = Duration.milliseconds(2500)

    private var dwellTask: Task<Void, Never>?
    private var graceTask: Task<Void, Never>?
    private var announcementTask: Task<Void, Never>?
    private var dragBase: CGFloat?

    var state: NotchState { machine.state }

    /// Non-nil while a drag is in flight: 0 at Peek, 1 at Expanded.
    private(set) var dragProgress: CGFloat?
    var isDragging: Bool { dragProgress != nil }

    /// Interpolated freely while dragging.
    ///
    /// This is what the single `VectorArithmetic` value was always for: width,
    /// height and both radii travel together, so a half-open panel is a real,
    /// coherent shape rather than four numbers guessed separately.
    /// The idle silhouette is wider when it has a countdown to hold — which is
    /// the whole of what `live` used to be.
    var showsTimer: Bool { pomodoro.isActive }

    var metrics: NotchMetrics {
        guard let dragProgress else {
            return .forState(machine.state, notch: notch,
                             expandedHeight: expandedHeight, showsTimer: showsTimer)
        }
        let peek = NotchMetrics.forState(.peek, notch: notch)
        var delta = NotchMetrics.forState(.expanded, notch: notch,
                                          expandedHeight: expandedHeight) - peek
        delta.scale(by: Double(dragProgress))
        return peek + delta
    }

    /// How far the pointer has to travel to open it.
    private var dragDistance: CGFloat {
        NotchMetrics.forState(.expanded, notch: notch, expandedHeight: expandedHeight).height
            - NotchMetrics.forState(.peek, notch: notch).height
    }

    // MARK: - Drag to open

    func updateDrag(translation: CGFloat) {
        // No animation here on purpose: while your hand is on it, the panel is
        // *at* your pointer, not springing towards it.
        if dragBase == nil { dragBase = state == .expanded ? 1 : 0 }
        dragProgress = DragToOpen.progress(base: dragBase ?? 0,
                                           translation: translation,
                                           distance: dragDistance)
    }

    /// Freezes the drag at a given progress. `ISLET_DRAG=0.5` uses it to make a
    /// half-open panel inspectable, which is otherwise impossible to hold still.
    func previewDrag(_ progress: CGFloat) {
        dragBase = 0
        dragProgress = progress
    }

    /// - Parameter velocity: points per millisecond, positive downwards.
    func endDrag(velocity: CGFloat) {
        let progress = dragProgress ?? 0
        let expanded = DragToOpen.resolve(progress: progress, velocity: velocity)
        dragBase = nil

        // Clearing the progress and settling the state in one transaction is what
        // makes the release interruptible: the spring starts from wherever the
        // shape actually is, rather than replaying from a fixed origin.
        withAnimation(expanded ? Motion.expand : Motion.collapse) {
            dragProgress = nil
            var updated = machine
            updated.handle(.dragEnded(expanded: expanded))
            machine = updated
        }
    }

    /// Rows shown, plus one for the undo placeholder that keeps a deleted row's
    /// space for four seconds.
    private var expandedHeight: CGFloat {
        // A review shows one card at a time, so sizing to the task list would be
        // meaningless — and it changes under you as you answer.
        if recap.isReviewing { return NotchMetrics.ExpandedHeight.review }
        let rows = tasks.visible.count + (tasks.pendingUndo == nil ? 0 : 1)
        return NotchMetrics.ExpandedHeight.forRows(rows, notchHeight: notch.height)
    }
    var isPointerInside: Bool { machine.isPointerInside }
    var isAwaitingDecision: Bool { machine.isAwaitingDecision }
    var isChromeHidden: Bool { machine.isChromeHidden }

    /// True while the panel is standing open because ⌥Space put it there.
    ///
    /// The keyboard path has to be instant *end to end*. Making only the
    /// silhouette skip its spring left the contents fading and cascading in
    /// behind it — which is exactly the wait the rule exists to remove, just
    /// moved somewhere less obvious.
    var presentedFromKeyboard: Bool { machine.isKeyboardPresented }

    init(notch: NotchDimensions, tasks: TaskModel,
         history: SessionHistoryModel, recap: RecapModel) {
        self.notch = notch
        self.tasks = tasks
        self.history = history
        self.recap = recap

        // Pending nudges the surface open only as far as Peek, and only when
        // something is already there to be interrupted. Reviewing needs the
        // whole panel and must not close behind your back.
        recap.onPhaseChanged = { [weak self] phase in
            guard let self else { return }
            switch phase {
            case .pending: send(.announcementBegan, animation: Motion.announce)
            case .reviewing:
                // Locked open *and* expanded. Locking alone left it sitting in
                // Peek, where the session-end card lives — so the review
                // announced itself by showing the wrong thing entirely.
                send(.decisionRequired)
                send(.clicked, animation: Motion.expand)
            case .idle:
                releaseRecapKeyboard()
                send(.decisionResolved)
            }
        }

        // Decision (a): while there is unsent text, only the keyboard can close
        // the panel. `isEditing` tracks "the draft has content", not "the field
        // has focus" — a focused empty field has nothing to lose.
        tasks.onDraftDirtyChanged = { [weak self] isDirty in
            self?.send(isDirty ? .editingBegan : .editingEnded, instant: true)
        }

        pomodoro.onActiveChanged = { [weak self] active in
            self?.send(active ? .timerBecameActive : .timerBecameIdle)
        }
        pomodoro.onSegmentChanged = { [weak self] segment in
            guard let self else { return }
            self.onSegmentBegan?(segment)
            guard self.isSurfaceAvailable else { return }
            self.announce(segment.kind.label)
        }
        pomodoro.onSessionFinished = { [weak self] in
            guard let self else { return }
            self.onSessionEnded?()
            guard self.isSurfaceAvailable else { return }
            self.requireDecision()
        }
    }

    func markAppeared() {
        guard !hasAppeared else { return }
        withAnimation(.easeOut(duration: 0.25 * Motion.slowFactor)) {
            hasAppeared = true
        }
    }

    /// `instant: true` is for keyboard-initiated presentation. An action
    /// repeated dozens of times a day must not be animated — same destination,
    /// different treatment depending on how you got there.
    func send(_ event: NotchStateMachine.Event,
              animation: Animation? = nil,
              instant: Bool = false) {
        let from = machine.state
        let hadKeyboardFocus = machine.isKeyboardPresented
        var updated = machine
        updated.handle(event)

        if updated.state != from && !instant {
            withAnimation(animation ?? Motion.morph(from: from, to: updated.state)) {
                machine = updated
            }
        } else {
            machine = updated
        }

        if machine.isKeyboardPresented != hadKeyboardFocus {
            onKeyboardFocusChanged?(machine.isKeyboardPresented)
        }

        // Reaching for a review with the pointer is enough of a statement.
        if event == .pointerEntered { claimKeyboardForRecap() }

        schedule(after: event)
    }

    // MARK: - Intent

    /// A click on the silhouette itself, anywhere that isn't a glyph.
    ///
    /// Only reachable from `peek`: in `resting` and `live` the surgical hit test
    /// hands those clicks to the menu bar underneath, on purpose.
    func silhouetteTapped() {
        switch state {
        case .idle, .peek:
            send(.clicked)
        case .hidden, .expanded:
            break
        }
    }

    /// ⌥Space. Keyboard-initiated, therefore **instant** — no morph, no spring.
    /// An action repeated dozens of times a day must not be animated; the same
    /// panel opened with the mouse animates fully.
    func toggleQuickAdd() {
        if state == .expanded {
            send(.dismissRequested, instant: true)
        } else {
            send(.presentedByKeyboard, instant: true)
        }
    }

    /// Escape, while the panel was summoned from the keyboard and never touched.
    @discardableResult
    func dismissFromKeyboard() -> Bool {
        guard machine.isKeyboardPresented else { return false }
        tasks.clearDraft()
        send(.dismissRequested, instant: true)
        return true
    }

    /// Every key Islet claims, in one place. Returns true when it consumed one.
    ///
    /// This is a *local* monitor, so it only ever sees keys while Islet is the
    /// active app — which is exactly the window in which these mean something.
    func handleKeyDown(keyCode: UInt16, characters: String?,
                       hasCommand: Bool, hasShift: Bool) -> Bool {
        if Self.logsKeys {
            log("key \(keyCode) chars=\(characters ?? "nil") cmd=\(hasCommand) state=\(state.rawValue)")
        }
        if keyCode == 53 { // Escape
            guard state == .expanded else { return false }
            // Escaping a review is not abandoning it: the rest rolls to tomorrow.
            if recap.isReviewing { dismissRecap(); return true }
            tasks.clearDraft()
            send(.dismissRequested, instant: true)
            return true
        }

        guard state == .expanded else { return false }

        // A review answers with the same ⌘-digit the rest of the app uses for
        // "pick the nth thing in front of me". There is no list to filter while
        // it is running, so the meaning does not collide.
        if recap.isReviewing {
            if hasCommand, let action = RecapModel.Action.forKeyCode(keyCode) {
                answerRecap(action)
                return true
            }
            return false
        }

        // Tab is about what you are *composing*; it sits inside the field's own
        // flow, and this micro-form has exactly one other thing to move through.
        if keyCode == UInt16(kVK_Tab) {
            tasks.cyclePendingCategory(backwards: hasShift)
            return true
        }

        // ⌫ deletes the row under the pointer — but only when the field is
        // empty, or it would eat the text you are typing.
        if keyCode == UInt16(kVK_Delete), !tasks.hasDraft,
           let hovered = tasks.hoveredTaskID {
            tasks.delete(hovered)
            return true
        }

        guard hasCommand else { return false }

        // ⌘-digit is about what you are *looking at*. That is what ⌘1/2/3 means
        // everywhere else on this platform — Safari tabs, Finder views — so
        // borrowing it for classification would be borrowing the wrong verb.
        if let category = TaskCategory.category(forKeyCode: keyCode) {
            tasks.setFilter(category)
            return true
        }
        if keyCode == UInt16(kVK_ANSI_0) || keyCode == UInt16(kVK_ANSI_Keypad0) {
            tasks.setFilter(nil)
            return true
        }
        if characters?.lowercased() == "z", tasks.canUndo {
            tasks.undoDelete()
            return true
        }
        return false
    }

    /// Start a session *on* a task — the only coupling between the two halves,
    /// and it is optional in both directions.
    func startFocus(on task: TaskItem) {
        tasks.setActiveTask(task.id)
        if !pomodoro.isActive || pomodoro.isFinished {
            pomodoro.start()
        }
    }

    /// Answering needs the keyboard, and the keyboard needs Islet to be the
    /// active app — a local monitor sees nothing otherwise.
    ///
    /// But the review opens itself, unprompted, at an hour you did not choose.
    /// Seizing the keyboard on top of that would swallow whatever you were
    /// typing elsewhere. So it waits for one deliberate act — the pointer
    /// arriving, or you opening it by hand — and takes focus then.
    private var holdsRecapKeyboard = false

    func claimKeyboardForRecap() {
        guard recap.isReviewing, !holdsRecapKeyboard else { return }
        holdsRecapKeyboard = true
        onKeyboardFocusChanged?(true)
    }

    private func releaseRecapKeyboard() {
        guard holdsRecapKeyboard else { return }
        holdsRecapKeyboard = false
        onKeyboardFocusChanged?(false)
    }

    func beginRecap() {
        recap.beginReview()
        send(.clicked)
        // Opening it by hand *is* the deliberate act.
        claimKeyboardForRecap()
    }

    func answerRecap(_ action: RecapModel.Action) {
        recap.answer(action)
    }

    func dismissRecap() {
        recap.dismiss()
        send(.dismissRequested)
    }

    func toggleTimer() {
        clearAnnouncement()
        pomodoro.primaryAction()
    }

    func restartSession() {
        resolveDecision()
        pomodoro.start()
    }

    func dismissSession() {
        resolveDecision()
        // Guard kept: stopping when nothing runs should do nothing at all.
        guard pomodoro.isActive else { return }
        pomodoro.stop()
    }

    func cycleSlowMotion() {
        slowFactor = Motion.cycleSlowMotion()
    }

    // MARK: - Announcements

    /// The best moment in the app, and it happens ~8 times a day for free.
    private func announce(_ text: String) {
        announcementTask?.cancel()
        withAnimation(Motion.contentIn) { announcement = text }
        send(.announcementBegan, animation: Motion.announce)

        announcementTask = Task { [weak self] in
            try? await Task.sleep(for: Self.announcementHold)
            guard !Task.isCancelled, let self else { return }
            self.clearAnnouncement()
            self.send(.announcementEnded)
        }
    }

    private func clearAnnouncement() {
        announcementTask?.cancel()
        announcementTask = nil
        guard announcement != nil else { return }
        withAnimation(Motion.contentOut) { announcement = nil }
    }

    private func requireDecision() {
        announcementTask?.cancel()
        withAnimation(Motion.contentIn) { announcement = nil }
        send(.decisionRequired, animation: Motion.announce)
    }

    private func resolveDecision() {
        send(.decisionResolved)
    }

    // MARK: - Timers

    private func startGrace() {
        graceTask?.cancel()
        graceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.grace)
            guard !Task.isCancelled else { return }
            self?.send(.graceElapsed)
        }
    }

    private func schedule(after event: NotchStateMachine.Event) {
        switch event {
        case .pointerEntered:
            graceTask?.cancel()
            graceTask = nil
            dwellTask?.cancel()
            dwellTask = Task { [weak self] in
                try? await Task.sleep(for: Self.dwell)
                guard !Task.isCancelled else { return }
                self?.send(.dwellElapsed)
            }

        case .pointerExited:
            dwellTask?.cancel()
            dwellTask = nil
            startGrace()

        case .editingEnded:
            // The grace timer that fired while editing was locked open is gone.
            // Without re-arming it, a panel left open with the pointer nowhere
            // near it has nothing left that could ever close it.
            guard !machine.isPointerInside, !machine.isLockedOpen else { break }
            startGrace()

        default:
            break
        }
    }
}
