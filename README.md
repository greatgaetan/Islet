# Islet

A to-do list and a Pomodoro timer that live around the notch of your MacBook —
or hang from the top edge of any Mac that hasn't got one.

Left of the notch: three categories — **To do**, **Defer**, **Delegate**. Right
of the notch: a Pomodoro session. Hover to reach the controls, click to open the
whole panel.

The point of Islet is not the feature list. It is that the motion feels like it
came with the machine. Read [DESIGN.md](DESIGN.md) for every decision behind
that, including the ones that were rejected.

## Status

**All five milestones are in.** The silhouette and its motion, the Pomodoro, the
tasks, the app bundle with its hotkey and sounds — and now the evening review and
the coupling between the two halves.

## Install

```sh
./Scripts/make-icon.sh    # once — generates Resources/Islet.icns
./Scripts/build-app.sh    # release build, bundle, code-sign
open build/Islet.app
```

Copy `build/Islet.app` to `/Applications` to keep it. The bundle is not
cosmetic: notifications and the login item both need a bundle identifier and
are inert without one.

```sh
ISLET_LOGIN_ITEM=on  open build/Islet.app   # start with your Mac
ISLET_LOGIN_ITEM=off open build/Islet.app
```

(Or use the toggle in Settings, ⌘,. From the third launch, the list window
offers it once and then stops asking.)

Data lives in `~/Library/Application Support/Islet/` as plain, readable JSON:
`tasks.json`, `settings.json` and `history.json`. Nothing leaves your Mac.

## Requirements

- macOS 14 (Sonoma) or later — it compiles for 14 unchanged, though it has only been *run* on 26
- Any Mac. With a notch it wraps the hardware; without one it hangs from the top edge of whichever display carries the menu bar
- Xcode 26 / Swift 6.2 toolchain

## Run from source

```sh
swift run
```

Faster to iterate on, but unbundled: notifications and the login item stay
inert. Islet has no Dock icon and no menu of its own. Look at your notch — it
should be 28 pt wider on each side, with a dim `+` on the left and a dim play
glyph on the right. To quit:

```sh
pkill -f Islet
```

### What works right now

| Do this | See this |
|---|---|
| Slow the pointer onto the notch | it widens into **Peek** in 80 ms — crossing it at speed still takes 250 ms, so passing by never opens it |
| Look at the bottom edge of Peek | a grabber, saying the panel opens |
| **Drag down** from Peek | the panel opens under your pointer; flick it, or release and it settles to whichever end is nearer. Drag up from Expanded to close |
| **Right-click** the notch | Tasks, Settings, Quit — the only way to quit without `pkill` |
| Click anywhere on the black | it opens into **Expanded** |
| Click the play glyph | a real session starts — 4 loops of 25/5, ending on a 15 min long break |
| Wait for a segment to end | the notch widens on its own for 2.5 s to announce the next one, and a short chime plays |
| Watch the ring | hue per segment: white for focus, mint for a short break, blue for a long one |
| Hover the timer half while a session runs | a **stop** appears in the clock's place — pause, skip and stop without opening anything |
| Let the session finish | it asks whether to start another, and stays open until you answer |
| Walk away for 30 minutes | the session stops itself instead of counting an empty room as focus |
| Press **⌥Space** | the panel opens **instantly** — no morph, no spring — with the caret already in the field |
| Type and press **Return** | the task is captured and the field stays open for the next one |
| Press **⌘1 / ⌘2 / ⌘3**, or **⌘0** | filters the list — what you are *looking at* |
| Press **Tab** or **⇧Tab** | picks the category of the task you are *typing*, shown as a pill in the field |
| Add a task | the panel grows by exactly one row; delete one and it shrinks back |
| Press **Escape** | it closes, and focus goes back where it came from |
| Instead, move the pointer into it and out again | the pointer takes over: it collapses on exit like any hover |
| Start typing, then move the mouse over the panel | nothing closes: while there is unsent text, only the keyboard can |
| Click a task in the notch | it is checked, the strike-through grows left to right, and it sinks below the open ones |
| Hover a task | a trash button appears, and **⌫** deletes it — the swipe is for when you know it, the button for when you don't |
| Look at the row marks | a cyan disc, an amber clock, an azure person — shape *and* colour, so the **All** view needs no words and the categories survive colour blindness |
| Swipe a task left | deleted — by distance **or** by a quick flick — with a 4 s Undo where the row was |
| ⌘L | the list window, with category filters — the key is printed in the panel, beside its glyph |
| ⌘, | settings: durations, review hour, sound, export, login item |
| Open either window | the island collapses — a window is in front, so the panel has nothing left to say |
| Hover a task and press the timer glyph | the session runs **on** that task, and its title shows in the notch while it does |
| Check or delete the active task mid-session | the session carries on and simply becomes untied — finishing early is not punished |
| At 18:00 | the review opens itself. Leave it untouched for half an hour and it rolls to tomorrow — or turn off *Open it automatically* in settings and it waits on the notch as a single dot |
| Answer the review | one card at a time — **⌘1** Done, **⌘2** Tomorrow, **⌘3** Defer, **⌘4** Delegate, **⌘5** Delete, or click. Escape stops, and the rest rolls to tomorrow |
| Move the pointer away | it collapses after a 400 ms grace period |
| Close the lid and keep working on an external display | the timer keeps running; segment ends arrive as system notifications |
| Send a window full screen | Islet retracts into the bezel, and returns when you touch the top edge |
| Click anywhere black that isn't a glyph, at rest | the click falls through — your menu bar still works |

