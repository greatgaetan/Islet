import XCTest
@testable import IsletCore

final class NotchStateMachineTests: XCTestCase {
    func testStartsAtRest() {
        XCTAssertEqual(NotchStateMachine().state, .idle)
    }

    func testDwellIsRequiredToReachPeek() {
        var machine = NotchStateMachine()
        machine.handle(.pointerEntered)
        XCTAssertEqual(machine.state, .idle, "entering alone must not expand anything")
        machine.handle(.dwellElapsed)
        XCTAssertEqual(machine.state, .peek)
    }

    func testDwellAfterExitIsIgnored() {
        var machine = NotchStateMachine()
        machine.handle(.pointerEntered)
        machine.handle(.pointerExited)
        machine.handle(.dwellElapsed)
        XCTAssertEqual(machine.state, .idle, "a late dwell must not resurrect the panel")
    }

    func testClickShortCircuitsDwell() {
        var machine = NotchStateMachine()
        machine.handle(.pointerEntered)
        machine.handle(.clicked)
        XCTAssertEqual(machine.state, .expanded)
    }

    func testGraceReturnsToRestOnlyOnceThePointerIsGone() {
        var machine = NotchStateMachine()
        machine.handle(.pointerEntered)
        machine.handle(.clicked)
        machine.handle(.graceElapsed)
        XCTAssertEqual(machine.state, .expanded, "pointer still inside")
        machine.handle(.pointerExited)
        machine.handle(.graceElapsed)
        XCTAssertEqual(machine.state, .idle)
    }

    func testEditingLocksThePanelOpen() {
        var machine = NotchStateMachine()
        machine.handle(.editingBegan)
        machine.handle(.pointerExited)
        machine.handle(.graceElapsed)
        XCTAssertEqual(machine.state, .expanded, "typed text must never be lost to a stray pointer")
        machine.handle(.editingEnded)
        machine.handle(.graceElapsed)
        XCTAssertEqual(machine.state, .idle)
    }

    /// The point of merging `resting` and `live`: a timer starting changes what
    /// the surface *shows*, and nothing about where it *is*.
    func testStartingATimerDoesNotMoveTheSurface() {
        var machine = NotchStateMachine()
        XCTAssertEqual(machine.state, .idle)
        machine.handle(.timerBecameActive)
        XCTAssertEqual(machine.state, .idle, "the appearance changed; the state did not")
        machine.handle(.timerBecameIdle)
        XCTAssertEqual(machine.state, .idle)
    }

    func testATimerStartingWhileExpandedDoesNotYankThePanelShut() {
        var machine = NotchStateMachine()
        machine.handle(.pointerEntered)
        machine.handle(.clicked)
        machine.handle(.timerBecameActive)
        XCTAssertEqual(machine.state, .expanded)
    }

    func testATimerRunningStillRestsAtIdle() {
        var machine = NotchStateMachine()
        machine.handle(.timerBecameActive)
        XCTAssertEqual(machine.state, .idle)
        machine.handle(.pointerEntered)
        machine.handle(.dwellElapsed)
        XCTAssertEqual(machine.state, .peek)
        machine.handle(.pointerExited)
        machine.handle(.graceElapsed)
        XCTAssertEqual(machine.state, .idle, "back to idle, not to hidden or peek")
    }

    func testHiddenChromeRetractsButATimerStillWins() {
        var machine = NotchStateMachine()
        machine.handle(.chromeHidden)
        XCTAssertEqual(machine.state, .hidden)

        machine.handle(.timerBecameActive)
        XCTAssertEqual(machine.state, .idle, "a quiet ring is worth most in full screen")

        machine.handle(.timerBecameIdle)
        XCTAssertEqual(machine.state, .hidden)
    }

    func testHiddenSurfaceIsSummonedByTheTopEdge() {
        var machine = NotchStateMachine()
        machine.handle(.chromeHidden)
        machine.handle(.pointerEntered)
        XCTAssertEqual(machine.state, .idle, "mirrors how the menu bar reveals itself")
        machine.handle(.pointerExited)
        machine.handle(.graceElapsed)
        XCTAssertEqual(machine.state, .hidden)
    }

    func testClickIsIgnoredWhileRetracted() {
        var machine = NotchStateMachine()
        machine.handle(.chromeHidden)
        machine.handle(.clicked)
        XCTAssertEqual(machine.state, .hidden)
    }

