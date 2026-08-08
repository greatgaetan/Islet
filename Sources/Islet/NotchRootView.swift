import AppKit
import IsletCore
import SwiftUI

struct NotchRootView: View {
    let model: NotchModel
    let geometry: PanelGeometry

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(metrics: model.metrics)
                // Pure black, no shadow, no material: the illusion is that the
                // hardware grew. Liquid Glass is reserved for surfaces that
                // float clearly below the bezel.
                .fill(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Hit area is the silhouette, not its bounding box: clicks in
                // the transparent corners belong to whatever is behind.
                .contentShape(NotchShape(metrics: model.metrics))
                .onTapGesture { model.silhouetteTapped() }
                .gesture(
                    // A grabber promises a drag, so it drags. `minimumDistance`
                    // keeps a click a click.
                    DragGesture(minimumDistance: 4)
                        .onChanged { model.updateDrag(translation: $0.translation.height) }
                        .onEnded { model.endDrag(velocity: $0.velocity.height / 1000) }
                )
                .contextMenu {
                    Button("Tasks") { model.onShowTasks?() }
                    Button("Settings…") { model.onShowSettings?() }
                    Divider()
                    Button("Quit Islet") { NSApp.terminate(nil) }
                }

            content
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        .opacity(model.hasAppeared ? 1 : 0)
        .onAppear { model.markAppeared() }
    }

    // MARK: - Content, one layer per state

    private var content: some View {
        ZStack(alignment: .top) {
            RestingContent(model: model)
                .notchLayer(model.state == .resting)
            LiveContent(model: model)
                .notchLayer(model.state == .live)
            PeekContent(model: model, isVisible: model.state == .peek)
                .notchLayer(model.state == .peek,
                            opacity: model.dragProgress.map { 1 - Double($0) })
            ExpandedContent(model: model, isVisible: model.state == .expanded)
                .notchLayer(model.state == .expanded,
                            opacity: model.dragProgress.map(Double.init),
                            instant: model.presentedFromKeyboard)
        }
        .frame(width: model.metrics.width, height: model.metrics.height, alignment: .top)
        .clipped()
    }
}

// MARK: - Layer visibility

private extension View {
    /// Container first, content second. Blur bridges the crossfade so the eye
    /// reads one transformation instead of two overlapping objects.
    /// `opacity` overrides the state-driven value while a drag is in flight.
    /// It is deliberately not animated — the value is already following a pointer.
    func notchLayer(_ visible: Bool, opacity: Double? = nil, instant: Bool = false) -> some View {
        self
            .opacity(opacity ?? (visible ? 1 : 0))
            // Tied to the crossfade rather than held constant: an incoming layer
            // that stays blurred until release snaps sharp at the end, which is
            // the pop the blur existed to prevent.
            .blur(radius: opacity.map { (1 - $0) * Motion.crossfadeBlur }
                  ?? (visible ? 0 : Motion.crossfadeBlur))
            .allowsHitTesting(visible)
            .animation(instant ? nil
                       : visible ? Motion.contentIn.delay(Motion.contentDelay)
                       : Motion.contentOut,
                       value: visible)
    }

    /// Per-row cascade. Offset only, never opacity: the layer already owns the
    /// fade, and multiplying two opacity curves gives a curve nobody chose.
    func staggered(_ visible: Bool, index: Int, instant: Bool = false) -> some View {
        self
            // Displacement is exactly what Reduce Motion asks us to drop; the
            // layer's own fade stays, because it aids comprehension.
            .offset(y: visible || Motion.prefersReducedMotion ? 0 : 6)
            .animation(
                instant ? nil
                    : visible
                    ? Motion.contentIn.delay(Motion.contentDelay + Double(index) * Motion.stagger)
                    : Motion.contentOut,
                value: visible
            )
    }
}

// MARK: - Resting

private struct RestingContent: View {
    let model: NotchModel

