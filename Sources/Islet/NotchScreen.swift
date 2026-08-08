import AppKit
import IsletCore

/// Locates the display Islet lives on, and reports whether the system is
/// currently showing its own top chrome.
struct NotchScreen {
    let screen: NSScreen
    let dimensions: NotchDimensions
    /// False on a Mac with no notch, where the silhouette is a floating pill
    /// rather than an extension of the hardware. It changes two things: the
    /// geometry it stands in for, and what "hidden" can mean.
    let hasPhysicalNotch: Bool

    static func locate() -> NotchScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        let candidates = screens.map { screen in
            ScreenCandidate(
                hasNotch: notchWidth(of: screen) != nil,
                // The menu bar lives on the display at the origin of the
                // arrangement — not on `NSScreen.main`, which follows the key
                // window and moves around under you.
                carriesMenuBar: screen.frame.origin == .zero
            )
        }
        guard let index = SurfaceScreen.choose(from: candidates) else { return nil }
        let screen = screens[index]

        if let width = notchWidth(of: screen) {
            return NotchScreen(
                screen: screen,
                dimensions: NotchDimensions(width: width, height: screen.safeAreaInsets.top),
                hasPhysicalNotch: true
            )
        }

        // No notch: the silhouette hangs from the top edge as a pill, sized to
        // sit within the menu bar rather than pretending there is hardware to
        // hug. Most Macs in use have no notch — every desktop, and every laptop
        // before 2021 — so this is not a fallback, it is the common case.
        return NotchScreen(
            screen: screen,
            dimensions: .synthetic(menuBarHeight: NSStatusBar.system.thickness),
            hasPhysicalNotch: false
        )
    }

    /// `ISLET_NO_NOTCH=1` pretends the hardware has none, so the pill rendering
    /// can be seen without unplugging anything. Most people run Islet this way
    /// for real; the author cannot.
    private static let ignoresHardware =
        ProcessInfo.processInfo.environment["ISLET_NO_NOTCH"] != nil

    private static func notchWidth(of screen: NSScreen) -> CGFloat? {
        guard !ignoresHardware else { return nil }
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let width = screen.frame.width - left.width - right.width
        guard width > 0, screen.safeAreaInsets.top > 0 else { return nil }
        return width
    }

    /// Islet mirrors its host: where macOS hides its menu bar, Islet retracts.
    ///
    /// Provisional heuristic — when the visible frame is flush with the top of
    /// the screen, the menu bar is not there (full-screen space, or the
    /// "automatically hide the menu bar" setting).
    var isChromeHidden: Bool {
        screen.visibleFrame.maxY >= screen.frame.maxY - 1
    }
}
