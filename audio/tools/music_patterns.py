"""Accompaniment patterns: comping, bass lines, arpeggios and drums.

Every function writes notes into a Part over a bar range, following the
song's chord timeline. Randomness comes from song.rng (seeded per song).
"""
from __future__ import annotations

import numpy as np

from music_core import Chord, nearest, voicing

# GM drum keys
KICK, KICK2, STICK, SNARE, CLAP, ESNARE = 36, 35, 37, 38, 39, 40
BR_TAP, BR_SLAP, BR_SWIRL = 38, 39, 40
HH, PEDAL, OHH, CRASH, RIDE, BELL = 42, 44, 46, 49, 51, 53
TAMB, COWBELL, BONGO_H, BONGO_L = 54, 56, 60, 61
CONGA_M, CONGA_O, CONGA_L = 62, 63, 64
CABASA, MARACA, CLAVES, SHAKER = 69, 70, 75, 82
TOM_LO, TOM_MID, TOM_HI = 45, 47, 50
TRI_MUTE, TRI_OPEN = 80, 81


def _bass_pitch(pc, prev, lo=28, hi=45):
    target = prev if prev is not None else 36
    return nearest(pc, target, lo, hi)


# --------------------------------------------------------------------------
# Harmony parts
# --------------------------------------------------------------------------

def pad(p, s, bar0, bar1, lo=55, hi=74, n=4, vel=60, retrig=None, root=False,
        gap=0.02, strum=0.0, swell=False):
    """Sustained chords with smooth voice leading."""
    prev = None
    for b, d, ch in s.segs(bar0, bar1):
        v = voicing(ch, lo, hi, n, prev, root=root)
        prev = v
        step = retrig or d
        t = b
        while t < b + d - 1e-6:
            dd = min(step, b + d - t)
            p.chord(t, v, dd - gap, vel, strum)
            t += step
    if swell:
        p.ramp(bar0 * s.bpb, bar1 * s.bpb, 11, 70, 127, 1.0)


def organ_comp(p, s, bar0, bar1, lo=55, hi=74, n=4, vel=55, style="hold"):
    """Lounge organ: held chords with occasional re-attack and push."""
    prev = None
    r = s.rng
    for b, d, ch in s.segs(bar0, bar1):
        v = voicing(ch, lo, hi, n, prev)
        prev = v
        if style == "hold" or d < 2:
            p.chord(b, v, d - 0.05, vel)
        elif style == "push":
            # stab on 1, held from the "and" of 2
            p.chord(b, v, 0.9, vel + 4)
            p.chord(b + 1.5, v, d - 1.55, vel - 4)
        elif style == "stabs":
            for off in (0, 1.5, 2.5) if d >= 4 else (0,):
                if off < d:
                    p.chord(b + off, v, 0.35, vel + (6 if off == 0 else 0))
        if r.random() < 0.15 and d >= 4:
            p.chord(b + d - 0.5, v, 0.4, vel - 10)


def bossa_guitar(p, s, bar0, bar1, lo=52, hi=71, n=4, vel=58, thumb=False):
    """Joao Gilberto style syncopated comping (alternating bar figures)."""
    pats = [[0, 1, 1.5, 2.5, 3.5], [0.5, 1.5, 2, 3]]
    prev = None
    for bar in range(bar0, bar1):
        pat = pats[(bar - bar0) % 2]
        for off in pat:
            beat = bar * s.bpb + off
            ch = s.chord_at(beat + 0.01)
            v = voicing(ch, lo, hi, n, prev)
            prev = v
            dur = 0.42 if off % 1 else 0.6
            p.chord(beat, v, dur, vel + (6 if off == 0 else 0), strum=0.008)
        if thumb:
            ch = s.chord_at(bar * s.bpb)
            p.note(bar * s.bpb, nearest(ch.bass, 43, 40, 52), 1.4, vel)
            p.note(bar * s.bpb + 2, nearest(ch.fifth_pc(), 45, 40, 54), 1.4, vel - 6)


def strum_waltz(p, s, bar0, bar1, lo=55, hi=74, n=4, vel=55):
    """'pah pah' on beats 2 and 3 of a 3/4 bar."""
    prev = None
    for bar in range(bar0, bar1):
        for off in (1, 2):
            beat = bar * s.bpb + off
            ch = s.chord_at(beat)
            v = voicing(ch, lo, hi, n, prev)
            prev = v
            p.chord(beat, v, 0.55, vel - (4 if off == 2 else 0), strum=0.01)


