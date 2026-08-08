import CoreGraphics
import Foundation

/// Pulling the panel open, and the rules for where it lands when you let go.
///
/// A grabber is the vocabulary of a sheet you drag. Drawing one on something that
/// only responds to clicks is an affordance that lies, so it drags.
public enum DragToOpen: Sendable {
    /// Past halfway, it opens. Only consulted when the release was slow.
    public static let midpoint: CGFloat = 0.5

    /// Points per millisecond above which the *direction of the flick* decides,
    /// whatever distance was covered. Things in the real world carry momentum;
    /// a quick pull should be enough without dragging the whole way.
    public static let flickSpeed: CGFloat = 0.25

    /// How much of an overdrag actually shows. Past the ends the panel resists
    /// instead of stopping dead — nothing in the real world hits a wall.
    public static let resistance: CGFloat = 0.22

    /// - Parameters:
    ///   - base: progress when the drag began — 0 from Peek, 1 from Expanded.
    ///   - translation: pointer movement in points, positive downwards.
    ///   - distance: points between the two states.
    public static func progress(base: CGFloat, translation: CGFloat, distance: CGFloat) -> CGFloat {
        guard distance > 0 else { return base }
        let raw = base + translation / distance
        if raw > 1 { return 1 + (raw - 1) * resistance }
        if raw < 0 { return raw * resistance }
        return raw
    }

    /// Where it settles. `true` means expanded.
    public static func resolve(progress: CGFloat, velocity: CGFloat) -> Bool {
        if velocity > flickSpeed { return true }
        if velocity < -flickSpeed { return false }
        return progress > midpoint
    }
}
