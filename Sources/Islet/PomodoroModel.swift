import AppKit
import IsletCore
import SwiftUI

/// Drives a planned Pomodoro block.
///
/// Two independent clocks on purpose: a 1 Hz tick for what is *displayed*, and
/// a precise sleep until the segment's absolute end for what *happens*. The
/// countdown does not need 120 Hz; the transition must not be late.
@MainActor
@Observable
final class PomodoroModel {
    var configuration: PomodoroConfiguration = .fromEnvironment
    private(set) var session: PomodoroSession?
    /// Advances at 1 Hz while running. Drives the countdown and the ring.
    private(set) var now: Date = .now

    /// Stops a session left running after you walked away, instead of counting
    /// an empty room as focus.
    static let idleCutoff: TimeInterval = 30 * 60

    /// `ISLET_TICK_LOG=1` prints every tick with its timestamp, so tick
    /// regularity can be checked numerically instead of squinted at.
    static let logsTicks = ProcessInfo.processInfo.environment["ISLET_TICK_LOG"] != nil

    var onSegmentChanged: ((PomodoroSegment) -> Void)?
    /// The segment that just ran all the way to zero. A skip never fires this —
    /// only work that actually happened is worth recording.
    var onSegmentCompleted: ((PomodoroSegment) -> Void)?
    var onSessionFinished: (() -> Void)?
    var onActiveChanged: ((Bool) -> Void)?

    private var ticker: Task<Void, Never>?
    private var segmentEnd: Task<Void, Never>?
    /// Islet is an accessory app that is never frontmost, so macOS App Nap
    /// throttles and coalesces its timers — which showed up as a countdown
    /// skipping two or three seconds at a time. This holds it off for as long
    /// as a session is running, while still allowing the Mac to sleep.
    private var activity: NSObjectProtocol?

    // MARK: - Derived state

    var isActive: Bool { session != nil }
    var isRunning: Bool { session?.isRunning ?? false }
    var isFinished: Bool { session?.isFinished ?? false }
    var current: PomodoroSegment? { session?.current }
    var remaining: TimeInterval { session?.remaining(at: now) ?? configuration.workSeconds }
    var progress: Double { session?.progress(at: now) ?? 0 }

    var clockText: String { remaining.clockText }

    var loopText: String {
        guard let session else { return "Loop 1 of \(max(1, configuration.loops))" }
        return "Loop \(session.current.loop) of \(session.totalLoops)"
    }

    // MARK: - Intent

    /// The play glyph does one thing at a time, and never asks a question.
    func primaryAction() {
        guard let session else { return start() }
        if session.isFinished { return start() }
        session.isPaused ? resume() : pause()
    }

    func start() {
        now = .now
        // The idle silhouette widens to hold the countdown. It used to be a state
        // transition with its own animation; it is a content change now, and it
        // still earns the same moment.
        withAnimation(Motion.timerAppeared) {
            session = PomodoroSession(configuration: configuration, startingAt: now)
        }
        onActiveChanged?(true)
        startTicking()
        scheduleSegmentEnd()
    }

    func stop() {
        withAnimation(Motion.timerAppeared) { session = nil }
        stopClocks()
        onActiveChanged?(false)
    }

    func pause() {
        guard var session, !session.isPaused else { return }
        now = .now
        session.pause(at: now)
        self.session = session
        // Nothing on screen changes while paused, so stop waking up for it.
        stopClocks()
    }

    func resume() {
        guard var session, session.isPaused else { return }
        now = .now
        session.resume(at: now)
        self.session = session
        startTicking()
        scheduleSegmentEnd()
    }

    private func stopClocks() {
        ticker?.cancel()
        ticker = nil
        segmentEnd?.cancel()
        segmentEnd = nil
        endActivity()
    }

    func skip() {
        guard var session, !session.isFinished else { return }
        now = .now
        session.skip(at: now)
        self.session = session
        handleAdvance()
    }

    // MARK: - Clocks

    private func startTicking() {
        ticker?.cancel()
        beginActivity()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.secondsUntilDisplayChanges() else { return }
                // `tolerance: .zero` forbids the runtime from coalescing this
                // wake-up with someone else's.
                try? await Task.sleep(for: .seconds(delay), tolerance: .zero)
                guard !Task.isCancelled, let self else { return }
                self.now = .now
                self.enforceIdleCutoff()
                if Self.logsTicks {
                    log(String(format: "tick %.3f → %@", self.now.timeIntervalSince1970, self.clockText))
                }
            }
        }
    }

    /// Sleep until the *displayed* value changes, not until the next whole
    /// wall-clock second.
    ///
    /// The countdown shows `ceil(remaining)`, and a segment's end date sits at
    /// an arbitrary fraction of a second. Ticking on wall-clock seconds means
    /// the boundary is crossed somewhere in the middle of a tick, which is what
    /// makes a 1 Hz clock look like it stutters.
    private func secondsUntilDisplayChanges() -> Double {
        guard let session, session.isRunning else { return 1 }
        let remaining = session.remaining(at: .now)
        guard remaining > 0 else { return 0.05 }
        let nextDisplayed = remaining.rounded(.up) - 1
        return max(0.01, remaining - nextDisplayed) + 0.008
    }

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            // Not `.userInitiated`: that one also blocks idle system sleep, and
            // a Pomodoro has no business keeping the Mac awake — the absolute
            // end date survives sleep on its own.
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Islet Pomodoro session"
        )
    }

    private func endActivity() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    private func scheduleSegmentEnd() {
        segmentEnd?.cancel()
        guard let session, session.isRunning else { return }
        let seconds = session.remaining(at: .now)
        segmentEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, seconds)), tolerance: .zero)
            guard !Task.isCancelled, let self else { return }
            self.completeCurrentSegment()
        }
    }

    private func completeCurrentSegment() {
        guard var session, session.isRunning else { return }
        now = .now
        let finished = session.complete(at: now)
        self.session = session
        if let finished { onSegmentCompleted?(finished) }
        handleAdvance()
    }

    private func handleAdvance() {
        guard let session else { return }
        if session.isFinished {
            stopClocks()
            onActiveChanged?(false)
            onSessionFinished?()
        } else {
            onSegmentChanged?(session.current)
            scheduleSegmentEnd()
        }
    }

    /// Seconds since the last keyboard or mouse event anywhere on the system.
    /// Needs no permission — it is a coarse system counter, not input contents.
    private func enforceIdleCutoff() {
        guard isRunning, let anyInput = CGEventType(rawValue: ~0) else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
        guard idle >= Self.idleCutoff else { return }
        log("idle for \(Int(idle))s — stopping the session")
        stop()
    }
}

extension PomodoroConfiguration {
    /// Development hatch. `ISLET_FAST=1` shrinks a whole session to under a
    /// minute so segment transitions and announcements can actually be watched
    /// instead of imagined.
    static var fromEnvironment: PomodoroConfiguration {
        guard ProcessInfo.processInfo.environment["ISLET_FAST"] != nil else { return .default }
        return PomodoroConfiguration(workSeconds: 8, shortBreakSeconds: 4,
                                     longBreakSeconds: 6, loops: 2)
    }
}
