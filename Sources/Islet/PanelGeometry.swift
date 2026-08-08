import AppKit
import IsletCore

/// Maps notch metrics onto window and screen coordinates.
///
/// The panel window itself never resizes. It is created at the maximum size
/// once and only the shape inside it animates — resizing a window at 120 Hz
/// puts the window server on the critical path and tears. This is the AppKit
/// equivalent of "only animate transform and opacity".
struct PanelGeometry {
    let notch: NotchDimensions

    /// Sized for the **largest** the silhouette can ever get, not for what it is
    /// showing now: the window is a fixed canvas and the shape animates inside
    /// it. Taking the current height here would clip the panel the moment it
    /// grew — which it did, cutting off the last task.
    var size: CGSize {
        let widest = NotchMetrics.forState(
            .expanded, notch: notch, expandedHeight: NotchMetrics.ExpandedHeight.maximum
        )
        return CGSize(width: widest.width + 160, height: widest.height + 60)
    }

    func frame(on screen: NSScreen) -> CGRect {
        let size = size
        return CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Surgical hit testing (Q33)

    /// Rects that may receive clicks, in window coordinates (AppKit, y-up).
    /// Everything else falls through to the menu bar underneath.
    func interactiveRects(for state: NotchState) -> [CGRect] {
        let slot = NotchMetrics.glyphSlot(for: state)
        guard slot > 0 else { return [] }

        let metrics = NotchMetrics.forState(state, notch: notch)
        let centerX = size.width / 2
        let y = size.height - metrics.height

        return [
            CGRect(x: centerX - notch.width / 2 - slot, y: y,
                   width: slot, height: metrics.height),
            CGRect(x: centerX + notch.width / 2, y: y,
                   width: slot, height: metrics.height),
        ]
    }

    // MARK: - Pointer hot zone

    /// Where the pointer counts as "on the notch", in screen coordinates.
    ///
    /// Takes the *live* metrics rather than deriving them: the expanded height
    /// depends on how many tasks are showing, and a hot zone that disagrees with
    /// what is drawn is a panel that closes under your own pointer.
    func hotZone(for state: NotchState, metrics: NotchMetrics, on screen: NSScreen) -> CGRect {
        // Retracted: a thin strip across the top so the surface can be
        // summoned back exactly the way the menu bar is.
        if state == .hidden {
            let width = notch.width + 240
            return CGRect(x: screen.frame.midX - width / 2,
                          y: screen.frame.maxY - 6,
                          width: width, height: 6)
        }

        let width = metrics.width + metrics.invertedRadius * 2
        return CGRect(x: screen.frame.midX - width / 2,
                      y: screen.frame.maxY - metrics.height - 2,
                      width: width,
                      height: metrics.height + 2)
    }
}
