import AppKit
import IsletCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tasks = TaskModel(
        store: JSONFile.inApplicationSupport(named: "tasks", fallback: TaskList())
    )
    private let settings = SettingsModel(
        store: JSONFile.inApplicationSupport(named: "settings", fallback: IsletSettings.default)
    )
    private let history = SessionHistoryModel(
        store: JSONFile.inApplicationSupport(named: "history", fallback: SessionHistory())
    )
    private lazy var recap = RecapModel(tasks: tasks)
    private lazy var controller = NotchController(tasks: tasks, history: history, recap: recap)
    private lazy var windows = WindowManager(tasks: tasks, settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let raw = ProcessInfo.processInfo.environment["ISLET_SLOWMO"],
           let factor = Double(raw) {
            Motion.slowFactor = factor
        }

        let launch = Preferences.recordLaunch()
        log("launch #\(launch), bundle \(Bundle.main.bundleIdentifier ?? "none — notifications and login item are inert")")

        switch ProcessInfo.processInfo.environment["ISLET_LOGIN_ITEM"] {
        case "on": LoginItem.enable()
        case "off": LoginItem.disable()
        default: break
        }

        windows.onWindowPresented = { [controller] in controller.collapsePanel() }
        MainMenu.install(target: windows)

        // The system can change this while Islet is running, so it is read now
        // and re-read whenever it changes.
        applyReducedMotion()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyReducedMotion() }
        }

        Chime.preload()
        controller.isSoundEnabled = { [settings] in settings.settings.playsSound }
        controller.onShowTasks = { [windows] in windows.showTasks() }
        controller.onShowSettings = { [windows] in windows.showSettings() }
        controller.start()

        settings.onPomodoroChanged = { [weak self] configuration in
            self?.controller.pomodoro?.configuration = configuration
        }

        Task { @MainActor in
            await settings.load()
            await tasks.load()
            await history.load()
            // Only after the list is on disk-backed footing: offering to review
            // an empty board because loading had not finished would be absurd.
            recap.start(recapHour: { [settings] in settings.settings.recapHour },
                        opensItself: { [settings] in settings.settings.recapOpensItself })
            controller.seedForVerification()

            // The window opens by itself exactly once, ever: on a first launch
            // the notch is at rest and therefore almost invisible, so without
            // this nobody would know Islet had started at all.
            if launch == 1 { windows.showTasks() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [controller] _ in
            MainActor.assumeIsolated { controller.screenParametersChanged() }
        }
    }

    private func applyReducedMotion() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard reduce != Motion.prefersReducedMotion else { return }
        Motion.prefersReducedMotion = reduce
        log("reduce motion \(reduce ? "on" : "off")")
    }

    /// A debounced save would lose the last edit on quit.
    func applicationWillTerminate(_ notification: Notification) {
        var finished = false
        Task { @MainActor in
            await tasks.flush()
            await settings.flush()
            await history.flush()
            finished = true
        }

        // Spin the run loop rather than blocking it. Blocking here — with a
        // semaphore or `DispatchGroup.wait` — deadlocks: the flush needs the
        // main actor, and the main thread would be the thing holding it up.
        let deadline = Date().addingTimeInterval(2)
        while !finished, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// No Dock icon: Islet is chrome, not an app window. It still gets a main menu,
// which it needs for ⌘V in the quick-add field.
application.setActivationPolicy(.accessory)
application.run()
