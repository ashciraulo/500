"""Notte FM's wider rotation: mus_nottefm_05 .. mus_nottefm_14.

The first four Notte FM pieces (music_tracks_more.py) are all pad-and-drone
ambient. These ten widen the station while keeping it a calm night drive:
lo-fi hip-hop, late-night city pop, dub, a vibraphone nocturne, Balearic
guitar, chillwave, felt piano and cello, trip-hop, a 3 am Rhodes ballad and
a beatless glassy drift. Same pipeline: Song/Part composition, FluidSynth,
mix, worn-tape chain. The radio's running order by hour is in
audio/music/programme_nottefm.json.

Set NOTTE_AUDIT=1 to print long melody notes that clash with the chord.
"""
from __future__ import annotations

import os

import numpy as np

import music_core as mc
import music_patterns as pt
import sfxlib
from music_core import SR, Song

# Notte FM's tape: older and duller than the day station
NOTTE_TAPE = {"age": 1.7, "lp_hz": 8500, "hiss_db": -47, "drive": 1.3, "width": 0.7,
              "dropouts": 1.5, "bump_db": 2.5}


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

def _tape(**kw):
    t = dict(NOTTE_TAPE)
    t.update(kw)
    return t


def _echo(song, beats=0.75, fb=0.45, wet=0.45, lp=2600, hp=220, taps=8, spread=0.6):
    """Tape-style feedback echo for one stem (each repeat darker, ping-pong)."""
    d = int(round(beats * song.spb * SR))

    def f(x):
        y = np.concatenate([x, np.zeros((d * taps, 2))])
        out = y.copy()
        tap = sfxlib.hp(y, hp, 1)
        g = wet
        for k in range(1, taps + 1):
            tap = sfxlib.lp(tap, lp, 1)
            sh = np.zeros_like(y)
            sh[k * d:] = tap[: len(y) - k * d]
            m = sh.mean(axis=1)
            sp = spread if k % 2 else -spread
            out[:, 0] += g * m * (1 + sp)
            out[:, 1] += g * m * (1 - sp)
            g *= fb
        return out
    return f


def _produce(song, gains, sends=None, eqs=None, fx=None, rev_size=2.0, rev_damp=4500,
             rev_gain=1.0, tape_kw=None, fade_in=0.0, fade_out=0.0):
    """mc.produce with per-stem time-domain effects (fx: stem -> fn)."""
    if os.environ.get("NOTTE_AUDIT"):
        for line in mc.audit(song):
            print("   audit " + line)
    stems = mc.render(song)
    for k, fn in (fx or {}).items():
        if k in stems:
            stems[k] = fn(stems[k])
    e = dict(mc.STEM_EQ)
    e.update(eqs or {})
    e = {k: v for k, v in e.items() if v is not None}
    x = mc.mix(song, stems, gains, sends, e, rev_size, rev_damp, song.seed, rev_gain)
    from scipy.ndimage import uniform_filter1d
    env = np.sqrt(np.maximum(uniform_filter1d(np.mean(x ** 2, axis=1), int(0.3 * SR)), 0))
    ref = np.median(env[env > env.max() * 1e-3])
    idx = np.nonzero(env > ref * 10 ** (-32 / 20))[0]
    length = (idx[-1] / SR + 0.4) if len(idx) else None
    x = mc.tape(x, seed=song.seed, **(tape_kw or NOTTE_TAPE))
    return mc.finish(x, False, fade_in, fade_out or 2.5, length=length)


def _comp(p, s, bar0, bar1, hits, lo=55, hi=74, n=4, vel=50, strum=0.0, root=False):
    """Chord hits per bar: hits = [(offset, dur, dvel)], voice-led."""
    prev = None
    for bar in range(bar0, bar1):
        for off, dur, dv in hits:
            beat = bar * s.bpb + off
            ch = s.chord_at(beat + 0.01)
            v = mc.voicing(ch, lo, hi, n, prev, root=root)
            prev = v
            p.chord(beat, v, dur, vel + dv, strum)


def _sw16(b, k, sw):
    """Position of 16th k in a bar starting at beat b, odd 16ths swung."""
    return b + k * 0.25 + (sw * 0.25 if k % 2 else 0.0)


def _bass_root_fifth(p, s, bar0, bar1, vel=78, lo=28, hi=45):
    """Waltz-time upright: root on 1, fifth or approach on 3."""
    prev = None
    for b, d, ch in s.segs(bar0, bar1):
        rt = mc.nearest(ch.bass, prev if prev is not None else 38, lo, hi)
        prev = rt
        if d >= 3:
            p.note(b, rt, 1.9, vel)
            nxt = s.chord_at(b + d + 0.01)
            if s.rng.random() < 0.5:
                q = mc.nearest(ch.fifth_pc(), rt + 5, lo, hi + 5)
            else:
                tgt = mc.nearest(nxt.bass, rt, lo, hi)
                q = tgt + (1 if tgt < rt else -1) if tgt != rt else rt + 7
            p.note(b + 2, q, 0.9, vel - 10)
        else:
            p.note(b, rt, d - 0.1, vel)


# --------------------------------------------------------------------------
# Drum patterns
# --------------------------------------------------------------------------

def _boombap(d, s, b0, b1, vel=72, sw=0.3, hats=True, kick=True, ghost=0.35):
    """Dusty swung boom-bap, two-bar phrase."""
    r = s.rng
    for bar in range(b0, b1):
        b = bar * s.bpb
        alt = (bar - b0) % 2
        if kick:
            ks = [(0, 0), (7, -16), (10, -4)] if not alt else [(0, 0), (6, -12), (10, -6), (13, -18)]
            for k, dv in ks:
                d.note(_sw16(b, k, sw), pt.KICK, 0.3, vel + dv)
        for k in (4, 12):
            d.note(_sw16(b, k, sw), pt.SNARE, 0.3, vel - 4)
        if alt:
            d.note(_sw16(b, 15, sw), pt.SNARE, 0.1, vel - 38)
        if hats:
            for k in range(16):
                if k % 2 == 0:
                    d.note(_sw16(b, k, sw), pt.HH, 0.1, vel - 18 + (6 if k % 4 == 0 else 0))
                elif r.random() < ghost:
                    d.note(_sw16(b, k, sw), pt.HH, 0.08, vel - 36)
            if alt and r.random() < 0.5:
                d.note(_sw16(b, 14, sw), pt.OHH, 0.4, vel - 26)


def _softkit(d, s, b0, b1, vel=60, back=pt.STICK):
    """Late-night city pop: soft 16th hats, kick on 1 and the and of 3."""
    for bar in range(b0, b1):
        b = bar * s.bpb
        alt = (bar - b0) % 2
        for k in range(16):
            d.note(b + k * 0.25, pt.HH, 0.1, vel - 18 + (6 if k % 4 == 0 else 0) - (10 if k % 2 else 0))
        d.note(b, pt.KICK, 0.3, vel)
        d.note(b + 2.5, pt.KICK, 0.3, vel - 6)
        if alt:
            d.note(b + 1.75, pt.KICK, 0.2, vel - 18)
            d.note(b + 3.5, pt.OHH, 0.3, vel - 28)
        d.note(b + 1, back, 0.3, vel - 2)
        d.note(b + 3, back, 0.3, vel)


def _onedrop(d, s, b0, b1, vel=68, sw=0.16, hats=True):
    """Roots one-drop: kick and cross-stick together on beat 3."""
    for bar in range(b0, b1):
        b = bar * s.bpb
        d.note(b + 2, pt.KICK, 0.3, vel)
        d.note(b + 2, pt.STICK, 0.2, vel - 2)
        if hats:
            for k in range(8):
                t = b + k * 0.5 + (sw * 0.5 if k % 2 else 0)
                d.note(t, pt.HH, 0.1, vel - 14 + (4 if k % 2 == 0 else -4))
        if (bar - b0) % 4 == 3:
            for off, dv in ((3.0, -14), (3.25 + sw * 0.25, -20), (3.5, -10)):
                d.note(b + off, pt.STICK, 0.1, vel + dv)
            d.note(b + 3.75, pt.TOM_LO, 0.2, vel - 18)


