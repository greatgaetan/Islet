import Carbon.HIToolbox
import Foundation

/// Eisenhower's four D's, minus *delete*.
///
/// The fourth D is a decision worth recording only where arbitration has to be
/// justified. Here it is an action: a task you will never do should disappear,
/// not become a fourth column to read past every evening.
public enum TaskCategory: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case toDo = "toDo"
    case deferred = "defer"
    case delegated = "delegate"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .toDo: "To do"
        case .deferred: "Defer"
        case .delegated: "Delegate"
        }
    }

    /// The large glyph, for empty states.
    public var symbol: String {
        switch self {
        case .toDo: "circle.dashed"
        case .deferred: "clock"
        case .delegated: "person"
        }
    }

    /// The small inline mark that replaces a coloured dot in a list row.
    ///
    /// Redundant encoding, and the point of it: on a 5 pt mark the eye resolves
    /// hue very poorly, so colour alone cannot carry the category. A silhouette
    /// survives small sizes, low opacity and colour blindness alike — solid
    /// round, hollow round, and not round at all.
    public var mark: String {
        switch self {
        case .toDo: "circle.fill"
        case .deferred: "clock"
        case .delegated: "person.fill"
        }
    }

    /// The digit shown on the chip badge. **Display only** — never match a
    /// keystroke against it; see `category(forKeyCode:)`.
    public var shortcut: String {
        switch self {
        case .toDo: "1"
        case .deferred: "2"
        case .delegated: "3"
        }
    }

    /// Which category a ⌘-digit keystroke selects, matched by **key code**.
    ///
    /// Matching the character would be wrong: on a French layout the key printed
    /// "1" produces `&` unshifted, so `characters == "1"` never fires. The
    /// *position* of a printed digit is the same across Latin layouts, so the key
    /// code is the stable identifier. Letters are the opposite case — the key
    /// printed "Z" sits at the QWERTY-W position there, so ⌘Z must follow the
    /// character, not the position.
    public static func category(forKeyCode keyCode: UInt16) -> TaskCategory? {
        switch Int(keyCode) {
        case kVK_ANSI_1, kVK_ANSI_Keypad1: .toDo
        case kVK_ANSI_2, kVK_ANSI_Keypad2: .deferred
        case kVK_ANSI_3, kVK_ANSI_Keypad3: .delegated
        default: nil
        }
    }
}

public struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    /// An attribute, not a separate list: triage *is* the method, so a task has
    /// to be able to move.
    public var category: TaskCategory
    public var createdAt: Date
    /// Set when checked. Stays visible and struck through until the evening
    /// recap archives it.
    public var completedAt: Date?
    /// *Defer* only. Optional — an undated defer is still a legitimate "not now".
    public var deferUntil: Date?
    /// *Delegate* only. Free text, never a Contacts link: this is a note to
    /// self, not a formal assignment.
    public var delegateTo: String?
    public var archivedAt: Date?
    /// When the evening recap last surfaced this task, and how many times.
    /// Together they make the nudges degressive rather than nightly.
    public var lastRemindedAt: Date?
    public var remindedCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        category: TaskCategory = .toDo,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        deferUntil: Date? = nil,
        delegateTo: String? = nil,
        archivedAt: Date? = nil,
        lastRemindedAt: Date? = nil,
        remindedCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.category = category
        // Rounded here, once, so nothing downstream has to think about it.
        self.createdAt = createdAt.wholeSecond
        self.completedAt = completedAt?.wholeSecond
        self.deferUntil = deferUntil?.wholeSecond
        self.delegateTo = delegateTo
        self.archivedAt = archivedAt?.wholeSecond
        self.lastRemindedAt = lastRemindedAt?.wholeSecond
        self.remindedCount = remindedCount
    }

    /// Older files predate the reminder fields; defaulting them beats refusing to
    /// decode somebody's task list.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        category = try c.decodeIfPresent(TaskCategory.self, forKey: .category) ?? .toDo
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        deferUntil = try c.decodeIfPresent(Date.self, forKey: .deferUntil)
        delegateTo = try c.decodeIfPresent(String.self, forKey: .delegateTo)
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        lastRemindedAt = try c.decodeIfPresent(Date.self, forKey: .lastRemindedAt)
        remindedCount = try c.decodeIfPresent(Int.self, forKey: .remindedCount) ?? 0
    }

    public var isCompleted: Bool { completedAt != nil }
    public var isArchived: Bool { archivedAt != nil }

    public func isDue(at now: Date) -> Bool {
        guard category == .deferred, let deferUntil else { return false }
        return deferUntil <= now
    }
}

public extension Date {
    /// Truncated to the second.
    ///
    /// Task dates live on disk as ISO8601, which carries no sub-second part. So
    /// rather than build machinery to preserve a precision nothing here needs,
    /// dates are rounded when they are created: memory and disk then hold the
    /// same value, and a save/load round trip is lossless by construction.
    var wholeSecond: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}
