import AppKit
import IsletCore
import SwiftUI

@MainActor
final class NotchController {
    private let tasks: TaskModel
    private let history: SessionHistoryModel
    private let recap: RecapModel
    /// Read from settings on every chime, so the switch takes effect at once.
    var isSoundEnabled: () -> Bool = { true }
    var onShowTasks: () -> Void = {}
    var onShowSettings: () -> Void = {}
    private var panel: NotchPanel?
    private var model: NotchModel?
    private var geometry: PanelGeometry?
    private var notchScreen: NotchScreen?
    private var monitor: EventMonitor?
    private var hotKey: HotKey?
    private let notifier = Notifier()
    private var lastChromeHidden: Bool?
    private var previousApp: NSRunningApplication?
    private var leaveWatchdog: Task<Void, Never>?
    /// Where and when the pointer last was, so its speed can be measured.
    private var lastSample: (point: CGPoint, at: Date)?
    private var enteredAt: Date?

    init(tasks: TaskModel, history: SessionHistoryModel, recap: RecapModel) {
        self.tasks = tasks
        self.history = history
        self.recap = recap
    }

    /// Exposed so the app can apply persisted settings and read timer state.
    var pomodoro: PomodoroModel? { model?.pomodoro }

    func start() {
        configure()
        registerHotKey()

        monitor = EventMonitor(
            onMove: { [weak self] location in self?.pointerMoved(to: location) },
            onOptionClick: { [weak self] in
                self?.model?.cycleSlowMotion()
                if let factor = self?.model?.slowFactor {
                    log("slow motion ×\(factor)")
                }
            },
            onKeyDown: { [weak self] keyCode, characters, hasCommand, hasShift in
                self?.model?.handleKeyDown(
                    keyCode: keyCode,
                    characters: characters,
                    hasCommand: hasCommand,
                    hasShift: hasShift
                ) ?? false
            }
        )
    }

    /// Get out of the way: a window just came forward.
    func collapsePanel() {
        model?.dismissForWindow()
    }

    func screenParametersChanged() {
        configure()
    }

    private func registerHotKey() {
        hotKey = HotKey(keyCode: HotKey.optionSpace.keyCode,
                        modifiers: HotKey.optionSpace.modifiers) { [weak self] in
            self?.model?.toggleQuickAdd()
        }
        if hotKey != nil { log("⌥Space registered — no Accessibility permission needed") }
    }