def _triphop(d, s, b0, b1, vel=78, sw=0.12, hats=True):
    r = s.rng
    for bar in range(b0, b1):
        b = bar * s.bpb
        alt = (bar - b0) % 2
        ks = [(0, 0), (3, -12), (10, -2)] if not alt else [(0, 0), (7, -10), (10, -4), (11, -14)]
        for k, dv in ks:
            d.note(_sw16(b, k, sw), pt.KICK, 0.3, vel + dv)
        for k in (4, 12):
            d.note(_sw16(b, k, sw), pt.SNARE, 0.4, vel)
        if r.random() < 0.5:
            d.note(_sw16(b, 9, sw), pt.SNARE, 0.1, vel - 38)
        if hats:
            for k in range(16):
                if k % 2 == 0:
                    d.note(_sw16(b, k, sw), pt.HH, 0.1, vel - 22 + (4 if k % 4 == 2 else 0))
                elif r.random() < 0.3:
                    d.note(_sw16(b, k, sw), pt.HH, 0.08, vel - 38)


def _machine(d, s, b0, b1, vel=66, hats=True, kick=True):
    """Soft 808: boom kick, claps on 2 and 4, airy hats."""
    for bar in range(b0, b1):
        b = bar * s.bpb
        alt = (bar - b0) % 2
        if kick:
            for k, dv in ((0, 0), (6, -14), (10, -4)):
                d.note(b + k * 0.25, pt.KICK, 0.5, vel + dv)
            d.note(b + 1, pt.CLAP, 0.3, vel - 8)
            d.note(b + 3, pt.CLAP, 0.3, vel - 6)
        if hats:
            for k in range(8):
                d.note(b + k * 0.5, pt.HH, 0.1, vel - 26 + (6 if k % 2 else 0))
            if alt:
                d.note(b + 3.5, pt.OHH, 0.4, vel - 24)


def _balearic(d, s, b0, b1, vel=60, kick=True):
    for bar in range(b0, b1):
        b = bar * s.bpb
        for k in range(16):
            d.note(b + k * 0.25, pt.SHAKER, 0.1, vel - 26 + (8 if k % 4 == 2 else 0))
        for off, n_, dv in ((0.5, pt.CONGA_M, -12), (1.5, pt.CONGA_O, -6), (2.75, pt.CONGA_M, -14),
                            (3, pt.CONGA_O, -8), (3.5, pt.CONGA_L, -6)):
            d.note(b + off, n_, 0.2, vel + dv)
        if kick:
            d.note(b, pt.KICK, 0.3, vel - 4)
            d.note(b + 2, pt.KICK, 0.3, vel - 10)
            d.note(b + 3, pt.STICK, 0.2, vel - 16)


# --------------------------------------------------------------------------
# 05 "Velluto": lo-fi hip-hop, Ab major, 80 BPM, swung beat, Rhodes
# --------------------------------------------------------------------------

PO_A = ["Dbmaj9", "Cm7 F7b9", "Bbm9", "Eb13sus4"]
PO_B = ["Fm9", "Ebm9 Ab13", "Dbmaj9", "Gm7b5 C7b9", "Fm9", "Bbm9", "Dbmaj7/Eb", "Eb13sus4"]
PO_MEL_A = ("r/1 c5/.5 eb5/.5 f5/1 ab5/1 | g5/1.5 eb5/.5 r/1 a4/1 | bb4/.5 c5/.5 db5/1 f5/1.5 eb5/.5 |"
            " c5/3 r/1 | r/1 c5/.5 eb5/.5 f5/1 c6/1 | bb5/1.5 g5/.5 eb5/1 gb5/1 |"
            " f5/1.5 db5/.5 c5/1 bb4/1 | ab4/2 r/2")
PO_MEL_B = ("c6/1.5 ab5/.5 g5/1 f5/1 | gb5/1.5 f5/.5 r/.5 eb5/.5 c5/1 | f5/3 r/1 |"
            " r/.5 bb4/.5 db5/.5 f5/.5 e5/1 db5/1 | c5/1.5 eb5/.5 g5/1 ab5/1 |"
            " bb5/1 ab5/.5 f5/.5 db5/2 | c5/1 db5/1 eb5/1 f5/1 | ab5/2 bb5/1 r/1")


def notte_05():
    s = Song("mus_nottefm_05", bpm=80, bpb=4, seed=505, swing=0.18)
    bar = s.chords(0, PO_A)
    A1 = bar; bar = s.chords(bar, PO_A * 2)
    A2 = bar; bar = s.chords(bar, PO_A * 2)
    B1 = bar; bar = s.chords(bar, PO_B)
    A3 = bar; bar = s.chords(bar, PO_A * 2)
    B2 = bar; bar = s.chords(bar, PO_B)
    A4 = bar; bar = s.chords(bar, PO_A * 2)
    OUT = bar; bar = s.chords(bar, PO_A[:3] + ["Dbmaj9"])
    END = bar
    ep = s.part("rhodes", 4, "lead", vol=104, pan=-0.08, ht=0.016, hv=6, drift=3)
    cp = s.part("rhodes_comp", 4, "keys", bank=8, vol=96, pan=0.18, ht=0.02, hv=4, drift=4, lag=0.012)
    bs = s.part("bass", 33, "bass", vol=104, ht=0.014, hv=4, lag=0.008)
    dr = s.part("drums", 8, "drums", drum=True, vol=100, ht=0.007, hv=5, swing=0.0)
    pd = s.part("pad", 89, "pad", vol=80, detune=-6, drift=5)
    ep.melody(A1, PO_MEL_A, vel=70)
    ep.melody(A2, mc.bars(PO_MEL_A, 0, 4) + " | " + mc.bars(PO_MEL_A, 0, 3) + " | ab4/1 c5/1 eb5/2", vel=72)
    ep.melody(B1, PO_MEL_B, vel=74)
    pt.sparse_melody(ep, s, A3, B2, lo=63, hi=82, density=0.4, vel=60, motif_bars=2, durs=(0.5, 1, 1.5, 0.5))
    ep.melody(B2, PO_MEL_B, vel=74)
    ep.melody(A4, PO_MEL_A, vel=70)
    ep.melody(OUT, "r/1 c5/.5 eb5/.5 f5/1 ab5/1 | g5/4 | f5/4 | r/4", vel=60)
    _comp(cp, s, 0, END, [(0, 1.75, 0), (2, 1.4, -6), (3.5, 0.45, -14)], lo=53, hi=70, vel=50)
    riff = [(0, 0, 1.6), (1.75, 0, 0.2), (2, 0, 0.9), (3, 7, 0.4), (3.5, 12, 0.4)]
    pt.bass_riff(bs, s, 2, OUT + 2, riff, vel=86, lo=31, hi=46)
    _boombap(dr, s, A1, A3, vel=74)
    _boombap(dr, s, A3, B2, vel=68, kick=True, ghost=0.2)
    _boombap(dr, s, B2, OUT, vel=74)
    dr.note(A1 * 4 - 0.5, pt.OHH, 0.4, 50)
    pt.pad(pd, s, A2, OUT + 3, lo=53, hi=72, n=4, vel=42, gap=0.0)
    end = END * 4
    cp.chord(end, mc.voicing(mc.Chord("Dbmaj9"), 53, 72, 5), 6, 48, strum=0.06)
    bs.note(end, mc.midi("db2"), 4, 70)
    return _produce(s, gains={"lead": 0, "keys": -4, "bass": -4, "drums": 1, "pad": -12},
                    sends={"lead": 0.35, "keys": 0.3, "bass": 0.02, "drums": 0.12, "pad": 0.5},
                    eqs={"drums": lambda f: mc.hp_resp(f, 45, 2) * mc.lp_resp(f, 6500, 1) * mc.bell_resp(f, 180, 2, 1),
                         "lead": lambda f: mc.hp_resp(f, 120, 2) * mc.lp_resp(f, 5000, 1),
                         "bass": lambda f: mc.lp_resp(f, 1400, 2) * mc.hp_resp(f, 35, 2)},
                    rev_size=1.8, tape_kw=_tape(lp_hz=7500, drive=1.6, hiss_db=-45), fade_in=0.5)


# --------------------------------------------------------------------------
# 06 "Lungomare": late-night city pop, E major, 92 BPM, sax + fretless
# --------------------------------------------------------------------------

