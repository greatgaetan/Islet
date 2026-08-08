# Sounds

Three events, three sounds, one meaning each.

| Event | Source | Frequency | Why it is allowed to make a noise |
|---|---|---|---|
| Work ended, a break begins | `work-done-back-to-break.wav` | ~4×/day | The announcement is otherwise purely visual |
| The break ended, work begins | `break-done-back-to-work.wav` | ~4×/day | Same — and a *different* sound, see below |
| A task deleted | `pop.wav` | 2–10×/day | Destructive. The sound confirms the system heard you |
| A session finished | `ping-bing.wav` | 2–3×/day | Rare, so it is allowed to be conclusive |

The two transitions have their own sounds rather than sharing one, and that is
the whole point: a transition makes a noise precisely because you are *not*
looking. One sound says something changed; two say **which way**, which is the
part you needed.

Levels are matched by measured **RMS**, not peak and not by ear — the two
transition files arrived about 10 dB hotter than the others and would have
flattened everything else at equal volume.

## Deliberately silent

Checking a task, adding one, opening the panel with ⌥Space, switching filters,
starting and pausing the timer, and **stopping a session by hand**.

The first four happen tens of times a day: the frequency rule that governs
animation governs audio more strictly, because an animation can be ignored out of
the corner of an eye and a sound cannot. Start and pause are silent for a
different reason — they are *opposites*, and one sound for both says nothing. A
pair (rising / falling) would be needed, and the visual feedback is already
unambiguous.

## Adding or replacing one

The role is the enum case in `Chime.swift`; the file name is a detail in one
table. Swapping a sound means editing that table and nothing else.

Wanted: **150–250 ms**, one timbre rather than a melody, mid-low rather than
bright, WAV/AIFF/CAF 16-bit 44.1 kHz. No leading silence — it reads as latency.
No long tail — it overlaps the next event. Loudness is trimmed in `Chime.swift`,
so a hot file needs no re-export.

Without these files Islet falls back to system sounds. That fallback is not
politeness: a missing asset would otherwise leave the app **silently mute**,
which is the one failure nobody would ever notice. `preload()` logs which source
each chime resolved to at launch, because macOS also ships a sound called *Pop* —
"it made a noise" is not proof the bundled file is being used.

## Licensing

All four files are **CC0** — a public domain dedication.

| File | Source |
|---|---|
| `work-done-back-to-break.wav` | [freesound.org](https://freesound.org) |
| `break-done-back-to-work.wav` | [freesound.org](https://freesound.org) |
| `pop.wav` | [freesound.org](https://freesound.org) or [kenney.nl](https://kenney.nl) |
| `ping-bing.wav` | [freesound.org](https://freesound.org) or [kenney.nl](https://kenney.nl) |

CC0 requires no attribution, so there is no `CREDITS.md` and nothing here
conflicts with the repository's MIT licence: anyone who clones Islet may
redistribute these files freely. This record exists so provenance is never in
doubt, not because it is owed. The last two rows name both sources because which
of the two each came from was not recorded at the time — invented precision would
be worse than none.

If you replace a file, check its licence before committing it. CC-BY needs
attribution in a root `CREDITS.md` plus a note that the audio is not under MIT;
non-commercial licences and "free with signup" stock libraries usually cannot be
redistributed in a public repository at all.
