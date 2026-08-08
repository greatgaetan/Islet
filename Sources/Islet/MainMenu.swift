import AppKit

/// A minimal main menu.
///
/// Not decoration: without an Edit menu, ⌘V does not work in a text field, and
/// without an App menu there is no ⌘, and no ⌘Q. It also means that when ⌥Space
/// activates Islet, the menu bar shows something credible instead of going bare.
@MainActor
enum MainMenu {
    static func install(target: WindowManager) {
        let main = NSMenu()

        // MARK: App
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Islet",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(WindowManager.showSettings),
                                  keyEquivalent: ",")
        settings.target = target
        appMenu.addItem(settings)
        let tasks = NSMenuItem(title: "Tasks",
                               action: #selector(WindowManager.showTasks),
                               keyEquivalent: "l")
        tasks.target = target
        appMenu.addItem(tasks)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Islet",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Islet",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // MARK: Edit — the reason this menu exists at all.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let undo = NSMenuItem(title: "Undo Delete",
                              action: #selector(WindowManager.undoDelete),
                              keyEquivalent: "z")
        undo.target = target
        editMenu.addItem(undo)
        editMenu.addItem(.separator())
        // Sent down the responder chain to whatever text field has focus, which
        // is why these have no target.
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        // MARK: Window
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close",
                           action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}
