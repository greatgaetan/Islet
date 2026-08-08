import XCTest
@testable import IsletCore

final class SessionHistoryTests: XCTestCase {
    /// Noon, so "same calendar day" tests are not sitting on a boundary.
    private let noon = Calendar(identifier: .gregorian)
        .date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                   year: 2026, month: 8, day: 7, hour: 12))!

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func work(_ minutes: Double, at date: Date) -> CompletedSegment {
        CompletedSegment(kind: .work, duration: minutes * 60, finishedAt: date)
    }

    func testOnlyWorkCounts() {
        var history = SessionHistory()
        history.record(work(25, at: noon))
        history.record(CompletedSegment(kind: .shortBreak, duration: 300, finishedAt: noon))
        history.record(CompletedSegment(kind: .longBreak, duration: 900, finishedAt: noon))
        XCTAssertEqual(history.workSegments(on: noon, calendar: utc), 1,
                       "a break is not a Pomodoro")
    }

    func testCountedAgainstTheCalendarDayNotARollingWindow() {
        var history = SessionHistory()
        history.record(work(25, at: noon))
        history.record(work(25, at: noon.addingTimeInterval(-20 * 3600))) // yesterday evening

        XCTAssertEqual(history.workSegments(on: noon, calendar: utc), 1,
                       "20 hours ago is still yesterday, and yesterday does not count today")
    }

    func testFocusedTimeAddsUpDurationsNotSegments() {
        var history = SessionHistory()
        history.record(work(25, at: noon))
        history.record(work(50, at: noon))
        XCTAssertEqual(history.focusedTime(on: noon, calendar: utc), 75 * 60)
    }

    func testPurgeKeepsTheLastThirtyDays() {
        var history = SessionHistory()
        history.record(work(25, at: noon))
        history.record(work(25, at: noon.addingTimeInterval(-29 * 86_400)))
        history.record(work(25, at: noon.addingTimeInterval(-31 * 86_400)))

        history.purge(at: noon)
        XCTAssertEqual(history.segments.count, 2)
    }

    func testDatesAreRoundedLikeEverythingElseOnDisk() {
        let segment = CompletedSegment(kind: .work, duration: 1500,
                                       finishedAt: Date(timeIntervalSince1970: 1_000.678))
        XCTAssertEqual(segment.finishedAt.timeIntervalSince1970, 1_000)
    }

    func testRoundTrip() throws {
        var history = SessionHistory()
        history.record(work(25, at: noon))
        history.record(CompletedSegment(kind: .longBreak, duration: 900, finishedAt: noon))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertEqual(try decoder.decode(SessionHistory.self,
                                          from: encoder.encode(history)), history)
    }

    func testEmptyHistoryCountsZeroRatherThanFailing() {
        XCTAssertEqual(SessionHistory().workSegments(on: noon, calendar: utc), 0)
        XCTAssertEqual(SessionHistory().focusedTime(on: noon, calendar: utc), 0)
    }
}

final class IsletSettingsMigrationTests: XCTestCase {
    /// Someone upgrading has a settings file with no `playsSound` in it. Losing
    /// their Pomodoro durations over a field that did not exist yet would be a
    /// poor trade.
    func testOlderFilesWithoutTheSoundFieldStillLoad() throws {
        let json = Data("""
        { "pomodoro": { "workSeconds": 1800, "shortBreakSeconds": 300,
                        "longBreakSeconds": 900, "loops": 3 } }
        """.utf8)

        let restored = try JSONDecoder().decode(IsletSettings.self, from: json)
        XCTAssertEqual(restored.pomodoro.workMinutes, 30, "their durations survive")
        XCTAssertTrue(restored.playsSound, "and the new field takes its default")
    }

    func testAnEmptyObjectFallsBackEntirely() throws {
        let restored = try JSONDecoder().decode(IsletSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(restored, .default)
    }
}
