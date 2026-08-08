import XCTest
@testable import IsletCore

final class TaskListTests: XCTestCase {
    func testRenameTrimsAndRefusesBlank() throws {
        var list = TaskList()
        let task = try XCTUnwrap(list.add(title: "call the plumer", category: .toDo))

        list.rename(task.id, to: "  call the plumber  ")
        XCTAssertEqual(list.items.first?.title, "call the plumber")

        // A row with no text is a row you can no longer identify, so a blank
        // title leaves the old one alone rather than storing nothing.
        list.rename(task.id, to: "   ")
        XCTAssertEqual(list.items.first?.title, "call the plumber")
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Adding

    func testNewestFirst() {
        var list = TaskList()
        list.add(title: "first")
        list.add(title: "second")
        XCTAssertEqual(list.items.map(\.title), ["second", "first"])
    }

    func testWhitespaceOnlyTitlesAreRefused() {
        var list = TaskList()
        XCTAssertNil(list.add(title: "   \n "))
        XCTAssertTrue(list.items.isEmpty)
    }

    func testTitlesAreTrimmed() {
        var list = TaskList()
        list.add(title: "  call the plumber  ")
        XCTAssertEqual(list.items.first?.title, "call the plumber")
    }

    func testCaptureDefaultsToToDo() {
        var list = TaskList()
        list.add(title: "anything")
        XCTAssertEqual(list.items.first?.category, .toDo,
                       "capture must have no friction; sorting happens at the recap")
    }

    // MARK: - Categories

    func testRecategorisingDropsMetadataThatNoLongerApplies() {
        var list = TaskList()
        let task = list.add(title: "ask Marie")!
        list.recategorise(task.id, to: .delegated)
        list.setDelegate(task.id, to: "Marie")
        XCTAssertEqual(list.items.first?.delegateTo, "Marie")

        list.recategorise(task.id, to: .toDo)
        XCTAssertNil(list.items.first?.delegateTo, "a stale recipient is worse than none")
    }

    func testDelegateNameIgnoresWhitespace() {
        var list = TaskList()
        let task = list.add(title: "x", category: .delegated)!
        list.setDelegate(task.id, to: "   ")
        XCTAssertNil(list.items.first?.delegateTo)
    }

    func testDeferDateOnlyAppliesToDeferredTasks() {
        var list = TaskList()
        let task = list.add(title: "x", category: .toDo)!
        list.setDeferDate(task.id, to: now)
        XCTAssertNil(list.items.first?.deferUntil)
    }

    func testCountsIgnoreCompletedAndArchived() {
        var list = TaskList()
        let a = list.add(title: "a")!
        list.add(title: "b")
        list.toggleCompletion(a.id, at: now)
        XCTAssertEqual(list.count(of: .toDo), 1)
        XCTAssertEqual(list.openCount, 1)
        XCTAssertEqual(list.live.count, 2, "a checked task is still on the board")
    }

    // MARK: - Completion

    func testCompletionToggles() {
        var list = TaskList()
        let task = list.add(title: "x")!
        list.toggleCompletion(task.id, at: now)
        XCTAssertEqual(list.items.first?.completedAt, now)
        list.toggleCompletion(task.id, at: now)
        XCTAssertNil(list.items.first?.completedAt)
    }

    func testCheckedTasksStayVisibleUntilArchived() {
        var list = TaskList()
        let task = list.add(title: "x")!
        list.toggleCompletion(task.id, at: now)
        XCTAssertEqual(list.live.count, 1)

        XCTAssertEqual(list.archiveCompleted(at: now), 1)
        XCTAssertTrue(list.live.isEmpty)
    }

    func testArchivingIsIdempotent() {
        var list = TaskList()
        let task = list.add(title: "x")!
        list.toggleCompletion(task.id, at: now)
        list.archiveCompleted(at: now)
        XCTAssertEqual(list.archiveCompleted(at: now), 0)
    }

    func testArchivePurgesAfterThirtyDays() {
        var list = TaskList()
        let task = list.add(title: "x")!
        list.toggleCompletion(task.id, at: now)
        list.archiveCompleted(at: now)

        list.purgeArchive(at: now.addingTimeInterval(29 * 86_400))
        XCTAssertEqual(list.items.count, 1)

        list.purgeArchive(at: now.addingTimeInterval(31 * 86_400))
        XCTAssertTrue(list.items.isEmpty)
    }

    // MARK: - Display order

    func testCheckedTasksSinkToTheBottom() {
        var list = TaskList()
        list.add(title: "a", at: now)
        let b = list.add(title: "b", at: now.addingTimeInterval(1))!
        list.add(title: "c", at: now.addingTimeInterval(2))

        XCTAssertEqual(list.live.map(\.title), ["c", "b", "a"])

        list.toggleCompletion(b.id, at: now)
        XCTAssertEqual(list.live.map(\.title), ["c", "a", "b"],
                       "what is still open belongs at the top")
    }

    func testOpenTasksStayNewestFirstWithinTheirGroup() {
        var list = TaskList()
        let a = list.add(title: "a", at: now)!
        let b = list.add(title: "b", at: now.addingTimeInterval(1))!
        list.toggleCompletion(a.id, at: now)
        list.toggleCompletion(b.id, at: now)
        XCTAssertEqual(list.live.map(\.title), ["b", "a"])
    }

    func testSortingIsTheViewOnlySoUndoIndicesStayValid() {
        var list = TaskList()
        list.add(title: "a", at: now)
        let b = list.add(title: "b", at: now.addingTimeInterval(1))!
        list.add(title: "c", at: now.addingTimeInterval(2))
        list.toggleCompletion(b.id, at: now)

        // Sorted view puts "b" last; stored order still has it in the middle.
        XCTAssertEqual(list.items.map(\.title), ["c", "b", "a"])
        let removed = list.delete(b.id)!
        XCTAssertEqual(removed.index, 1)
        list.restore(removed.task, at: removed.index)
        XCTAssertEqual(list.items.map(\.title), ["c", "b", "a"])
    }

    // MARK: - Deleting and undo

    func testDeleteReturnsEnoughToPutItBack() {
        var list = TaskList()
        list.add(title: "a")
        let middle = list.add(title: "b")!
        list.add(title: "c")
        // Newest first: c, b, a — so "b" sits at index 1.
        let removed = list.delete(middle.id)
        XCTAssertEqual(removed?.index, 1)
        XCTAssertEqual(list.items.map(\.title), ["c", "a"])

        list.restore(removed!.task, at: removed!.index)
        XCTAssertEqual(list.items.map(\.title), ["c", "b", "a"],
                       "undo must put it back where it was, not on top")
    }

    func testRestoringOutOfBoundsDoesNotTrap() {
        var list = TaskList()
        let task = TaskItem(title: "x")
        list.restore(task, at: 99)
        XCTAssertEqual(list.items.count, 1)
    }

    func testDeletingSomethingAbsentIsHarmless() {
        var list = TaskList()
        XCTAssertNil(list.delete(UUID()))
    }

    // MARK: - Deferred tasks coming due

    func testDatedDeferComesBackOnItsDay() {
        var list = TaskList()
        let task = list.add(title: "renew passport", category: .deferred)!
        list.setDeferDate(task.id, to: now)

        XCTAssertTrue(list.promoteDueDefers(at: now.addingTimeInterval(-60)).isEmpty)
        XCTAssertEqual(list.items.first?.category, .deferred)

        let promoted = list.promoteDueDefers(at: now)
        XCTAssertEqual(promoted.count, 1)
        XCTAssertEqual(list.items.first?.category, .toDo)
        XCTAssertNil(list.items.first?.deferUntil, "it is back on the board, not still pending")
    }

    func testUndatedDeferNeverComesBackOnItsOwn() {
        var list = TaskList()
        list.add(title: "learn Norwegian", category: .deferred)
        XCTAssertTrue(list.promoteDueDefers(at: now.addingTimeInterval(9_999_999)).isEmpty)
    }

    func testArchivedDefersAreLeftAlone() {
        var list = TaskList()
        let task = list.add(title: "x", category: .deferred)!
        list.setDeferDate(task.id, to: now)
        list.toggleCompletion(task.id, at: now)
        list.archiveCompleted(at: now)
        XCTAssertTrue(list.promoteDueDefers(at: now).isEmpty)
    }

    // MARK: - Round trip

    func testJSONRoundTripSurvivesEveryField() throws {
        var list = TaskList()
        let a = list.add(title: "plain")!
        let b = list.add(title: "later", category: .deferred)!
        let c = list.add(title: "hand off", category: .delegated)!
        list.setDeferDate(b.id, to: now)
        list.setDelegate(c.id, to: "Marie")
        list.toggleCompletion(a.id, at: now)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(TaskList.self, from: encoder.encode(list))
        XCTAssertEqual(restored, list)
    }

    func testCategoryRawValuesAreStableOnDisk() {
        // Renaming a case must never orphan someone's saved tasks.
        XCTAssertEqual(TaskCategory.toDo.rawValue, "toDo")
        XCTAssertEqual(TaskCategory.deferred.rawValue, "defer")
        XCTAssertEqual(TaskCategory.delegated.rawValue, "delegate")
    }

    /// Regression: these were matched on `characters` and could never fire on a
    /// French layout, where the key printed "1" produces `&` unshifted.
    func testCategoryShortcutsMatchKeyCodesNotCharacters() {
        XCTAssertEqual(TaskCategory.category(forKeyCode: 18), .toDo)      // kVK_ANSI_1
        XCTAssertEqual(TaskCategory.category(forKeyCode: 19), .deferred)  // kVK_ANSI_2
        XCTAssertEqual(TaskCategory.category(forKeyCode: 20), .delegated) // kVK_ANSI_3
        XCTAssertNil(TaskCategory.category(forKeyCode: 21))               // kVK_ANSI_4
    }

    func testNumericKeypadWorksToo() {
        XCTAssertEqual(TaskCategory.category(forKeyCode: 83), .toDo)
        XCTAssertEqual(TaskCategory.category(forKeyCode: 84), .deferred)
        XCTAssertEqual(TaskCategory.category(forKeyCode: 85), .delegated)
    }

    func testBadgeDigitsStayAlignedWithTheKeysTheyName() {
        for category in TaskCategory.allCases {
            let keyCode = UInt16(17 + (Int(category.shortcut) ?? 0)) // 18, 19, 20
            XCTAssertEqual(TaskCategory.category(forKeyCode: keyCode), category,
                           "the badge must name the key that actually works")
        }
    }
}

final class PersistenceTests: XCTestCase {
    func testJSONFileRoundTrip() async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("islet-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let file = JSONFile(url: url, fallback: TaskList())
        var list = TaskList()
        list.add(title: "persisted")
        await file.save(list)

        let reloaded = await file.load()
        XCTAssertEqual(reloaded.items.map(\.title), ["persisted"])
    }

