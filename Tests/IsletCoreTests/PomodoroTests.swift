import XCTest
@testable import IsletCore

final class PomodoroPlanTests: XCTestCase {
    func testDefaultPlanIsTheClassicShape() {
        let plan = PomodoroConfiguration.default.plan
        XCTAssertEqual(plan.map(\.kind), [
            .work, .shortBreak,
            .work, .shortBreak,
            .work, .shortBreak,
            .work, .longBreak,
        ], "the long break replaces the fourth short one — it is not added after it")
    }

    func testDefaultSessionRunsTwoHoursTen() {
        // 4×25 + 3×5 + 15 = 130 minutes. The decision, locked in a test.
        XCTAssertEqual(PomodoroConfiguration.default.totalSeconds, 130 * 60)
    }

    func testSessionEndsOnTheLongBreak() {
        XCTAssertEqual(PomodoroConfiguration.default.plan.last?.kind, .longBreak,
                       "ending rested is the right moment to be asked about another")
    }

    func testSingleLoopStillGetsALongBreak() {
        let plan = PomodoroConfiguration(loops: 1).plan
        XCTAssertEqual(plan.map(\.kind), [.work, .longBreak])
    }

    func testZeroLoopsIsClampedRatherThanEmpty() {
        XCTAssertFalse(PomodoroConfiguration(loops: 0).plan.isEmpty)
    }

    func testLoopNumbersAreOneBased() {
        let plan = PomodoroConfiguration.default.plan
        XCTAssertEqual(plan.first?.loop, 1)
        XCTAssertEqual(plan.last?.loop, 4)
    }
}

final class PomodoroSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testRemainingIsDerivedFromAnAbsoluteEndDate() {
        let session = PomodoroSession(startingAt: start)
        XCTAssertEqual(session.remaining(at: start), 25 * 60)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(600)), 15 * 60)
    }

    func testSleepingPastTheEndClampsAtZeroInsteadOfGoingNegative() {
        let session = PomodoroSession(startingAt: start)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(9_999)), 0)
    }

    func testPauseFreezesTheClockAndResumeShiftsTheEndDate() {
        var session = PomodoroSession(startingAt: start)
        session.pause(at: start.addingTimeInterval(300))
        XCTAssertTrue(session.isPaused)

        // Ten minutes of real time pass while paused.
        let frozen = session.remaining(at: start.addingTimeInterval(900))
        XCTAssertEqual(frozen, 20 * 60, "pausing freezes the clock, nothing more")

        session.resume(at: start.addingTimeInterval(900))
        XCTAssertFalse(session.isPaused)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(900)), 20 * 60)
    }

    func testOnlySegmentsRunToZeroCount() {
        var session = PomodoroSession(startingAt: start)
        session.skip(at: start)
        XCTAssertEqual(session.completedWorkSegments, 0, "a skip must not count")

        var other = PomodoroSession(startingAt: start)
        other.complete(at: start.addingTimeInterval(25 * 60))
        XCTAssertEqual(other.completedWorkSegments, 1)
    }

    func testASkipDoesNotResetProgressEither() {
        var session = PomodoroSession(startingAt: start)
        session.complete(at: start)          // work 1 done
        session.skip(at: start)              // skipped the break
        XCTAssertEqual(session.completedWorkSegments, 1)
        XCTAssertEqual(session.current.kind, .work)
        XCTAssertEqual(session.current.loop, 2)
    }

    func testAdvancingThroughThePlanFinishesOnTheLongBreak() {
        var session = PomodoroSession(startingAt: start)
        var now = start
        for _ in 0..<(session.plan.count - 1) {
            now = now.addingTimeInterval(session.current.duration)
            session.complete(at: now)
            XCTAssertFalse(session.isFinished)
        }
        XCTAssertEqual(session.current.kind, .longBreak)
        now = now.addingTimeInterval(session.current.duration)
        session.complete(at: now)
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.completedWorkSegments, 4)
    }

    func testAFinishedSessionIgnoresFurtherInput() {
        var session = PomodoroSession(configuration: .init(loops: 1), startingAt: start)
        session.complete(at: start)
        session.complete(at: start)
        XCTAssertTrue(session.isFinished)
        XCTAssertNil(session.complete(at: start))
        XCTAssertNil(session.skip(at: start))
        XCTAssertEqual(session.remaining(at: start), 0)
    }

    func testProgressSpansZeroToOne() {
        let session = PomodoroSession(startingAt: start)
        XCTAssertEqual(session.progress(at: start), 0, accuracy: 0.0001)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(12.5 * 60)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(25 * 60)), 1, accuracy: 0.0001)
    }
}

final class ClockTextTests: XCTestCase {
    func testFormatting() {
        XCTAssertEqual(TimeInterval(0).clockText, "0:00")
        XCTAssertEqual(TimeInterval(59).clockText, "0:59")
        XCTAssertEqual(TimeInterval(60).clockText, "1:00")
        XCTAssertEqual(TimeInterval(1500).clockText, "25:00")
    }

    func testRoundsUpSoItNeverShowsZeroWhileStillRunning() {
        XCTAssertEqual(TimeInterval(0.4).clockText, "0:01")
        XCTAssertEqual(TimeInterval(59.2).clockText, "1:00")
    }
}
