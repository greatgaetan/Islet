import IsletCore
import SwiftUI

/// Every colour in Islet, in one place.
///
/// Restraint is the constraint: these sit on a black bezel all day, so anything
/// saturated reads as a toy. They are desaturated enough to be quiet and far
/// enough apart in hue to be told apart at a 5 pt dot.
/// Separated by **lightness**, not only by hue.
///
/// Lab ΔE was the wrong yardstick: it describes two large patches, and these are
/// 5 pt marks, sometimes at 55 % opacity. At that size hue discrimination
/// collapses and lightness is what carries. An earlier attempt measured ΔE 58 —
/// comfortably "distinct" on paper — while sitting at L* 74 / 76 / 69: three
/// marks of effectively identical brightness. It looked wrong because it *was*
/// wrong.
///
/// These sit at L* **86 / 73 / 56**, which reads at a glance.
///
/// Delegate is an azure blue and not the plum it started as, because the palette
/// is **simulated under colour vision deficiency** and scored on its weakest
/// pair. The plum measured a healthy ΔE 59 to a normal eye and collapsed to
/// **ΔE 19** under deuteranopia and tritanopia — which is precisely what a
/// colour-blind reader reported. This blue holds at **ΔE 64 at its worst across
/// normal, deuteran, protan and tritan vision**, at 5.8:1 contrast on black.
///
/// A slightly deeper blue scored 74 and was passed over: it sat exactly on the
/// 4.5:1 AA floor, and ten points of separation are worth less than legibility
/// on a 9 pt glyph. And the mark itself
/// now carries a silhouette too (`TaskCategory.mark`), so the colour reinforces
/// the category rather than being the only thing that states it.
extension TaskCategory {
    var tint: Color {
        switch self {
        case .toDo: Color(red: 0.62, green: 0.88, blue: 0.98)      // pale cyan, L* 86
        case .deferred: Color(red: 0.88, green: 0.66, blue: 0.26)  // amber,      L* 73
        case .delegated: Color(red: 0.08, green: 0.52, blue: 1.00) // azure,      L* 56
        }
    }
}

extension PomodoroSegmentKind {
    /// The work tint is deliberately colourless, so a running timer is never
    /// mistaken for a category. The long-break blue does land within 14° of the
    /// To do cyan — accepted knowingly: it appears once per session, on a ring,
    /// in the other column, where no task dot is. Moving To do away from it
    /// would have meant green, which collides with the far more frequent
    /// short-break mint.
    var tint: Color {
        switch self {
        case .work: Color(red: 0.96, green: 0.96, blue: 0.96)
        case .shortBreak: Color(red: 0.55, green: 0.85, blue: 0.72)
        case .longBreak: Color(red: 0.56, green: 0.76, blue: 0.96)
        }
    }
}
