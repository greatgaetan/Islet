import XCTest
@testable import IsletCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func at(_ day: Int, _ hour: Int) -> Date {
    utc.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                  year: 2026, month: 8, day: day, hour: hour))!
}

final class RecapScheduleTests: XCTestCase {
    func testNothingBeforeTheChosenHour() {
        XCTAssertFalse(RecapSchedule.isDue(at: at(8, 17), hour: 18, lastRun: nil, calendar: utc))
        XCTAssertTrue(RecapSchedule.isDue(at: at(8, 18), hour: 18, lastRun: nil, calendar: utc))
    }

    func testOnceADayAndNoMore() {
        let ranAtSix = at(8, 18)
        XCTAssertFalse(RecapSchedule.isDue(at: at(8, 21), hour: 18,
                                           lastRun: ranAtSix, calendar: utc),
                       "being asked twice in one evening is how an app gets uninstalled")
        XCTAssertTrue(RecapSchedule.isDue(at: at(9, 18), hour: 18,
                                          lastRun: ranAtSix, calendar: utc))
    }

    func testAMissedEveningIsNotOwedTheNextMorning() {
        // 9 a.m. is before the hour, so yesterday's skipped recap does not
        // ambush you over breakfast.
        XCTAssertFalse(RecapSchedule.isDue(at: at(9, 9), hour: 18,
                                           lastRun: at(7, 18), calendar: utc))
    }
}

final class RecapPlanTests: XCTestCase {
    private let evening = at(8, 18)

    private func list(_ items: [TaskItem]) -> TaskList { TaskList(items: items) }

    func testOpenToDoTasksAreTheBulkOfIt() {
        var l = TaskList()
        l.add(title: "a", at: at(8, 9))
        l.add(title: "b", at: at(8, 10))
        let cards = RecapPlan.cards(from: l, at: evening, calendar: utc)
        XCTAssertEqual(cards.count, 2)
        XCTAssertTrue(cards.allSatisfy { $0.reason == .open })
    }

    func testOnlyTodaysCompletionsAreAcknowledged() {
        var l = TaskList()
        let today = l.add(title: "today", at: at(8, 9))!
        let earlier = l.add(title: "yesterday", at: at(7, 9))!
        l.toggleCompletion(today.id, at: at(8, 11))
        l.toggleCompletion(earlier.id, at: at(7, 11))

        let completed = RecapPlan.cards(from: l, at: evening, calendar: utc)
            .filter { $0.reason == .completed }
        XCTAssertEqual(completed.map(\.task.title), ["today"])
    }

    func testADatedDeferIsLeftAloneBecauseItHasItsOwnWakeUp() {
        var l = TaskList()
        let task = l.add(title: "renew passport", category: .deferred, at: at(8, 9))!
        l.setDeferDate(task.id, to: at(20, 9))
        XCTAssertTrue(RecapPlan.cards(from: l, at: evening, calendar: utc).isEmpty)
    }

    func testAnUndatedDeferResurfacesWeeklyNotNightly() {
        var l = TaskList()
        let task = l.add(title: "learn Norwegian", category: .deferred, at: at(1, 9))!

        XCTAssertEqual(RecapPlan.cards(from: l, at: evening, calendar: utc).first?.reason,
                       .deferNudge, "never shown yet, so it shows")

        l.recordReminder(task.id, at: evening)
        XCTAssertTrue(RecapPlan.cards(from: l, at: at(9, 18), calendar: utc).isEmpty,
                      "six identical lines every night become six lines nobody reads")
        XCTAssertEqual(RecapPlan.cards(from: l, at: at(15, 18), calendar: utc).count, 1,
                       "a week later it is worth raising again")
    }

    func testADelegationIsChasedThreeEveningsThenSettlesToWeekly() {
        var l = TaskList()
        let task = l.add(title: "hand over the report", category: .delegated, at: at(1, 9))!

        for day in 8...10 {
            let cards = RecapPlan.cards(from: l, at: at(day, 18), calendar: utc)
            XCTAssertEqual(cards.first?.reason, .delegateNudge,
                           "evening \(day - 7) of the grace period")
            l.recordReminder(task.id, at: at(day, 18))
        }

        XCTAssertTrue(RecapPlan.cards(from: l, at: at(11, 18), calendar: utc).isEmpty,
                      "after three evenings the chasing goes weekly")
        XCTAssertEqual(RecapPlan.cards(from: l, at: at(17, 18), calendar: utc).count, 1)
    }

    func testArchivedTasksNeverAppear() {
        var l = TaskList()
        let task = l.add(title: "done and gone", at: at(8, 9))!
        l.toggleCompletion(task.id, at: at(8, 10))
        l.archiveCompleted(at: at(8, 11))
        XCTAssertTrue(RecapPlan.cards(from: l, at: evening, calendar: utc).isEmpty)
    }

    func testAnEmptyBoardMakesAnEmptyRecap() {
        XCTAssertTrue(RecapPlan.cards(from: TaskList(), at: evening, calendar: utc).isEmpty)
    }
}

final class TaskItemMigrationTests: XCTestCase {
    /// A task file written before milestone 5 has no reminder fields. Refusing
    /// to decode it would lose the user's entire list over two optional values.
    func testTasksWrittenBeforeTheRecapExistedStillLoad() throws {
        let json = Data("""
        {"items":[{"id":"6889BAB3-C269-49FD-AE4F-B6E582EE46A9","title":"call the plumber",
        "category":"toDo","createdAt":"2026-08-07T15:02:55Z"}]}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let list = try decoder.decode(TaskList.self, from: json)
        XCTAssertEqual(list.items.first?.title, "call the plumber")
        XCTAssertNil(list.items.first?.lastRemindedAt)
        XCTAssertEqual(list.items.first?.remindedCount, 0)
    }
}
