# Islet — decision record

Every decision below was settled before any code was written. Nothing here is
an assumption; if something is missing, it is out of scope on purpose.

## What it is

A macOS app that lives around the notch of the built-in display. Left half: a
to-do list with three categories (To do / Defer / Delegate). Right half: a
Pomodoro timer. Plus one window for managing both.

The stated goal is not the feature set. It is that the motion feels native.

## Platform

- Native Swift only. AppKit `NSPanel` shell, SwiftUI content. There is no
  public Dynamic Island API on macOS — the whole illusion is hand-built.
- The **built-in notched display**, always. Never `NSScreen.main`: on this
  machine the main display is frequently an external monitor. Measured notch:
  220 × 38 pt.
- No external-display fallback, no fake notch elsewhere.
- Local data only. No sync, no account. Public GitHub, MIT, clone-and-build.

## Presentation states

| State | Silhouette | Contents |
|---|---|---|
| `hidden` | exactly the physical notch | nothing — invisible against the bezel |
| `resting` | notch + 28 pt each side | `+` glyph left, play glyph right, 35 % opacity |
| `live` | notch + 84 pt each side | active task title left, progress ring + time right |
| `peek` | notch + 120 pt, +22 pt tall | task count + `+`, play/pause + time, and a **grabber** |
| `expanded` | 640 × **content-sized**, 230–394 pt | two columns: list & quick-add, timer & controls |

Transitions: **the dwell depends on how the pointer arrived** — 80 ms once it has
slowed to aim, 250 ms for one crossing at speed. A single fixed delay cannot do
both jobs: the notch sits directly under the path to the menu bar, so a short
delay opens on every crossing, and a long one makes a deliberate hover feel
sluggish dozens of times a day. Slowing down *is* the statement of intent, and it
is a far better signal than any timer. Click → `expanded` directly; pointer exit
+ 400 ms grace → back to rest. Editing locks the panel open. A running timer
means the rest state is `live`, not `resting`.

`hidden` is the retracted silhouette rather than a hidden window, so **every
transition is the morph of a shape that already exists**. Nothing appears from
nothing.

Islet mirrors its host: where macOS hides the menu bar (full-screen space,
auto-hide setting), Islet retracts; where macOS reveals it on a top-edge
hover, Islet returns. A running timer overrides this — the ring stays visible
in full screen, because that is when a quiet timer is worth most.

## Motion contract

| Transition | Spring | Why |
|---|---|---|
| → `peek` | `duration 0.22, bounce 0.10` | seen dozens of times a day; short, barely any bounce |
| → `expanded` | `duration 0.32, bounce 0.18` | the signature morph; enough bounce to read as alive |
| any collapse | `duration 0.20, bounce 0` | exit always faster than entry |
| segment announce | `duration 0.40, bounce 0.25` | ≈8×/day; rare enough to have character |
| content | `easeOut 0.16`, +80 ms delay, 40 ms stagger | container morphs first, always |
| press | `scaleEffect 0.97`, `easeOut 0.14` | the interface must feel heard |

- Springs, not durations, for state changes: a spring keeps its velocity when
  interrupted. Interruptibility is the entire point.
- All four dimensions (width, height, both radii) travel as **one**
  `VectorArithmetic` value, so they cannot desynchronise mid-morph.
- Pure black, no shadow, no material. Liquid Glass is reserved for surfaces
  that float clearly below the bezel — never for the part extending the notch.
- **The panel pins its appearance to dark.** It is always black, but it inherits
  the system appearance, so in Light mode every system-drawn detail inside it —
  text-field placeholders, selection highlights, menus — was being painted for a
  light background and disappearing. Pinning fixes the whole class at once.
- Two concave corners flaring out of the screen's top edge, two convex corners
  at the bottom, radii growing with size.
- A transient 3 pt blur bridges content crossfades: without it the eye sees
  two objects overlapping, with it one thing transforming.
- **Reduce Motion means fewer and gentler, not none.** Opacity and colour
  transitions stay — they aid comprehension. What goes is physics and
  displacement: springs become a short 80 ms ease, and the row cascade stops
  moving anything. Read live, and re-read when the system setting changes.