LU_INTRO = ["Amaj7", "B13", "G#m7", "C#m9"]
LU_A = ["Amaj7", "B13", "G#m7", "C#m9", "F#m9", "B13sus4 B13", "Emaj9", "C#m7"]
LU_B = ["F#m9", "G#m7", "Amaj7", "Am6", "G#m7", "C#7b9", "F#m9", "B13sus4"]
LU_MEL_A = ("r/.5 c#5/.5 e5/.5 g#5/1.5 e5/1 | f#5/1.5 d#5/.5 c#5/2 | r/.5 b4/.5 d#5/.5 f#5/1.5 d#5/1 |"
            " e5/3 r/1 | r/.5 a4/.5 c#5/.5 e5/1 g#5/1.5 | a5/1.5 g#5/.5 f#5/1 d#5/1 |"
            " e5/1 f#5/.5 g#5/.5 b5/2 | g#5/3 r/1")
LU_MEL_A2_END = (" r/.5 a4/.5 c#5/.5 e5/1 a5/1.5 | b5/1.5 a5/.5 g#5/1 f#5/1 | g#5/1 e5/1 d#5/1 b4/1 |"
                 " c#5/3 r/1")
LU_MEL_B = ("c#6/1.5 a5/.5 g#5/1 e5/1 | f#5/1.5 d#5/.5 b4/2 | c#5/.5 e5/.5 g#5/.5 b5/.5 a5/2 |"
            " c5/1.5 e5/.5 f#5/2 | f#5/1.5 d#5/.5 b4/1 g#4/1 | e#5/1 d5/1 b4/1 g#4/1 |"
            " a4/1 c#5/1 e5/1 g#5/1 | f#5/3 r/1")


def notte_06():
    s = Song("mus_nottefm_06", bpm=92, bpb=4, seed=506)
    bar = s.chords(0, LU_INTRO)
    A1 = bar; bar = s.chords(bar, LU_A)
    A2 = bar; bar = s.chords(bar, LU_A)
    B1 = bar; bar = s.chords(bar, LU_B)
    A3 = bar; bar = s.chords(bar, LU_A)
    B2 = bar; bar = s.chords(bar, LU_B)
    A4 = bar; bar = s.chords(bar, LU_A)
    OUT = bar; bar = s.chords(bar, ["Amaj7", "B13sus4", "Emaj9", "Emaj9"])
    sax = s.part("sax", 65, "lead", vol=100, pan=0.06, ht=0.014, hv=5, expr=True)
    ep2 = s.part("ep_lead", 5, "lead2", vol=100, pan=-0.15, ht=0.012, hv=5)
    ep = s.part("ep", 5, "keys", vol=96, pan=-0.25, ht=0.01, hv=4)
    gt = s.part("guitar", 27, "gtr", vol=92, pan=0.4, ht=0.006, hv=4)
    bs = s.part("fretless", 35, "bass", vol=110, ht=0.008, hv=4)
    dr = s.part("drums", 0, "drums", drum=True, vol=96, ht=0.006, hv=4)
    st = s.part("strings", 49, "pad", vol=84, pan=0.2)
    sax.melody(A1, LU_MEL_A, vel=74)
    sax.melody(A2, mc.bars(LU_MEL_A, 0, 4) + " | " + LU_MEL_A2_END, vel=76)
    sax.melody(B1, LU_MEL_B, vel=78)
    ep2.melody(A3, LU_MEL_A, vel=70, shift=12)
    sax.melody(B2, LU_MEL_B, vel=78)
    sax.melody(A4, mc.bars(LU_MEL_A, 0, 4) + " | " + LU_MEL_A2_END, vel=74)
    sax.melody(OUT, "r/.5 c#5/.5 e5/.5 g#5/1.5 e5/1 | f#5/1.5 e5/.5 b4/2 | g#4/4 | r/4", vel=66)
    _comp(ep, s, 0, OUT + 3, [(0, 0.9, 0), (1.5, 0.4, -8), (2.75, 1.1, -4)], lo=55, hi=74, vel=52)
    _comp(gt, s, A1, OUT + 2, [(1, 0.18, 0), (2.75, 0.12, -12), (3, 0.18, 0)], lo=62, hi=79, n=3,
          vel=50, strum=0.006)
    riff = [(0, 0, 1.4), (1.5, 0, 0.4), (2, 7, 0.9), (3, 12, 0.4), (3.5, 7, 0.4)]
    pt.bass_riff(bs, s, 0, OUT + 3, riff, vel=84, lo=28, hi=45)
    _softkit(dr, s, A1, B1, vel=60, back=pt.STICK)
    _softkit(dr, s, B1, A3, vel=62, back=pt.SNARE)
    _softkit(dr, s, A3, B2, vel=58, back=pt.STICK)
    _softkit(dr, s, B2, A4, vel=62, back=pt.SNARE)
    _softkit(dr, s, A4, OUT + 2, vel=60, back=pt.STICK)
    for b in (A1, B1, A3, B2, A4):
        pt.fill(dr, s, b - 1, vel=56, kind="toms")
    pt.pad(st, s, B1, A3, lo=55, hi=74, n=4, vel=42)
    pt.pad(st, s, B2, OUT + 4, lo=55, hi=74, n=4, vel=40)
    end = (OUT + 4) * 4
    ep.chord(end, mc.voicing(mc.Chord("Emaj9"), 55, 76, 5), 6, 54, strum=0.04)
    bs.note(end, mc.midi("e1"), 5, 76)
    dr.note(end, pt.RIDE, 3, 40)
    return _produce(s, gains={"lead": 0, "lead2": -2, "keys": -5, "gtr": -8, "bass": -5, "drums": -3, "pad": -10},
                    sends={"lead": 0.4, "lead2": 0.4, "keys": 0.3, "gtr": 0.25, "bass": 0.03, "drums": 0.15,
                           "pad": 0.5},
                    eqs={"lead": lambda f: mc.hp_resp(f, 160, 2) * mc.lp_resp(f, 6000, 1),
                         "drums": lambda f: mc.hp_resp(f, 40, 2) * mc.lp_resp(f, 7000, 1)},
                    rev_size=2.2, tape_kw=_tape(), fade_in=0.3)


# --------------------------------------------------------------------------
# 07 "Eco del porto": dub, G minor, 72 BPM, echoing melodica
# --------------------------------------------------------------------------

EP_A = ["Gm7", "Gm7", "Cm9", "Cm9", "Ebmaj7", "Dm7", "Cm9", "D7sus4"]
EP_BASS = ("g1/1.5 g1/.5 r/.5 bb1/.5 d2/1 | f2/.5 d2/.5 r/1 c2/.5 bb1/.5 a1/1 |"
           " c2/1.5 c2/.5 r/.5 eb2/.5 g2/1 | bb1/.5 g1/.5 r/1 bb1/.5 c2/.5 d2/1 |"
           " eb2/1.5 eb2/.5 r/.5 g2/.5 bb1/1 | d2/1.5 d2/.5 r/.5 f2/.5 a1/1 |"
           " c2/1.5 c2/.5 r/.5 eb2/.5 g2/1 | d2/1.5 d2/.5 r/.5 c2/.5 a1/1")
EP_MEL_1 = ("r/1 d5/.5 f5/.5 g5/1.5 f5/.5 | d5/2 r/2 | r/1 eb5/.5 g5/.5 bb5/1.5 g5/.5 | f5/2 d5/1 r/1 |"
            " r/.5 g5/.5 bb5/.5 d6/.5 c6/1 bb5/1 | a5/2 f5/1 d5/1 | eb5/1.5 d5/.5 c5/1 bb4/1 | a4/2 r/2")
EP_MEL_2 = ("r/1 bb5/.5 a5/.5 g5/1.5 d5/.5 | f5/2 r/2 | r/1 g5/.5 bb5/.5 c6/1.5 bb5/.5 | g5/2 eb5/1 r/1 |"
            " r/.5 d5/.5 eb5/.5 g5/.5 bb5/1 a5/1 | f5/2 e5/1 d5/1 | c5/1.5 eb5/.5 d5/1 c5/1 | a4/3 r/1")


