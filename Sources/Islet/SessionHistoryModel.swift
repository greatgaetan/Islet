import IsletCore
import SwiftUI

/// Records segments that ran to zero. Feeds the evening recap, and today's count
/// in the panel — so the data is visible rather than merely stored.
@MainActor
@Observable
final class SessionHistoryModel {
    private(set) var history = SessionHistory()

    private let store: any Persisting<SessionHistory>
    private var saveTask: Task<Void, Never>?

    init(store: any Persisting<SessionHistory>) {
        self.store = store
    }

    func load() async {
        var loaded = await store.load()
        loaded.purge()

        // Same merge rule as tasks: a segment completed while the file was still
        // loading must not be thrown away.
        let known = Set(loaded.segments.map(\.finishedAt))
        loaded.segments.append(contentsOf: history.segments.filter { !known.contains($0.finishedAt) })

        history = loaded
    }

    func record(_ segment: PomodoroSegment, at now: Date = .now) {
        history.record(CompletedSegment(kind: segment.kind,
                                        duration: segment.duration,
                                        finishedAt: now))
        scheduleSave()
    }

    var workSegmentsToday: Int { history.workSegments(on: .now) }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = history
        saveTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await store.save(snapshot)
        }
    }

    func flush() async {
        saveTask?.cancel()
        await store.save(history)
    }
}