    func testMissingFileFallsBackInsteadOfFailing() async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("islet-absent-\(UUID().uuidString).json")
        let file = JSONFile(url: url, fallback: TaskList())
        let loaded = await file.load()
        XCTAssertTrue(loaded.items.isEmpty)
    }

    func testCorruptFileFallsBackRatherThanLosingTheNextSession() async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("islet-corrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try? Data("not json at all".utf8).write(to: url)

        let file = JSONFile(url: url, fallback: TaskList())
        let loaded = await file.load()
        XCTAssertTrue(loaded.items.isEmpty)
    }
}

final class IsletSettingsTests: XCTestCase {
    func testMinutesAccessorsClampInsteadOfAcceptingNonsense() {
        var configuration = PomodoroConfiguration.default
        configuration.workMinutes = 9_999
        XCTAssertEqual(configuration.workMinutes, PomodoroConfiguration.workRange.upperBound)
        configuration.workMinutes = 0
        XCTAssertEqual(configuration.workMinutes, PomodoroConfiguration.workRange.lowerBound)
    }

    func testTotalTextReadsLikeAHumanWroteIt() {
        XCTAssertEqual(PomodoroConfiguration.default.totalText, "2 h 10")
        XCTAssertEqual(PomodoroConfiguration(loops: 1).totalText, "40 min")
    }

    func testDefaultsRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let restored = try decoder.decode(
            IsletSettings.self, from: encoder.encode(IsletSettings.default)
        )
        XCTAssertEqual(restored, .default)
    }
}