def notte_07():
    s = Song("mus_nottefm_07", bpm=72, bpb=4, seed=507, swing=0.12)
    bar = s.chords(0, EP_A[:4])
    A1 = bar; bar = s.chords(bar, EP_A)
    A2 = bar; bar = s.chords(bar, EP_A)
    D1 = bar; bar = s.chords(bar, EP_A)
    A3 = bar; bar = s.chords(bar, EP_A)
    D2 = bar; bar = s.chords(bar, EP_A)
    OUT = bar; bar = s.chords(bar, ["Gm7", "Gm7", "Gm7", "Gm7"])
    mel = s.part("melodica", 22, "lead", vol=88, pan=0.05, ht=0.014, hv=5)
    reed = s.part("reed", 20, "lead", vol=70, pan=-0.05, ht=0.014, hv=4)
    sk = s.part("skank", 27, "gtr", vol=96, pan=0.3, ht=0.005, hv=4)
    org = s.part("organ", 17, "keys", vol=78, pan=-0.3, ht=0.006, hv=3)
    bs = s.part("bass", 33, "bass", vol=118, ht=0.01, hv=3)
    dr = s.part("drums", 0, "drums", drum=True, vol=100, ht=0.007, hv=4, swing=0.0)
    for part, v in ((mel, 78), (reed, 52)):
        part.melody(A1, EP_MEL_1, vel=v)
        part.melody(A2, EP_MEL_2, vel=v)
        part.melody(A3, EP_MEL_1, vel=v + 2)
        part.melody(OUT, "r/1 d5/.5 f5/.5 g5/1.5 f5/.5 | d5/2 r/2 | g4/4 | r/4", vel=v - 8)
    # dub sections: melodica throws into the echo
    for D in (D1, D2):
        mel.melody(D + 1, mc.bars(EP_MEL_1, 0, 1), vel=72)
        mel.melody(D + 4, mc.bars(EP_MEL_2, 4, 5), vel=70)
        mel.melody(D + 7, "r/2 a5/1 r/1", vel=66)
    # bass: the line, with dropouts in the dub sections
    bs.melody(0, mc.bars(EP_BASS, 0, 4), vel=96)
    for b0 in (A1, A2, A3):
        bs.melody(b0, EP_BASS, vel=96)
    for D in (D1, D2):
        bs.melody(D, mc.bars(EP_BASS, 0, 3) + " | r/4 | " + mc.bars(EP_BASS, 4, 7) + " | r/2 d2/1 a1/1", vel=96)
    bs.melody(OUT, mc.bars(EP_BASS, 0, 2) + " | g1/4 | r/4", vel=92)
    # skank on 2 and 4; organ bubble on the off-beats
    for b0, b1, dens in ((0, D1, 1.0), (D1, A3, 0.45), (A3, D2, 1.0), (D2, OUT, 0.45), (OUT, OUT + 2, 1.0)):
        prev = None
        for bb in range(b0, b1):
            for off in (1, 3):
                if s.rng.random() > dens:
                    continue
                ch = s.chord_at(bb * 4 + off + 0.01)
                v = mc.voicing(ch, 62, 77, 3, prev)
                prev = v
                sk.chord(bb * 4 + off, v, 0.16, 58, strum=0.004)
    for b0, b1 in ((0, D1), (A3, D2), (OUT, OUT + 2)):
        _comp(org, s, b0, b1, [(0.5, 0.3, 0), (1.5, 0.3, -6), (2.5, 0.3, 0), (3.5, 0.3, -6)],
              lo=55, hi=70, n=3, vel=48)
    _onedrop(dr, s, 2, D1, vel=70)
    _onedrop(dr, s, D1, A3, vel=68, hats=False)
    _onedrop(dr, s, A3, D2, vel=70)
    _onedrop(dr, s, D2, OUT + 2, vel=68, hats=False)
    for b in range(D1, A3, 2):
        dr.note(b * 4 + 3.5, pt.OHH, 0.4, 44)
    dr.note(OUT * 4 + 8, pt.KICK, 0.4, 60)
    return _produce(s, gains={"lead": 2, "gtr": -3, "keys": -6, "bass": -4, "drums": 0},
                    sends={"lead": 0.3, "gtr": 0.35, "keys": 0.25, "bass": 0.0, "drums": 0.22},
                    eqs={"bass": lambda f: mc.lp_resp(f, 900, 2) * mc.hp_resp(f, 30, 2) * mc.bell_resp(f, 70, 2, 1),
                         "lead": lambda f: mc.hp_resp(f, 200, 2) * mc.lp_resp(f, 4000, 2),
                         "gtr": lambda f: mc.hp_resp(f, 400, 2) * mc.lp_resp(f, 4500, 1),
                         "drums": lambda f: mc.hp_resp(f, 40, 2) * mc.lp_resp(f, 6000, 1)},
                    fx={"lead": _echo(s, 0.75, fb=0.5, wet=0.5, lp=2200),
                        "gtr": _echo(s, 0.75, fb=0.55, wet=0.55, lp=2000, hp=400)},
                    rev_size=2.6, tape_kw=_tape(lp_hz=7800, bump_db=3.0), fade_in=0.3)


# --------------------------------------------------------------------------
# 08 "Notturno blu": vibraphone + upright bass nocturne, D minor, 3/4, 84 BPM
# --------------------------------------------------------------------------

NB_A = ["Dm9", "Dm9", "Bbmaj7", "Bbmaj7", "Gm9", "A7b9", "Dm9", "Dm7/C",
        "Bm7b5", "Bbmaj7", "Em7b5", "A7b9", "Dm9", "Gm9", "Em7b5:2 A7b9:1", "Dm9"]
NB_B = ["Gm9", "C9", "Fmaj7", "Bbmaj7", "Em7b5", "A7b9", "Dm9", "Dm9",
        "Gm9", "C9", "Fmaj7", "Dm9", "Bbmaj7", "Gm9", "A7sus4", "A7b9"]
NB_MEL_A = ("a4/1 c5/1 e5/1 | f5/2 e5/1 | d5/1.5 c5/.5 a4/1 | f4/3 | g4/1 bb4/1 d5/1 | c#5/2 bb4/1 |"
            " a4/3 | r/1 c5/1 d5/1 | f5/2 d5/1 | a5/2 f5/1 | g5/1.5 f5/.5 e5/1 | c#5/2 e5/1 |"
            " d5/1 f5/1 a5/1 | bb5/2 a5/1 | g5/1 e5/1 c#5/1 | d5/3")
NB_MEL_B = ("d5/1 f5/1 a5/1 | g5/2 e5/1 | a5/1.5 g5/.5 f5/1 | d5/3 | e5/1 g5/1 bb5/1 | a5/2 g5/1 |"
            " f5/3 | r/1 e5/1 f5/1 | g5/1 a5/1 bb5/1 | c6/2 bb5/1 | a5/1 g5/1 f5/1 | e5/3 |"
            " d5/1 f5/1 a5/1 | bb5/1.5 a5/.5 g5/1 | e5/1 d5/1 e5/1 | c#5/3")


def notte_08():
    s = Song("mus_nottefm_08", bpm=84, bpb=3, seed=508, swing=0.1)
    bar = s.chords(0, ["Dm9", "Dm9", "Bbmaj7", "A7b9"])
    A1 = bar; bar = s.chords(bar, NB_A)
    B1 = bar; bar = s.chords(bar, NB_B)
    A2 = bar; bar = s.chords(bar, NB_A)
    A3 = bar; bar = s.chords(bar, NB_A)
    CODA = bar; bar = s.chords(bar, ["Gm9", "A7b9", "Dm9", "Dm9"])
    vib = s.part("vibes", 11, "lead", vol=108, pan=-0.1, ht=0.012, hv=6)
    vc = s.part("vibes_comp", 11, "keys", vol=88, pan=0.25, ht=0.02, hv=4)
    bs = s.part("upright", 32, "bass", vol=112, ht=0.012, hv=5)
    dr = s.part("brushes", 40, "drums", drum=True, vol=92, ht=0.01, hv=4, swing=0.0)
    vib.melody(A1, NB_MEL_A, vel=72)
    vib.melody(B1, NB_MEL_B, vel=76)
    pt.sparse_melody(vib, s, A2, A3, lo=62, hi=81, density=0.45, vel=62, motif_bars=2, durs=(1, 0.5, 2, 1))
    vib.melody(A3, mc.bars(NB_MEL_A, 0, 15) + " | d5/1 a5/1 d6/1", vel=74)
    vib.melody(CODA, "bb5/2 a5/1 | c#6/3 | d6/3 | r/3", vel=62)
    _comp(vc, s, 0, CODA + 3, [(0, 2.8, 0)], lo=50, hi=67, n=3, vel=40)
    _comp(vc, s, B1, A2, [(1.5, 1.3, -10)], lo=55, hi=70, n=2, vel=40)
    _bass_root_fifth(bs, s, 0, A2, vel=80)
    pt.bass_walk(bs, s, A2, A3, vel=74, lo=28, hi=45)
    _bass_root_fifth(bs, s, A3, CODA + 3, vel=78)
    pt.brush_waltz(dr, s, B1, A3, vel=42)
    pt.brush_waltz(dr, s, A3, CODA + 2, vel=36)
    end = (CODA + 3) * 3
    vc.chord(end, [mc.midi(n) for n in ("f4", "a4", "c5", "e5")], 6, 44, strum=0.08)
    bs.note(end, mc.midi("d2"), 5, 70)
    return _produce(s, gains={"lead": 0, "keys": -5, "bass": -9, "drums": -5},
                    sends={"lead": 0.4, "keys": 0.45, "bass": 0.05, "drums": 0.3},
                    eqs={"lead": lambda f: mc.hp_resp(f, 150, 2) * mc.lp_resp(f, 7000, 1),
                         "bass": lambda f: mc.lp_resp(f, 2500, 2) * mc.hp_resp(f, 35, 2)},
                    rev_size=3.0, rev_damp=4000, tape_kw=_tape(), fade_in=0.5)


