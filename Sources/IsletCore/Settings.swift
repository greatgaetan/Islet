import Foundation

/// Everything the user can change. Deliberately small: good defaults matter
/// more than options.
/// Named `IsletSettings`, not `Settings`: SwiftUI already has a `Settings`
/// scene type, and the collision is invisible until it isn't.
public struct IsletSettings: Codable, Equatable, Sendable {
    public var pomodoro: PomodoroConfiguration
    /// A short chime when a segment ends.
    ///
    /// There is no reliable public way to read whether a Focus mode is on, and a
    /// rule that cannot be applied reliably is worth less than a switch the user
    /// can see. So: one switch, on by default — without it, a segment ending
    /// while you look away is completely silent.
    public var playsSound: Bool
    /// The hour the evening review is offered. 24-hour clock.
    public var recapHour: Int
    /// Whether the review opens itself, or waits to be asked.
    ///
    /// On by default: a ritual you are never pulled into is a ritual you never
    /// perform. It can still be skipped in one keystroke, which is what makes
    /// insisting acceptable — and turned off entirely here for the days that
    /// cannot take the interruption.
    public var recapOpensItself: Bool

    public static let recapHourRange: ClosedRange<Int> = 12...23

    public init(pomodoro: PomodoroConfiguration = .default,
                playsSound: Bool = true,
                recapHour: Int = 18,
                recapOpensItself: Bool = true) {
        self.pomodoro = pomodoro
        self.playsSound = playsSound
        self.recapHour = recapHour
        self.recapOpensItself = recapOpensItself
    }

    // Older files have no `playsSound`; default it rather than losing the file.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pomodoro = try container.decodeIfPresent(
            PomodoroConfiguration.self, forKey: .pomodoro
        ) ?? .default
        playsSound = try container.decodeIfPresent(Bool.self, forKey: .playsSound) ?? true
        recapHour = try container.decodeIfPresent(Int.self, forKey: .recapHour) ?? 18
        recapOpensItself = try container.decodeIfPresent(
            Bool.self, forKey: .recapOpensItself
        ) ?? true
    }

    public static let `default` = IsletSettings()
}

public extension PomodoroConfiguration {
    /// Bounds for the settings fields. Not validation theatre — a zero-second
    /// work segment would spin the segment scheduler.
    static let workRange: ClosedRange<Int> = 1...120
    static let shortBreakRange: ClosedRange<Int> = 1...60
    static let longBreakRange: ClosedRange<Int> = 1...90
    static let loopsRange: ClosedRange<Int> = 1...12

    var workMinutes: Int {
        get { Int(workSeconds / 60) }
        set { workSeconds = TimeInterval(newValue.clamped(to: Self.workRange) * 60) }
    }

    var shortBreakMinutes: Int {
        get { Int(shortBreakSeconds / 60) }
        set { shortBreakSeconds = TimeInterval(newValue.clamped(to: Self.shortBreakRange) * 60) }
    }

    var longBreakMinutes: Int {
        get { Int(longBreakSeconds / 60) }
        set { longBreakSeconds = TimeInterval(newValue.clamped(to: Self.longBreakRange) * 60) }
    }

    /// "2 h 10" — what the four numbers actually add up to.
    var totalText: String {
        let minutes = Int(totalSeconds / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) min" }
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder)"
    }
}

public extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
