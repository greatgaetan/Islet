import AppKit
import IsletCore
import SwiftUI

struct SettingsView: View {
    let model: SettingsModel
    let tasks: TaskModel

    @State private var launchesAtLogin = LoginItem.isEnabled
    @State private var exportNote: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: WindowStyle.Spacing.betweenSections) {
                    pomodoro
                    quickAdd
                    eveningReview
                    sound
                    general
                }
                .padding(WindowStyle.Spacing.windowPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            IsletStatusBar(leading: statusLine, trailing: Bundle.main.isletVersion)
        }
        .background(WindowStyle.background)
        .frame(width: 420, height: 460)
    }

    /// What the app is holding right now — the same two facts the open island
    /// puts either side of the notch, so the window agrees with it.
    private var statusLine: String {
        let count = tasks.openCount
        let tasksText = count == 1 ? "1 task" : "\(count) tasks"
        let time = String(format: "%02d:%02d",
                          model.settings.recapHour, model.settings.recapMinute)
        return "\(tasksText) · review at \(time)"
    }

    // MARK: - Sections

    private var pomodoro: some View {
        IsletSection(
            title: "Pomodoro",
            footnote: "The long break replaces the last short one, so a session ends "
                    + "rested — which is the right moment to be asked about another."
        ) {
            minutes("Focus", value: work, range: PomodoroConfiguration.workRange)
            IsletDivider()
            minutes("Short break", value: shortBreak,
                    range: PomodoroConfiguration.shortBreakRange)
            IsletDivider()
            minutes("Long break", value: longBreak,
                    range: PomodoroConfiguration.longBreakRange)
            IsletDivider()
            IsletRow(title: "Loops per session") {
                IsletValue(text: "\(model.pomodoro.loops)")
                Stepper("", value: loops, in: PomodoroConfiguration.loopsRange)
                    .labelsHidden()
            }
            IsletDivider()
            IsletRow(title: "A session lasts") {
                IsletValue(text: model.pomodoro.totalText)
            }
        }
    }

    private var quickAdd: some View {
        IsletSection(
            title: "Quick add",
            footnote: "Opens instantly, with no animation: an action repeated dozens of "
                    + "times a day should never make you wait. ⌘1 / ⌘2 / ⌘3 file it as "
                    + "you type; Return keeps the field open for the next one."
        ) {
            IsletRow(title: "Shortcut") { IsletValue(text: "⌥Space") }
        }
    }

    private var eveningReview: some View {
        IsletSection(
            title: "Evening review",
            footnote: "It widens the notch once and then keeps quiet. Left alone for "
                    + "half an hour it gives up and tries again tomorrow, and anything "
                    + "you do not answer simply rolls to tomorrow — stopping halfway "
                    + "loses nothing. Turn the switch off and it waits on the notch "
                    + "until you ask for it."
        ) {
            // Two popups, not the typed field this used to be. `DatePicker`
            // renders as an `NSDatePicker`, and its stepper field keeps the
            // caret once it has it — you cannot click your way out — and it
            // does not move to the minutes when the two hour digits are in.
            // Nothing to type is better than something to type badly.
            IsletRow(title: "Offered at") {
                HStack(spacing: 4) {
                    Picker("Hour", selection: recapHour) {
                        ForEach(Array(IsletSettings.recapHourRange), id: \.self) { hour in
                            Text(hourLabel(hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    // Two bordered popups side by side read as two settings.
                    // The colon says they are one time.
                    Text(":").foregroundStyle(WindowStyle.secondary)

                    Picker("Minute", selection: recapMinute) {
                        ForEach(IsletSettings.recapMinuteSteps, id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            IsletDivider()
            IsletRow(title: "Open it automatically") {
                Toggle("", isOn: recapOpensItself).isletSwitch()
            }
        }
    }

    private var sound: some View {
        IsletSection(
            title: "Sound",
            footnote: "There is no reliable way to read whether a Focus mode is on, "
                    + "so this is a switch rather than a guess. Without it, a segment "
                    + "ending while you look away is completely silent."
        ) {
            IsletRow(title: "Chime when a segment ends") {
                Toggle("", isOn: playsSound).isletSwitch()
            }
        }
    }

    private var general: some View {
        IsletSection(
            title: "General",
            // Quitting was always possible and never findable: an accessory app
            // has no Dock icon to right-click and no menu bar of its own on
            // screen, so ⌘Q and the notch's context menu are invisible until you
            // already know them.
            footnote: "Islet has no Dock icon, so this is the one place a quit button "
                    + "can live. ⌘Q does it too while Islet is in front, as does a "
                    + "right-click on the notch. Anything unsaved is written out first."
        ) {
            IsletRow(title: "Start Islet when I log in",
                     subtitle: LoginItem.isAvailable ? nil
                             : "Running from source, so this is inert.") {
                Toggle("", isOn: $launchesAtLogin)
                    .isletSwitch()
                    .onChange(of: launchesAtLogin) { _, enabled in
                        enabled ? LoginItem.enable() : LoginItem.disable()
                        Preferences.hasOfferedLoginItem = true
                    }
                    .disabled(!LoginItem.isAvailable)
            }
            IsletDivider()
            IsletRow(title: "Tasks", subtitle: exportNote) {
                Button("Export…") { export() }
            }
            IsletDivider()
            IsletRow(title: "Islet") {
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
    }

    // MARK: - Bindings

    private func minutes(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        IsletRow(title: title) {
            IsletValue(text: "\(value.wrappedValue) min")
            Stepper("", value: value, in: range).labelsHidden()
        }
    }

    private var work: Binding<Int> {
        Binding(get: { model.pomodoro.workMinutes },
                set: { var c = model.pomodoro; c.workMinutes = $0; model.pomodoro = c })
    }

    private var shortBreak: Binding<Int> {
        Binding(get: { model.pomodoro.shortBreakMinutes },
                set: { var c = model.pomodoro; c.shortBreakMinutes = $0; model.pomodoro = c })
    }

    private var longBreak: Binding<Int> {
        Binding(get: { model.pomodoro.longBreakMinutes },
                set: { var c = model.pomodoro; c.longBreakMinutes = $0; model.pomodoro = c })
    }

    private var recapOpensItself: Binding<Bool> {
        Binding(get: { model.settings.recapOpensItself },
                set: { model.setRecapOpensItself($0) })
    }

    private var recapHour: Binding<Int> {
        Binding(get: { model.settings.recapHour },
                set: { model.setRecapTime(hour: $0, minute: model.settings.recapMinute) })
    }

    private var recapMinute: Binding<Int> {
        Binding(get: { model.settings.recapMinute },
                set: { model.setRecapTime(hour: model.settings.recapHour, minute: $0) })
    }

    /// "18" on a 24-hour clock, "6 PM" on a 12-hour one. Built from the locale's
    /// own hour template rather than hard-coded, because the popup lists hours
    /// alone and `%02d` would be a lie in half the world.
    private func hourLabel(_ hour: Int) -> String {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0,
                                              locale: .current) ?? "HH"
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = format
        guard let date = Calendar.current.date(bySettingHour: hour, minute: 0,
                                               second: 0, of: .now) else {
            return String(format: "%02d", hour)
        }
        return formatter.string(from: date)
    }

    private var playsSound: Binding<Bool> {
        Binding(get: { model.settings.playsSound },
                set: { model.setPlaysSound($0) })
    }

    private var loops: Binding<Int> {
        Binding(get: { model.pomodoro.loops },
                set: { var c = model.pomodoro; c.loops = $0.clamped(to: PomodoroConfiguration.loopsRange); model.pomodoro = c })
    }

    // MARK: - Export

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "islet-tasks.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(tasks.list) else {
            exportNote = "Could not encode."
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            exportNote = "Saved."
        } catch {
            exportNote = "Could not write."
        }
    }
}