# --------------------------------------------------------------------------
# 09 "Isola": Balearic guitar, D major, 100 BPM
# --------------------------------------------------------------------------

IS_A = ["Dmaj9", "Cmaj7#11", "Gmaj9", "A9sus4"] * 2
IS_B = ["Bm9", "Gmaj7", "Em9", "A9sus4", "Bm9", "Gmaj7", "Em9", "A9sus4"]
IS_MEL_A = ("f#5/1.5 e5/.5 d5/1 a4/1 | b4/1.5 c5/.5 e5/2 | d5/1 f#5/1 a5/1.5 g5/.5 | e5/3 r/1 |"
            " f#5/1.5 a5/.5 c#6/1 a5/1 | b5/1.5 g5/.5 e5/2 | f#5/1 d5/1 b4/1 a4/1 | d5/3 r/1")
IS_MEL_B = ("c#6/1.5 b5/.5 a5/1 f#5/1 | g5/1 f#5/1 d5/2 | e5/1.5 f#5/.5 g5/1 b5/1 | a5/3 r/1 |"
            " d6/1.5 c#6/.5 b5/1 f#5/1 | b5/1 a5/1 g5/1 d5/1 | e5/1 g5/1 f#5/1 d5/1 | e5/2 r/2")


def notte_09():
    s = Song("mus_nottefm_09", bpm=100, bpb=4, seed=509, swing=0.0)
    bar = s.chords(0, IS_A)
    A1 = bar; bar = s.chords(bar, IS_A)
    A2 = bar; bar = s.chords(bar, IS_A)
    B1 = bar; bar = s.chords(bar, IS_B)
    A3 = bar; bar = s.chords(bar, IS_A)
    BR = bar; bar = s.chords(bar, IS_A)
    B2 = bar; bar = s.chords(bar, IS_B)
    A4 = bar; bar = s.chords(bar, IS_A)
    OUT = bar; bar = s.chords(bar, ["Dmaj9", "Cmaj7#11", "Dmaj9", "Dmaj9"])
    gt = s.part("nylon", 24, "lead", vol=112, pan=-0.08, ht=0.012, hv=6)
    fl = s.part("flute", 73, "lead2", vol=90, pan=0.15, ht=0.012, hv=4, expr=True)
    ar = s.part("arp_gtr", 27, "gtr", vol=88, pan=0.35, ht=0.004, hv=5)
    bs = s.part("bass", 33, "bass", vol=104, ht=0.01, hv=4)
    dr = s.part("perc", 0, "drums", drum=True, vol=92, ht=0.008, hv=5)
    pd = s.part("pad", 89, "pad", vol=88, detune=5, drift=4)
    gt.melody(A1, IS_MEL_A, vel=82, shift=-12)
    gt.melody(A2, IS_MEL_A, vel=80, shift=-12)
    fl.melody(A2, IS_MEL_A, vel=62)
    fl.melody(B1, IS_MEL_B, vel=70)
    gt.melody(A3, IS_MEL_A, vel=84, shift=-12)
    gt.melody(B2, IS_MEL_B, vel=82, shift=-12)
    fl.melody(B2 + 4, mc.bars(IS_MEL_B, 4, 8), vel=62)
    gt.melody(A4, IS_MEL_A, vel=80, shift=-12)
    gt.melody(OUT, "f#5/1.5 e5/.5 d5/1 a4/1 | b4/1.5 c5/.5 e5/2 | d5/4 | r/4", vel=72, shift=-12)
    # strummed nylon behind the flute in B1
    _comp(gt, s, B1, A3, [(0, 0.9, 0), (1.5, 0.45, -8), (2.5, 1.4, -4)], lo=52, hi=69, n=4, vel=50, strum=0.012)
    pt.arp(ar, s, 0, OUT + 2, lo=57, hi=79, pattern=(0, 2, 1, 3, 2, 1, 3, 2), step=0.5, vel=46, gate=1.2, n=4)
    riff = [(0, 0, 1.4), (1.5, 7, 0.4), (2, 12, 0.9), (3, 7, 0.4), (3.5, 0, 0.4)]
    pt.bass_riff(bs, s, A1, BR, riff, vel=80, lo=33, hi=48)
    pt.bass_riff(bs, s, BR + 4, OUT + 3, riff, vel=80, lo=33, hi=48)
    _balearic(dr, s, A1, BR, vel=60)
    _balearic(dr, s, BR, BR + 8, vel=56, kick=False)
    _balearic(dr, s, B2, OUT + 2, vel=60)
    pt.pad(pd, s, 0, A1, lo=55, hi=74, n=4, vel=46, gap=0.0)
    pt.pad(pd, s, B1, A3, lo=55, hi=74, n=4, vel=40, gap=0.0)
    pt.pad(pd, s, BR, B2 + 8, lo=55, hi=74, n=4, vel=44, gap=0.0)
    pt.pad(pd, s, OUT, OUT + 4, lo=55, hi=74, n=4, vel=44, gap=0.0)
    end = (OUT + 4) * 4
    gt.chord(end - 4, [mc.midi(n) for n in ("d3", "a3", "e4", "f#4", "c#5")], 8, 56, strum=0.08)
    bs.note(end - 4, mc.midi("d2"), 6, 70)
    return _produce(s, gains={"lead": 0, "lead2": -4, "gtr": -9, "bass": -4, "drums": -7, "pad": -10},
                    sends={"lead": 0.3, "lead2": 0.45, "gtr": 0.3, "bass": 0.03, "drums": 0.2, "pad": 0.55},
                    eqs={"lead": lambda f: mc.hp_resp(f, 90, 2) * mc.lp_resp(f, 7000, 1),
                         "gtr": lambda f: mc.hp_resp(f, 250, 2) * mc.lp_resp(f, 5000, 1)},
                    fx={"gtr": _echo(s, 0.75, fb=0.4, wet=0.4, lp=3000)},
                    rev_size=2.6, tape_kw=_tape(age=1.4, lp_hz=9000), fade_in=1.5)


# --------------------------------------------------------------------------
# 10 "Neon lento": chillwave, Bb major, 84 BPM, soft 808, warbly synths
# --------------------------------------------------------------------------

NL_A = ["Gm9", "Ebmaj7", "Bbmaj7/D", "F9sus4"] * 2
NL_B = ["Ebmaj7", "Dm7", "Cm9", "F9sus4", "Ebmaj7", "Dm7", "Gm9", "F9sus4"]
NL_MEL_A = ("d5/1.5 f5/.5 a5/2 | g5/1.5 f5/.5 d5/2 | f5/1 d5/1 c5/1 a4/1 | bb4/3 r/1 |"
            " d5/1.5 f5/.5 bb5/2 | a5/1.5 g5/.5 d5/2 | f5/1 a5/1 c6/1 a5/1 | g5/3 r/1")
NL_MEL_B = ("bb5/2 g5/1 d5/1 | c5/1.5 d5/.5 f5/2 | eb5/1.5 d5/.5 c5/1 g4/1 | bb4/3 r/1 |"
            " g5/1 bb5/1 d6/2 | c6/1.5 a5/.5 f5/2 | g5/1 f5/1 d5/1 bb4/1 | c5/3 r/1")


