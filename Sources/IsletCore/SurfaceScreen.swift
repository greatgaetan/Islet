import Foundation

/// Which display Islet draws on.
///
/// With a notch the answer is obvious: the hardware is there, so that is where
/// the illusion lives. Without one it has to be chosen, and the only defensible
/// choice is the display carrying the **menu bar** — Islet is chrome at the top
/// of the screen, and that is where the top of the screen means something.
///
/// Never "the main screen": `NSScreen.main` follows the key window and moves
/// around under you.
public struct ScreenCandidate: Equatable, Sendable {
    public let hasNotch: Bool
    /// The display the menu bar lives on — the one at the origin of the
    /// arrangement, not whichever happens to hold the focused window.
    public let carriesMenuBar: Bool

    public init(hasNotch: Bool, carriesMenuBar: Bool) {
        self.hasNotch = hasNotch
        self.carriesMenuBar = carriesMenuBar
    }
}

public enum SurfaceScreen: Sendable {
    /// Index of the display to draw on, or nil when there is nothing to draw on.
    public static func choose(from candidates: [ScreenCandidate]) -> Int? {
        // A real notch always wins, even when it is not the menu bar's display:
        // that is the whole point of the app, and the only place the silhouette
        // can be genuinely invisible at rest.
        if let notched = candidates.firstIndex(where: \.hasNotch) { return notched }
        if let primary = candidates.firstIndex(where: \.carriesMenuBar) { return primary }
        return candidates.isEmpty ? nil : 0
    }
}

public extension NotchDimensions {
    /// What stands in for a notch on a display that has none.
    ///
    /// Width is not zero: the two halves need somewhere to sit apart, or the
    /// glyphs collide and the silhouette stops reading as an island with sides.
    /// It is narrower than a real notch because there is no camera housing to
    /// clear — only a gap to keep.
    static func synthetic(menuBarHeight: CGFloat) -> NotchDimensions {
        NotchDimensions(width: 56, height: max(22, menuBarHeight))
    }
}
