import SwiftUI

/// The motion contract. One place, so the whole app sings in tune.
///
/// Springs rather than durations for state changes: a spring keeps its
/// velocity when interrupted, a keyframe restarts from zero. Interruptibility
/// is the whole point.
@MainActor
public enum Motion {
    /// Debug slow-motion multiplier. Cheapest possible investment: at ×5 every
    /// easing mistake and every mistimed content reveal becomes obvious.
    public static var slowFactor: Double = 1

    public static let slowFactorCycle: [Double] = [1, 2, 5]

    /// Mirrors the system's "Reduce motion" setting, refreshed when it changes.
    ///
    /// Reduced motion means *fewer and gentler*, not none: opacity and colour
    /// transitions stay, because they aid comprehension. What goes is physics
    /// and displacement — springs become a short ease, and the row cascade stops
    /// moving anything.
    public static var prefersReducedMotion = false

    private static func spring(_ duration: Double, _ bounce: Double) -> Animation {
        if prefersReducedMotion { return .easeOut(duration: 0.08 * slowFactor) }
        return .spring(duration: duration * slowFactor, bounce: bounce)
    }

    /// Seen dozens of times a day → short, almost no bounce. At this frequency
    /// every 40 ms of it is felt.
    public static var peekIn: Animation { spring(0.18, 0.08) }

    /// The signature morph. Under 300 ms perceived, with just enough bounce.
    public static var expand: Animation { spring(0.32, 0.18) }

    /// Exit is always faster than entry: slow where the user decides, fast
    /// where the system responds.
    public static var collapse: Animation { spring(0.20, 0) }

    /// Rare (≈8×/day) → allowed to have character.
    public static var announce: Animation { spring(0.40, 0.25) }

    /// The panel growing or shrinking because its contents changed. Softer than
    /// an expansion: nothing was asked for, something simply arrived.
    public static var resize: Animation { spring(0.28, 0.12) }

    /// Content entering, behind the container.
    public static var contentIn: Animation { .easeOut(duration: 0.16 * slowFactor) }
    /// Content leaving. Shorter than `contentIn`: the same asymmetry as the
    /// silhouette, for the same reason.
    public static var contentOut: Animation { .easeOut(duration: 0.11 * slowFactor) }
    public static var glyph: Animation { .easeOut(duration: 0.14 * slowFactor) }
    /// Countdown text and progress ring: driven at 1 Hz, interpolated linearly
    /// so a ring advancing 1/1500 per second reads as continuous motion.
    public static var tick: Animation { .linear(duration: 1) }

    /// The container morphs first, the content follows. Never the reverse.
    public static var contentDelay: Double { 0.08 * slowFactor }
    public static var stagger: Double { 0.04 * slowFactor }

    /// Blur bridges a crossfade: without it the eye sees two objects
    /// overlapping, with it one thing transforming.
    public static let crossfadeBlur: CGFloat = 3

    public static let glyphRestOpacity: Double = 0.35
    public static let pressScale: CGFloat = 0.97

    public static func morph(from: NotchState, to: NotchState) -> Animation {
        if to == .expanded { return expand }
        if to == .peek { return peekIn }
        if from == .resting && to == .live { return announce }
        return collapse
    }

    @discardableResult
    public static func cycleSlowMotion() -> Double {
        let index = slowFactorCycle.firstIndex(of: slowFactor) ?? 0
        slowFactor = slowFactorCycle[(index + 1) % slowFactorCycle.count]
        return slowFactor
    }
}