    private func configure() {
        guard let found = NotchScreen.locate() else {
            panel?.orderOut(nil)
            // The timer keeps running: it is a time model, not a view. Only the
            // announcement has to go somewhere else.
            model?.isSurfaceAvailable = false
            log("no notched display attached — announcements fall back to notifications")
            return
        }

        notchScreen = found
        let geometry = PanelGeometry(notch: found.dimensions)
        self.geometry = geometry

        let isFirstConfigure = self.model == nil
        let model = model ?? NotchModel(notch: found.dimensions, tasks: tasks, history: history, recap: recap)
        model.notch = found.dimensions
        model.isSurfaceAvailable = true
        model.hasPhysicalNotch = found.hasPhysicalNotch
        self.model = model
        if isFirstConfigure { wire(model) }

        if panel == nil {
            let panel = NotchPanel(size: geometry.size)
            panel.install(
                rootView: NotchRootView(model: model, geometry: geometry),
                isFullyInteractive: { [weak model] in
                    guard let model else { return false }
                    return model.state == .peek || model.state == .expanded
                },
                interactiveRects: { [weak model] in
                    guard let model else { return [] }
                    return geometry.interactiveRects(for: model.state, showsTimer: model.showsTimer)
                }
            )
            self.panel = panel
        }

        panel?.setFrame(geometry.frame(on: found.screen), display: true)
        panel?.orderFrontRegardless()

        log("""
            attached to \(found.screen.localizedName) — \
            notch \(Int(found.dimensions.width))×\(Int(found.dimensions.height))pt\
            \(found.hasPhysicalNotch ? "" : " (simulated)")
            """)
        if Self.logsInteractivity {
            let window = panel?.frame ?? .zero
            let zone = geometry.hotZone(for: .idle,
                                       metrics: .forState(.idle, notch: found.dimensions),
                                       on: found.screen)
            log("window \(rect(window)) — deaf to the mouse: \(panel?.ignoresMouseEvents ?? false)")
            log("resting hot zone \(rect(zone)) — only this is ever interactive at rest")
            logFirstMouseAnswer(geometry)
        }

        applyChromeVisibility(found.isChromeHidden)

        // Development hatch: start a session immediately so the segment
        // transitions can be inspected without clicking anything.
        if ProcessInfo.processInfo.environment["ISLET_AUTOSTART"] != nil,
           !model.pomodoro.isActive {
            model.pomodoro.start()
        }

        // Development hatch: run the evening review now, whatever the clock says.
        // `ISLET_RECAP=1` stops at *pending*, so the real path can be walked:
        // the dot, the hover, the invitation, then the cards. `=review` skips
        // straight to the cards when only they are being worked on.
        if isFirstConfigure,
           let mode = ProcessInfo.processInfo.environment["ISLET_RECAP"] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                Preferences.lastRecap = nil
                recap.checkIfDue(now: Calendar.current.date(
                    bySettingHour: 22, minute: 0, second: 0, of: .now) ?? .now)
                log("recap forced — \(recap.remaining) cards, phase \(recap.phase)")
                if ProcessInfo.processInfo.environment["ISLET_RECAP_KEYS"] != nil {
                    try? await Task.sleep(for: .milliseconds(400))
                    model.claimKeyboardForRecap()
                    // Activation is asynchronous; reading it synchronously proves
                    // nothing. And asking from outside the app brings the asker
                    // to the front, which is worse than useless.
                    try? await Task.sleep(for: .milliseconds(600))
                    let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
                    log("settled — active=\(NSApp.isActive) isKey=\(self.panel?.isKeyWindow ?? false) front=\(front)")
                }
                guard mode == "review" else {
                    log("hover the notch to be offered it")
                    return
                }
                try? await Task.sleep(for: .milliseconds(600))
                recap.beginReview()
                model.send(.clicked)
            }
        }

        // Development hatch: hold the panel part-open, so the interpolated shape
        // and the crossfade can actually be looked at.
        if isFirstConfigure,
           let raw = ProcessInfo.processInfo.environment["ISLET_DRAG"],
           let progress = Double(raw) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                model.send(.pointerEntered)
                model.send(.dwellElapsed)
                model.previewDrag(CGFloat(progress))
            }
        }

        // Development hatch: exercise the ⌥Space path without a keystroke, then
        // let go again — this is how the keyboard-focus handover gets verified.
        if isFirstConfigure, ProcessInfo.processInfo.environment["ISLET_QUICKADD"] != nil {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                model.toggleQuickAdd()
                try? await Task.sleep(for: .seconds(2))
                log("escape consumed = \(model.dismissFromKeyboard())")
            }
        }
    }

    private func wire(_ model: NotchModel) {
        model.pomodoro.onSegmentCompleted = { [weak self] finished in
            self?.history.record(finished)
        }
        model.onSegmentBegan = { [weak self] segment in
            guard let self else { return }
            // The callback carries the segment that just *began*, so a break
            // starting means work just ended, and the other way round.
            let chime: Chime = segment.kind.isBreak ? .workEnded : .breakEnded
            chime.play(enabled: isSoundEnabled())
            // Asked the first time a segment ends, not at launch: the
            // permission arrives once its usefulness is obvious.
            notifier.requestAuthorizationIfNeeded()
            guard !model.isSurfaceAvailable else { return }
            notifier.post(title: segment.kind.label,
                          body: "\(segment.duration.clockText) · Islet")
        }
        model.onSessionEnded = { [weak self] in
            guard let self else { return }
            Chime.sessionEnd.play(enabled: isSoundEnabled())
            guard !model.isSurfaceAvailable else { return }
            notifier.post(title: "Session done", body: "Islet")
        }
        tasks.onDeleted = { [weak self] in
            guard let self else { return }
            Chime.delete.play(enabled: isSoundEnabled())
        }
        model.onKeyboardFocusChanged = { [weak self] hasFocus in
            self?.setKeyboardFocus(hasFocus)
        }
        // Was never wired: the review would have offered itself over a
        // full-screen presentation, and then burnt its own patience timer and
        // skipped the day entirely.
        recap.isSurfaceAvailable = { [weak model] in
            guard let model else { return false }
            return model.isSurfaceAvailable && !model.isChromeHidden
        }
        model.onShowTasks = { [weak self] in self?.onShowTasks() }
        model.onShowSettings = { [weak self] in self?.onShowSettings() }
    }

    /// Keyboard input requires being the active app — there is no way around it
    /// short of an Accessibility permission. So ⌥Space activates Islet, and
    /// giving the panel up hands focus straight back to where it came from.
    private func setKeyboardFocus(_ hasFocus: Bool) {
        guard let panel else { return }

        if hasFocus {
            previousApp = NSWorkspace.shared.frontmostApplication
            // Cooperative activation — plain `activate()` — asks the frontmost
            // app to yield, and it does not. A hotkey utility has to insist, or
            // keystrokes never reach it and every shortcut is dead.
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            log("keyboard focus taken — isKey=\(panel.isKeyWindow) active=\(NSApp.isActive)")
        } else {
            panel.orderFrontRegardless()
            if let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp.activate()
            }
            previousApp = nil
        }
    }

    private func pointerMoved(to location: CGPoint) {
        guard let model, let geometry, let notchScreen else { return }

        // Dragging the panel open takes the pointer *out* of the hot zone almost
        // immediately. Letting the zone logic run would make the panel collapse
        // under the very hand opening it.
        guard !model.isDragging else { return }

        applyChromeVisibility(notchScreen.isChromeHidden)

        let inside = geometry
            .hotZone(for: model.state, metrics: model.metrics, on: notchScreen.screen)
            .contains(location)

        // The window is much larger than what it draws, so it must stay deaf to
        // the mouse unless the pointer is actually on the silhouette. Otherwise
        // it swallows every click aimed at whatever is underneath — browser
        // tabs, menu bar items, anything in the top third of the screen.
        setPanelInteractive(inside)

        accelerateDwellIfSettled(inside: inside, at: location, model: model)

        guard inside != model.isPointerInside else { return }
        model.send(inside ? .pointerEntered : .pointerExited)
    }

    /// The model's timer guarantees the crossing delay; this only ever makes the
    /// panel open *sooner*, when the pointer has slowed enough to mean it.
    ///
    /// The 50 ms leave-watchdog supplies the samples, which matters: a pointer
    /// that lands and stops emits no more mouse-moved events at all, so nothing
    /// event-driven would ever fire.
    private func accelerateDwellIfSettled(inside: Bool, at location: CGPoint, model: NotchModel) {
        defer { lastSample = (location, Date()) }

        guard inside else {
            enteredAt = nil
            return
        }
        if enteredAt == nil { enteredAt = Date() }

        guard model.state == .idle,
              let enteredAt, let lastSample else { return }

        let now = Date()
        let speed = DwellGate.speed(from: lastSample.point, to: location,
                                    seconds: now.timeIntervalSince(lastSample.at))
        guard DwellGate.hasDwelled(insideFor: now.timeIntervalSince(enteredAt),
                                   speed: speed) else { return }
        model.send(.dwellElapsed)
    }

    private func setPanelInteractive(_ interactive: Bool) {
        guard let panel, panel.ignoresMouseEvents == interactive else { return }
        panel.ignoresMouseEvents = !interactive
        if Self.logsInteractivity { log("panel interactive = \(interactive)") }
        interactive ? startLeaveWatchdog() : stopLeaveWatchdog()
    }

    /// Correctness must not depend on event delivery.
    ///
    /// While the panel is interactive, mouse-moved events go to *us*, so the
    /// global monitor stops seeing them — and delivery to an inactive app's
    /// non-key panel is not something to rely on. If both monitors went quiet
    /// with the panel left interactive, it would silently swallow clicks again.
    /// So while it *is* interactive, poll instead. That is precisely the window
    /// in which the user is already interacting, so the cost is nothing.
    private func startLeaveWatchdog() {
        leaveWatchdog?.cancel()
        leaveWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                self.pointerMoved(to: NSEvent.mouseLocation)
            }
        }
    }

    private func stopLeaveWatchdog() {
        leaveWatchdog?.cancel()
        leaveWatchdog = nil
    }

    private static let logsInteractivity =
        ProcessInfo.processInfo.environment["ISLET_HIT_LOG"] != nil

    private func applyChromeVisibility(_ hidden: Bool) {
        guard lastChromeHidden != hidden else { return }
        lastChromeHidden = hidden
        model?.send(hidden ? .chromeHidden : .chromeShown)
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("islet: \(message)\n".utf8))
}

