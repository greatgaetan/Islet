#!/usr/bin/env python3
"""Trim a chime so it lands on time and carries no dead weight.

    ./Scripts/prepare-sound.py source.wav Resources/Sounds/name.wav

Two things matter more than the file format, and downloaded sounds usually get
both wrong:

* **Leading silence reads as latency.** A chime meant to coincide with a visual
  announcement that starts 30 ms late is a chime that feels disconnected from it.
* **A trailing tail is dead weight** — bytes in the repository, and a sound that
  is nominally still playing long after it is audible.

The tail is cut at a much lower threshold than the head and given a short
fade-out, because a decay below the detection threshold is still a decay, and
cutting it square produces a click.

Run `afconvert` first if the source is not already 16-bit PCM:

    afconvert -f WAVE -d LEI16@44100 in.wav out.wav
"""
import struct
import sys
import wave

HEAD_THRESHOLD = 0.02   # generous: only strip what is plainly nothing
TAIL_THRESHOLD = 0.002  # strict: a quiet decay is still part of the sound
FADE_MS = 20            # guarantees no click at the cut


def main(source: str, destination: str) -> None:
    with wave.open(source) as w:
        channels, width, rate, frames = (
            w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        )
        raw = w.readframes(frames)

    if width != 2:
        sys.exit(f"{source}: {width * 8}-bit — convert to 16-bit first (see afconvert above)")

    samples = list(struct.unpack("<%dh" % (len(raw) // 2), raw))
    mono = samples[0::channels]
    peak = max((abs(s) for s in mono), default=1) or 1

    head = next((i for i, s in enumerate(mono) if abs(s) > peak * HEAD_THRESHOLD), 0)
    tail = next(
        (i for i in range(len(mono) - 1, -1, -1) if abs(mono[i]) > peak * TAIL_THRESHOLD),
        len(mono) - 1,
    )

    trimmed = samples[head * channels:(tail + 1) * channels]

    fade = min(int(rate * FADE_MS / 1000), (tail - head) // 2)
    for i in range(fade):
        gain = i / fade
        index = len(trimmed) - (fade - i) * channels
        for c in range(channels):
            trimmed[index + c] = int(trimmed[index + c] * gain)

    with wave.open(destination, "wb") as out:
        out.setnchannels(channels)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(struct.pack("<%dh" % len(trimmed), *trimmed))

    print(
        f"{destination}: {frames / rate * 1000:.0f} ms → "
        f"{len(trimmed) // channels / rate * 1000:.0f} ms "
        f"(head {head / rate * 1000:.0f} ms, tail {(frames - 1 - tail) / rate * 1000:.0f} ms removed)"
    )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