    // MARK: - Announcements

    func testAnnouncementOpensAndClosesItself() {
        var machine = NotchStateMachine()
        machine.handle(.timerBecameActive)
        machine.handle(.announcementBegan)
        XCTAssertEqual(machine.state, .peek)
        machine.handle(.announcementEnded)
        XCTAssertEqual(machine.state, .idle)
    }

    func testAnnouncementNeverYanksAnOpenPanelShut() {
        var machine = NotchStateMachine()
        machine.handle(.pointerEntered)
        machine.handle(.clicked)
        machine.handle(.announcementBegan)
        XCTAssertEqual(machine.state, .expanded)
    }

    func testAnnouncementStaysSilentInFullScreen() {
        var machine = NotchStateMachine()
        machine.handle(.chromeHidden)
        machine.handle(.timerBecameActive)
        machine.handle(.announcementBegan)
        XCTAssertEqual(machine.state, .idle, "only the ring hue changes in full screen")
    }

    func testAnnouncementDoesNotCloseUnderThePointer() {
        var machine = NotchStateMachine()
        machine.handle(.timerBecameActive)
        machine.handle(.announcementBegan)
        machine.handle(.pointerEntered)
        machine.handle(.announcementEnded)
        XCTAssertEqual(machine.state, .peek)
    }

    // MARK: - Pending decision

    func testAPendingDecisionLocksThePanelOpen() {
        var machine = NotchStateMachine()
        machine.handle(.decisionRequired)
        XCTAssertEqual(machine.state, .peek)
        XCTAssertTrue(machine.isLockedOpen)

        machine.handle(.pointerExited)
        machine.handle(.graceElapsed)
        XCTAssertEqual(machine.state, .peek, "a question must not close before it is answered")

        machine.handle(.decisionResolved)
        machine.handle(.graceElapsed)
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - Summoned from the keyboard

    func testKeyboardPresentationOpensExpandedAndStaysThere() {
        var machine = NotchStateMachine()
        machine.handle(.presentedByKeyboard)
        XCTAssertEqual(machine.state, .expanded)

        // The pointer was never near it, so the usual exit-plus-grace rule has
        // nothing to work with — it must not close on its own.
        machine.handle(.graceElapsed)
        XCTAssertEqual(machine.state, .expanded)
    }

    func testThePointerTakesOverOnceItArrives() {
        var machine = NotchStateMachine()
        machine.handle(.presentedByKeyboard)

        machine.handle(.pointerEntered)
        XCTAssertFalse(machine.isKeyboardPresented, "the pointer now owns the panel")
        XCTAssertEqual(machine.state, .expanded)

        machine.handle(.pointerExited)
        machine.handle(.graceElapsed)
        XCTAssertEqual(machine.state, .idle, "from then on it behaves like any hover")
    }

    func testEscapeClosesAPanelThePointerNeverTouched() {
        var machine = NotchStateMachine()
        machine.handle(.presentedByKeyboard)
        machine.handle(.dismissRequested)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertFalse(machine.isKeyboardPresented)
    }

    func testKeyboardPresentationFallsBackToLiveWhenATimerRuns() {
        var machine = NotchStateMachine()
        machine.handle(.timerBecameActive)
        machine.handle(.presentedByKeyboard)
        machine.handle(.dismissRequested)
        XCTAssertEqual(machine.state, .idle)
    }

    func testADragCanLandInEitherState() {
        var machine = NotchStateMachine()
        machine.handle(.pointerEntered)
        machine.handle(.dwellElapsed)

        machine.handle(.dragEnded(expanded: true))
        XCTAssertEqual(machine.state, .expanded)

        // Nothing else in the machine could take Expanded back to Peek, which is
        // exactly why this event exists.
        machine.handle(.dragEnded(expanded: false))
        XCTAssertEqual(machine.state, .peek)
    }

    func testDismissClearsEveryLock() {
        var machine = NotchStateMachine()
        machine.handle(.editingBegan)
        machine.handle(.decisionRequired)
        machine.handle(.presentedByKeyboard)
        machine.handle(.dismissRequested)
        XCTAssertFalse(machine.isLockedOpen)
        XCTAssertEqual(machine.state, .idle)
    }
}

final class NotchMetricsTests: XCTestCase {
    private let notch = NotchDimensions(width: 200, height: 38)