- **The panel window never resizes.** It is created once at maximum size; only
  the shape inside animates. Resizing a window at 120 Hz puts the window
  server on the critical path.
- Countdown text updates at 1 Hz. 120 Hz is for transitions, not for time.

### Being findable at all

Islet has no Dock icon and no status item, and its menu bar only exists while it
is the active app. Three things followed from that, and the third was serious:

- **Nothing said the panel could be opened.** Peek now carries a sheet
  **grabber** at its bottom edge — the established sign for "there is more
  below". It appears only once you are already hovering, so it is never permanent
  clutter.
- **And it drags.** A grabber is the vocabulary of a sheet you pull; drawing one
  on something that only answers clicks is an affordance that lies. Dragging down
  from Peek opens the panel *under the pointer* — no animation while your hand is
  on it, because the panel is at your pointer rather than springing towards it.
  Release settles it with a spring from wherever it actually is, so the gesture
  is interruptible by construction. A flick past 0.25 pt/ms decides by direction
  whatever distance it covered; a slow release goes to whichever end is nearer;
  overdragging at either end resists rather than stopping dead. Dragging up from
  Expanded closes it the same way.

  This cost almost nothing to build, and only because the silhouette was always
  **one `VectorArithmetic` value**: a half-open panel is `peek + (expanded - peek)
  × progress`, a coherent shape rather than four numbers guessed separately.

  Two things only a screenshot of a half-open panel could reveal: the incoming
  layer's blur has to **track the crossfade** (held constant, it snapped sharp on
  release — the very pop the blur exists to prevent), and the grabber has to hide
  the moment the drag starts, because Peek keeps its own height while the
  silhouette grows past it and leaves the grabber marooned mid-panel.
- **⌘, worked from day one and was written nowhere.** A quiet gear sits at the
  panel's top-right, and both empty states name the shortcut.
- **There was no way to quit.** Not a discoverability problem — an actual dead
  end, escapable only with `pkill`. Right-clicking the silhouette now opens
  Tasks, Settings and Quit. The macOS idiom, and it costs no pixels.

Layout note learned twice over: **never infer a height from what happens to be
proposed.** Every state's layer lives in the same `ZStack`, so its natural height
is set by the tallest — Expanded, present even when invisible. A
`maxHeight: .infinity` inside it put the grabber hundreds of points below the
silhouette, where `clipped()` erased it entirely.

### Expanded panel layout

Five things were wrong with the first pass, and each has a rule behind it:

- **A flat 12 pt rhythm groups nothing.** Three levels only — 4 pt inside a group,
  14 pt after a section header, 18 pt between groups. "Loop 1 of 4" belongs to
  the timer, not equidistant between the timer and the buttons.
- **One focal point.** A 44 pt empty ring beside a large number gave two. The
  ring shrank to 34 pt and became the number's satellite.
- **The section header carries the segment.** "FOCUS" above and "Focus" below
  said the same thing twice, and when a break was running the header was simply
  lying. One word, in the place a section name belongs, doing both jobs.
- **Buttons need a hierarchy.** Three identical grey pills tell you nothing about
  which one you want. Pause is filled and semibold; Skip is quieter; **Stop has
  no fill at all** until you reach for it, and turns a muted terracotta on hover —
  it should never look like an offer.
- **The columns are not half and half.** Task chips need ~265 pt, the timer ~175.
  Splitting equally was a reflex.

### The keyboard exception

⌥Space opens the quick-add **instantly, end to end** — no morph, and no fade or
cascade for the contents either. Making only the silhouette skip its spring was
not enough: the panel snapped open while the field, the chips and the rows faded
in behind it, which is the same wait the rule exists to remove, just moved
somewhere less obvious. Every layer and every staggered row takes a `nil`
animation while the panel is keyboard-presented. The same panel opened with the
mouse animates fully. An action repeated dozens of
times a day must not be animated; Raycast's lack of an open animation is a
craft decision, not an omission. Same destination, two treatments.

A panel summoned this way needs its own dismissal rules, because the pointer was
never near it and the usual exit-plus-grace rule has nothing to work with:

1. ⌥Space opens it, expanded.
2. It **stays** open — no grace timer can close it.
3. The **first time the pointer enters**, the pointer takes over: from then on
   leaving collapses it like any other hover. No second rule to learn.