    var body: some View {
        HStack(spacing: 0) {
            NotchGlyph(symbol: "plus") { model.send(.clicked) }
                .frame(width: NotchMetrics.glyphSlot(for: .resting))
                .overlay(alignment: .topTrailing) {
                    // The evening review announces itself with one dot and then
                    // shuts up. Anything louder, at 18:00 during a call, is an
                    // app you uninstall.
                    if model.recap.isPending {
                        Circle()
                            .fill(TaskCategory.toDo.tint)
                            .frame(width: 4, height: 4)
                            .offset(x: 1, y: 2)
                    }
                }
            Spacer(minLength: 0)
                .frame(width: model.notch.width)
            NotchGlyph(symbol: model.pomodoro.isRunning ? "pause.fill" : "play.fill") {
                model.toggleTimer()
            }
            .frame(width: NotchMetrics.glyphSlot(for: .resting))
        }
        .frame(height: model.notch.height)
    }
}

// MARK: - Live

private struct LiveContent: View {
    let model: NotchModel

    var body: some View {
        HStack(spacing: 0) {
            // The active task if a session is running on one, otherwise the
            // segment name. Never blank: an empty half beside a full one reads
            // as something missing rather than something absent.
            Text(model.tasks.activeTask?.title ?? model.pomodoro.current?.kind.label ?? "")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                // Centred in its half, not flush against the notch: the label is
                // often much shorter than the slot ("Focus" against "Long break"),
                // and hugging the notch left a void on the outside that made the
                // two halves look mismatched.
                .frame(width: NotchMetrics.glyphSlot(for: .live), alignment: .center)

            Spacer(minLength: 0)
                .frame(width: model.notch.width)

            HStack(spacing: 6) {
                ProgressRing(progress: model.pomodoro.progress,
                             tint: model.pomodoro.current?.kind.tint ?? .white)
                    .frame(width: 14, height: 14)
                Text(model.pomodoro.clockText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.numericText(countsDown: true))
            }
            .padding(.horizontal, 10)
            .frame(width: NotchMetrics.glyphSlot(for: .live), alignment: .center)
        }
        .frame(height: model.notch.height)
        .opacity(model.pomodoro.isRunning ? 1 : 0.55)
    }
}

// MARK: - Peek

private struct PeekContent: View {
    let model: NotchModel
    let isVisible: Bool

