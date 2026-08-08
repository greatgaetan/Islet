import IsletCore
import SwiftUI

struct TaskListView: View {
    let model: TaskModel
    @State private var showsLoginItemOffer = Preferences.shouldOfferLoginItem

    var body: some View {
        VStack(spacing: 0) {
            filters
            Divider()

            if model.visible.isEmpty {
                EmptyState(filter: model.filter)
            } else {
                list
            }

            if showsLoginItemOffer {
                Divider()
                loginItemOffer
            }
        }
        .frame(minWidth: 380, minHeight: 320)
    }

    // MARK: - Filters

    private var filters: some View {
        HStack(spacing: 6) {
            FilterChip(title: "All", tint: .primary, shortcut: nil,
                       count: model.openCount, isOn: model.filter == nil) {
                model.setFilter(nil)
            }
            ForEach(TaskCategory.allCases) { category in
                FilterChip(
                    title: category.label,
                    tint: category.tint,
                    shortcut: category.shortcut,
                    count: model.count(of: category),
                    isOn: model.filter == category
                ) {
                    model.setFilter(model.filter == category ? nil : category)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.visible) { task in
                    TaskRow(task: task, model: model)
                    Divider().padding(.leading, 38)
                }
            }
        }
    }

    // MARK: - Login item

    private var loginItemOffer: some View {
        HStack(spacing: 10) {
            Text("Start Islet when you log in?")
                .font(.system(size: 12))
            Spacer(minLength: 0)
            Button("Not now") {
                Preferences.hasOfferedLoginItem = true
                withAnimation(Motion.contentOut) { showsLoginItemOffer = false }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Button("Yes") {
                LoginItem.enable()
                Preferences.hasOfferedLoginItem = true
                withAnimation(Motion.contentOut) { showsLoginItemOffer = false }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Row

private struct TaskRow: View {
    let task: TaskItem
    let model: TaskModel

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                model.toggleCompletion(task.id)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : task.category.mark)
                    .font(.system(size: 13))
                    .foregroundStyle(task.isCompleted ? AnyShapeStyle(.secondary)
                                                      : AnyShapeStyle(task.category.tint))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13))
                    .strikethrough(task.isCompleted, color: .secondary)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                // The metadata is editable here and nowhere else. *Defer* and
                // *Delegate* each carry an optional field, and until now nothing
                // in the app could set either — two thirds of the method were
                // decoration.
                switch task.category {
                case .deferred: deferEditor
                case .delegated: delegateEditor
                case .toDo: EmptyView()
                }
            }

            Spacer(minLength: 0)

            // Nothing here may be taller than the text it sits beside, or the row
            // changes height on hover and the whole list twitches under the
            // pointer. The old `Picker` was a real `NSPopUpButton` — some 24 pt
            // against the 14 pt label it replaced.
            //
            // So the category is a *menu wearing the label's clothes*: identical
            // height, always visible, and directly clickable instead of hiding
            // until hovered.
            Menu {
                ForEach(TaskCategory.allCases) { option in
                    Button(option.label) { model.recategorise(task.id, to: option) }
                }
            } label: {
                Text(task.category.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(task.category.tint.opacity(task.isCompleted ? 0.4 : 0.9))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change category")

            // Always in the hierarchy, never conditionally inserted, and capped
            // at the line height so it can never grow the row.
            Button {
                model.delete(task.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0)
                    .frame(width: 24, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isHovered)
            .help("Delete")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .background(isHovered ? Color.primary.opacity(0.04) : .clear)
    }

    // MARK: - Editors

    /// A date is optional: an undated defer is still a legitimate "not now", so
    /// the control has to be able to hold nothing.
    @ViewBuilder
    private var deferEditor: some View {
        if let date = task.deferUntil {
            HStack(spacing: 4) {
                DatePicker("", selection: deferDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .controlSize(.mini)
                Button {
                    model.setDeferDate(task.id, to: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Remove the date — it stays deferred, just undated")
            }
            .opacity(task.isCompleted ? 0.5 : 1)
            // Silent on purpose: an already-due defer is about to be promoted
            // anyway, at the app's next wake.
            .accessibilityLabel("Comes back on \(date.formatted(date: .abbreviated, time: .omitted))")
        } else {
            Button("Add a date") {
                model.setDeferDate(task.id, to: .now.addingTimeInterval(86_400))
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
    }

    /// Free text, never a Contacts link: this is a note to self, not an
    /// assignment.
    private var delegateEditor: some View {
        TextField("Who?", text: delegateName)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(task.delegateTo == nil ? .tertiary : .secondary)
            .frame(maxWidth: 160, alignment: .leading)
    }

    // MARK: - Bindings

    private var category: Binding<TaskCategory> {
        Binding(get: { task.category },
                set: { model.recategorise(task.id, to: $0) })
    }

    private var deferDate: Binding<Date> {
        Binding(get: { task.deferUntil ?? .now },
                set: { model.setDeferDate(task.id, to: $0) })
    }

    private var delegateName: Binding<String> {
        Binding(get: { task.delegateTo ?? "" },
                set: { model.setDelegate(task.id, to: $0) })
    }
}

// MARK: - Pieces

private struct FilterChip: View {
    let title: String
    let tint: Color
    /// The ⌘ digit that files a new task here. Shown, not hidden in a tooltip:
    /// a shortcut nobody sees is a shortcut nobody uses.
    let shortcut: String?
    let count: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let shortcut {
                    Text("⌘\(shortcut)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tint.opacity(isOn ? 0.28 : 0.14))
                        )
                }
                Text(title).font(.system(size: 11, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, design: .rounded))
                        .monospacedDigit()
                        .opacity(0.6)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(isOn ? 0.18 : 0.06)))
            .foregroundStyle(isOn ? tint : .primary)
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyState: View {
    let filter: TaskCategory?

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: filter?.symbol ?? "tray")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.quaternary)
            Text(filter.map { "Nothing in \($0.label)." } ?? "No tasks yet.")
                .font(.system(size: 13, weight: .medium))
            // The two things a new user has no way of guessing.
            Text("Press ⌥Space to add one, or hover the notch.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("⌘, for settings · right-click the notch for everything else")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
