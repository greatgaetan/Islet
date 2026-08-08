import IsletCore
import SwiftUI

/// The silhouette: two concave corners flaring out of the screen's top edge,
/// two convex corners at the bottom.
///
/// The concave pair is the whole trick. Without them the panel reads as a box
/// glued under the notch; with them the black appears to flow out of the bezel.
struct NotchShape: Shape {
    var metrics: NotchMetrics

    var animatableData: NotchMetrics {
        get { metrics }
        set { metrics = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let width = max(metrics.width, 1)
        let height = max(metrics.height, 1)

        let centerX = rect.midX
        let left = centerX - width / 2
        let right = centerX + width / 2
        let top = rect.minY

        // Clamp so extreme intermediate spring values can never self-intersect.
        let bottom = min(metrics.bottomRadius, min(width / 2, height))
        let inverted = max(0, min(metrics.invertedRadius,
                                  min(left - rect.minX, rect.maxX - right)))

        var path = Path()

        // Concave flare, top-left. The control point sits *at* the corner, so
        // the curve bows towards it and bites into the black.
        path.move(to: CGPoint(x: left - inverted, y: top))
        path.addQuadCurve(to: CGPoint(x: left, y: top + inverted),
                          control: CGPoint(x: left, y: top))

        path.addLine(to: CGPoint(x: left, y: top + height - bottom))
        path.addQuadCurve(to: CGPoint(x: left + bottom, y: top + height),
                          control: CGPoint(x: left, y: top + height))

        path.addLine(to: CGPoint(x: right - bottom, y: top + height))
        path.addQuadCurve(to: CGPoint(x: right, y: top + height - bottom),
                          control: CGPoint(x: right, y: top + height))

        path.addLine(to: CGPoint(x: right, y: top + inverted))
        path.addQuadCurve(to: CGPoint(x: right + inverted, y: top),
                          control: CGPoint(x: right, y: top))

        // Closing runs straight back along the screen's top edge.
        path.closeSubpath()
        return path
    }
}