    /// The whole Peek panel is hovered by definition — this is the *timer half*
    /// specifically, which is what reveals the stop.
    @State private var isTimerHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.recap.isPending {
                    recapInvitation
                } else if model.isAwaitingDecision {
                    decision
                } else if let announcement = model.announcement {
                    self.announcement(announcement)
                } else {
                    controls
                }
            }
            .frame(height: model.notch.height)

            Spacer(minLength: 0)
            // Hidden once the drag starts: it has already said what it had to
            // say, and Peek keeps its own height while the silhouette grows past
            // it — leaving the grabber marooned mid-panel.
            grabber.opacity(model.isDragging ? 0 : 1)
        }
        .frame(height: peekHeight, alignment: .top)
    }

    /// Explicit heights, not `maxHeight: .infinity`.
    ///
    /// Every layer lives in the same `ZStack`, so its natural height is set by
    /// the tallest one — Expanded, present even when invisible. Filling that
    /// put the grabber hundreds of points below the silhouette, where `clipped()`
    /// erased it. Nothing about the layout may be inferred from what happens to
    /// be proposed.
    private var peekHeight: CGFloat {
        NotchMetrics.forState(.peek, notch: model.notch).height
    }

    /// Nothing said the panel could be opened at all. A sheet grabber is the
    /// established sign for "there is more below": it appears only once you are
    /// already hovering, and it is quiet enough to be read rather than noticed.
    private var grabber: some View {
        Capsule()
            .fill(.white.opacity(0.22))
            .frame(width: 20, height: 2.5)
            .padding(.bottom, 6)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                NotchGlyph(symbol: "plus") { model.send(.clicked) }
                    .frame(width: 20)
                Text(taskSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(width: NotchMetrics.glyphSlot(for: .peek), alignment: .trailing)

            Spacer(minLength: 0)
                .frame(width: model.notch.width)

            HStack(spacing: 8) {
                NotchGlyph(symbol: model.pomodoro.isRunning ? "pause.fill" : "play.fill") {
                    model.toggleTimer()
                }
                .frame(width: 20)

                if model.pomodoro.isActive {
                    NotchGlyph(symbol: "forward.fill") { model.pomodoro.skip() }
                        .frame(width: 20)
                }

                // Stopping a session should not mean opening the whole panel.
                // There is no room for a fourth control *and* the clock in 96 pt,
                // so the stop takes the clock's place while you are reaching for
                // it — the time is still in Live, one state away, and it is not
                // what you are looking at when your hand is on the controls.
                if model.pomodoro.isActive, isTimerHovered {
                    NotchGlyph(symbol: "stop.fill") { model.dismissSession() }
                        .frame(width: 20)
                        .help("Stop the session")
                } else {
                    Text(model.pomodoro.clockText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            .padding(.horizontal, 12)
            .frame(width: NotchMetrics.glyphSlot(for: .peek), alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(Motion.glyph) { isTimerHovered = hovering }
            }
        }
    }

    /// Offered, never imposed: it widens on its own but only *this* far, and
    /// opening the review is still a thing you choose to do.
    private var recapInvitation: some View {
        HStack(spacing: 0) {
            Text("Evening review")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(width: NotchMetrics.glyphSlot(for: .peek), alignment: .trailing)

            Spacer(minLength: 0).frame(width: model.notch.width)

            HStack(spacing: 8) {
                Text("\(model.recap.remaining)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                NotchGlyph(symbol: "chevron.down", restOpacity: 0.7) {
                    model.beginRecap()
                }
                .frame(width: 20)
            }
            .padding(.horizontal, 12)
            .frame(width: NotchMetrics.glyphSlot(for: .peek), alignment: .leading)
        }
    }

    private var taskSummary: String {
        switch model.tasks.openCount {
        case 0: "No tasks"
        case 1: "1 task"
        case let count: "\(count) tasks"
        }
    }

    /// Label on the left, duration on the right — the notch is 120 pt a side,
    /// so "Long break · 15:00" on one line would not fit.
    private func announcement(_ text: String) -> some View {
        HStack(spacing: 0) {
            Text(model.pomodoro.current?.kind.label ?? text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.pomodoro.current?.kind.tint ?? .white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(width: NotchMetrics.glyphSlot(for: .peek), alignment: .trailing)

            Spacer(minLength: 0)
                .frame(width: model.notch.width)

            Text((model.pomodoro.current?.duration ?? 0).clockText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .frame(width: NotchMetrics.glyphSlot(for: .peek), alignment: .leading)
        }
    }

    private var decision: some View {
        HStack(spacing: 0) {
            // One line, so it stays on the same baseline as the two buttons.
            // "Session complete" wraps inside a 120 pt slot and looks clumsy.
            Text("Session done")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(width: NotchMetrics.glyphSlot(for: .peek), alignment: .trailing)

            Spacer(minLength: 0)
                .frame(width: model.notch.width)

            HStack(spacing: 12) {
                NotchGlyph(symbol: "arrow.clockwise", restOpacity: 0.7) {
                    model.restartSession()
                }
                .frame(width: 22)
                NotchGlyph(symbol: "xmark", restOpacity: 0.7) {
                    model.dismissSession()
                }
                .frame(width: 22)
            }
            .padding(.horizontal, 12)
            .frame(width: NotchMetrics.glyphSlot(for: .peek), alignment: .leading)
        }
    }
}

// MARK: - Expanded

private struct ExpandedContent: View {
    let model: NotchModel
    let isVisible: Bool

    /// ⌥Space opens instantly, so nothing inside may fade or cascade either.
    private var instant: Bool { model.presentedFromKeyboard }

    var body: some View {
        if model.recap.isReviewing {
            RecapCards(model: model, isVisible: isVisible)
                .padding(.top, model.notch.height + 16)
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            panel
        }
    }

    private var panel: some View {
        HStack(alignment: .top, spacing: 0) {
            tasks
            // The separator needs room on both sides, or the two halves read as
            // one crowded block with a line drawn through it.
            Divider()
                .overlay(.white.opacity(0.07))
                .padding(.horizontal, 18)
            // Not half and half: the task chips need ~265 pt and the timer needs
            // ~175. Splitting equally was a reflex, and it crushed the chips.
            focus.frame(width: 215)
        }
        .overlay(alignment: .topTrailing) { settingsGlyph }
        .padding(.top, model.notch.height + 16)
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var tasks: some View {
        column(title: "TASKS") {
            QuickAddField(model: model, isVisible: isVisible)
                .staggered(isVisible, index: 0, instant: instant)

            Spacer(minLength: 0).frame(height: Spacing.withinGroup + 6)

            CategoryFilters(tasks: model.tasks)
                .staggered(isVisible, index: 1, instant: instant)

            Spacer(minLength: 0).frame(height: Spacing.betweenGroups - 6)

            if let pending = model.tasks.pendingUndo {
                UndoRow(title: pending.task.title) { model.tasks.undoDelete() }
                    .staggered(isVisible, index: 2, instant: instant)
            }

            if model.tasks.visible.isEmpty {
                Text(model.tasks.openCount == 0 && model.tasks.filter == nil
                     ? "Type above to capture one. ⌘, for settings."
                     : "Nothing here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 2)
                    .staggered(isVisible, index: 3, instant: instant)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(Array(model.tasks.visible.enumerated()), id: \.element.id) { index, task in
                            NotchTaskRow(task: task, tasks: model.tasks, model: model)
                                .staggered(isVisible, index: min(index + 3, 8), instant: instant)
                        }
                    }
                }
                // Exactly the height the silhouette was sized for, so neither
                // can drift from the other.
                .frame(height: NotchMetrics.ExpandedHeight.rowsHeight(
                    model.tasks.visible.count + (model.tasks.pendingUndo == nil ? 0 : 1),
                    notchHeight: model.notch.height
                ))
            }
        }
    }

    /// The section header carries the segment, so nothing repeats it below.
    ///
    /// "FOCUS" above and "Focus" underneath said the same thing twice — and when
    /// a break was running, the header was simply lying. One word, in the place a
    /// section name belongs, doing both jobs.
    private var focusTitle: String {
        model.pomodoro.current?.kind.label.uppercased() ?? "FOCUS"
    }

    /// Today's tally rides along with the loop line: recorded history should be
    /// visible, and it does not deserve a row of its own.
    private var statusLine: String {
        let done = model.history.workSegmentsToday
        guard done > 0 else { return model.pomodoro.loopText }
        return "\(model.pomodoro.loopText) · \(done) today"
    }

    private var focus: some View {
        column(title: focusTitle, tint: model.pomodoro.current?.kind.tint) {
            // Status group: the time is the single focal point, the ring is its
            // satellite and the loop line is tucked underneath — one unit.
            VStack(alignment: .leading, spacing: Spacing.withinGroup) {
                HStack(alignment: .center, spacing: 12) {
                    ProgressRing(progress: model.pomodoro.progress,
                                 tint: model.pomodoro.current?.kind.tint ?? .white,
                                 lineWidth: 2.5)
                        .frame(width: 34, height: 34)

                    Text(model.pomodoro.clockText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(model.pomodoro.isRunning ? 0.95 : 0.6))
                        .contentTransition(.numericText(countsDown: true))
                }

                Text(statusLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.32))
            }
            .staggered(isVisible, index: 0, instant: instant)

            // A real gap here, not another 12: this is where reading stops and
            // acting begins.
            Spacer(minLength: 0).frame(height: Spacing.betweenGroups)

            HStack(spacing: 8) {
                PanelButton(model.pomodoro.isRunning ? "Pause"
                            : model.pomodoro.isActive ? "Resume" : "Start",
                            emphasis: .primary) {
                    model.toggleTimer()
                }
                if model.pomodoro.isActive {
                    PanelButton("Skip", emphasis: .secondary) { model.pomodoro.skip() }
                    PanelButton("Stop", emphasis: .quiet) { model.dismissSession() }
                }
            }
            .staggered(isVisible, index: 1, instant: instant)
        }
    }

    /// ⌘, worked from the first day and was referenced nowhere — no Dock icon, no
    /// status item, and a menu bar that only exists while Islet is active. A
    /// shortcut nobody can discover is a shortcut nobody has.
    private var settingsGlyph: some View {
        NotchGlyph(symbol: "gearshape", restOpacity: 0.22) {
            model.onShowSettings?()
        }
        .frame(width: 22, height: 16)
        .help("Settings — ⌘,")
    }

    /// Three levels, and only three. A flat rhythm groups nothing.
    private enum Spacing {
        static let withinGroup: CGFloat = 4
        static let afterHeader: CGFloat = 14
        static let betweenGroups: CGFloat = 18
    }

    private func column<Content: View>(
        title: String,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(tint?.opacity(0.75) ?? .white.opacity(0.35))
                .animation(Motion.contentIn, value: title)

            Spacer(minLength: 0).frame(height: Spacing.afterHeader)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pieces

/// Permanent affordance: quiet at rest, awake on hover, and it answers a press.
///
/// Hover state is local, never shared through the model: a glyph in a hidden
/// layer must not light up because its twin in the visible layer is hovered.
struct NotchGlyph: View {
    let symbol: String
    var restOpacity: Double = Motion.glyphRestOpacity
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .opacity(isHovered ? 1 : restOpacity)
            .scaleEffect(isPressed ? Motion.pressScale : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onLongPressGesture(minimumDuration: 0) {
                action()
            } onPressingChanged: { pressing in
                withAnimation(Motion.glyph) { isPressed = pressing }
            }
            .animation(Motion.glyph, value: isHovered)
    }
}

struct PanelButton: View {
    /// Three identical grey pills tell you nothing about which one you want.
    enum Emphasis {
        case primary    // the one thing you came here to do
        case secondary  // available, not offered
        case quiet      // reachable, never inviting — Stop lives here
    }

    let title: String
    let emphasis: Emphasis
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    init(_ title: String, emphasis: Emphasis = .secondary, action: @escaping () -> Void) {
        self.title = title
        self.emphasis = emphasis
        self.action = action
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: emphasis == .primary ? .semibold : .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(background))
            )
            .scaleEffect(isPressed ? Motion.pressScale : 1)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onLongPressGesture(minimumDuration: 0) {
                action()
            } onPressingChanged: { pressing in
                withAnimation(Motion.glyph) { isPressed = pressing }
            }
            .animation(Motion.glyph, value: isHovered)
    }

    private var background: Double {
        switch emphasis {
        case .primary: isHovered ? 0.22 : 0.15
        case .secondary: isHovered ? 0.12 : 0.07
        // No fill until you reach for it: Stop should never look like an offer.
        case .quiet: isHovered ? 0.10 : 0
        }
    }

    private var foreground: Color {
        switch emphasis {
        case .primary: .white.opacity(isHovered ? 1 : 0.92)
        case .secondary: .white.opacity(isHovered ? 0.9 : 0.65)
        // A muted terracotta on hover says "this ends things" without shouting
        // it in red on a black bezel all day.
        case .quiet: isHovered
            ? Color(red: 0.92, green: 0.62, blue: 0.55)
            : .white.opacity(0.4)
        }
    }
}

private struct ProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // 1 Hz data, linearly interpolated: continuous to the eye,
                // cheap to the battery.
                .animation(Motion.tick, value: progress)
        }
    }
}


