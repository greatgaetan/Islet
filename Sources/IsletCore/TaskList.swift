import Foundation

/// The whole task collection, and every operation on it — pure, so it is free
/// to test and impossible to test wrong.
public struct TaskList: Codable, Equatable, Sendable {
    public var items: [TaskItem]

    public init(items: [TaskItem] = []) {
        self.items = items
    }

    /// How long an archived task is kept before it is purged for good.
    public static let archiveRetention: TimeInterval = 30 * 24 * 60 * 60

    // MARK: - Reading

    /// Everything still on the board, in display order: **open tasks first**,
    /// checked ones sunk to the bottom, newest first within each group.
    ///
    /// Sorting the *view* rather than `items` is deliberate: undo restores a
    /// deleted task by index into `items`, so the stored order has to stay put.
    public var live: [TaskItem] {
        items
            .filter { !$0.isArchived }
            .sorted { left, right in
                if left.isCompleted != right.isCompleted { return !left.isCompleted }
                return left.createdAt > right.createdAt
            }
    }

    public func live(in category: TaskCategory?) -> [TaskItem] {
        guard let category else { return live }
        return live.filter { $0.category == category }
    }

    public func count(of category: TaskCategory) -> Int {
        live.lazy.filter { $0.category == category && !$0.isCompleted }.count
    }

    public var openCount: Int { live.lazy.filter { !$0.isCompleted }.count }

    public func index(of id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    // MARK: - Writing

    /// Returns the new task, or nil when the title was only whitespace.
    @discardableResult
    public mutating func add(
        title: String,
        category: TaskCategory = .toDo,
        at now: Date = .now
    ) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = TaskItem(title: trimmed, category: category, createdAt: now)
        items.insert(task, at: 0)
        return task
    }

    public mutating func toggleCompletion(_ id: UUID, at now: Date = .now) {
        guard let index = index(of: id) else { return }
        items[index].completedAt = items[index].isCompleted ? nil : now.wholeSecond
    }

    /// Renames a task. A blank title is refused rather than stored: a row with
    /// no text is a row you can no longer identify, and the caller's field shows
    /// its placeholder in the meantime, so nothing is lost by keeping the old one
    /// until something real is typed.
    public mutating func rename(_ id: UUID, to title: String) {
        guard let index = index(of: id) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items[index].title = trimmed
    }

    public mutating func recategorise(_ id: UUID, to category: TaskCategory) {
        guard let index = index(of: id) else { return }
        items[index].category = category
        // Metadata that no longer applies goes with it, rather than lurking.
        if category != .deferred { items[index].deferUntil = nil }
        if category != .delegated { items[index].delegateTo = nil }
    }

    public mutating func setDeferDate(_ id: UUID, to date: Date?) {
        guard let index = index(of: id), items[index].category == .deferred else { return }
        items[index].deferUntil = date?.wholeSecond
    }

    public mutating func setDelegate(_ id: UUID, to name: String?) {
        guard let index = index(of: id), items[index].category == .delegated else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].delegateTo = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// Removes the task and hands back everything needed to put it back.
    /// Deletion is immediate — it is undo, not confirmation, that makes it safe.
    @discardableResult
    public mutating func delete(_ id: UUID) -> (task: TaskItem, index: Int)? {
        guard let index = index(of: id) else { return nil }
        return (items.remove(at: index), index)
    }

    public mutating func restore(_ task: TaskItem, at index: Int) {
        items.insert(task, at: min(max(0, index), items.count))
    }

    // MARK: - Day boundaries

    /// A dated defer comes back on its day — driven from the app's first wake,
    /// never from midnight: a state change you cannot see does not count.
    /// Returns the tasks that came back.
    @discardableResult
    public mutating func promoteDueDefers(at now: Date = .now) -> [TaskItem] {
        var promoted: [TaskItem] = []
        for index in items.indices where !items[index].isArchived {
            guard items[index].isDue(at: now) else { continue }
            items[index].category = .toDo
            items[index].deferUntil = nil
            promoted.append(items[index])
        }
        return promoted
    }

    /// Checked tasks stay visible until the recap, then leave the board.
    @discardableResult
    public mutating func archiveCompleted(at now: Date = .now) -> Int {
        var count = 0
        for index in items.indices
        where items[index].isCompleted && !items[index].isArchived {
            items[index].archivedAt = now.wholeSecond
            count += 1
        }
        return count
    }

    /// Marks a task as having been shown tonight, which is what makes the next
    /// nudge later than this one.
    public mutating func recordReminder(_ id: UUID, at now: Date = .now) {
        guard let index = index(of: id) else { return }
        items[index].lastRemindedAt = now.wholeSecond
        items[index].remindedCount += 1
    }

    public mutating func purgeArchive(at now: Date = .now) {
        items.removeAll { task in
            guard let archivedAt = task.archivedAt else { return false }
            return now.timeIntervalSince(archivedAt) > Self.archiveRetention
        }
    }
}
