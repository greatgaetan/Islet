import IsletCore
import SwiftUI

/// The evening review: what it offers, and when it dares to offer it.
@MainActor
@Observable
final class RecapModel {
    enum Phase: Equatable {
        /// Nothing due.
        case idle
        /// Due, and waiting to be noticed. It pulses once and then keeps quiet.
        case pending
        /// Being answered, one card at a time.
        case reviewing
    }

    enum Action: CaseIterable {
        case done, tomorrow, postpone, delegate, delete

        public var label: String {
            switch self {
            case .done: "Done"
            case .tomorrow: "Tomorrow"
            case .postpone: "Defer"
            case .delegate: "Delegate"
            case .delete: "Delete"
            }
        }

        /// The digit shown on the button. Display only — the keystroke is matched
        /// by key code, because on a French layout the key printed "1" produces
        /// `&` and a character comparison could never fire.
        public var shortcut: String { String(Self.allCases.firstIndex(of: self)! + 1) }

        static func forKeyCode(_ keyCode: UInt16) -> Action? {
            let digits: [UInt16] = [18, 19, 20, 21, 23]   // kVK_ANSI_1 … _5
            guard let index = digits.firstIndex(of: keyCode),
                  index < allCases.count else { return nil }
            return allCases[index]
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var cards: [RecapCard] = []
    private(set) var index = 0

    var current: RecapCard? { index < cards.count ? cards[index] : nil }
    var remaining: Int { max(0, cards.count - index) }
    var isPending: Bool { phase == .pending }
    var isReviewing: Bool { phase == .reviewing }

    /// Set by the controller: the recap must never interrupt a full-screen app.
    var isSurfaceAvailable: () -> Bool = { true }
    var onPhaseChanged: ((Phase) -> Void)?

    private let tasks: TaskModel
    private var settings: () -> (hour: Int, minute: Int) = { (18, 0) }
    private var opensItself: () -> Bool = { true }
    private var ticker: Task<Void, Never>?
    private var patience: Task<Void, Never>?

    init(tasks: TaskModel) {
        self.tasks = tasks
    }

    func start(recapHour: @escaping () -> (hour: Int, minute: Int),
               opensItself: @escaping () -> Bool) {
        settings = recapHour
        self.opensItself = opensItself
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                // A minute is plenty: the recap is due at an hour, not a second.
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.checkIfDue()
            }
        }
        checkIfDue()
    }

    // MARK: - Scheduling

    func checkIfDue(now: Date = .now) {
        guard phase == .idle,
              isSurfaceAvailable(),
              RecapSchedule.isDue(at: now, hour: settings().hour, minute: settings().minute,
                                  lastRun: Preferences.lastRecap)
        else { return }

        let due = RecapPlan.cards(from: tasks.list, at: now)
        guard !due.isEmpty else {
            // An empty evening still counts as done, or it would be reconsidered
            // every minute until midnight.
            Preferences.lastRecap = now
            return
        }

        cards = due
        index = 0

        // Insisting is the point: a review you are never pulled into is a review
        // you never do. It costs one keystroke to escape, and the setting turns
        // the insistence off for good.
        if opensItself() {
            setPhase(.reviewing)
        } else {
            setPhase(.pending)
        }

        startPatience()
    }

    /// Left *untouched* — not merely left open — it gives up and rolls over.
    ///
    /// The distinction matters now that it opens itself: a panel that insisted on
    /// appearing and then sat there all evening would be worse than one that
    /// never appeared. Every answer resets the clock, so a review in progress is
    /// never closed underneath you.
    private func startPatience() {
        patience?.cancel()
        patience = Task { [weak self] in
            try? await Task.sleep(for: .seconds(RecapSchedule.patience))
            guard !Task.isCancelled, let self, phase != .idle else { return }
            log("recap untouched for \(Int(RecapSchedule.patience / 60)) min — rolling to tomorrow")
            finish(now: .now)
        }
    }

    // MARK: - Reviewing

    func beginReview() {
        guard phase == .pending else { return }
        setPhase(.reviewing)
        startPatience()
    }

    func answer(_ action: Action, now: Date = .now) {
        guard let card = current else { return }
        let id = card.task.id

        switch action {
        case .done:
            if !card.task.isCompleted { tasks.toggleCompletion(id) }
        case .tomorrow:
            // Explicitly kept. Recording it is what makes the next nudge later.
            tasks.recordReminder(id, at: now)
        case .postpone:
            tasks.recategorise(id, to: .deferred)
            tasks.recordReminder(id, at: now)
        case .delegate:
            tasks.recategorise(id, to: .delegated)
            tasks.recordReminder(id, at: now)
        case .delete:
            tasks.delete(id)
        }

        withAnimation(Motion.contentIn) { index += 1 }
        if current == nil { finish(now: now) } else { startPatience() }
    }

    /// Stopping halfway is not a failure — whatever was not answered simply rolls
    /// to tomorrow, which is the promise the whole ritual rests on.
    func dismiss(now: Date = .now) {
        guard phase != .idle else { return }
        finish(now: now)
    }

    private func finish(now: Date) {
        patience?.cancel()
        patience = nil
        Preferences.lastRecap = now
        // Checked tasks have had their moment of visible satisfaction; now they
        // leave the board.
        tasks.archiveCompleted(at: now)
        cards = []
        index = 0
        setPhase(.idle)
    }

    private func setPhase(_ next: Phase) {
        guard next != phase else { return }
        phase = next
        onPhaseChanged?(next)
    }
}