### Debug

`⌥`-click Islet to cycle slow motion ×1 → ×2 → ×5. Watch a transition at ×5 and
the mistakes become obvious: content arriving before the shape has finished
growing, a corner radius jumping, a collapse replaying the expansion backwards
instead of resuming from its current velocity.

```sh
ISLET_SLOWMO=5 swift run       # start slowed down
ISLET_NO_NOTCH=1 swift run     # pretend the hardware has none, to see the pill rendering
ISLET_FAST=1 swift run         # a whole session in 26s, so transitions can be watched
ISLET_AUTOSTART=1 swift run    # start a session at launch, without clicking
ISLET_TICK_LOG=1 swift run     # print every tick with its timestamp
ISLET_QUICKADD=1 swift run     # exercise the ⌥Space path without a keystroke
ISLET_KEY_LOG=1 swift run      # print every keystroke with its key code
ISLET_SOUND_LOG=1 swift run    # print each sound as it plays, and its source
ISLET_DRAG=0.5 swift run       # hold the panel half-open, to inspect the interpolated shape
ISLET_RECAP=1 swift run        # offer the review now — stops at the dot, so the real path can be walked
ISLET_RECAP=review swift run   # skip straight to the cards
ISLET_RECAP_KEYS=1 swift run   # stand in for the pointer, so the keyboard path runs headless
ISLET_SEED=1 swift run         # write three sample tasks through the real store

ISLET_FAST=1 ISLET_AUTOSTART=1 ISLET_SLOWMO=5 swift run   # the useful combination
```

## Tests

```sh
swift test
```

120 tests. The state machine, the geometry, the Pomodoro plan and every task
operation are pure, so all of them are tested. The views are not — see
[DESIGN.md](DESIGN.md).

## Layout

```
Sources/IsletCore/     models, state machine, motion tokens — no UI
  NotchState.swift     the five states and every transition between them
  NotchMetrics.swift   the silhouette as one animatable value
  Motion.swift         the spring vocabulary, in one place
  Pomodoro.swift       plan, session, absolute end date — pure and tested
  Task.swift           TaskItem and the three categories
  TaskList.swift       every task operation — pure, so all of it is tested
  Persistence.swift    JSON behind a protocol; SwiftData stays swappable-in
  Recap.swift          which tasks the evening raises, and how often — pure
Sources/Islet/         AppKit shell + SwiftUI content
  NotchShape.swift     concave corners flaring out of the screen's top edge
  NotchPanel.swift     borderless non-activating panel, surgical hit testing
  NotchScreen.swift    finds the notched display; never NSScreen.main
  PanelGeometry.swift  window and screen coordinate maths
  PomodoroModel.swift  two clocks: 1 Hz for display, precise sleep for events
  HotKey.swift         Carbon RegisterEventHotKey — no Accessibility permission
  Notifier.swift       the lid-closed fallback, never the main event
  RecapModel.swift     when the review is offered, and what answering does
  RecapCards.swift     one card, one decision, then the next
  TaskModel.swift      tasks, debounced saves, the 4 s undo window
  WindowManager.swift  the list and settings windows, built by hand
  MainMenu.swift       minimal menu — without an Edit menu, ⌘V does not work
Resources/Info.plist   LSUIElement, bundle identity
Scripts/               build-app.sh, make-icon.sh
```

## Licence

MIT — see [LICENSE](LICENSE).

The four bundled sounds in `Resources/Sounds/` are **CC0** (public domain), from
freesound.org and kenney.nl, so the whole repository is free to redistribute.
