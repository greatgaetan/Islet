import Foundation

/// When the evening review is due.
public enum RecapSchedule: Sendable {
    /// Fires once a day, at the hour you chose, and never twice.
    public static func isDue(
        at now: Date,
        hour: Int,
        minute: Int = 0,
        lastRun: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let elapsed = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard elapsed >= hour * 60 + minute else { return false }
        guard let lastRun else { return true }
        return !calendar.isDate(lastRun, inSameDayAs: now)
    }

    /// Left alone for this long, it gives up and tries again tomorrow. Being
    /// nagged by something you already ignored is how an app gets uninstalled.
    public static let patience: TimeInterval = 30 * 60
}

/// One thing to decide about, and what may be decided.
public struct RecapCard: Equatable, Sendable, Identifiable {
    public enum Reason: String, Sendable {
        /// Checked today. Acknowledged, then archived.
        case completed
        /// Still open. The bulk of the review.
        case open
        /// An undated defer, resurfacing on its weekly nudge.
        case deferNudge
        /// A delegation, resurfacing to be chased.
        case delegateNudge
    }

    public let task: TaskItem
    public let reason: Reason
    public var id: UUID { task.id }

    public init(task: TaskItem, reason: Reason) {
        self.task = task
        self.reason = reason
    }
}

/// Builds the evening's cards.
///
/// Card by card, one at a time — triage is the ritual, not reading. A list you
/// scroll is a list you skim; a card you must answer is a decision you make.
public enum RecapPlan: Sendable {
    /// An undated defer is not forgotten, only quiet. It comes back weekly
    /// rather than every evening, because six identical lines every night become
    /// six lines you stop reading by Thursday.
    public static let deferNudgeInterval: TimeInterval = 7 * 24 * 60 * 60
    /// A delegation is chased for three evenings, then settles to weekly.
    public static let delegateGraceEvenings = 3
    public static let delegateNudgeInterval: TimeInterval = 7 * 24 * 60 * 60

    public static func cards(
        from list: TaskList,
        at now: Date,
        calendar: Calendar = .current
    ) -> [RecapCard] {
        var cards: [RecapCard] = []

        for task in list.live where task.isCompleted {
            guard let completedAt = task.completedAt,
                  calendar.isDate(completedAt, inSameDayAs: now) else { continue }
            cards.append(RecapCard(task: task, reason: .completed))
        }

        for task in list.live where !task.isCompleted {
            switch task.category {
            case .toDo:
                cards.append(RecapCard(task: task, reason: .open))

            case .deferred:
                // A dated defer has its own wake-up and is left alone here.
                guard task.deferUntil == nil,
                      isNudgeDue(task, at: now, after: deferNudgeInterval, calendar: calendar)
                else { continue }
                cards.append(RecapCard(task: task, reason: .deferNudge))

            case .delegated:
                guard isDelegateNudgeDue(task, at: now, calendar: calendar) else { continue }
                cards.append(RecapCard(task: task, reason: .delegateNudge))
            }
        }

        return cards
    }

    private static func isNudgeDue(
        _ task: TaskItem,
        at now: Date,
        after interval: TimeInterval,
        calendar: Calendar
    ) -> Bool {
        guard let last = task.lastRemindedAt else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    private static func isDelegateNudgeDue(
        _ task: TaskItem,
        at now: Date,
        calendar: Calendar
    ) -> Bool {
        // The first three evenings it shows every time — that is when you can
        // still actually hand the thing over.
        if task.remindedCount < delegateGraceEvenings {
            guard let last = task.lastRemindedAt else { return true }
            return !calendar.isDate(last, inSameDayAs: now)
        }
        return isNudgeDue(task, at: now, after: delegateNudgeInterval, calendar: calendar)
    }
}