def notte_10():
    s = Song("mus_nottefm_10", bpm=84, bpb=4, seed=510)
    bar = s.chords(0, NL_A)
    A1 = bar; bar = s.chords(bar, NL_A)
    A2 = bar; bar = s.chords(bar, NL_A)
    B1 = bar; bar = s.chords(bar, NL_B)
    BR = bar; bar = s.chords(bar, NL_A)
    A3 = bar; bar = s.chords(bar, NL_A)
    B2 = bar; bar = s.chords(bar, NL_B)
    OUT = bar; bar = s.chords(bar, ["Ebmaj7", "F9sus4", "Bbmaj7", "Bbmaj7"])
    ld = s.part("square", 80, "lead", vol=92, pan=-0.05, ht=0.01, hv=4, detune=-6, drift=6)
    ld2 = s.part("sine", 80, "lead", bank=8, vol=80, pan=0.1, ht=0.01, hv=3, detune=7, drift=6)
    pa = s.part("polyA", 90, "pad", vol=96, pan=-0.5, detune=9, drift=7, ht=0.02, hv=3)
    pb = s.part("polyB", 90, "pad", vol=96, pan=0.5, detune=-9, drift=7, ht=0.02, hv=3)
    ar = s.part("arp", 90, "arp", vol=88, pan=0.3, detune=5, drift=5, ht=0.004, hv=6)
    bs = s.part("synthbass", 39, "bass", vol=100, ht=0.006, hv=3)
    dr = s.part("808", 25, "drums", drum=True, vol=100, ht=0.004, hv=4)
    for p, v, sh in ((ld, 72, 0), (ld2, 50, 12)):
        p.melody(A1, NL_MEL_A, vel=v, shift=sh)
        p.melody(A2, mc.bars(NL_MEL_A, 0, 4) + " | " + mc.bars(NL_MEL_A, 0, 3) + " | f5/2 g5/1 c5/1", vel=v, shift=sh)
        p.melody(B1, NL_MEL_B, vel=v + 2, shift=sh)
        p.melody(A3, NL_MEL_A, vel=v, shift=sh)
        p.melody(B2, NL_MEL_B, vel=v + 2, shift=sh)
        p.melody(OUT, "bb5/2 g5/1 d5/1 | c5/4 | d5/4 | r/4", vel=v - 8, shift=sh)
    pt.pad(pa, s, 0, OUT + 4, lo=53, hi=72, n=4, vel=48, gap=0.0)
    pt.pad(pb, s, 0, OUT + 4, lo=53, hi=72, n=4, vel=46, gap=0.0)
    pt.arp(ar, s, 4, OUT + 2, lo=62, hi=86, pattern=(0, 1, 2, 3, 4, 3, 2, 1), step=0.5, vel=42, gate=0.6, n=5)
    riff = [(0, 0, 0.9), (1, 0, 0.4), (1.5, 12, 0.4), (2, 0, 0.9), (3, 7, 0.4), (3.5, 12, 0.4)]
    pt.bass_riff(bs, s, A1, BR, riff, vel=82, lo=31, hi=46)
    pt.bass_riff(bs, s, BR + 6, OUT + 3, riff, vel=82, lo=31, hi=46)
    _machine(dr, s, A1, BR, vel=64)
    _machine(dr, s, BR, BR + 8, vel=56, kick=False)
    _machine(dr, s, A3, OUT + 2, vel=64)
    dr.note((BR + 8) * 4 - 1, pt.CLAP, 0.3, 50)
    end = (OUT + 4) * 4
    bs.note((OUT + 3) * 4, mc.midi("bb1"), 4, 70)
    return _produce(s, gains={"lead": 0, "pad": -3, "arp": -6, "bass": -3, "drums": -6},
                    sends={"lead": 0.45, "pad": 0.6, "arp": 0.5, "bass": 0.02, "drums": 0.3},
                    eqs={"lead": lambda f: mc.hp_resp(f, 200, 2) * mc.lp_resp(f, 3200, 2),
                         "pad": lambda f: mc.hp_resp(f, 150, 2) * mc.lp_resp(f, 4500, 2),
                         "arp": lambda f: mc.hp_resp(f, 300, 2) * mc.lp_resp(f, 3000, 2),
                         "bass": lambda f: mc.lp_resp(f, 900, 2) * mc.hp_resp(f, 32, 2),
                         "drums": lambda f: mc.hp_resp(f, 35, 2) * mc.lp_resp(f, 6500, 1)},
                    fx={"arp": _echo(s, 0.75, fb=0.45, wet=0.5, lp=2500)},
                    rev_size=3.5, rev_damp=4000,
                    tape_kw=_tape(wow=0.0034, drift=0.002, lp_hz=7600, hiss_db=-46), fade_in=2.5)


# --------------------------------------------------------------------------
# 11 "Ninna nanna": felt piano and cello, C major, 66 BPM
# --------------------------------------------------------------------------

NN_A = ["Fmaj7", "Em7", "Dm9", "G7sus4", "Cmaj7", "Am9", "Dm9", "Gsus4"]
NN_B = ["Am9", "Em7", "Fmaj7", "Cmaj7/E", "Dm9", "Am7", "Bbmaj7", "G7sus4"]
NN_MEL_A = ("e5/1.5 c5/.5 a4/2 | b4/1.5 d5/.5 g5/2 | f5/1 e5/1 d5/1 a4/1 | c5/3 r/1 |"
            " g5/1.5 e5/.5 b4/2 | c5/1 e5/1 b5/2 | a5/1.5 f5/.5 e5/1 d5/1 | d5/3 r/1")
NN_MEL_B = ("e4/2 c4/1 b3/1 | g3/3 b3/1 | a3/1.5 c4/.5 e4/2 | g4/3 e4/1 |"
            " f4/2 e4/1 d4/1 | c4/2 e4/2 | d4/2 f4/1 a4/1 | g4/4")


def notte_11():
    s = Song("mus_nottefm_11", bpm=66, bpb=4, seed=511)
    bar = s.chords(0, NN_A[:4])
    A1 = bar; bar = s.chords(bar, NN_A)
    A2 = bar; bar = s.chords(bar, NN_A)
    B1 = bar; bar = s.chords(bar, NN_B)
    A3 = bar; bar = s.chords(bar, NN_A)
    B2 = bar; bar = s.chords(bar, NN_B)
    OUT = bar; bar = s.chords(bar, ["Fmaj7", "G7sus4", "Cmaj7", "Cmaj7"])
    pno = s.part("piano", 0, "lead", vol=100, pan=-0.05, ht=0.016, hv=5)
    lh = s.part("piano_lh", 0, "keys", vol=92, pan=0.05, ht=0.02, hv=4)
    vc = s.part("cello", 42, "lead2", vol=104, pan=0.2, ht=0.02, hv=4, expr=True)
    vc2 = s.part("cello_counter", 42, "pad", vol=92, pan=0.3, ht=0.03, hv=3, expr=True)
    pno.melody(A1, NN_MEL_A, vel=56)
    vc.melody(A2, NN_MEL_A, vel=74, shift=-12)
    vc.melody(B1, NN_MEL_B, vel=78)
    pno.melody(A3, NN_MEL_A, vel=58)
    pno.melody(B2, NN_MEL_B, vel=58, shift=12)
    pno.melody(OUT, "a5/1.5 f5/.5 e5/2 | d5/4 | e5/4 | r/4", vel=50)
    # felt-piano left hand: rolling eighths, held like a sustain pedal
    pt.arp(lh, s, 0, OUT + 3, lo=43, hi=64, pattern=(0, 1, 2, 3, 2, 1, 2, 3), step=0.5, vel=40, gate=2.4, n=4)
    # a few high piano notes answering the cello
    pt.sparse_melody(pno, s, A2, A3, lo=72, hi=86, density=0.22, vel=40, motif_bars=2, durs=(1, 2, 1.5))
    # cello counterline: slow guide tones under the piano
    prev = None
    for b, d, ch in s.segs(A3, OUT + 2):
        v = mc.voicing(ch, 48, 60, 1, prev)
        prev = v
        vc2.note(b, v[0], d - 0.05, 56)
    end = (OUT + 3) * 4
    pno.chord(end, [mc.midi(n) for n in ("c3", "g3", "d4", "e4", "b4")], 6, 46, strum=0.1)
    vc.note(end, mc.midi("c3"), 5, 58)
    return _produce(s, gains={"lead": 0, "keys": -5, "lead2": -4, "pad": -8},
                    sends={"lead": 0.35, "keys": 0.35, "lead2": 0.4, "pad": 0.45},
                    eqs={"lead": lambda f: mc.hp_resp(f, 80, 2) * mc.lp_resp(f, 2800, 2) * mc.bell_resp(f, 250, 1.5, 1),
                         "keys": lambda f: mc.hp_resp(f, 60, 2) * mc.lp_resp(f, 2200, 2),
                         "lead2": lambda f: mc.hp_resp(f, 60, 2) * mc.lp_resp(f, 5000, 1),
                         "pad": lambda f: mc.hp_resp(f, 60, 2) * mc.lp_resp(f, 3500, 1)},
                    rev_size=2.8, rev_damp=3800, tape_kw=_tape(lp_hz=7800), fade_in=0.5)


