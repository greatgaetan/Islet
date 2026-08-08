import AppKit
import IsletCore
import SwiftUI

@MainActor
@Observable
final class TaskModel {
    private(set) var list = TaskList()
    var filter: TaskCategory?
    /// The quick-add field's text. Non-empty means "do not close this panel".
    var draft = ""
    /// What the task being typed will be filed as. ⌘1/2/3 sets it, Tab cycles
    /// it, Return commits with it — so you always see the choice before making
    /// it, instead of firing blind.
    var pendingCategory: TaskCategory = .toDo
    /// The row under the pointer, so ⌫ has a target. Safe to keep on the model
    /// unlike glyph hover: task rows exist in one layer only, so nothing can
    /// light up by proxy.
    var hoveredTaskID: UUID?
    /// The task a session is running *on*, if any. Optional by design: a session
    /// with no task attached is equally legitimate, and forcing one would be a
    /// harness on the days you just want 25 minutes of quiet.
    private(set) var activeTaskID: UUID?

    /// A deletion waiting to be regretted. The row keeps its space for four
    /// seconds instead of snapping shut, so undo has somewhere to live.
    private(set) var pendingUndo: (task: TaskItem, index: Int)?

    static let undoWindow = Duration.seconds(4)

    /// Fires when the draft crosses between empty and non-empty: while there is
    /// text, only the keyboard may close the panel.
    var onDraftDirtyChanged: ((Bool) -> Void)?
    /// A task was removed by the user. The controller turns this into a sound —
    /// the model has no business knowing that sound exists.
    var onDeleted: (() -> Void)?

    private let store: any Persisting<TaskList>
    private var saveTask: Task<Void, Never>?
    private var undoTask: Task<Void, Never>?

    init(store: any Persisting<TaskList>) {
        self.store = store
    }

    var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var visible: [TaskItem] { list.live(in: filter) }
    var openCount: Int { list.openCount }

    func count(of category: TaskCategory) -> Int { list.count(of: category) }

    var activeTask: TaskItem? {
        guard let activeTaskID else { return nil }
        return list.items.first { $0.id == activeTaskID }
    }

    func setActiveTask(_ id: UUID?) { activeTaskID = id }

    /// The session never stops because the task went away.
    ///
    /// You are mid-flow; being interrupted for finishing early would be a
    /// punishment. It simply becomes a session with no task attached.
    private func detachIfActive(_ id: UUID) {
        guard activeTaskID == id else { return }
        withAnimation(Motion.contentOut) { activeTaskID = nil }
    }

    // MARK: - Lifecycle

    func load() async {
        var loaded = await store.load()
        loaded.purgeArchive()
        // A dated defer returns to To do at the app's first wake on its day.
        let promoted = loaded.promoteDueDefers()

        // ⌥Space works from the moment the app launches, but loading is async.
        // Assigning straight over `list` would silently destroy anything typed
        // in between — rare, and unforgivable in a capture tool. So merge:
        // whatever is already here and not on disk was added just now.
        let known = Set(loaded.items.map(\.id))
        let addedBeforeLoad = list.items.filter { !known.contains($0.id) }
        loaded.items.insert(contentsOf: addedBeforeLoad, at: 0)

        list = loaded
        if !promoted.isEmpty { log("\(promoted.count) deferred task(s) came due") }
        if !promoted.isEmpty || !addedBeforeLoad.isEmpty { scheduleSave() }
    }

    // MARK: - Draft

    func updateDraft(_ text: String) {
        let wasDirty = hasDraft
        draft = text
        if hasDraft != wasDirty { onDraftDirtyChanged?(hasDraft) }
    }

    /// Return commits and keeps the field open, so several tasks can be typed in
    /// a row. Categorising stays optional — the evening triage is where sorting
    /// belongs, so capture must have no friction at all.
    ///
    /// The pending category survives a commit: entering three deferred tasks in
    /// a row should not mean choosing "Defer" three times.
    @discardableResult
    func commitDraft(as category: TaskCategory? = nil) -> Bool {
        guard hasDraft else { return false }
        _ = withAnimation(Motion.resize) {
            list.add(title: draft, category: category ?? pendingCategory)
        }
        draft = ""
        onDraftDirtyChanged?(false)
        scheduleSave()
        return true
    }

