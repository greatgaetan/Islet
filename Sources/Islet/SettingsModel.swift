import IsletCore
import SwiftUI

@MainActor
@Observable
final class SettingsModel {
    private(set) var settings: IsletSettings = .default

    /// Called whenever the Pomodoro configuration changes, so a running app
    /// picks it up without a restart.
    var onPomodoroChanged: ((PomodoroConfiguration) -> Void)?

    private let store: any Persisting<IsletSettings>
    private var saveTask: Task<Void, Never>?

    init(store: any Persisting<IsletSettings>) {
        self.store = store
    }

    func load() async {
        settings = await store.load()
        onPomodoroChanged?(settings.pomodoro)
    }

    var pomodoro: PomodoroConfiguration {
        get { settings.pomodoro }
        set {
            guard newValue != settings.pomodoro else { return }
            settings.pomodoro = newValue
            onPomodoroChanged?(newValue)
            scheduleSave()
        }
    }

    func setRecapTime(hour: Int, minute: Int) {
        let h = hour.clamped(to: IsletSettings.recapHourRange)
        let m = IsletSettings.snappedMinute(minute)
        guard h != settings.recapHour || m != settings.recapMinute else { return }
        settings.recapHour = h
        settings.recapMinute = m
        scheduleSave()
    }

    func setRecapOpensItself(_ enabled: Bool) {
        guard enabled != settings.recapOpensItself else { return }
        settings.recapOpensItself = enabled
        scheduleSave()
    }

    func setPlaysSound(_ enabled: Bool) {
        guard enabled != settings.playsSound else { return }
        settings.playsSound = enabled
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = settings
        saveTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await store.save(snapshot)
        }
    }

    func flush() async {
        saveTask?.cancel()
        await store.save(settings)
    }
}
