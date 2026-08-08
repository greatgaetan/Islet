import Foundation

public struct PomodoroConfiguration: Equatable, Sendable, Codable {
    public var workSeconds: TimeInterval
    public var shortBreakSeconds: TimeInterval
    public var longBreakSeconds: TimeInterval
    public var loops: Int

    public init(workSeconds: TimeInterval = 25 * 60,
                shortBreakSeconds: TimeInterval = 5 * 60,
                longBreakSeconds: TimeInterval = 15 * 60,
                loops: Int = 4) {
        self.workSeconds = workSeconds
        self.shortBreakSeconds = shortBreakSeconds
        self.longBreakSeconds = longBreakSeconds
        self.loops = loops
    }

    /// Good defaults matter more than options.
    public static let `default` = PomodoroConfiguration()

    /// work, short, work, short, …, work, **long**.
    ///
    /// The long break *replaces* the final short one, so the default 4 loops of
    /// 25/5/15 run 2 h 10 and the session ends on the long break — which is the
    /// right moment to be asked whether to start another.
    public var plan: [PomodoroSegment] {
        let loops = max(1, self.loops)
        return (1...loops).flatMap { loop -> [PomodoroSegment] in
            [
                PomodoroSegment(kind: .work, duration: workSeconds, loop: loop),
                loop == loops
                    ? PomodoroSegment(kind: .longBreak, duration: longBreakSeconds, loop: loop)
                    : PomodoroSegment(kind: .shortBreak, duration: shortBreakSeconds, loop: loop),
            ]
        }
    }

    public var totalSeconds: TimeInterval {
        plan.reduce(0) { $0 + $1.duration }
    }
}

public enum PomodoroSegmentKind: String, Sendable, Codable {
    case work, shortBreak, longBreak

    public var isBreak: Bool { self != .work }

    public var label: String {
        switch self {
        case .work: "Focus"
        case .shortBreak: "Break"
        case .longBreak: "Long break"
        }
    }
}

public struct PomodoroSegment: Equatable, Sendable {
    public let kind: PomodoroSegmentKind
    public let duration: TimeInterval
    /// 1-based loop this segment belongs to.
    public let loop: Int

    public init(kind: PomodoroSegmentKind, duration: TimeInterval, loop: Int) {
        self.kind = kind
        self.duration = duration
        self.loop = loop
    }
}

/// A planned block of work, advancing on its own.
///
/// Time is stored as an **absolute end date**, never as a countdown, so sleeping
/// and waking recompute correctly instead of losing the difference.
public struct PomodoroSession: Equatable, Sendable {
    public let configuration: PomodoroConfiguration
    public let plan: [PomodoroSegment]
    public private(set) var index: Int
    public private(set) var endsAt: Date
    /// Non-nil while paused: pausing freezes the clock, nothing more. No
    /// penalty logic — this is a personal tool, not a judge.
    public private(set) var pausedRemaining: TimeInterval?
    /// Only segments run to zero count.
    public private(set) var completedWorkSegments: Int
    public private(set) var isFinished: Bool

    public init(configuration: PomodoroConfiguration = .default, startingAt now: Date) {
        self.configuration = configuration
        let plan = configuration.plan
        self.plan = plan
        self.index = 0
        self.endsAt = now.addingTimeInterval(plan[0].duration)
        self.pausedRemaining = nil
        self.completedWorkSegments = 0
        self.isFinished = false
    }

    public var current: PomodoroSegment { plan[min(index, plan.count - 1)] }
    public var isPaused: Bool { pausedRemaining != nil }
    public var isRunning: Bool { !isPaused && !isFinished }
    public var totalLoops: Int { max(1, configuration.loops) }

    public func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return max(0, pausedRemaining) }
        if isFinished { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    public func progress(at now: Date) -> Double {
        guard current.duration > 0 else { return 1 }
        let elapsed = current.duration - remaining(at: now)
        return min(1, max(0, elapsed / current.duration))
    }

    public mutating func pause(at now: Date) {
        guard !isPaused, !isFinished else { return }
        pausedRemaining = remaining(at: now)
    }

    public mutating func resume(at now: Date) {
        guard let pausedRemaining, !isFinished else { return }
        endsAt = now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
    }

    /// The segment ran to zero: it counts, and the next one starts immediately.
    @discardableResult
    public mutating func complete(at now: Date) -> PomodoroSegment? {
        guard !isFinished else { return nil }
        let ended = current
        if ended.kind == .work { completedWorkSegments += 1 }
        moveOn(at: now)
        return ended
    }

    /// The user skipped ahead: it does not count, and it does not reset
    /// anything either.
    @discardableResult
    public mutating func skip(at now: Date) -> PomodoroSegment? {
        guard !isFinished else { return nil }
        let ended = current
        moveOn(at: now)
        return ended
    }

    private mutating func moveOn(at now: Date) {
        pausedRemaining = nil
        guard index + 1 < plan.count else {
            isFinished = true
            endsAt = now
            return
        }
        index += 1
        endsAt = now.addingTimeInterval(plan[index].duration)
    }
}

public extension TimeInterval {
    /// `24:35`. Rounds up, so a timer never shows 0:00 while still running.
    var clockText: String {
        let total = Int(rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