// MARK: - Quick add

/// Capture with no friction: type, press Return, keep going. Categorising is
/// optional — the evening triage is where sorting belongs.
private struct QuickAddField: View {
    let model: NotchModel
    let isVisible: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))

            // Placeholder drawn by hand rather than left to the text field: on a
            // permanently black panel the system's own placeholder colour is
            // only legible by accident.
            ZStack(alignment: .leading) {
                if !model.tasks.hasDraft {
                    Text("New task")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.28))
                        .allowsHitTesting(false)
                }
                TextField("", text: draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .focused($isFocused)
                    .onSubmit { model.tasks.commitDraft() }
            }

            // What Return will file it as. Click to cycle, same as Tab.
            Button {
                model.tasks.cyclePendingCategory()
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(model.tasks.pendingCategory.tint)
                        .frame(width: 5, height: 5)
                    Text(model.tasks.pendingCategory.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(model.tasks.pendingCategory.tint)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(model.tasks.pendingCategory.tint.opacity(0.14))
                )
            }
            .buttonStyle(.plain)
            .help("Tab or ⇧Tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .onChange(of: isVisible) { _, visible in
            // Focus follows the panel, so ⌥Space lands the caret in the field.
            isFocused = visible
        }
        .onAppear { isFocused = isVisible }
    }

    private var draft: Binding<String> {
        Binding(get: { model.tasks.draft },
                set: { model.tasks.updateDraft($0) })
    }
}

