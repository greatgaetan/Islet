import AppKit
import IsletCore
import SwiftUI

struct SettingsView: View {
    let model: SettingsModel
    let tasks: TaskModel

    @State private var launchesAtLogin = LoginItem.isEnabled
    @State private var exportNote: String?

    var body: some View {
        Form {
            Section("Pomodoro") {
                minutes("Focus", value: work, range: PomodoroConfiguration.workRange)
                minutes("Short break", value: shortBreak,
                        range: PomodoroConfiguration.shortBreakRange)
                minutes("Long break", value: longBreak,
                        range: PomodoroConfiguration.longBreakRange)
                Stepper(value: loops, in: PomodoroConfiguration.loopsRange) {
                    LabeledContent("Loops per session", value: "\(model.pomodoro.loops)")
                }
                LabeledContent("A session lasts", value: model.pomodoro.totalText)
                    .foregroundStyle(.secondary)
                Text("The long break replaces the last short one, so a session ends rested — "
                     + "which is the right moment to be asked about another.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Section("Quick add") {
                LabeledContent("Shortcut", value: "⌥Space")
                Text("Opens instantly, with no animation: an action repeated dozens of times "
                     + "a day should never make you wait. ⌘1 / ⌘2 / ⌘3 file it as you type; "
                     + "Return keeps the field open for the next one.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Section("Evening review") {
                // Two popups, not the typed field this used to be. `DatePicker`
                // renders as an `NSDatePicker`, and its stepper field keeps the
                // caret once it has it — you cannot click your way out — and it
                // does not move to the minutes when the two hour digits are in,
                // so you type "18" and then have to reach for the mouse anyway.
                // Nothing to type is better than something to type badly.
                //
                // Quarter hours are the whole cost: 18:50 can no longer be
                // asked for. For the hour an evening review is offered, that is
                // not a real loss.
                //
                // The scheduler ticks once a minute, so the review appears
                // within a minute of this time, not on the second.
                LabeledContent("Offered at") {
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
                        Text(":")
                            .foregroundStyle(.secondary)

                        Picker("Minute", selection: recapMinute) {
                            ForEach(IsletSettings.recapMinuteSteps, id: \.self) { minute in
                                Text(String(format: "%02d", minute)).tag(minute)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                Toggle("Open it automatically", isOn: recapOpensItself)
                Text("It widens the notch once and then keeps quiet. Left alone for "
                     + "half an hour it gives up and tries again tomorrow, and anything "
                     + "you do not answer simply rolls to tomorrow — stopping halfway "
                     + "loses nothing. Turn the switch off and it waits on the notch "
                     + "until you ask for it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Section("Sound") {
                Toggle("Chime when a segment ends", isOn: playsSound)
                Text("There is no reliable way to read whether a Focus mode is on, "
                     + "so this is a switch rather than a guess. Without it, a segment "
                     + "ending while you look away is completely silent.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Section("General") {
                Toggle("Start Islet when I log in", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in
                        enabled ? LoginItem.enable() : LoginItem.disable()
                        Preferences.hasOfferedLoginItem = true
                    }
                    .disabled(!LoginItem.isAvailable)

                HStack {
                    Button("Export tasks…") { export() }
                    if let exportNote {
                        Text(exportNote)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                if !LoginItem.isAvailable {
                    Text("Running from source, so the login item is inert. "
                         + "Build Islet.app to use it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                // Quitting was always possible and never findable. An accessory
                // app has no Dock icon to right-click and no menu bar of its own
                // on screen, so both existing routes — ⌘Q, and the notch's
                // context menu — are invisible until you already know them. An
                // app you cannot work out how to close is one people force-quit.
                Button("Quit Islet") { NSApp.terminate(nil) }
                Text("Islet has no Dock icon, so this is the one place a quit "
                     + "button can live. ⌘Q does it too while Islet is in front, "
                     + "as does a right-click on the notch. Anything unsaved is "
                     + "written out first.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 400)
    }

    // MARK: - Bindings

    private func minutes(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent(title, value: "\(value.wrappedValue) min")
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
