import AppKit
import IsletCore
import SwiftUI

/// Owns the two ordinary windows. Built by hand rather than with SwiftUI scenes,
/// because Islet drives `NSApplication` itself — it has to, to own a panel that
/// lives above the menu bar.
@MainActor
final class WindowManager: NSObject {
    private let tasks: TaskModel
    private let settings: SettingsModel
    /// Fires whenever a window comes forward, whatever route brought it there —
    /// the gear, the context menu, ⌘L, ⌘,. A single choke point, so no path can
    /// forget to collapse the island behind it.
    var onWindowPresented: (() -> Void)?

    private var taskWindow: NSWindow?
    private var settingsWindow: NSWindow?

    init(tasks: TaskModel, settings: SettingsModel) {
        self.tasks = tasks
        self.settings = settings
        super.init()
    }

    // MARK: - Tasks

    @objc func showTasks() {
        if let taskWindow {
            present(taskWindow)
            return
        }

        let window = makeWindow(
            title: "Islet",
            size: CGSize(width: 460, height: 560),
            minSize: CGSize(width: 380, height: 320),
            content: TaskListView(model: tasks)
        )
        taskWindow = window
        present(window)
    }

    // MARK: - Settings

    @objc func showSettings() {
        if let settingsWindow {
            present(settingsWindow)
            return
        }

        let window = makeWindow(
            title: "Islet Settings",
            size: CGSize(width: 420, height: 400),
            minSize: CGSize(width: 420, height: 400),
            content: SettingsView(model: settings, tasks: tasks),
            resizable: false
        )
        settingsWindow = window
        present(window)
    }

    @objc func undoDelete() {
        tasks.undoDelete()
    }

    // MARK: - Plumbing

    private func makeWindow<Content: View>(
        title: String,
        size: CGSize,
        minSize: CGSize,
        content: Content,
        resizable: Bool = true
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        // No `.fullSizeContentView`, no transparent bar. Both were there for
        // the seamless look and both let the form scroll into the title: with a
        // transparent bar the rows crossed the title outright, and making the
        // bar opaque only turned that into a blurred ghost beside it. Neither is
        // worth a settings window. Content now stops where the title bar starts.
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.center()
        window.contentView = NSHostingView(rootView: content)
        return window
    }

    /// An accessory app has to activate to show a real window, or it opens
    /// behind whatever is in front.
    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // A window is in front now. Leaving the panel hanging open behind it
        // says two things are demanding attention when only one is.
        onWindowPresented?()
    }
}
