import AppKit
import IsletCore

/// Locates the display Islet lives on, and reports whether the system is
/// currently showing its own top chrome.
struct NotchScreen {
    let screen: NSScreen
    let dimensions: NotchDimensions
    let hasPhysicalNotch: Bool

    /// Always the built-in notched display — never `NSScreen.main`, which is
    /// frequently an external monitor. Islet lives where the hardware is.
    static func locate() -> NotchScreen? {
        for screen in NSScreen.screens {
            guard let leftArea = screen.auxiliaryTopLeftArea,
                  let rightArea = screen.auxiliaryTopRightArea else { continue }

            let notchWidth = screen.frame.width - leftArea.width - rightArea.width
            let notchHeight = screen.safeAreaInsets.top
            guard notchWidth > 0, notchHeight > 0 else { continue }

            return NotchScreen(
                screen: screen,
                dimensions: NotchDimensions(width: notchWidth, height: notchHeight),
                hasPhysicalNotch: true
            )
        }

        // Development escape hatch: no notched display attached (lid closed, or
        // external-only). Draws the silhouette on the main screen so geometry
        // work can continue. Opt-in, never a shipping path.
        guard ProcessInfo.processInfo.environment["ISLET_FAKE_NOTCH"] != nil,
              let main = NSScreen.main else { return nil }

        return NotchScreen(screen: main, dimensions: .fallback, hasPhysicalNotch: false)
    }

    /// Islet mirrors its host: where macOS hides its menu bar, Islet retracts.
    ///
    /// Provisional heuristic — when the visible frame is flush with the top of
    /// the screen, the menu bar is not there (full-screen space, or the
    /// "automatically hide the menu bar" setting). Worth revisiting in
    /// milestone 3 once there is real content to protect.
    var isChromeHidden: Bool {
        screen.visibleFrame.maxY >= screen.frame.maxY - 1
    }
}
