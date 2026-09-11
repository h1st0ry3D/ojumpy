#!/usr/bin/env python3
"""Ojumpy sound cues, synthesized (stdlib only).

Each cue is a short linearly swept sine with a squared decay envelope, built
sample by sample, so the plugin ships no audio editor project and no third-party
asset — just this recipe and its output:

  step  320 -> 200 Hz, 0.06 s, 0.22   one footstep
  land  190 ->  80 Hz, 0.16 s, 0.60   landing thud
  bump  130 ->  55 Hz, 0.18 s, 0.60   player-vs-player hit (deeper, thud-like)
  orb   C6-E6-G6 bell arpeggio        touching the summit orb
  bing  G6 bell (single note)         Glyph Hunt: picked up your own colour
  jump  440 -> 880 Hz, 0.18 s, 0.50   leaving the ground

`orb` is not a sweep: it is the collectible cue (a three-note bell
a three-note bell arpeggio — 1046.5 / 1318.5 / 1568 Hz, each
note 0.14 s with a 0.04 s gap, a sine plus its octave partial at 0.3, squared
decay envelope — ported here so the two games share the reward sound.

Every cue is written once per entry of PITCH_SCALES and the game picks a variant
at random per play: a fixed pitch repeating every 0.3 s is grating.

The rendered WAVs are *committed* (`sfx/` next to this script), so a plain clone
gives a complete plugin — this is only the recipe:

  python3 -B ojumpy-sfx.py            # rewrites ./sfx

Do not run it at plugin startup: writing into the plugin folder touches the tree
the shell hot-reloads. Runtime state belongs in `~/.local/state/ojumpy/`.
"""
import argparse
import math
import os
import wave

MIX_RATE = 44100

# name -> (freq_start, freq_end, duration, volume)
CUES = {
    "step": (320.0, 200.0, 0.06, 0.22),
    "land": (190.0, 80.0, 0.16, 0.60),
    "bump": (130.0, 55.0, 0.18, 0.60),
    "jump": (440.0, 880.0, 0.18, 0.50),   # a rising 440 -> 880 blip
}

# Arpeggios: name -> (note frequencies, note duration, gap, volume). Ported from
# The collectible cue: three bell-ish notes, each with an octave partial.
ARPEGGIOS = {
    "orb": ([1046.5, 1318.5, 1568.0], 0.14, 0.04, 0.5),
    # Glyph Hunt: one bright bell for a correct grab (a single note of the
    # same recipe, so it reads as the reward family the orb cue belongs to)
    "bing": ([1568.0], 0.10, 0.0, 0.5),
}

# Scaling the sweep frequencies shifts pitch without changing the cue's length;
# resampling would scale pitch and duration together, and a 10 % length
# difference on a 60 ms blip is not worth the extra machinery.
PITCH_SCALES = (0.90, 0.95, 1.00, 1.05, 1.10)


def make_tone(freq_start, freq_end, duration, volume, pitch_scale=1.0):
    """16-bit mono PCM samples: linear sweep + squared decay envelope. The phase
    integrates the instantaneous frequency, so the sweep is clean instead of
    stepping once per sample."""
    f0 = freq_start * pitch_scale
    f1 = freq_end * pitch_scale
    samples = int(MIX_RATE * duration)
    data = bytearray(samples * 2)
    for i in range(samples):
        t = i / MIX_RATE
        frac = t / duration
        # phase = TAU * (f0*t + 0.5*(f1-f0)*t^2/duration)
        phase = 2.0 * math.pi * (f0 * t + 0.5 * (f1 - f0) * t * t / duration)
        env = (1.0 - frac) ** 2
        value = int(max(-1.0, min(1.0, math.sin(phase) * volume * env)) * 32767.0)
        data[i * 2] = value & 0xFF
        data[i * 2 + 1] = (value >> 8) & 0xFF
    return bytes(data)


def make_arpeggio(notes, note_dur, gap, volume, pitch_scale=1.0):
    """Bell-ish arpeggio: each note is a sine plus its octave partial at 0.3 under
    a squared decay envelope, notes spaced note_dur + gap apart."""
    step = note_dur + gap
    total = step * len(notes)
    samples = int(MIX_RATE * total)
    data = bytearray(samples * 2)
    for n, f0 in enumerate(notes):
        f0 = f0 * pitch_scale
        start = int(MIX_RATE * n * step)
        end = int(MIX_RATE * (n * step + note_dur))
        for i in range(start, min(end, samples)):
            t = (i - start) / MIX_RATE
            frac = t / note_dur
            env = (1.0 - frac) ** 2
            sample = (math.sin(2.0 * math.pi * f0 * t)
                      + 0.3 * math.sin(2.0 * math.pi * f0 * 2.0 * t)) * volume * env
            value = int(max(-1.0, min(1.0, sample)) * 32767.0)
            data[i * 2] = value & 0xFF
            data[i * 2 + 1] = (value >> 8) & 0xFF
    return bytes(data)


def write_wav(path, pcm):
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(MIX_RATE)
        wav.writeframes(pcm)


def main():
    ap = argparse.ArgumentParser(description="render Ojumpy's sound effects")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "sfx"),
                    help="directory for the generated WAVs (default: ./sfx in the plugin)")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    for name, (f0, f1, duration, volume) in CUES.items():
        for i, scale in enumerate(PITCH_SCALES):
            pcm = make_tone(f0, f1, duration, volume, scale)
            write_wav(os.path.join(args.out, "%s-%d.wav" % (name, i)), pcm)
    for name, (notes, note_dur, gap, volume) in ARPEGGIOS.items():
        for i, scale in enumerate(PITCH_SCALES):
            pcm = make_arpeggio(notes, note_dur, gap, volume, scale)
            write_wav(os.path.join(args.out, "%s-%d.wav" % (name, i)), pcm)


if __name__ == "__main__":
    main()
