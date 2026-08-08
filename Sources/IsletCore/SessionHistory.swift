import Foundation

/// A segment that ran all the way to zero. Skipped ones are not recorded —
/// only work that actually happened counts.
public struct CompletedSegment: Codable, Equatable, Sendable {
    public let kind: PomodoroSegmentKind
    public let duration: TimeInterval
    public let finishedAt: Date

    public init(kind: PomodoroSegmentKind, duration: TimeInterval, finishedAt: Date) {
        self.kind = kind
        self.duration = duration
        self.finishedAt = finishedAt.wholeSecond
    }
}

/// What the evening recap counts, and the only place session data lives.
public struct SessionHistory: Codable, Equatable, Sendable {
    public var segments: [CompletedSegment]

    public init(segments: [CompletedSegment] = []) {
        self.segments = segments
    }

    /// Same window as the task archive: long enough to look back at a month,
    /// short enough that the file never becomes a liability.
    public static let retention: TimeInterval = 30 * 24 * 60 * 60

    public mutating func record(_ segment: CompletedSegment) {
        segments.append(segment)
    }

    public mutating func purge(at now: Date = .now) {
        segments.removeAll { now.timeIntervalSince($0.finishedAt) > Self.retention }
    }

    /// "4 Pomodoros today" — the number the recap opens with.
    ///
    /// Counted against the *calendar* day, not a rolling 24 hours: a day boundary
    /// you can point at on a clock is the only one that means anything here.
    public func workSegments(on day: Date, calendar: Calendar = .current) -> Int {
        segments.lazy
            .filter { $0.kind == .work && calendar.isDate($0.finishedAt, inSameDayAs: day) }
            .count
    }

    public func focusedTime(on day: Date, calendar: Calendar = .current) -> TimeInterval {
        segments.lazy
            .filter { $0.kind == .work && calendar.isDate($0.finishedAt, inSameDayAs: day) }
            .reduce(0) { $0 + $1.duration }
    }
}