    func testHiddenMatchesTheHardwareExactly() {
        let metrics = NotchMetrics.forState(.hidden, notch: notch)
        XCTAssertEqual(metrics.width, notch.width)
        XCTAssertEqual(metrics.height, notch.height)
        XCTAssertEqual(metrics.bottomRadius, 0)
        XCTAssertEqual(metrics.invertedRadius, 0)
    }

    func testEveryStateGrowsMonotonically() {
        let widths = [
            NotchMetrics.forState(.hidden, notch: notch).width,
            NotchMetrics.forState(.idle, notch: notch).width,
            NotchMetrics.forState(.idle, notch: notch, showsTimer: true).width,
            NotchMetrics.forState(.peek, notch: notch).width,
            NotchMetrics.forState(.expanded, notch: notch).width,
        ]
        XCTAssertEqual(widths, widths.sorted(), "a state must never be narrower than a smaller one")
    }

    func testIdleWidensToHoldACountdown() {
        let bare = NotchMetrics.forState(.idle, notch: notch)
        let timing = NotchMetrics.forState(.idle, notch: notch, showsTimer: true)
        XCTAssertGreaterThan(timing.width, bare.width)
        XCTAssertEqual(timing.height, bare.height, "it widens; it does not grow taller")
    }

    func testExpandedHeightFollowsItsContent() {
        let empty = NotchMetrics.ExpandedHeight.forRows(0, notchHeight: 38)
        let few = NotchMetrics.ExpandedHeight.forRows(4, notchHeight: 38)
        let many = NotchMetrics.ExpandedHeight.forRows(40, notchHeight: 38)

        XCTAssertEqual(empty, NotchMetrics.ExpandedHeight.minimum,
                       "the timer column sets the floor")
        XCTAssertGreaterThan(few, empty)

        // Rows are quantised, so the ceiling is reached in whole rows and never
        // exactly — which is the point: a partial row can never be drawn.
        let cap = NotchMetrics.ExpandedHeight.maxRows(notchHeight: 38)
        XCTAssertEqual(many, NotchMetrics.ExpandedHeight.forRows(cap, notchHeight: 38),
                       "past the ceiling the list scrolls instead of the notch growing")
        XCTAssertLessThanOrEqual(many, NotchMetrics.ExpandedHeight.maximum)
    }

    func testTheListIsGivenExactlyTheRoomTheShapeAllows() {
        // The panel height and the list height come from the same function, so
        // a row can never be half-drawn at the bottom.
        let notch: CGFloat = 38
        for rows in 0...12 {
            let panel = NotchMetrics.ExpandedHeight.forRows(rows, notchHeight: notch)
            let list = NotchMetrics.ExpandedHeight.rowsHeight(rows, notchHeight: notch)
            XCTAssertLessThanOrEqual(
                notch + NotchMetrics.ExpandedHeight.chrome + list, panel + 0.001,
                "\(rows) rows do not fit in the silhouette they were sized against"
            )
        }
    }

    func testRowsStopGrowingAtTheCeiling() {
        let notch: CGFloat = 38
        let cap = NotchMetrics.ExpandedHeight.maxRows(notchHeight: notch)
        XCTAssertGreaterThan(cap, 3, "a notch panel that fits three tasks is not worth having")
        XCTAssertEqual(NotchMetrics.ExpandedHeight.rowsHeight(cap + 20, notchHeight: notch),
                       NotchMetrics.ExpandedHeight.rowsHeight(cap, notchHeight: notch))
    }

    func testEachExtraRowAddsExactlyOneRowOfHeight() {
        let five = NotchMetrics.ExpandedHeight.forRows(5, notchHeight: 38)
        let six = NotchMetrics.ExpandedHeight.forRows(6, notchHeight: 38)
        XCTAssertEqual(six - five, NotchMetrics.ExpandedHeight.row, accuracy: 0.001)
    }

    func testNegativeRowCountsCannotShrinkThePanel() {
        XCTAssertEqual(NotchMetrics.ExpandedHeight.forRows(-3, notchHeight: 38),
                       NotchMetrics.ExpandedHeight.minimum)
    }