    func clearDraft() {
        pendingCategory = .toDo
        guard hasDraft else { return }
        draft = ""
        onDraftDirtyChanged?(false)
    }

    /// Tab and ⇧Tab, while the field has focus. Tab belongs to what you are
    /// composing; ⌘-digit belongs to what you are looking at.
    func cyclePendingCategory(backwards: Bool = false) {
        let all = TaskCategory.allCases
        let current = all.firstIndex(of: pendingCategory) ?? 0
        let next = (current + (backwards ? all.count - 1 : 1)) % all.count
        withAnimation(Motion.glyph) { pendingCategory = all[next] }
    }

    func setPendingCategory(_ category: TaskCategory) {
        guard category != pendingCategory else { return }
        withAnimation(Motion.glyph) { pendingCategory = category }
    }

    /// Changing what you are looking at also sets what a new task will be.
    ///
    /// If you are reading your deferred tasks and you type something, you almost
    /// certainly mean it to be a deferred task. The two mechanisms cooperate
    /// rather than compete.
    func setFilter(_ category: TaskCategory?) {
        withAnimation(Motion.resize) { filter = category }
        setPendingCategory(category ?? .toDo)
    }

    /// Adds without going through the draft. Used by the seeding hatch: typing
    /// into the draft has side effects (it expands the panel), which is exactly
    /// what a verification fixture must not do.
    func addDirectly(_ title: String, category: TaskCategory) {
        _ = withAnimation(Motion.resize) { list.add(title: title, category: category) }
        scheduleSave()
    }

    // MARK: - Editing

    func toggleCompletion(_ id: UUID) {
        // Checking sinks the row to the bottom, so the list reorders under it.
        withAnimation(Motion.resize) { list.toggleCompletion(id) }
        if list.items.first(where: { $0.id == id })?.isCompleted == true { detachIfActive(id) }
        scheduleSave()
    }

    func recordReminder(_ id: UUID, at now: Date = .now) {
        list.recordReminder(id, at: now)
        scheduleSave()
    }

    func archiveCompleted(at now: Date = .now) {
        guard withAnimation(Motion.resize, { list.archiveCompleted(at: now) }) > 0 else { return }
        scheduleSave()
    }

    func recategorise(_ id: UUID, to category: TaskCategory) {
        list.recategorise(id, to: category)
        scheduleSave()
    }

    func setDeferDate(_ id: UUID, to date: Date?) {
        list.setDeferDate(id, to: date)
        scheduleSave()
    }

    func setDelegate(_ id: UUID, to name: String?) {
        list.setDelegate(id, to: name)
        scheduleSave()
    }

    func delete(_ id: UUID) {
        if hoveredTaskID == id { hoveredTaskID = nil }
        detachIfActive(id)
        guard let removed = withAnimation(Motion.resize, { list.delete(id) }) else { return }
        scheduleSave()
        onDeleted?()
        startUndoWindow(with: removed)
    }

    func undoDelete() {
        guard let pendingUndo else { return }
        undoTask?.cancel()
        undoTask = nil
        list.restore(pendingUndo.task, at: pendingUndo.index)
        withAnimation(Motion.contentIn) { self.pendingUndo = nil }
        scheduleSave()
    }

    var canUndo: Bool { pendingUndo != nil }

    private func startUndoWindow(with removed: (task: TaskItem, index: Int)) {
        undoTask?.cancel()
        withAnimation(Motion.contentIn) { pendingUndo = removed }
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled, let self else { return }
            withAnimation(Motion.contentOut) { self.pendingUndo = nil }
        }
    }

    // MARK: - Persistence

    /// Debounced: typing three tasks in a row should write once, not three times.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = list
        saveTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await store.save(snapshot)
        }
    }

    /// Called on quit, where a debounce would lose the last edit.
    func flush() async {
        saveTask?.cancel()
        await store.save(list)
    }
}
