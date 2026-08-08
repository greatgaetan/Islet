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
                Picker("Offered at", selection: recapHour) {
                    ForEach(Array(IsletSettings.recapHourRange), id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
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
                set: { model.setRecapHour($0) })
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