private struct CategoryFilters: View {
    let tasks: TaskModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                // "All" is explicit rather than "click the active one again": a
                // hidden way back is not a way back.
                chip(label: "All", tint: .white, badge: nil,
                     isOn: tasks.filter == nil) {
                    tasks.setFilter(nil)
                }

                ForEach(TaskCategory.allCases) { category in
                    chip(label: category.label,
                         tint: category.tint,
                         badge: category.shortcut,
                         isOn: tasks.filter == category) {
                        tasks.filter = tasks.filter == category ? nil : category
                    }
                }
                Spacer(minLength: 0)
            }

            // The numbered badges only make sense once you know what the number
            // is for. One quiet line, said once.
            Text("⌘1–3 to view, ⌘0 for all · Tab to file")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.28))
        }
    }

    /// Counts are left to the list window: four chips with labels, badges *and*
    /// counts overflow the 290 pt column, and the badge is what teaches.
    private func chip(
        label: String,
        tint: Color,
        badge: String?,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .frame(width: 12, height: 12)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tint.opacity(isOn ? 0.30 : 0.16))
                        )
                } else {
                    Circle()
                        .fill(tint.opacity(isOn ? 1 : 0.7))
                        .frame(width: 5, height: 5)
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(isOn ? 0.20 : 0.07)))
            .foregroundStyle(isOn ? tint : .white.opacity(0.55))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Task row, in the notch