def ballad_piano(p, s, bar0, bar1, lo=48, hi=76, vel=58):
    """Broken-chord piano accompaniment: low root+fifth, then upper voicing."""
    prev = None
    r = s.rng
    for b, d, ch in s.segs(bar0, bar1):
        v = voicing(ch, 60, hi, 4, prev)
        prev = v
        bass = nearest(ch.bass, 43, 36, 50)
        p.note(b, bass, d * 0.95, vel)
        p.note(b + 0.5, bass + 7 if ch.bass == ch.root else bass + 12, d * 0.8, vel - 12)
        p.chord(b + 1.0, v, d - 1.05, vel - 6, strum=0.03)
        if d >= 4 and r.random() < 0.6:
            p.note(b + 2.5, v[r.integers(0, len(v))] + 12, 1.2, vel - 14)


def arp(p, s, bar0, bar1, lo=60, hi=84, pattern=(0, 1, 2, 3, 2, 1), step=0.5,
        vel=60, n=4, accent_every=None, gate=1.6):
    prev = None
    k = 0
    for b, d, ch in s.segs(bar0, bar1):
        v = voicing(ch, lo, hi, n, prev, root=True)
        prev = v
        t = b
        while t < b + d - 1e-6:
            idx = pattern[k % len(pattern)]
            pitch = v[idx % len(v)] + 12 * (idx // len(v))
            acc = 8 if accent_every and k % accent_every == 0 else 0
            p.note(t, pitch, step * gate, vel + acc)
            t += step
            k += 1


def tremolo_chord(p, s, bar0, bar1, lo=55, hi=79, n=3, vel=48, rate=0.125):
    """String/mandolin tremolo on chord tones."""
    prev = None
    for b, d, ch in s.segs(bar0, bar1):
        v = voicing(ch, lo, hi, n, prev)
        prev = v
        t = b
        k = 0
        while t < b + d - 1e-6:
            for x in v:
                p.note(t, x, rate * 0.9, vel + (4 if k % 2 == 0 else -2))
            t += rate
            k += 1


# --------------------------------------------------------------------------
# Bass lines
# --------------------------------------------------------------------------

def bass_bossa(p, s, bar0, bar1, vel=88, lo=28, hi=45):
    prev = None
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        segs = s.segs(bar, bar + 1)
        if len(segs) == 1:
            ch = segs[0][2]
            r = _bass_pitch(ch.bass, prev, lo, hi)
            f = nearest(ch.fifth_pc(), r + 5, lo, hi + 5)
            nxt = s.chord_at(b + s.bpb + 0.01)
            p.note(b, r, 1.45, vel)
            p.note(b + 1.5, f, 0.45, vel - 14)
            p.note(b + 2, f, 1.45, vel - 6)
            # anticipate or walk toward the next bar
            if s.rng.random() < 0.5:
                p.note(b + 3.5, nearest(nxt.bass, r, lo, hi), 0.45, vel - 8)
            else:
                p.note(b + 3.5, r, 0.45, vel - 12)
            prev = r
        else:
            for sb, sd, ch in segs:
                r = _bass_pitch(ch.bass, prev, lo, hi)
                p.note(sb, r, min(1.45, sd - 0.05), vel)
                if sd >= 2:
                    f = nearest(ch.fifth_pc(), r + 5, lo, hi + 5)
                    p.note(sb + 1.5, f, 0.45, vel - 12)
                prev = r


def bass_walk(p, s, bar0, bar1, vel=86, lo=28, hi=48):
    r = s.rng
    prev = None
    beats = [bar * s.bpb + k for bar in range(bar0, bar1) for k in range(s.bpb)]
    for k, beat in enumerate(beats):
        ch = s.chord_at(beat + 0.01)
        nxt_beat = beat + 1
        nxt = s.chord_at(nxt_beat + 0.01)
        chord_start = any(abs(b - beat) < 1e-6 for b, d, c in s.timeline)
        if chord_start or prev is None:
            pitch = _bass_pitch(ch.bass, prev, lo, hi)
        elif nxt is not ch and any(abs(b - nxt_beat) < 1e-6 for b, d, c in s.timeline):
            tgt = _bass_pitch(nxt.bass, prev, lo, hi)
            pitch = tgt + (1 if r.random() < 0.5 else -1)
            if pitch == prev:
                pitch = tgt + 2
        else:
            sc = ch.scale()
            cand = [q for q in range(prev - 5, prev + 6) if q % 12 in sc and q != prev and lo <= q <= hi]
            tones = [q for q in cand if q % 12 in ch.pcs()]
            pool = tones if (tones and r.random() < 0.6) else cand
            pitch = pool[r.integers(0, len(pool))] if pool else prev
        p.note(beat, pitch, 0.92, vel - (6 if (beat % 2) else 0))
        prev = pitch


def bass_two(p, s, bar0, bar1, vel=84, lo=28, hi=45, push=0.3):
    prev = None
    for b, d, ch in s.segs(bar0, bar1):
        rt = _bass_pitch(ch.bass, prev, lo, hi)
        prev = rt
        if d >= 4:
            p.note(b, rt, 1.9, vel)
            f = nearest(ch.fifth_pc(), rt + 5, lo, hi + 5)
            if s.rng.random() < push:
                p.note(b + 2, f, 1.4, vel - 8)
                p.note(b + 3.5, rt + 12 if rt + 12 <= hi + 7 else rt, 0.45, vel - 14)
            else:
                p.note(b + 2, f, 1.9, vel - 8)
        else:
            p.note(b, rt, d - 0.1, vel)


def bass_waltz(p, s, bar0, bar1, vel=86, lo=28, hi=45):
    prev = None
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        ch = s.chord_at(b + 0.01)
        rt = _bass_pitch(ch.bass, prev, lo, hi)
        if prev is not None and (bar - bar0) % 2 == 1 and s.chord_at(b - 1) is ch:
            rt = nearest(ch.fifth_pc(), rt, lo, hi)
        p.note(b, rt, 0.95, vel)
        prev = rt


def bass_funk(p, s, bar0, bar1, vel=90, lo=28, hi=45, variant=0):
    """16th-note library-funk line: root, octave pops, b7 and approach."""
    figs = [
        [(0, 0, 0.7), (0.75, 0, 0.2), (1.5, 12, 0.3), (2, 0, 0.5), (2.75, 7, 0.2), (3, 10, 0.3), (3.5, 12, 0.3)],
        [(0, 0, 0.45), (0.5, 0, 0.2), (0.75, 7, 0.2), (1.5, 10, 0.4), (2, 12, 0.3), (2.5, 0, 0.45), (3.25, 3, 0.2), (3.5, 5, 0.3)],
    ]
    prev = None
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        fig = figs[(bar + variant) % 2]
        for off, iv, d in fig:
            ch = s.chord_at(b + off + 0.01)
            rt = _bass_pitch(ch.bass, prev, lo, hi)
            if off == 0:
                prev = rt
            pc_iv = iv
            if iv == 3 and not ch.minor:
                pc_iv = 4
            p.note(b + off, rt + pc_iv, d, vel - (0 if off in (0, 2) else 12))


def bass_drive(p, s, bar0, bar1, vel=90, lo=28, hi=45):
    """Driving eighths: root pedal with octave and fifth leaps."""
    prev = None
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for k in range(8):
            off = k * 0.5
            ch = s.chord_at(b + off + 0.01)
            rt = _bass_pitch(ch.bass, prev, lo, hi)
            if k == 0 or abs((b + off) - next((x for x, d, c in s.timeline if abs(x - b - off) < 1e-6), -99)) < 1e-6:
                prev = rt
            pitch = rt
            if k == 3:
                pitch = rt + 12
            elif k == 6:
                pitch = nearest(ch.fifth_pc(), rt + 7, lo, hi + 12)
            elif k == 7:
                nxt = s.chord_at(b + 4.01)
                pitch = _bass_pitch(nxt.bass, rt, lo, hi) - 1 if s.rng.random() < 0.4 else rt
            p.note(b + off, pitch, 0.42, vel - (0 if k % 2 == 0 else 12))


def bass_riff(p, s, bar0, bar1, riff, vel=88, lo=28, hi=48):
    """riff = list of (beat_offset, semitones_above_root, dur) per bar."""
    prev = None
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for off, iv, d in riff:
            ch = s.chord_at(b + off + 0.01)
            rt = _bass_pitch(ch.bass, prev, lo, hi)
            if off == 0:
                prev = rt
            p.note(b + off, rt + iv, d, vel - (0 if off == 0 else 10))


def drone(p, s, bar0, bar1, pcs, lo=36, vel=50, dur_bars=4):
    for bar in range(bar0, bar1, dur_bars):
        L = min(dur_bars, bar1 - bar) * s.bpb
        for pc in pcs:
            p.note(bar * s.bpb, nearest(pc, lo + 6, lo, lo + 12), L - 0.05, vel)


# --------------------------------------------------------------------------
# Generative sparse melody (night station, fills)
# --------------------------------------------------------------------------

def sparse_melody(p, s, bar0, bar1, lo=60, hi=79, density=0.35, vel=56,
                  motif_bars=2, chord_tone_bias=0.7, durs=(1, 1.5, 2, 0.5, 3)):
    """Seeded, motif-based sparse line: a motif is generated as a rhythm and
    contour, repeated with small variations and re-fitted to each chord."""
    r = s.rng
    L = motif_bars * s.bpb
    slots = np.arange(0, L, 0.5)
    rhythm = []
    t = 0.0
    while t < L - 0.5:
        if r.random() < density:
            d = float(r.choice(durs))
            d = min(d, L - t)
            rhythm.append((t, d))
            t += d
        else:
            t += float(r.choice([0.5, 1.0]))
    contour = list(np.cumsum(r.integers(-2, 3, size=len(rhythm))))
    prev = (lo + hi) // 2
    for start in range(bar0, bar1, motif_bars):
        var = r.random()
        rh = list(rhythm)
        if var < 0.3 and rh:
            rh = rh[:-1]
        elif var < 0.5:
            rh = [(t + (0.5 if r.random() < 0.3 else 0), d) for t, d in rh]
        base = prev
        for k, (t, d) in enumerate(rh):
            beat = start * s.bpb + t
            if beat >= bar1 * s.bpb:
                break
            ch = s.chord_at(beat + 0.01)
            pcs = ch.pcs() if r.random() < chord_tone_bias else ch.scale()
            avoid = {(c + 1) % 12 for c in ch.pcs()} - set(ch.pcs())
            pcs = [q for q in pcs if q not in avoid] or ch.pcs()
            target = base + 2 * (contour[k % len(contour)] if contour else 0)
            target = min(max(target, lo), hi)
            cands = [q for q in range(lo, hi + 1) if q % 12 in pcs]
            pitch = min(cands, key=lambda q: abs(q - target) + 0.1 * r.random())
            p.note(beat, pitch, d * 0.95, vel + r.normal(0, 4))
            prev = pitch


# --------------------------------------------------------------------------
# Drums
# --------------------------------------------------------------------------

def brush_bossa(d, s, bar0, bar1, vel=60, clave=True, kick=True, swirl=True):
    cl = [0, 1.5, 3, 5, 6.5]  # 3-2 bossa clave over two bars, in beats
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        if swirl:
            for k in range(4):
                d.note(b + k, BR_SWIRL, 0.95, vel - 18)
        for k in range(8):
            # brushed eighths on the snare, accents on 2 and 4
            acc = 10 if k in (2, 6) else 0
            d.note(b + k * 0.5, BR_TAP, 0.2, vel - 22 + acc + (4 if k % 2 == 0 else 0))
        if kick:
            d.note(b, KICK, 0.3, vel - 4)
            d.note(b + 1.5, KICK, 0.2, vel - 18)
            d.note(b + 2, KICK, 0.3, vel - 8)
            d.note(b + 3.5, KICK, 0.2, vel - 18)
        if clave:
            for c in cl:
                if (bar - bar0) % 2 == int(c // 4):
                    d.note(bar * s.bpb + (c % 4), STICK, 0.2, vel - 6)
        d.note(b + 1, PEDAL, 0.2, vel - 20)
        d.note(b + 3, PEDAL, 0.2, vel - 20)


def brush_swing(d, s, bar0, bar1, vel=58, ride=False):
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for k in range(s.bpb):
            d.note(b + k, BR_SWIRL, 0.95, vel - 16)
        for k in (1, 3):
            if k < s.bpb:
                d.note(b + k, BR_SLAP, 0.2, vel - 4)
                d.note(b + k, PEDAL, 0.2, vel - 18)
        if ride:
            for k in range(s.bpb):
                d.note(b + k, RIDE, 0.4, vel - 10)
                if k % 2 == 1:
                    d.note(b + k + 0.5, RIDE, 0.3, vel - 22)
        d.note(b, KICK, 0.3, vel - 16)


def brush_ballad(d, s, bar0, bar1, vel=52):
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for k in range(s.bpb):
            d.note(b + k, BR_SWIRL, 0.95, vel - 12)
        d.note(b, KICK, 0.4, vel - 10)
        d.note(b + 2.5, KICK, 0.3, vel - 22)
        d.note(b + 3, BR_SLAP, 0.3, vel - 8)
        d.note(b + 1, BR_TAP, 0.3, vel - 20)


def brush_waltz(d, s, bar0, bar1, vel=56):
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        d.note(b, KICK, 0.3, vel - 6)
        d.note(b, BR_SWIRL, 2.9, vel - 14)
        d.note(b + 1, BR_TAP, 0.2, vel - 14)
        d.note(b + 2, BR_TAP, 0.2, vel - 18)
        d.note(b + 2.5, BR_TAP, 0.2, vel - 26)
        d.note(b + 1, PEDAL, 0.2, vel - 22)
        d.note(b + 2, PEDAL, 0.2, vel - 24)


def kit_funk(d, s, bar0, bar1, vel=74, open_hat=True):
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for k in range(16):
            t = b + k * 0.25
            if k % 2 == 0:
                d.note(t, HH, 0.2, vel - 12 + (6 if k % 4 == 0 else 0))
            elif s.rng.random() < 0.4:
                d.note(t, HH, 0.1, vel - 30)
        d.note(b, KICK, 0.3, vel + 2)
        d.note(b + 0.75, KICK, 0.2, vel - 14)
        d.note(b + 2.5, KICK, 0.3, vel - 4)
        d.note(b + 1, SNARE, 0.3, vel)
        d.note(b + 3, SNARE, 0.3, vel)
        for gk in (1.75, 2.25, 3.75):
            if s.rng.random() < 0.5:
                d.note(b + gk, SNARE, 0.1, vel - 42)
        if open_hat and (bar - bar0) % 2 == 1:
            d.note(b + 3.5, OHH, 0.4, vel - 14)


def kit_drive(d, s, bar0, bar1, vel=80, ride=False):
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for k in range(8):
            t = b + k * 0.5
            d.note(t, RIDE if ride else HH, 0.3, vel - 10 + (6 if k % 2 == 0 else -4))
        d.note(b, KICK, 0.3, vel + 4)
        d.note(b + 1.5, KICK, 0.3, vel - 8)
        d.note(b + 2, KICK, 0.3, vel)
        d.note(b + 1, SNARE, 0.3, vel)
        d.note(b + 3, SNARE, 0.3, vel + 2)
        d.note(b + 3.75, SNARE, 0.1, vel - 36)
        for k in range(4):
            d.note(b + k + 0.5, TAMB, 0.2, vel - 22)


def latin_perc(d, s, bar0, bar1, vel=60):
    """Bongos, conga and shaker, for library tension and funk layers."""
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for k in range(16):
            d.note(b + k * 0.25, SHAKER, 0.1, vel - 24 + (8 if k % 4 == 2 else 0))
        for off, n_, dv in ((0, CONGA_L, 0), (1.5, CONGA_O, -2), (2.5, CONGA_M, -10), (3, CONGA_O, -4), (3.5, CONGA_L, -6)):
            d.note(b + off, n_, 0.2, vel + dv)
        for off in (0.75, 1.25, 2.75):
            d.note(b + off, BONGO_H, 0.1, vel - 10)


def fill(d, s, bar, vel=70, kind="brush"):
    """One-bar fill ending a section."""
    b = bar * s.bpb
    if kind == "brush":
        for k, off in enumerate((2, 2.5, 3, 3.25, 3.5, 3.75)):
            d.note(b + off, BR_SLAP if k % 2 == 0 else BR_TAP, 0.2, vel - 14 + k * 3)
    else:
        toms = [TOM_HI, TOM_HI, TOM_MID, TOM_MID, TOM_LO, TOM_LO, SNARE, SNARE]
        for k, n_ in enumerate(toms):
            d.note(b + 2 + k * 0.25, n_, 0.2, vel - 10 + k * 3)


def crash(d, s, bar, vel=70, note=CRASH):
    d.note(bar * s.bpb, note, 2, vel)
