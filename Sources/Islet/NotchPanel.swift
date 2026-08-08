import AppKit
import SwiftUI

/// A borderless, non-activating panel that sits above the menu bar.
///
/// Non-activating matters more than it looks: clicking the glyph must never
/// steal focus from whatever you are typing in.
final class NotchPanel: NSPanel {
    private var passthrough: PassthroughContentView?

    init(size: CGSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Do not seize key status just because someone clicked a button. Without
        // this the panel takes the keyboard on any click, and AppKit spends that
        // click on the transfer instead of delivering it — the "click twice to do
        // anything" bug. A text field still gets key status, because it needs it.
        becomesKeyOnlyIfNeeded = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // hardware does not cast a shadow on itself
        // The silhouette is always black, whatever the system appearance is. Without
        // this, every system-drawn detail inside it — text-field placeholders,
        // selection highlights, menus — gets painted for a light background and
        // vanishes. Pinning the appearance fixes the whole class at once.
        appearance = NSAppearance(named: .darkAqua)
        acceptsMouseMovedEvents = true
        // Starts deaf to the mouse, and only wakes up while the pointer is
        // actually on the silhouette. This window is far larger than what it
        // draws — returning `nil` from `hitTest` does *not* pass a click
        // through, it only stops one of our own views from handling it, so the
        // click would be swallowed. `ignoresMouseEvents` is the only mechanism
        // that genuinely hands the click to the window underneath.
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func install<Content: View>(
        rootView: Content,
        isFullyInteractive: @escaping () -> Bool,
        interactiveRects: @escaping () -> [CGRect]
    ) {
        let container = PassthroughContentView()
        container.isFullyInteractive = isFullyInteractive
        container.interactiveRects = interactiveRects

        let hosting = FirstMouseHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        contentView = container
        passthrough = container
    }
}

/// Lets clicks through everywhere except the few rects that mean something.
///
/// The menu bar stays sovereign: Islet is the guest. Returning `nil` from
/// `hitTest` hands the event to whatever window is underneath.
final class PassthroughContentView: NSView {
    var isFullyInteractive: () -> Bool = { false }
    var interactiveRects: () -> [CGRect] = { [] }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isFullyInteractive() { return super.hitTest(point) }
        for rect in interactiveRects() where rect.contains(point) {
            return super.hitTest(point)
        }
        return nil
    }

    /// The first click has to *do* the thing, not merely wake the window up.
    /// Islet is never the active app when you reach for it, so every click on it
    /// would otherwise be a first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// `NSHostingView` says no to first mouse by default, and AppKit asks whichever
/// view `hitTest` returned — so the answer has to be given here too.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