    func testCornerRadiusGrowsWithSize() {
        let resting = NotchMetrics.forState(.idle, notch: notch)
        let expanded = NotchMetrics.forState(.expanded, notch: notch)
        XCTAssertGreaterThan(expanded.bottomRadius, resting.bottomRadius)
        XCTAssertGreaterThan(expanded.invertedRadius, resting.invertedRadius)
    }

    func testMetricsInterpolateAsOneValue() {
        let a = NotchMetrics.forState(.idle, notch: notch)
        let b = NotchMetrics.forState(.expanded, notch: notch)
        var midpoint = b - a
        midpoint.scale(by: 0.5)
        let halfway = a + midpoint
        XCTAssertEqual(halfway.width, (a.width + b.width) / 2, accuracy: 0.001)
        XCTAssertEqual(halfway.bottomRadius, (a.bottomRadius + b.bottomRadius) / 2, accuracy: 0.001)
    }
}

final class DwellGateTests: XCTestCase {
    func testASettledPointerOpensAlmostAtOnce() {
        XCTAssertTrue(DwellGate.hasDwelled(insideFor: 0.09, speed: 0.05),
                      "slowing down to aim is the clearest statement of intent there is")
    }

    func testAPointerCrossingOnItsWayToTheMenuBarIsIgnored() {
        XCTAssertFalse(DwellGate.hasDwelled(insideFor: 0.09, speed: 2.0))
        XCTAssertFalse(DwellGate.hasDwelled(insideFor: 0.20, speed: 2.0))
    }

    func testEvenAFastPointerOpensItIfItStaysLongEnough() {
        XCTAssertTrue(DwellGate.hasDwelled(insideFor: 0.26, speed: 9.0),
                      "the crossing delay is a floor, not a veto")
    }

    func testNothingOpensBeforeTheSettledDelay() {
        XCTAssertFalse(DwellGate.hasDwelled(insideFor: 0.01, speed: 0))
    }

    func testSpeedIsPointsPerMillisecond() {
        let speed = DwellGate.speed(from: .zero, to: CGPoint(x: 100, y: 0), seconds: 0.1)
        XCTAssertEqual(speed, 1.0, accuracy: 0.0001)
    }

    func testADuplicateSampleIsNotInfinitelyFast() {
        XCTAssertEqual(DwellGate.speed(from: .zero, to: CGPoint(x: 5, y: 5), seconds: 0), 0,
                       "a divide by zero here would veto every hover forever")
    }
}

final class DragToOpenTests: XCTestCase {
    private let distance: CGFloat = 250

    func testDraggingDownFromPeekTracksThePointer() {
        XCTAssertEqual(DragToOpen.progress(base: 0, translation: 125, distance: distance),
                       0.5, accuracy: 0.0001)
    }

    func testDraggingUpFromExpandedTracksItToo() {
        XCTAssertEqual(DragToOpen.progress(base: 1, translation: -125, distance: distance),
                       0.5, accuracy: 0.0001)
    }

    func testOverdraggingResistsInsteadOfHittingAWall() {
        let past = DragToOpen.progress(base: 1, translation: 250, distance: distance)
        XCTAssertGreaterThan(past, 1, "some of the overdrag still shows")
        XCTAssertLessThan(past, 1.3, "but far less than it was asked for")
    }

    func testUnderdraggingResistsSymmetrically() {
        let under = DragToOpen.progress(base: 0, translation: -250, distance: distance)
        XCTAssertLessThan(under, 0)
        XCTAssertGreaterThan(under, -0.3)
    }

    func testAQuickFlickWinsWhateverTheDistance() {
        XCTAssertTrue(DragToOpen.resolve(progress: 0.05, velocity: 1.2),
                      "a flick carries momentum; it should not have to travel the whole way")
        XCTAssertFalse(DragToOpen.resolve(progress: 0.95, velocity: -1.2))
    }

    func testASlowReleaseGoesToWhicheverIsNearer() {
        XCTAssertTrue(DragToOpen.resolve(progress: 0.6, velocity: 0.01))
        XCTAssertFalse(DragToOpen.resolve(progress: 0.4, velocity: 0.01))
    }

    func testZeroDistanceCannotDivideByZero() {
        XCTAssertEqual(DragToOpen.progress(base: 0.3, translation: 99, distance: 0), 0.3)
    }
}