4. **Escape** closes it as long as the pointer never touched it. ⌥Space again
   also toggles it shut.

Step 4 forces a trade: keyboard input only reaches an app that is **active**.
The alternatives were a global key monitor (Accessibility permission — ruled out)
or a global Carbon hotkey on Escape (which would confiscate Escape system-wide
while the panel sits open). So ⌥Space **activates Islet** and hands focus back to
the previous app on the way out, the way Raycast does — and the milestone 4 text
field needs this anyway. This is the one place the "never steal focus" rule from
Q33 is deliberately broken: there, the user was clicking a glyph mid-work; here,
they pressed a hotkey to type.

## Tasks

- Category is an **attribute**, not three separate lists. Triage is the method,
  so a task must be able to move.
- *Defer*: optional date. *Delegate*: optional free-text recipient — a note to
  self, not a formal assignment.
- No *delete* category. Eisenhower's fourth D is a decision worth recording
  only where arbitration must be justified; here it is an action.
- Checked stays visible and struck through until the evening recap, then
  auto-archives. Archive purges after 30 days. No "abandoned" state.
- Delete is immediate but undoable: ⌘Z in the window, and a 4 s "Undo" in the
  notch where the row was — the gap contracts when the delay expires.
- Capture has no friction: default *To do*, Return enqueues and keeps the field
  open, Escape closes. No prefix parsing.
- **The expanded panel is sized to its content**, not fixed. A fixed 380 pt left
  it visibly half empty with a handful of tasks. Sizing to content removes the
  void and buys a motion moment for free — the island grows as you add to it.
  The floor (230 pt) is set by the timer column; past the ceiling the list
  scrolls, because a panel taller than that stops reading as a notch. Row height
  is quantised, so a partial row can never be drawn — the panel height and the
  list height come from the same function, and a test holds them together.
- **⌘-digit is for what you are looking at; Tab is for what you are composing.**
  ⌘1/2/3 filters the list and ⌘0 shows everything — that is what ⌘-digit means
  everywhere else on this platform, so using it to *classify* would be borrowing
  the wrong verb. Tab and ⇧Tab cycle the category of the task being typed; Tab
  lives inside the field's own flow. Changing the filter also seeds the pending
  category: if you are reading your deferred tasks and you type something, you
  almost certainly mean a deferred task.
- **Digits are matched by key code, letters by character.** On a French layout
  the key printed "1" produces `&` unshifted, so `characters == "1"` can never
  fire — the *position* of a printed digit is what is stable across Latin
  layouts. Letters are the opposite: the key printed "Z" sits at the QWERTY-W
  position there, so ⌘Z has to follow the character. Shipped wrong once, and
  ⌘1/2/3 silently did nothing on the author's own keyboard.
- **⌘1/2/3 and Tab *choose* the category; Return commits.** Selecting and
  committing in one keystroke means never seeing what you picked. The choice is
  shown as a tinted pill inside the field, and the chips carry numbered badges —
  a shortcut nobody sees is a shortcut nobody uses.
- The pending category survives a commit: entering three deferred tasks in a row
  must not mean choosing "Defer" three times.
- **Display order: open tasks first, checked ones sunk to the bottom**, newest
  first within each group. Sorting the *view* only — undo restores by index into
  stored order, which therefore has to stay put.
- **One muted colour per category** — To do **cyan**, Defer **amber**, Delegate
  **magenta** — so the "All" view needs no words.

  **Lab ΔE was the wrong yardstick.** It describes two large patches; these are
  5 pt marks, sometimes at 55 % opacity, where hue discrimination collapses and
  lightness carries. A palette measuring a comfortable ΔE 58 still looked wrong,
  because it sat at L* 74 / 76 / 69 — three marks of effectively identical
  brightness. Lightness is now spread deliberately: **L\* 86 / 73 / 59**.

  **The palette is simulated under colour vision deficiency**, and scored on its
  weakest pair across normal, deuteran, protan and tritan vision. That is not a
  formality: a plum measuring a healthy ΔE 59 to a normal eye collapsed to
  **ΔE 19** under deuteranopia — which is exactly what a colour-blind reader
  reported, unprompted. Delegate is now an azure blue holding **ΔE 64 at its
  worst across all four**, at 5.8:1 contrast on black. A deeper blue scored 74
  and was passed over for sitting exactly on the 4.5:1 AA floor.

  **And colour is no longer the only channel.** Each row carries the category's
  silhouette — a filled disc, a hollow clock, a person — so the category survives
  small sizes, low opacity and colour blindness alike, and the colour reinforces
  rather than states. Redundant encoding beats a better palette.

  A pure red/green/blue triad measures best of all and was rejected on judgement:
  saturated primaries on a black bezel read as a toy, red already means
  *destructive* here, and green sits beside the short-break mint. The measurement
  is a floor to clear, never the designer.
