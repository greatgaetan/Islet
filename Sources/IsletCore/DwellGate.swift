import CoreGraphics
import Foundation

/// Decides when hovering the notch counts as *intent* rather than *passing by*.
///
/// A single fixed delay cannot do both jobs. The notch sits directly under the
/// path your pointer takes to reach the menu bar, so a short delay opens the
/// panel every time you cross it — and a long one makes a deliberate hover feel
/// sluggish, dozens of times a day.
///
/// So the delay depends on how the pointer arrived. Aiming at something means
/// slowing down; crossing means not slowing down at all. That is a far better
/// signal than any timer.
public enum DwellGate: Sendable {
    /// Deliberate arrival: the pointer has slowed to aim.
    public static let settled: TimeInterval = 0.08
    /// Fly-past: the delay a crossing pointer has to survive.
    public static let crossing: TimeInterval = 0.25
    /// Points per millisecond. Above this, the pointer is travelling somewhere
    /// else and the notch is merely in the way.
    public static let crossingSpeed: CGFloat = 0.35

    /// - Parameters:
    ///   - elapsed: seconds the pointer has been inside the hot zone.
    ///   - speed: current pointer speed in points per millisecond.
    public static func hasDwelled(insideFor elapsed: TimeInterval, speed: CGFloat) -> Bool {
        if elapsed >= crossing { return true }
        return speed < crossingSpeed && elapsed >= settled
    }

    /// Points per millisecond between two samples. Zero when no time passed, so
    /// a duplicate sample never reads as infinite speed.
    public static func speed(from: CGPoint, to: CGPoint, seconds: TimeInterval) -> CGFloat {
        guard seconds > 0 else { return 0 }
        let dx = to.x - from.x
        let dy = to.y - from.y
        return (dx * dx + dy * dy).squareRoot() / CGFloat(seconds * 1000)
    }
}