func rect(_ r: CGRect) -> String {
    String(format: "x %.0f…%.0f, y %.0f…%.0f (%.0f×%.0f)",
           r.minX, r.maxX, r.minY, r.maxY, r.width, r.height)
}

extension NotchController {
    /// `ISLET_SEED=1` writes three tasks straight through the model, so the
    /// store, the reload and the notch layout can be checked without typing.
    func seedForVerification() {
        guard ProcessInfo.processInfo.environment["ISLET_SEED"] != nil else { return }
        tasks.addDirectly("call the plumber", category: .toDo)
        tasks.addDirectly("renew passport", category: .deferred)
        tasks.addDirectly("hand the report to Marie", category: .delegated)
        tasks.addDirectly("book the dentist", category: .toDo)
        // One checked, to see it sink to the bottom.
        if let done = tasks.list.live.first { tasks.toggleCompletion(done.id) }
        log("seeded \(tasks.list.live.count) tasks")
    }
}

extension NotchController {
    /// AppKit asks whichever view `hitTest` returned whether it accepts the
    /// first mouse. Asking the hierarchy the same question is the only way to
    /// know the answer without a real click.
    fileprivate func logFirstMouseAnswer(_ geometry: PanelGeometry) {
        guard let panel, let content = panel.contentView else { return }
        for rect in geometry.interactiveRects(for: .idle) {
            let point = CGPoint(x: rect.midX, y: rect.midY)
            guard let hit = content.hitTest(point) else {
                log("first mouse at \(Int(point.x)),\(Int(point.y)): no view — click falls through")
                continue
            }
            log("first mouse at \(Int(point.x)),\(Int(point.y)): \(type(of: hit)) answers \(hit.acceptsFirstMouse(for: nil))")
        }
        log("panel becomesKeyOnlyIfNeeded = \(panel.becomesKeyOnlyIfNeeded)")
    }
}
