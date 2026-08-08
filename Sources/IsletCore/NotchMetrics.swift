import CoreGraphics
import SwiftUI

/// The physical notch of a display, in points.
public struct NotchDimensions: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat

    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }


}

/// Every dimension of the silhouette, as a *single* animatable value.
///
/// Width, height and both corner radii travel through one spring together, so
/// they cannot desynchronise mid-morph. That class of bug is invisible at full
/// speed and glaring at ×5.
public struct NotchMetrics: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    /// Convex radius of the two bottom corners.
    public var bottomRadius: CGFloat
    /// Concave radius where the silhouette flares out of the screen's top edge.
    /// This is what sells "the hardware got wider" instead of "a box appeared".
    public var invertedRadius: CGFloat

    public init(width: CGFloat, height: CGFloat, bottomRadius: CGFloat, invertedRadius: CGFloat) {
        self.width = width
        self.height = height
        self.bottomRadius = bottomRadius
        self.invertedRadius = invertedRadius
    }

    /// Width of one glyph slot beside the notch, per state.
    public static func glyphSlot(for state: NotchState, showsTimer: Bool = false) -> CGFloat {
        switch state {
        case .hidden: 0
        case .idle: showsTimer ? 84 : 28
        case .peek: 120
        case .expanded: 0
        }
    }

    /// How tall the expanded panel needs to be for what it is showing.
    ///
    /// A fixed height left the panel visibly half empty with a handful of tasks.
    /// Sizing to content removes the void *and* buys a motion moment for free:
    /// the island grows as you add to it.
    public enum ExpandedHeight {
        /// Imposed by the timer column — ring, loop line and buttons.
        public static let minimum: CGFloat = 230
        /// Past this the task list scrolls instead: a panel taller than this
        /// stops reading as a notch and starts reading as a window.
        public static let maximum: CGFloat = 420
        public static let row: CGFloat = 28
        /// Everything that is not a row: label, quick-add field, chips, hint and
        /// both paddings. Measured against the rendered layout — the list is
        /// given this exact height back, so the two cannot drift apart.
        public static let chrome: CGFloat = 162

        /// One card, its subtitle and a row of actions. Fixed, because a review
        /// that resized as you answered would move the buttons under your hand.
        public static let review: CGFloat = 250

        public static func forRows(_ rows: Int, notchHeight: CGFloat) -> CGFloat {
            let wanted = notchHeight + chrome + rowsHeight(rows, notchHeight: notchHeight)
            return Swift.min(Swift.max(wanted, minimum), maximum)
        }

        /// How much room the rows get — the same number the view uses, so the
        /// silhouette and its contents cannot disagree.
        public static func rowsHeight(_ rows: Int, notchHeight: CGFloat) -> CGFloat {
            let capped = Swift.min(Swift.max(0, rows), maxRows(notchHeight: notchHeight))
            return CGFloat(capped) * row
        }

        /// Past this the list scrolls rather than the notch growing without end.
        /// Longer lists are what the window is for.
        public static func maxRows(notchHeight: CGFloat) -> Int {
            Int(((maximum - notchHeight - chrome) / row).rounded(.down))
        }
    }

    public static func forState(
        _ state: NotchState,
        notch: NotchDimensions,
        expandedHeight: CGFloat? = nil,
        showsTimer: Bool = false
    ) -> NotchMetrics {
        let slot = glyphSlot(for: state, showsTimer: showsTimer)
        switch state {
        case .hidden:
            // Exactly the hardware: drawn black on black, invisible.
            return .init(width: notch.width, height: notch.height,
                         bottomRadius: 0, invertedRadius: 0)
        case .idle:
            // Same shape, wider when there is a countdown to hold. One state, one
            // rule: the silhouette fits what it carries.
            return .init(width: notch.width + slot * 2, height: notch.height,
                         bottomRadius: showsTimer ? 12 : 10,
                         invertedRadius: showsTimer ? 9 : 8)
        case .peek:
            return .init(width: notch.width + slot * 2, height: notch.height + 22,
                         bottomRadius: 16, invertedRadius: 10)
        case .expanded:
            return .init(width: max(640, notch.width + 300),
                         height: expandedHeight ?? ExpandedHeight.minimum,
                         bottomRadius: 26, invertedRadius: 14)
        }
    }
}

extension NotchMetrics: VectorArithmetic {
    public static var zero: NotchMetrics {
        .init(width: 0, height: 0, bottomRadius: 0, invertedRadius: 0)
    }

    public static func + (lhs: NotchMetrics, rhs: NotchMetrics) -> NotchMetrics {
        .init(width: lhs.width + rhs.width,
              height: lhs.height + rhs.height,
              bottomRadius: lhs.bottomRadius + rhs.bottomRadius,
              invertedRadius: lhs.invertedRadius + rhs.invertedRadius)
    }

    public static func - (lhs: NotchMetrics, rhs: NotchMetrics) -> NotchMetrics {
        .init(width: lhs.width - rhs.width,
              height: lhs.height - rhs.height,
              bottomRadius: lhs.bottomRadius - rhs.bottomRadius,
              invertedRadius: lhs.invertedRadius - rhs.invertedRadius)
    }

    public mutating func scale(by rhs: Double) {
        width *= rhs
        height *= rhs
        bottomRadius *= rhs
        invertedRadius *= rhs
    }

    public var magnitudeSquared: Double {
        Double(width * width + height * height
               + bottomRadius * bottomRadius
               + invertedRadius * invertedRadius)
    }
}