- Deleting is reachable two ways on purpose: **swipe for when you know it, a
  hover trash button for when you don't.**
- **A target is a slot, not the ink in it.** The trash started as a 10 pt glyph,
  which is a 10 pt target — miss it by two points and the row tap underneath
  checked the task instead. It is now a 28 pt-wide slot filling the row's height,
  with a faint background while the pointer is on it so you can see you have it.
  It is also *always* in the hierarchy rather than inserted on hover: a button
  that only exists once hover has registered is not there yet if you arrive and
  click in the same instant.
- The trash cannot be given an explicit height: the **28 pt row pitch is what the
  panel's height is calculated from**, so it fills the row instead of growing it.
- In the notch: click a row to check (strike-through propagates via a mask),
  swipe left to delete (velocity **and** distance thresholds, damping past the
  limit), ⌫ deletes the hovered row for external-mouse days.

## Pomodoro

- A session is a **planned block**: 4 loops, work 25 / short 5 / long 15, all
  configurable. The long break **replaces** the fourth short one, so a session
  runs 2 h 10 and ends on the long break.
- Fully automatic between segments. Pause any time, work or break — pause just
  freezes the clock, with no penalty logic.
- Every segment transition triggers a brief self-closing announcement (≈2.5 s),
  never in full screen. Ring hue differs per segment.
- The session ends and **asks** whether to start another. "Chain
  automatically" exists in settings and is off by default.
- Only a segment run to zero counts. The loop counter resets at the day
  boundary — the same boundary as the recap.
- Auto-stop after 30 minutes with no keyboard or mouse activity.
- Pause, skip **and stop** are all reachable from Peek. There is no room for a
  fourth control beside the clock in 96 pt, so the stop takes the clock's place
  while the pointer is on the timer half: the time is one state away in Live, and
  it is not what you are looking at when your hand is on the controls.
- State is an **absolute end date**, never a countdown, so sleep and wake
  recompute correctly.
- Two things make a 1 Hz countdown look broken, and both had to be fixed:
  - **App Nap.** Islet is an accessory app that is never frontmost, so macOS
    throttles and coalesces its timers — the countdown skipped two or three
    seconds at a time. `ProcessInfo.beginActivity(.userInitiatedAllowingIdle`
    `SystemSleep)` holds it off while a session runs, without keeping the Mac
    awake. Wake-ups also pass `tolerance: .zero`.
  - **Tick phase.** The display shows `ceil(remaining)`, and a segment's end
    date sits at an arbitrary fraction of a second. Ticking on whole wall-clock
    seconds crosses that boundary mid-tick, which reads as a stutter. Ticks are
    aligned to *when the displayed value changes*, not to the wall clock. Lid closed: the timer keeps running, the UI goes quiet,
  the end arrives as a system notification.
- The notch **is** the notification. System notifications are the fallback only
  when the built-in display is unavailable.
- **Four sounds**: one for work ending, a *different* one for the break ending,
  `pop` when a task is deleted, and `ping-bing` when a session completes. The two
  transitions do not share a sound on purpose — a transition makes a noise
  precisely because you are not looking, so one sound saying "something changed"
  is worth much less than two saying **which way**. Levels are matched by
  measured RMS, not by peak and not by ear. Checking,
  adding, opening the panel and switching filters are **deliberately silent**:
  they happen tens of times a day, and the frequency rule binds audio more
  tightly than motion, because a sound cannot be ignored peripherally. Start and
  pause are silent because they are *opposites* — one sound for both says
  nothing, and the visual feedback is already unambiguous. So is stopping a
  session by hand: you just clicked Stop and watched it stop. Repeats inside
  120 ms collapse, so three fast deletions confirm three times instead of
  rattling.