# --------------------------------------------------------------------------
# 12 "Pioggia fine": trip-hop, B minor, 82 BPM, muted guitar riff
# --------------------------------------------------------------------------

PF_A = ["Bm9", "Gmaj7", "Em9", "F#7b13"] * 2
PF_B = ["Gmaj7", "F#m7", "Em9", "Bm9", "Gmaj7", "A6", "Em9", "F#7b13"]
PF_RIFF = ("b3/.5 r/.25 d4/.25 f#4/.5 b3/.5 a4/.5 f#4/.25 r/.25 e4/.5 d4/.5 |"
           " g3/.5 r/.25 b3/.25 d4/.5 g3/.5 f#4/.5 d4/.25 r/.25 b3/.5 a3/.5 |"
           " e3/.5 r/.25 g3/.25 b3/.5 e3/.5 d4/.5 b3/.25 r/.25 f#4/.5 g4/.5 |"
           " f#3/.5 r/.25 a#3/.25 c#4/.5 f#3/.5 e4/.5 d4/.25 r/.25 c#4/.5 a#3/.5")
PF_STR = ("f#5/3 d5/1 | c#5/4 | b4/2 d5/1 e5/1 | f#5/4 | g5/2 f#5/1 d5/1 | e5/3 c#5/1 |"
          " d5/2 b4/2 | a#4/2 c#5/2")


def notte_12():
    s = Song("mus_nottefm_12", bpm=82, bpb=4, seed=512, swing=0.1)
    bar = s.chords(0, PF_A[:4])
    A1 = bar; bar = s.chords(bar, PF_A)
    A2 = bar; bar = s.chords(bar, PF_A)
    B1 = bar; bar = s.chords(bar, PF_B)
    A3 = bar; bar = s.chords(bar, PF_A)
    BR = bar; bar = s.chords(bar, PF_A[:4])
    B2 = bar; bar = s.chords(bar, PF_B)
    A4 = bar; bar = s.chords(bar, PF_A)
    OUT = bar; bar = s.chords(bar, PF_A[:3] + ["Bm9"])
    gt = s.part("muted_gtr", 28, "lead", vol=104, pan=-0.2, ht=0.006, hv=6)
    st = s.part("strings", 49, "lead2", vol=100, pan=0.15, ht=0.02, hv=4, expr=True)
    ep = s.part("rhodes", 4, "keys", vol=92, pan=0.3, ht=0.02, hv=5, drift=4)
    bs = s.part("sub", 38, "bass", vol=104, ht=0.008, hv=3)
    dr = s.part("drums", 8, "drums", drum=True, vol=104, ht=0.008, hv=5, swing=0.0)
    pd = s.part("pad", 89, "pad", vol=84, detune=-6, drift=5)
    for b0 in (0, A1, A1 + 4, A2, A2 + 4, A3, A3 + 4, BR, A4, A4 + 4, OUT):
        gt.melody(b0, PF_RIFF, vel=74)
    # in the B sections the guitar thins out to a quiet arpeggio
    pt.arp(gt, s, B1, A3, lo=50, hi=67, pattern=(0, 1, 2, 1, 3, 1, 2, 1), step=0.5, vel=52, gate=0.5, n=4)
    pt.arp(gt, s, B2, A4, lo=50, hi=67, pattern=(0, 1, 2, 1, 3, 1, 2, 1), step=0.5, vel=52, gate=0.5, n=4)
    st.melody(B1, PF_STR, vel=72)
    st.melody(B2, PF_STR, vel=76)
    st.melody(B2, PF_STR, vel=60, shift=-12)
    pt.sparse_melody(ep, s, A2, B1, lo=62, hi=81, density=0.3, vel=54, motif_bars=2, durs=(1, 1.5, 2, 0.5))
    pt.sparse_melody(ep, s, A4, OUT, lo=62, hi=81, density=0.3, vel=52, motif_bars=2, durs=(1, 1.5, 2, 0.5))
    riff = [(0, 0, 1.4), (1.75, 0, 0.6), (2.5, 12, 0.4), (3, 0, 0.9)]
    pt.bass_riff(bs, s, A1, OUT + 2, riff, vel=88, lo=31, hi=46)
    _triphop(dr, s, A1, BR, vel=80)
    _triphop(dr, s, BR, BR + 4, vel=76, hats=False)
    _triphop(dr, s, B2, OUT + 2, vel=80)
    pt.crash(dr, s, B1, vel=46)
    pt.crash(dr, s, B2, vel=46)
    pt.pad(pd, s, 0, OUT + 4, lo=50, hi=69, n=4, vel=40, gap=0.0)
    end = (OUT + 4) * 4
    bs.note(end - 4, mc.midi("b1"), 5, 72)
    return _produce(s, gains={"lead": -1, "lead2": -3, "keys": -6, "bass": -3, "drums": -5, "pad": -12},
                    sends={"lead": 0.2, "lead2": 0.5, "keys": 0.45, "bass": 0.0, "drums": 0.22, "pad": 0.5},
                    eqs={"lead": lambda f: mc.hp_resp(f, 120, 2) * mc.lp_resp(f, 5000, 1),
                         "bass": lambda f: mc.lp_resp(f, 700, 2) * mc.hp_resp(f, 30, 2),
                         "drums": lambda f: mc.hp_resp(f, 45, 2) * mc.lp_resp(f, 5000, 2) * mc.bell_resp(f, 120, 2.5, 1)},
                    rev_size=2.4, tape_kw=_tape(lp_hz=7600, drive=1.7, bump_db=3.0), fade_in=0.5)


# --------------------------------------------------------------------------
# 13 "Le tre di notte": Rhodes and brushes, Eb major, 66 BPM jazz ballad
# --------------------------------------------------------------------------

TN_A = ["Ebmaj9", "Cm9", "Fm9", "Bb13", "Gm7", "C7b9", "Fm9", "Bb7sus4",
        "Abmaj7", "Abm6", "Gm7", "Gbdim7", "Fm9", "Bb13", "Ebmaj9", "Fm7 Bb7b9"]
TN_END = TN_A[:14] + ["Ebmaj9", "Ebmaj9"]
TN_MEL = ("g4/1 bb4/1 d5/1.5 f5/.5 | eb5/3 r/1 | c5/1 eb5/1 g5/1.5 f5/.5 | d5/2 c5/1 r/1 |"
          " bb4/1 d5/1 f5/1.5 d5/.5 | e5/2 db5/1 bb4/1 | ab4/1.5 c5/.5 eb5/1 g5/1 | f5/3 r/1 |"
          " eb5/1 g5/1 c6/1.5 bb5/.5 | cb6/2 ab5/1 f5/1 | g5/1.5 f5/.5 d5/1 bb4/1 | c5/2 a4/1 eb5/1 |"
          " ab5/1.5 g5/.5 f5/1 c5/1 | d5/2 g5/1 f5/1 | g5/3 r/1 | ab5/1 f5/1 d5/1 b4/1")