/// Click to check, swipe left to delete.
///
/// The most frequent gesture — checking — is the simplest one. Deletion needs a
/// deliberate drag, triggers on **velocity as well as distance** so a quick
/// flick is enough, and damps past its limit rather than hitting a wall.
private struct NotchTaskRow: View {
    let task: TaskItem
    let tasks: TaskModel
    /// Only the notch's rows can start a session; the window's cannot reach the
    /// timer, and pretending otherwise would be a dead button.
    var model: NotchModel?

    @State private var isHovered = false
    /// Hovering the delete target specifically, so it can say so.
    @State private var isTrashHovered = false
    @State private var isFocusHovered = false
    @State private var drag: CGFloat = 0

    private static let deleteThreshold: CGFloat = 64
    /// Emil's number: px per millisecond, above which a flick counts regardless
    /// of how far it actually travelled.
    private static let flickVelocity: CGFloat = 0.11

    var body: some View {
        ZStack(alignment: .trailing) {
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(min(1, abs(drag) / Self.deleteThreshold)))
                .padding(.trailing, 8)

            HStack(spacing: 8) {
                // Shape *and* colour. Either one alone would be readable; the
                // pair is readable at 9 pt, at low opacity, and to someone who
                // cannot separate the hues at all.
                Image(systemName: tasks.activeTaskID == task.id
                      ? "timer" : task.category.mark)
                    .font(.system(size: 9))
                    .foregroundStyle(task.category.tint.opacity(task.isCompleted ? 0.35 : 0.95))
                    .frame(width: 11)

                StrikeThroughTitle(title: task.title, isCompleted: task.isCompleted)
                Spacer(minLength: 0)

                // Start a session on this task. Hidden until hover, like the
                // trash, and the same slot size for the same reason.
                Button {
                    model?.startFocus(on: task)
                } label: {
                    Image(systemName: "timer")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(isFocusHovered ? 0.95
                                                        : isHovered ? 0.6 : 0))
                        .frame(width: 26)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(.white.opacity(isFocusHovered ? 0.12 : 0))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isHovered && model != nil)
                .onHover { hovering in
                    withAnimation(Motion.glyph) { isFocusHovered = hovering }
                }
                .help("Focus on this task")

                // Discoverable as well as fast: the swipe is for when you know
                // it, the button is for when you don't.
                //
                // Always in the hierarchy, never conditionally inserted. A button
                // that only exists once hover has registered is not there yet if
                // you arrive and click in the same instant — and the row tap
                // underneath then checks the task instead of deleting it.
                Button {
                    tasks.delete(task.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(isTrashHovered ? 0.95
                                                        : isHovered ? 0.6 : 0))
                        // The target is the slot, not the ink. A 10 pt glyph was
                        // a 10 pt target, and missing it by two points did the
                        // wrong thing.
                        //
                        // Width is fixed, height *fills* the row: an explicit
                        // height taller than the text would grow the row, and the
                        // 28 pt pitch is what the panel's height is calculated
                        // from. Widening is free; growing is not.
                        .frame(width: 28)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(.white.opacity(isTrashHovered ? 0.12 : 0))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isHovered)
                .onHover { hovering in
                    withAnimation(Motion.glyph) { isTrashHovered = hovering }
                }
                .help("Delete — or press ⌫")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.07 : 0))
            )
            .offset(x: drag)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Motion.glyph) {
                isHovered = hovering
                if !hovering { isTrashHovered = false }
            }
            if hovering {
                tasks.hoveredTaskID = task.id
            } else if tasks.hoveredTaskID == task.id {
                tasks.hoveredTaskID = nil
            }
        }
        .onTapGesture { tasks.toggleCompletion(task.id) }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    let raw = value.translation.width
                    // Rightwards, and past the limit, the row resists instead of
                    // following: things in the real world slow down before they
                    // stop.
                    drag = raw > 0 ? raw * 0.25 : damped(raw)
                }
                .onEnded { value in
                    let travelled = -value.translation.width
                    let predicted = -value.predictedEndTranslation.width
                    let flicked = predicted > Self.deleteThreshold * 2
                    if travelled > Self.deleteThreshold || flicked {
                        withAnimation(Motion.collapse) { drag = -240 }
                        tasks.delete(task.id)
                    } else {
                        withAnimation(Motion.peekIn) { drag = 0 }
                    }
                }
        )
    }

    private func damped(_ raw: CGFloat) -> CGFloat {
        let limit = Self.deleteThreshold
        guard raw < -limit else { return raw }
        return -limit + (raw + limit) * 0.35
    }

    private var badge: String? {
        switch task.category {
        case .toDo: nil
        case .deferred: "DEFER"
        case .delegated: "DELEGATE"
        }
    }
}

/// The strike-through grows left to right rather than simply appearing, so
/// checking something off reads as an act instead of a style change.
private struct StrikeThroughTitle: View {
    let title: String
    let isCompleted: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(isCompleted ? 0.4 : 0.85))
            .lineLimit(1)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(.white.opacity(0.5))
                        .frame(width: isCompleted ? proxy.size.width : 0, height: 1)
                        .offset(y: proxy.size.height / 2)
                }
            }
            .animation(Motion.contentIn, value: isCompleted)
    }
}

private struct UndoRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Deleted “\(title)”")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Undo", action: action)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
}