- **A chime at every segment transition, on by default, with a
  switch in settings.** Not a nicety: on the built-in display the announcement is
  purely visual, so without a sound a segment ending while you look away tells
  you nothing at all.
- Originally this was "under Do Not Disturb the visual plays, the sound does
  not". **Reversed:** there is no reliable public way to read whether a Focus
  mode is on, and the alternatives were a fragile system-plist read or a rule
  that silently fails. A switch the user can see is worth more than a guess.
- Session history is recorded for every segment that ran **to zero** — a skip is
  not work that happened. Kept 30 days, the same window as the task archive.
  Today's tally rides along with the loop line, because recorded data that is
  never shown is data nobody trusts.

## The two halves talk

A Pomodoro can run **on** a task, optionally — a global session with no task is
equally valid. Checking, deleting or switching the active task never stops the
session; it simply becomes global. No "here's the next one" conveyor.

## The evening recap

- Configurable hour, 18:00 by default. The notch goes `live` with a badge that
  pulses once, and expands **only on hover**. Ignored for 30 minutes, it drops
  back and retries tomorrow. Never during a full-screen app or a Focus mode.
- Card-by-card triage, one task at a time: done / tomorrow / defer / delegate /
  delete. Triage is the ritual, not reading.
- Ignored means nothing is lost: everything rolls to tomorrow.
- Reminders are **degressive**: a dated *defer* returns to *To do* at the app's
  first wake on the day (never at midnight — a state change you cannot see does
  not count). An undated *defer* returns every 7 days. A *delegate* shows for
  three evenings, then weekly.

## Surfaces

- One window: the list, with category filters at the top. Plus the standard
  `Settings` scene (⌘,) for durations, hotkey, recap hour, JSON export.
- No history tab in v1. The archive exists in the data, not the UI.
- The window opens by itself **only on the very first launch**, with an empty
  state that says three things: the hotkey, the notch hover, nothing else.
- Interface in English. *To do / Defer / Delegate* carry their meaning
  worldwide; localisation is cheap to add later and expensive to maintain now.

## Permissions and the menu bar

- Hover detection uses a global **mouse-moved** monitor, which needs no
  Accessibility permission. Only keyboard monitors do — which is why ⌥Space
  will use `RegisterEventHotKey` instead. Islet must never open with a
  permission prompt.
- **Click-through is `ignoresMouseEvents`, and nothing else.** The panel window
  is fixed at the largest state (800 × 440 pt) so it never has to resize during
  an animation — but it draws only 292 × 40 pt at rest, so **97 % of it must be
  transparent to the mouse** or it swallows every click aimed at the top third
  of the screen.

  Returning `nil` from `hitTest` does **not** achieve this. `hitTest` only
  routes *within* a window that has already been handed the event; a `nil`
  result means the click is discarded, not forwarded. This was shipped wrong
  once, and it made browser tabs unclickable.

  The rule: the window is `ignoresMouseEvents = true` by default, and becomes
  interactive **only while the pointer is inside the current silhouette**. Hover
  is detected by a global monitor, which keeps working precisely because the
  window is ignoring events. Surgical `hitTest` stays on top of that, to stop
  our own views claiming clicks inside the black.

  Correctness there must not depend on event delivery: while the panel *is*
  interactive, mouse-moved events go to us and the global monitor goes quiet, so
  a 20 Hz poll watches for the pointer leaving. It runs only while the user is
  already interacting.

- **The first click has to do the thing.** Islet is never the active app when
  you reach for it, so *every* click on it is a first click — and by default
  AppKit spends a first click on transferring key status instead of delivering
  it. That is the "click twice to do anything" bug. Two fixes together:
  `becomesKeyOnlyIfNeeded` so ordinary clicks do not seize the keyboard at all,
  and `acceptsFirstMouse` returning true on the container *and* on an
  `NSHostingView` subclass — AppKit asks whichever view `hitTest` returned, and
  `NSHostingView` says no by default.

- In `peek` and `expanded` the panel takes the whole silhouette — the menu bar
  is sacrificed during interaction only, and the panel goes inert the instant a
  menu opens. The menu bar is sovereign; Islet is the guest.