def notte_13():
    s = Song("mus_nottefm_13", bpm=66, bpb=4, seed=513, swing=0.2)
    bar = s.chords(0, ["Fm9", "Bb13sus4"])
    A1 = bar; bar = s.chords(bar, TN_A)
    A2 = bar; bar = s.chords(bar, TN_A)
    A3 = bar; bar = s.chords(bar, TN_END)
    CODA = bar; bar = s.chords(bar, ["Abmaj7", "Abm6", "Ebmaj9", "Ebmaj9"])
    ep = s.part("rhodes", 4, "lead", vol=106, pan=-0.05, ht=0.018, hv=6, drift=3)
    cp = s.part("rhodes_comp", 4, "keys", bank=8, vol=92, pan=0.2, ht=0.025, hv=4, drift=4)
    bs = s.part("upright", 32, "bass", vol=110, ht=0.012, hv=5)
    dr = s.part("brushes", 40, "drums", drum=True, vol=94, ht=0.012, hv=4)
    st = s.part("strings", 49, "pad", vol=80, pan=0.25)
    ep.melody(A1, TN_MEL, vel=70)
    pt.sparse_melody(ep, s, A2, A3, lo=60, hi=80, density=0.42, vel=60, motif_bars=2, durs=(1, 0.5, 1.5, 2))
    ep.melody(A3, mc.bars(TN_MEL, 0, 14) + " | eb5/4 | r/4", vel=72)
    ep.melody(CODA, "c6/2 bb5/1 g5/1 | cb6/2 ab5/1 f5/1 | g5/4 | r/4", vel=60)
    _comp(cp, s, 0, CODA + 2, [(0, 1.9, 0), (2, 1.6, -8)], lo=52, hi=70, vel=46, strum=0.015)
    pt.bass_two(bs, s, 0, A2, vel=76, push=0.25)
    pt.bass_walk(bs, s, A2, A3, vel=72, lo=28, hi=46)
    pt.bass_two(bs, s, A3, CODA + 2, vel=74, push=0.2)
    pt.brush_ballad(dr, s, A1, A2, vel=48)
    pt.brush_swing(dr, s, A2, A3, vel=50, ride=False)
    pt.brush_ballad(dr, s, A3, CODA + 2, vel=46)
    pt.fill(dr, s, A2 - 1, vel=56)
    pt.fill(dr, s, A3 - 1, vel=56)
    pt.pad(st, s, A3, CODA + 3, lo=55, hi=74, n=4, vel=38)
    end = (CODA + 2) * 4
    cp.chord(end, [mc.midi(n) for n in ("g3", "d4", "f4", "bb4", "eb5")], 8, 46, strum=0.07)
    bs.note(end, mc.midi("eb2"), 6, 66)
    return _produce(s, gains={"lead": 0, "keys": -6, "bass": -4, "drums": -1, "pad": -12},
                    sends={"lead": 0.4, "keys": 0.35, "bass": 0.04, "drums": 0.3, "pad": 0.5},
                    eqs={"lead": lambda f: mc.hp_resp(f, 110, 2) * mc.lp_resp(f, 5000, 1),
                         "bass": lambda f: mc.lp_resp(f, 2500, 2) * mc.hp_resp(f, 35, 2)},
                    rev_size=2.6, rev_damp=3800, tape_kw=_tape(), fade_in=0.5)


# --------------------------------------------------------------------------
# 14 "Ore piccole": near-beatless glassy drift, B major/lydian, 52 BPM
# --------------------------------------------------------------------------

OP = ["Bmaj9", "Bmaj9", "Gmaj7#11", "Gmaj7#11", "Emaj9", "Emaj9", "Cmaj7#11", "F#9sus4"]
OP_MEL_1 = "f#5/3 c#6/1 | a#5/4 | b5/3 d6/1 | c#6/4 | g#5/3 b5/1 | f#5/4 | e5/2 g5/2 | c#5/4"
OP_MEL_2 = "d#5/2 f#5/2 | c#6/3 a#5/1 | b5/2 f#5/2 | d5/4 | b4/2 e5/2 | d#5/4 | g5/2 b5/1 e5/1 | b4/4"


def notte_14():
    s = Song("mus_nottefm_14", bpm=52, bpb=4, seed=514)
    bar = 0
    P = []
    for _ in range(4):
        P.append(bar)
        bar = s.chords(bar, OP)
    END = bar
    bar = s.chords(bar, ["Bmaj9", "Bmaj9"])
    N = bar
    pa = s.part("glassA", 92, "pad", vol=100, pan=-0.5, detune=7, drift=6, ht=0.03, hv=3)
    pb = s.part("glassB", 92, "pad", vol=100, pan=0.5, detune=-7, drift=6, ht=0.03, hv=3)
    hi = s.part("halo", 94, "pad2", vol=86, pan=0.2, detune=-4, drift=8, ht=0.05, hv=3)
    sub = s.part("sine", 80, "drone", bank=8, vol=90, detune=-3, drift=3)
    cel = s.part("celesta", 8, "lead", vol=100, pan=-0.15, ht=0.03, hv=5, detune=-4, drift=3)
    mb = s.part("musicbox", 10, "lead2", vol=86, pan=0.25, ht=0.03, hv=4, detune=5, drift=4)
    ar = s.part("crystal", 98, "arp", vol=84, pan=0.35, detune=6, drift=4, ht=0.01, hv=6)
    pt.pad(pa, s, 0, N, lo=52, hi=71, n=4, vel=52, gap=0.0)
    pt.pad(pb, s, 0, N, lo=52, hi=71, n=4, vel=50, gap=0.0)
    pt.pad(hi, s, P[1], END, lo=67, hi=84, n=3, vel=38, gap=0.0)
    for b, d, ch in s.segs(0, N):
        sub.note(b, mc.nearest(ch.bass, 38, 33, 45), d - 0.02, 58)
    pt.arp(ar, s, 0, P[2], lo=66, hi=90, pattern=(0, 2, 4, 1, 3, 2), step=1.5, vel=38, gate=1.4, n=5)
    pt.arp(ar, s, P[3], END, lo=66, hi=90, pattern=(0, 2, 4, 1, 3, 2), step=1.5, vel=34, gate=1.4, n=5)
    cel.melody(P[1], OP_MEL_1, vel=62)
    mb.melody(P[2], OP_MEL_2, vel=52, shift=12)
    cel.melody(P[2], "r/4 | r/2 a#5/2 | r/4 | r/4 | r/4 | r/2 g#5/2 | r/4 | r/4", vel=50)
    cel.melody(P[3], mc.bars(OP_MEL_1, 0, 4) + " | r/4 | r/4 | r/4 | r/4", vel=56)
    cel.melody(END, "f#5/3 a#5/1 | b5/4", vel=50)
    for p in (pa, pb, sub):
        p.ramp(END * 4, N * 4, 11, 127, 0, 0.25)
    return _produce(s, gains={"pad": 0, "pad2": -6, "drone": -5, "lead": 5, "lead2": 4, "arp": -3},
                    sends={"pad": 0.55, "pad2": 0.7, "drone": 0.25, "lead": 0.55, "lead2": 0.6, "arp": 0.6},
                    eqs={"pad": lambda f: mc.hp_resp(f, 110, 2) * mc.lp_resp(f, 6000, 2) * mc.bell_resp(f, 300, -2.5, 0.8),
                         "pad2": lambda f: mc.hp_resp(f, 300, 2) * mc.lp_resp(f, 5000, 2),
                         "drone": lambda f: mc.lp_resp(f, 500, 2) * mc.hp_resp(f, 30, 2),
                         "lead": lambda f: mc.hp_resp(f, 200, 2) * mc.lp_resp(f, 6000, 1),
                         "lead2": lambda f: mc.hp_resp(f, 300, 2) * mc.lp_resp(f, 5500, 1),
                         "arp": lambda f: mc.hp_resp(f, 300, 2) * mc.lp_resp(f, 4000, 2)},
                    fx={"lead": _echo(s, 1.5, fb=0.4, wet=0.35, lp=3000),
                        "arp": _echo(s, 1.0, fb=0.45, wet=0.4, lp=2500)},
                    rev_size=4.5, rev_damp=3500,
                    tape_kw=_tape(lp_hz=8000, wow=0.0026), fade_in=3.0, fade_out=4.0)


TRACKS = {
    f"mus_nottefm_{k:02d}": (lambda fn, k: (lambda: {f"mus_nottefm_{k:02d}": (fn(), False)}))(fn, k)
    for k, fn in ((5, notte_05), (6, notte_06), (7, notte_07), (8, notte_08), (9, notte_09),
                  (10, notte_10), (11, notte_11), (12, notte_12), (13, notte_13), (14, notte_14))
}
