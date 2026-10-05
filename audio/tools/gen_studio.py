#!/usr/bin/env python3
"""The home studio's instruments, picked up and played a little: a strum on
the Gibson Dove, a few clean chords on the Telecaster (unplugged, or through
the little practice amp), and a bass line on the Jazz Bass. Variants so a
player strumming twice doesn't hear the same take. Writes audio/home/.

    python3 audio/tools/gen_studio.py

FluidSynth with FluidR3_GM (as the music), then a small bedroom's reverb.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import music_core as mc  # noqa: E402
import sfxlib as S  # noqa: E402
from music_core import Song  # noqa: E402

OUT = "home"
STEEL, CLEAN, MUTED, FINGER_BASS = 25, 27, 28, 33

# Open chords as six strings low to high (None = not played).
SHAPES = {
    "G": ["g2", "b2", "d3", "g3", "b3", "g4"],
    "Cadd9": [None, "c3", "e3", "g3", "d4", "g4"],
    "Dsus4": [None, None, "d3", "a3", "d4", "g4"],
    "Em7": ["e2", "b2", "e3", "g3", "d4", "g4"],
    "Am7": [None, "a2", "e3", "g3", "c4", "e4"],
    "D": [None, None, "d3", "a3", "d4", "f#4"],
    "A": [None, "a2", "e3", "a3", "c#4", "e4"],
    "E": ["e2", "b2", "e3", "g#3", "b3", "e4"],
}


def _strings(shape, up=False):
    notes = [mc.midi(n) for n in SHAPES[shape] if n]
    return notes[::-1] if up else notes


def _room(x, size=0.35, wet=0.12, seed=5):
    y = S.reverb(x, size_s=size, damp_hz=5000, wet=wet, predelay_s=0.004, seed=seed)
    return y.mean(axis=1) if y.ndim == 2 else y


def _render(song, length, gain=0.5):
    stems = mc.render(song, gain=gain)
    x = sum(stems.values()).mean(axis=1)
    # the render starts with a little pre-roll: start on the first note
    on = np.flatnonzero(np.abs(x) > 1e-4)
    x = x[max(0, on[0] - S.secs(0.01)):] if len(on) else x
    return x[: S.secs(length)]


def dove_strum(v):
    """A few bars on the Dove, strummed with a pick: a down-down-up pattern
    and a ringing last chord. Big, warm, a little boomy (a dreadnought)."""
    progs = [["G", "Cadd9", "G"], ["Em7", "Cadd9", "Dsus4"], ["G", "D", "Em7"]]
    s = Song(f"home_studio_dove_strum_{v + 1:02d}", bpm=92 + 4 * v, seed=8100 + v)
    g = s.part("dove", STEEL, "gtr", vol=110, ht=0.006, hv=8)
    beat = 0.0
    for k, ch in enumerate(progs[v]):
        last = k == len(progs[v]) - 1
        pattern = [(0, False, 92), (1, False, 80), (1.5, True, 64), (2.5, True, 60), (3, False, 84), (3.5, True, 66)]
        for at, up, vel in ([(0, False, 96)] if last else pattern):
            g.chord(beat + at, _strings(ch, up), 3.5 if last else 0.9, vel, strum=0.06 if not up else 0.035)
        beat += 4
    x = _render(s, beat * 60 / s.bpm - 3.0 + 4.0)
    x = S.hp(x, 70)
    return S.fade(_room(x, 0.4, 0.14, 8100 + v), 0.002, 1.0)


def tele_chords(v):
    """The Telecaster through the little practice amp, clean: a few bright
    chord stabs and a twangy lick, the amp's hum underneath."""
    s = Song(f"home_studio_tele_{v + 1:02d}", bpm=104 + 6 * v, seed=8200 + v)
    g = s.part("tele", CLEAN, "gtr", vol=110, ht=0.004, hv=6)
    figs = [
        (["A", "D", "E"], "e4/.5 g4/.5 a4/1 r/2"),
        (["E", "A", "E"], "b4/.5 a4/.5 g#4/.5 e4/1.5 r/1"),
        (["D", "G", "A"], "f#4/.5 a4/.5 d5/2 r/1"),
    ]
    chords, lick = figs[v]
    beat = 0.0
    for ch in chords:
        for at in (0, 1.5, 2.5):
            g.chord(beat + at, _strings(ch)[-4:], 0.45, 88, strum=0.02)
        beat += 4
    g.melody(int(beat / 4), lick, vel=94)
    x = _render(s, (beat + 4) * 60 / s.bpm + 1.0)
    # a small open-backed amp: no deep lows, a bit of honk, a little hum
    x = S.bp(x, 110, 6000)
    t = S.t_axis(len(x))
    hum = 0.004 * (np.sin(2 * np.pi * 50 * t) + 0.5 * np.sin(2 * np.pi * 100 * t))
    x = np.tanh(1.6 * x / (np.abs(x).max() + 1e-9)) + hum
    return S.fade(_room(x, 0.3, 0.12, 8200 + v), 0.05, 0.6)


def jbass_line(v):
    """A walking bass line on the Jazz Bass through the practice amp."""
    s = Song(f"home_studio_jbass_{v + 1:02d}", bpm=96 + 5 * v, seed=8300 + v)
    b = s.part("jbass", FINGER_BASS, "bass", vol=115, ht=0.006, hv=6)
    lines = [
        "e2/1 g2/1 a2/1 b2/1 | d3/1 b2/1 a2/1 g2/1 | e2/3 r/1",
        "a1/1 c#2/1 e2/1 f#2/1 | a2/1 f#2/1 e2/1 c#2/1 | a1/3 r/1",
        "d2/.5 d2/.5 f#2/1 a2/1 c3/1 | b2/1 a2/1 f#2/1 e2/1 | d2/3 r/1",
    ]
    b.melody(0, lines[v], vel=96)
    x = _render(s, 12 * 60 / s.bpm + 2.0)
    x = S.lp(S.hp(x, 40), 3500)
    return S.fade(_room(x, 0.3, 0.08, 8300 + v), 0.01, 0.6)


def _trim(x, floor_db=-60.0):
    """Drop the silence after the last ring dies away."""
    loud = np.flatnonzero(np.abs(x) > np.abs(x).max() * 10 ** (floor_db / 20))
    return S.fade(x[: loud[-1] + S.secs(0.05)], fout=0.05) if len(loud) else x


def main(argv=()):
    for v in range(3):
        for name, fn in (("dove_strum", dove_strum), ("tele", tele_chords), ("jbass", jbass_line)):
            S.save(f"{OUT}/home_studio_{name}_{v + 1:02d}", _trim(fn(v)), "peak", quality=3, rate=32000)


if __name__ == "__main__":
    main(sys.argv[1:])