- The 28 pt overhang can overlap a long menu bar (Xcode) or many status items.
  Accepted: detecting menu width needs the Accessibility API, and that trade is
  not worth 28 pt.
- Non-activating panel: clicking a glyph must never steal focus from what you
  are typing in.
- Notification permission is requested at the **first completed segment**, never
  at launch. (Originally specified as the first completed *session*, but a
  session is 2 h 10 — far too long to wait for a permission whose whole purpose
  is the lid-closed fallback.) Login item is offered at the **third** launch.

## Storage

JSON `Codable` behind a `TaskStore` / `SessionStore` protocol — not SwiftData.
Not for simplicity: with a hand-written `@Observable` store, the code controls
to the millisecond *when* state changes, and therefore when springs fire.
`@Query` refreshes when it decides, and an animation firing at a moment you did
not choose is exactly the defect being eliminated. Migrating to SwiftData later
is a separate exercise the protocol keeps cheap.

Session history is persisted (it feeds "4 Pomodoros today"), with no stats UI
in v1. Manual JSON export/import in settings.

Two things learned while building it:

- **Dates are rounded to the second when they are created.** ISO8601 on disk has
  no sub-second part, so storing full precision means a save/load round trip is
  silently lossy and `Date` equality stops holding. Rather than build machinery
  to preserve a precision a to-do list has no use for, don't create it.
- **Never block the main thread waiting for a `@MainActor` flush.** On quit, a
  semaphore or `DispatchGroup.wait` deadlocks — the flush needs the actor the
  blocked thread is holding. Spin the run loop instead.
- **Loading merges, it does not assign.** ⌥Space works from launch while loading
  is async, so overwriting `list` with what came off disk would silently destroy
  anything typed in between. Rare, and unforgivable in a capture tool.

The type is `IsletSettings`, not `Settings`: SwiftUI owns that name for its
scene type, and the collision is invisible until it isn't.

## Architecture

- One Xcode-free SwiftPM package for now: `IsletCore` (models, state machine,
  motion tokens — testable without a UI) and the `Islet` executable.
- `@Observable`, one root `AppState`. Named state machine with explicit
  transitions, never scattered `isHovering` / `isExpanded` booleans.
- Swift 6, everything `@MainActor` except the persistence actor.
- **`MainActor.assumeIsolated` asserts, it does not hop.** Framework callbacks
  that arrive on their own queue — `UNUserNotificationCenter` is one — must use
  `Task { @MainActor in }`. Reserve `assumeIsolated` for callbacks already known
  to be on the main run loop: Carbon hot keys, `NSEvent` monitors.
- Unit tests on the state machine only. It is pure, so they are free. No UI
  tests.

## How motion gets verified

- A permanent **×5 slow-motion** multiplier in debug, cycled with ⌥-click. At
  ×5 every mistake is glaring: content arriving before the shape finishes,
  a radius jumping, a collapse replaying the expansion backwards instead of
  resuming from current velocity.
- 120 fps QuickTime captures for frame-by-frame study of key moments.
- Side-by-side with a real iPhone Dynamic Island **once**, at the start, to
  calibrate the eye before writing anything.
- Review the next day with fresh eyes.

## Milestones

1. **Geometric spike** — panel above the menu bar, the silhouette with concave
   corners, morphing between the states, global hover detection, surgical hit
   testing. Zero features. *If this fails there is no project.*
2. **State machine + ×5 slow motion** — the five states, interruptible, with
   the spring vocabulary. Still zero features.
3. **Pomodoro** — absolute end date, auto-advance, segment announcement, ring.
4. **Tasks** — JSON store, instant ⌥Space quick-add, the three categories,
   gesture check/delete, the list window.
5. **Evening recap** — card triage, task↔timer coupling, degressive reminders.

Milestones 1 and 2 land before any feature. Retro-fitting the notch junction
and interruptibility is not possible; they shape the view hierarchy.

## Explicitly out of scope for v1

iCloud sync · iOS app or widget · statistics and charts · sub-tasks · tags ·
due dates on *To do* · recurrence · Reminders/Calendar integration · themes ·
multi-display support · drag and drop · Shortcuts/AppleScript · menu bar item.
