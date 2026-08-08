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

    enum Action { case done, tomorrow, postpone, delegate, delete }

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
    private var settings: () -> Int = { 18 }
    private var ticker: Task<Void, Never>?
    private var patience: Task<Void, Never>?

    init(tasks: TaskModel) {
        self.tasks = tasks
    }

    func start(recapHour: @escaping () -> Int) {
        settings = recapHour
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
              RecapSchedule.isDue(at: now, hour: settings(), lastRun: Preferences.lastRecap)
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
        setPhase(.pending)

        // Left alone, it gives up rather than nagging.
        patience?.cancel()
        patience = Task { [weak self] in
            try? await Task.sleep(for: .seconds(RecapSchedule.patience))
            guard !Task.isCancelled, let self, phase == .pending else { return }
            log("recap ignored — trying again tomorrow")
            finish(now: .now)
        }
    }

    // MARK: - Reviewing

    func beginReview() {
        guard phase == .pending else { return }
        patience?.cancel()
        setPhase(.reviewing)
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
        if current == nil { finish(now: now) }
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
