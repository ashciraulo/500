"""Main theme, mission tension stems, stingers and the midnight theme."""
from __future__ import annotations

import numpy as np

import music_core as mc
import music_patterns as pt
from music_core import Song

# --------------------------------------------------------------------------
# mus_main_theme: D major lounge bossa, 96 BPM, 56 bars (140 s) loop
# --------------------------------------------------------------------------

MAIN_INTRO = ["Dmaj7", "Bm9", "Em9", "A13sus4"]
MAIN_A = ["Dmaj7", "Bm7", "Em9", "A13",
          "F#m7", "B7b9", "Em9", "A7sus4 A7",
          "Gmaj7", "Gm6", "F#m7", "B7b9",
          "Em9", "A13", "D69", "Em7 A7"]
MAIN_B = ["Bbmaj7", "Am7 D7", "Gmaj7", "Gm6",
          "F#m7", "B7b9", "Em9", "A7sus4",
          "Bbmaj7", "Cmaj7", "Bm9", "E9",
          "Em9", "Gm6", "Dmaj9", "A13sus4 A7b9"]
MAIN_A2 = MAIN_A[:15] + ["D7"]
MAIN_OUTRO = ["Gmaj7", "Gm6", "Dmaj9", "A13sus4"]

MEL_INTRO = ("r/2 a5/.5 f#5/.5 e5/1 | d5/3 r/1 | r/2 g5/.5 f#5/.5 e5/1 | e5/2 d5/2")
MEL_A = ("r/.5 a4/.5 d5/.5 f#5/1.5 e5/1 | d5/1.5 b4/.5 a4/2 | r/.5 g4/.5 b4/.5 f#5/1.5 e5/1 |"
         " e5/1.5 c#5/.5 f#5/2 |"
         " a5/1.5 f#5/.5 e5/1 c#5/1 | d#5/1.5 c5/.5 b4/1 a4/1 | g5/1.5 f#5/.5 e5/1 b4/1 |"
         " d5/2 c#5/2 |"
         " r/.5 b4/.5 d5/.5 f#5/1.5 a5/1 | a5/1 g5/.5 e5/.5 bb4/2 | a4/1.5 c#5/.5 e5/2 |"
         " d#5/1.5 c5/.5 a4/2 |"
         " g4/.5 b4/.5 d5/.5 f#5/2.5 | e5/1 f#5/.5 e5/.5 c#5/2 | r/.5 b4/.5 d5/3 |"
         " r/2 a4/.5 b4/.5 c#5/.5 e5/.5")
MEL_A2_END = (" g5/1.5 f#5/.5 e5/1 b4/1 | c#5/1 e5/.5 f#5/.5 a5/2 | f#5/4 | r/2 c5/.5 a4/.5 f#4/1")
MEL_B = ("a5/3 f5/1 | e5/2 f#5/1 c5/1 | b4/3 d5/1 | e5/2 d5/1 bb4/1 |"
         " c#5/3 a4/1 | d#5/2 c5/1 b4/1 | f#5/4 | e5/2 d5/1 e5/1 |"
         " f5/1.5 a5/.5 d6/2 | b5/2 g5/1 e5/1 | c#6/2 b5/1 f#5/1 | g#5/2 f#5/1 d5/1 |"
         " g5/1.5 f#5/.5 e5/1 d5/1 | e5/1.5 d5/.5 bb4/2 | a4/1 c#5/.5 e5/2.5 | d5/2 c#5/1 a4/1")
MEL_OUTRO = "b5/3 a5/1 | bb5/2 g5/1 e5/1 | f#5/4 | r/4"


def main_theme(short=False):
    """short=True: intro + A only (20 bars), used as the midnight source."""
    s = Song("mus_main_theme" if not short else "mus_main_short", bpm=96, bpb=4, loop=True,
             seed=101, swing=0.0)
    bar = 0
    bar = s.chords(bar, MAIN_INTRO)      # 0-3
    A = bar
    bar = s.chords(bar, MAIN_A)          # 4-19
    B = bar
    bar = s.chords(bar, MAIN_B)          # 20-35
    A2 = bar
    bar = s.chords(bar, MAIN_A2)         # 36-51
    OUT = bar
    bar = s.chords(bar, MAIN_OUTRO)      # 52-55

    vib = s.part("vibes", 11, "lead", vol=110, pan=-0.15, ht=0.010, hv=7, lag=0.008)
    flu = s.part("flute", 73, "lead", vol=96, pan=0.15, ht=0.012, hv=5, expr=True, lag=0.01)
    whi = s.part("whistle", 78, "lead", vol=92, pan=0.05, ht=0.012, hv=5, expr=True, lag=0.01)
    org = s.part("organ", 16, "keys", vol=80, pan=0.25, ht=0.006, hv=3)
    gtr = s.part("guitar", 24, "gtr", vol=100, pan=-0.35, ht=0.007, hv=6)
    bas = s.part("bass", 32, "bass", vol=110, ht=0.008, hv=5, lag=0.004)
    dr = s.part("drums", 40, "drums", drum=True, vol=100, ht=0.007, hv=5)
    st = s.part("strings", 49, "pad", vol=80, pan=0.3, ht=0.01, hv=3)
    ch = s.part("choir", 53, "pad", vol=70, pan=-0.3, ht=0.01, hv=3)
    vib2 = s.part("vibes2", 11, "keys", vol=80, pan=-0.4, ht=0.01, hv=6)

    # intro
    vib.melody(0, MEL_INTRO, vel=70)
    pt.organ_comp(org, s, 0, 4, vel=48)
    pt.bossa_guitar(gtr, s, 0, 4, vel=50)
    pt.bass_bossa(bas, s, 2, 4, vel=74)
    pt.brush_bossa(dr, s, 0, 2, vel=46, clave=False, kick=False)
    pt.brush_bossa(dr, s, 2, 4, vel=52, clave=False)
    pt.fill(dr, s, 3, vel=58)
    # A
    vib.melody(A, MEL_A, vel=86)
    pt.organ_comp(org, s, A, A + 16, vel=50, style="push")
    pt.bossa_guitar(gtr, s, A, A + 16, vel=56)
    pt.bass_bossa(bas, s, A, A + 16, vel=86)
    pt.brush_bossa(dr, s, A, A + 16, vel=60, clave=False)
    pt.fill(dr, s, A + 15, vel=64)
    if short:
        s.nbars = 20
        s.timeline = [x for x in s.timeline if x[0] < 20 * s.bpb]
        return mc.produce(
            s, gains={"lead": 0, "keys": 1, "gtr": -3, "bass": -4, "drums": -1, "pad": -7},
            sends={"lead": 0.35, "keys": 0.3, "gtr": 0.2, "bass": 0.03, "drums": 0.18, "pad": 0.45},
            rev_size=2.2, return_mix=True)[1], s
    # B: flute takes the tune, strings bloom, vibes arpeggiate
    flu.melody(B, MEL_B, vel=84)
    pt.pad(st, s, B, B + 16, lo=53, hi=72, n=4, vel=50)
    pt.arp(vib2, s, B, B + 16, lo=62, hi=81, pattern=(0, 2, 1, 3, 2, 1, 0, 3), step=0.5, vel=44)
    pt.organ_comp(org, s, B, B + 16, vel=42, style="hold", lo=52, hi=70)
    pt.bossa_guitar(gtr, s, B, B + 16, vel=52)
    pt.bass_bossa(bas, s, B, B + 16, vel=84)
    pt.brush_bossa(dr, s, B, B + 16, vel=58, clave=True)
    pt.fill(dr, s, B + 15, vel=66)
    pt.crash(dr, s, B, vel=46, note=pt.RIDE)
    # A': whistle with vibes an octave below, choir oohs
    a2 = MEL_A.rsplit("|", 4)[0] + "|" + MEL_A2_END
    whi.melody(A2, a2, vel=82)
    vib.melody(A2, a2, vel=62)
    pt.pad(ch, s, A2, A2 + 16, lo=55, hi=72, n=3, vel=46)
    pt.organ_comp(org, s, A2, A2 + 16, vel=46, style="push")
    pt.bossa_guitar(gtr, s, A2, A2 + 16, vel=56)
    pt.bass_bossa(bas, s, A2, A2 + 16, vel=86)
    pt.brush_bossa(dr, s, A2, A2 + 16, vel=62, clave=True)
    pt.fill(dr, s, A2 + 15, vel=60)
    # outro / turnaround into the intro
    vib.melody(OUT, MEL_OUTRO, vel=72)
    pt.pad(st, s, OUT, OUT + 4, lo=53, hi=72, n=4, vel=44)
    pt.organ_comp(org, s, OUT, OUT + 4, vel=46)
    pt.bossa_guitar(gtr, s, OUT, OUT + 4, vel=50)
    pt.bass_bossa(bas, s, OUT, OUT + 4, vel=78)
    pt.brush_bossa(dr, s, OUT, OUT + 4, vel=52, clave=False)

    return mc.produce(
        s,
        gains={"lead": 0, "keys": 1, "gtr": -3, "bass": -4, "drums": -1, "pad": -7},
        sends={"lead": 0.35, "keys": 0.3, "gtr": 0.2, "bass": 0.03, "drums": 0.18, "pad": 0.45},
        rev_size=2.2,
    ), s


# --------------------------------------------------------------------------
# Mission tension: C minor library-crime groove, 120 BPM, 48 bars (96 s).
# Two sample-aligned stems: base groove and an intensity layer.
# --------------------------------------------------------------------------

TEN_A = ["Cm9", "Cm9", "Abmaj7", "G7b9", "Cm9", "Cm9", "Fm9", "G7#9"]
TEN_B = ["Ebmaj7", "Dm7b5 G7b9", "Cm9", "Bbm7 Eb7", "Abmaj7", "Dbmaj7", "G7sus4", "G7b9"]
TEN_TAG = ["Cm9", "Abmaj7", "Dbmaj7", "G7#9"]
TEN_MEL_A = ("r/2 g4/.5 c5/.5 eb5/.5 d5/.5 | c5/2 r/1 bb4/.5 c5/.5 | eb5/1.5 g5/.5 c5/2 |"
             " b4/2 ab4/1 g4/1 | r/2 g4/.5 c5/.5 eb5/.5 f5/.5 | g5/2 f5/.5 eb5/.5 d5/1 |"
             " ab5/1.5 g5/.5 f5/1 c5/1 | d5/1 b4/1 r/2")
TEN_MEL_A2 = ("r/2 g5/.5 c6/.5 eb6/.5 d6/.5 | c6/2 r/1 bb5/.5 c6/.5 | eb6/1.5 g5/.5 c6/2 |"
              " b5/2 ab5/1 g5/1 | r/2 g5/.5 c6/.5 eb6/.5 f6/.5 | g6/2 f6/.5 eb6/.5 d6/1 |"
              " c6/1.5 bb5/.5 ab5/1 f5/1 | d5/1 b4/1 r/2")
TEN_MEL_B = ("g5/3 f5/1 | f5/2 ab5/2 | g5/3 eb5/1 | db5/2 g5/2 | c6/3 bb5/1 | f5/4 |"
             " c5/2 d5/2 | b4/2 ab4/2")


def _tension_kit(d, s, bar0, bar1, vel=70, busy=False):
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for k in range(8):
            d.note(b + k * 0.5, pt.HH, 0.2, vel - 14 + (6 if k % 2 == 0 else 0))
        if busy or (bar - bar0) % 2 == 1:
            d.note(b + 3.75, pt.HH, 0.1, vel - 26)
        d.note(b, pt.KICK, 0.3, vel)
        d.note(b + 0.75, pt.KICK, 0.2, vel - 16)
        d.note(b + 2.5, pt.KICK, 0.3, vel - 6)
        d.note(b + 1, pt.STICK, 0.2, vel - 4)
        d.note(b + 3, pt.STICK, 0.2, vel - 2)
        if (bar - bar0) % 4 == 3:
            d.note(b + 3.5, pt.OHH, 0.4, vel - 16)


def _tension_bass(p, s, bar0, bar1, vel=90):
    prev = None
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for off, iv, dur in ((0, 0, 0.55), (0.75, 0, 0.2), (1.5, 7, 0.4), (2, 12, 0.35),
                             (2.5, 7, 0.3), (3, 0, 0.4)):
            ch = s.chord_at(b + off + 0.01)
            rt = pt._bass_pitch(ch.bass, prev, 28, 43)
            if off == 0:
                prev = rt
            p.note(b + off, rt + iv if iv != 7 else mc.nearest(ch.fifth_pc(), rt + 7, rt, rt + 12),
                   dur, vel - (0 if off in (0, 2.5) else 10))
        nxt = s.chord_at(b + 4.01)
        tgt = pt._bass_pitch(nxt.bass, prev, 28, 43)
        p.note(b + 3.5, tgt - 1 if tgt - 1 != prev else tgt + 1, 0.4, vel - 8)


def mission_tension():
    s = Song("mus_mission_tension", bpm=120, bpb=4, loop=True, seed=202)
    bar = s.chords(0, ["Cm9"] * 4)
    A1 = bar
    bar = s.chords(bar, TEN_A)
    A2 = bar
    bar = s.chords(bar, TEN_A)
    B1 = bar
    bar = s.chords(bar, TEN_B)
    B2 = bar
    bar = s.chords(bar, TEN_B)
    A3 = bar
    bar = s.chords(bar, TEN_A)
    TAG = bar
    bar = s.chords(bar, TEN_TAG)
    N = bar

    # ---- base stems
    dr = s.part("kit", 32, "b_drums", drum=True, vol=100, ht=0.005, hv=5)
    bs = s.part("bass", 33, "b_bass", vol=110, ht=0.005, hv=4)
    rh = s.part("rhodes", 4, "b_keys", vol=96, pan=-0.25, ht=0.006, hv=5)
    tp = s.part("mtrumpet", 59, "b_lead", vol=100, pan=0.1, ht=0.01, hv=5, expr=True, lag=0.006)
    gt = s.part("guitar", 26, "b_keys", vol=86, pan=0.35, ht=0.005, hv=4)
    _tension_kit(dr, s, 0, N, vel=70)
    for b0 in (A1 - 1, B1 - 1, A3 - 1, TAG - 1):
        pt.fill(dr, s, b0, vel=60, kind="kit") if b0 >= 0 else None
    _tension_bass(bs, s, 0, N, vel=92)
    pt.organ_comp(rh, s, 0, N, lo=55, hi=72, n=4, vel=58, style="stabs")
    # muted guitar: octave chops on the offbeats
    for bar in range(0, N):
        b = bar * s.bpb
        ch = s.chord_at(b + 0.01)
        r = mc.nearest(ch.root, 62, 55, 66)
        for off in (0.5, 1.5, 2.5, 3.5):
            gt.chord(b + off, [r, r + 12], 0.15, 54)
    tp.melody(A1, TEN_MEL_A, vel=88)
    tp.melody(B1, TEN_MEL_B, vel=82)
    tp.melody(A3, TEN_MEL_A, vel=86)

    # ---- intensity stems
    st = s.part("trem", 44, "i_strings", vol=100, pan=-0.2, ht=0.01, hv=3)
    st2 = s.part("strmel", 48, "i_strings", vol=100, pan=0.2, ht=0.01, hv=3, expr=True)
    hp = s.part("harpsi", 6, "i_keys", vol=90, pan=0.4, ht=0.004, hv=4)
    br = s.part("brass", 61, "i_brass", vol=100, pan=0.05, ht=0.006, hv=5)
    ti = s.part("timp", 47, "i_brass", vol=110, ht=0.004, hv=3)
    pc = s.part("perc", 0, "i_perc", drum=True, vol=100, ht=0.005, hv=5)
    pt.pad(st, s, 0, N, lo=60, hi=79, n=3, vel=58)
    st2.melody(A2, TEN_MEL_A2, vel=70)
    st2.melody(B2, TEN_MEL_B, vel=74, shift=12)
    pt.arp(hp, s, 0, N, lo=67, hi=86, pattern=(0, 1, 2, 3, 2, 1, 0, 2), step=0.25, vel=48, gate=0.8, accent_every=4)
    pt.latin_perc(pc, s, 0, N, vel=62)
    for bar in range(0, N):
        b = bar * s.bpb
        ch = s.chord_at(b + 0.01)
        v = mc.voicing(ch, 58, 74, 4)
        if bar % 2 == 0:
            br.chord(b, v, 0.5, 74)
        br.chord(b + 2.5, v, 0.3, 64)
        if bar % 4 == 0:
            ti.note(b, mc.nearest(ch.root, 43, 38, 50), 1.5, 86)
            ti.note(b + 3.5, mc.nearest(ch.fifth_pc(), 43, 38, 50), 0.5, 62)
        if bar % 4 == 3:
            for k in range(4):
                pc.note(b + 2 + k * 0.5, pt.TOM_LO if k < 2 else pt.TOM_MID, 0.2, 60 + k * 5)
    pt.crash(pc, s, A2, vel=60)
    pt.crash(pc, s, B2, vel=64)

    stems = mc.render(s)
    e = dict(mc.STEM_EQ)
    base = {k: v for k, v in stems.items() if k.startswith("b_")}
    inten = {k: v for k, v in stems.items() if k.startswith("i_")}
    eq = {"b_bass": e["bass"], "b_keys": e["keys"], "b_lead": e["lead"], "b_drums": e["drums"],
          "i_strings": e["pad"], "i_keys": e["keys"], "i_brass": e["keys"], "i_perc": e["drums"]}
    xb = mc.mix(s, base, {"b_bass": -3, "b_keys": -3, "b_lead": 0, "b_drums": -2},
                {"b_lead": 0.3, "b_keys": 0.25, "b_drums": 0.12, "b_bass": 0.02}, eq, 1.6, 4500, 202)
    xi = mc.mix(s, inten, {"i_strings": -6.5, "i_keys": -2.5, "i_brass": -3.5, "i_perc": -2.5},
                {"i_strings": 0.4, "i_keys": 0.25, "i_brass": 0.3, "i_perc": 0.15}, eq, 1.6, 4500, 202)
    # Shared gains so the two stems keep their mix relationship; the same
    # tape seed gives both identical wow/flutter, so they stay sample-aligned.
    sc = 0.11 / mc.rms(xb)
    yb = mc.tape(xb, seed=202, scale=sc)
    yi = mc.tape(xi, seed=202, scale=sc, hiss_db=-200)
    g = mc.lufs_gain(yb)
    return mc.finish(yb, True, gain=g), mc.finish(yi, True, gain=g), s


# --------------------------------------------------------------------------
# Stingers, D major / D minor like the UI stingers (96 BPM)
# --------------------------------------------------------------------------

def _sting_song(name, seed, bpm=96):
    s = Song(name, bpm=bpm, bpb=4, loop=False, seed=seed)
    s.tail_s = 5.0
    return s


def _sting_produce(s, gains, sends, fade_out=0.6, length=6.0):
    return mc.produce(s, gains=gains, sends=sends, rev_size=2.4,
                      tape_kw={"dropouts": 0.0, "hiss_db": -56}, fade_out=fade_out,
                      length=length)


def sting_complete():
    s = _sting_song("mus_sting_complete", 301)
    s.chords(0, ["A13sus4:1.5 Dmaj9:2.5", "Dmaj9"])
    vib = s.part("vibes", 11, "lead", vol=110, ht=0.004, hv=4)
    flu = s.part("flute", 73, "lead", vol=90, pan=0.2, ht=0.004, hv=3)
    org = s.part("organ", 16, "keys", vol=80, pan=-0.2, ht=0.003, hv=2)
    bas = s.part("bass", 32, "bass", vol=110, ht=0.003)
    dr = s.part("dr", 40, "drums", drum=True, vol=100, ht=0.003)
    vib.melody(0, "a4/.25 b4/.25 d5/.25 e5/.25 f#5/.25 a5/.25 >d6/2.5 | r/4", vel=78)
    flu.melody(0, "r/1.5 a5/2.5 | f#5/3 r/1", vel=74)
    org.chord(0, mc.voicing(mc.Chord("A13sus4"), 57, 74, 4), 1.45, 52)
    org.chord(1.5, mc.voicing(mc.Chord("Dmaj9"), 57, 76, 5), 5.5, 56)
    bas.note(0, mc.midi("a1"), 1.4, 80)
    bas.note(1.5, mc.midi("d2"), 5.0, 92)
    dr.note(0, pt.BR_SWIRL, 1.4, 50)
    dr.note(1.5, pt.KICK, 0.3, 70)
    dr.note(1.5, pt.RIDE, 3, 62)
    dr.note(1.5, pt.BELL, 3, 50)
    return _sting_produce(s, {"lead": 0, "keys": -4, "bass": -5, "drums": -6},
                          {"lead": 0.4, "keys": 0.3, "drums": 0.3, "bass": 0.05}, fade_out=1.2, length=5.5)


def sting_failed():
    s = _sting_song("mus_sting_failed", 302)
    s.chords(0, ["Bbmaj7:1 Gm6:1 A7b9:2", "Dm69"])
    vib = s.part("vibes", 11, "lead", vol=105, ht=0.006, hv=4)
    tp = s.part("mtrumpet", 59, "lead", vol=92, pan=0.15, ht=0.006, hv=3, expr=True)
    org = s.part("organ", 16, "keys", vol=78, pan=-0.2)
    bas = s.part("bass", 32, "bass", vol=110)
    dr = s.part("dr", 40, "drums", drum=True, vol=100)
    tp.melody(0, "f5/1 e5/1 c#5/2 | d5/4", vel=74)
    vib.melody(0, "r/4 | r/.5 a4/.5 f4/.5 e4/.5 d4/2", vel=60)
    org.chord(0, mc.voicing(mc.Chord("Bbmaj7"), 53, 70, 4), 0.95, 50)
    org.chord(1, mc.voicing(mc.Chord("Gm6"), 53, 70, 4), 0.95, 48)
    org.chord(2, mc.voicing(mc.Chord("A7b9"), 53, 70, 4), 1.95, 50)
    org.chord(4, mc.voicing(mc.Chord("Dm69"), 50, 67, 4), 4, 46)
    bas.melody(0, "bb1/1 g1/1 a1/2 | d1/4", vel=86, stacc=0.95)
    dr.note(0, pt.BR_SWIRL, 1, 44)
    dr.note(4, pt.KICK, 0.3, 54)
    dr.note(4, pt.BR_SWIRL, 2, 40)
    return _sting_produce(s, {"lead": 0, "keys": -4, "bass": -5, "drums": -8},
                          {"lead": 0.4, "keys": 0.35, "drums": 0.3, "bass": 0.05}, fade_out=1.5, length=6.5)


def sting_tier_unlock():
    s = _sting_song("mus_sting_tier_unlock", 303, bpm=120)
    s.chords(0, ["Dmaj7:2 Gmaj7:2", "A13sus4:2 D69:2", "D69"])
    harp = s.part("harp", 46, "keys", vol=105, pan=-0.2, ht=0.002, hv=3)
    cel = s.part("celesta", 8, "lead", vol=100, pan=0.2, ht=0.004, hv=3)
    vib = s.part("vibes", 11, "lead", vol=100, ht=0.004, hv=4)
    st = s.part("strings", 49, "pad", vol=100)
    bas = s.part("bass", 32, "bass", vol=110)
    # rising harp arpeggios through the progression
    pt.arp(harp, s, 0, 2, lo=50, hi=88, pattern=(0, 1, 2, 3, 4, 5, 6, 7), step=0.25, n=4, vel=62, gate=3)
    harp.chord(8, [62, 66, 69, 71, 76, 78, 81], 4, 58, strum=0.06)
    cel.melody(0, "r/2 b5/1 d6/1 | e6/2 f#6/2 | a6/4", vel=70)
    vib.melody(0, "r/4 | r/2 a5/1 b5/1 | f#5/4", vel=64)
    pt.pad(st, s, 0, 3, lo=55, hi=76, n=4, vel=58, swell=True)
    bas.melody(0, "d2/2 g1/2 | a1/2 d2/2 | d2/4", vel=84, stacc=0.95)
    return _sting_produce(s, {"lead": 0, "keys": -3, "pad": -6, "bass": -6},
                          {"lead": 0.45, "keys": 0.35, "pad": 0.5, "bass": 0.05}, fade_out=1.8, length=7.5)


def sting_new_car():
    s = _sting_song("mus_sting_new_car", 304, bpm=120)
    s.chords(0, ["Dmaj7", "Em9:2 A13:2", "Dmaj9"])
    vib = s.part("vibes", 11, "lead", vol=110, pan=-0.1, ht=0.006, hv=4)
    whi = s.part("whistle", 78, "lead", vol=88, pan=0.1, ht=0.008, hv=3, expr=True)
    org = s.part("organ", 16, "keys", vol=80, pan=0.25)
    gtr = s.part("guitar", 24, "gtr", vol=100, pan=-0.35)
    bas = s.part("bass", 32, "bass", vol=110)
    dr = s.part("dr", 40, "drums", drum=True, vol=100)
    mel = "r/.5 a4/.5 d5/.5 f#5/1.5 e5/1 | g5/1.5 f#5/.5 e5/1 c#5/1 | d5/4"
    vib.melody(0, mel, vel=84)
    whi.melody(0, mel, vel=70, shift=12)
    pt.organ_comp(org, s, 0, 3, vel=48)
    pt.bossa_guitar(gtr, s, 0, 2, vel=52)
    gtr.chord(8, mc.voicing(mc.Chord("Dmaj9"), 52, 71, 5), 4, 50, strum=0.05)
    pt.bass_bossa(bas, s, 0, 2, vel=82)
    bas.note(8, mc.midi("d2"), 4, 86)
    pt.brush_bossa(dr, s, 0, 2, vel=56, clave=False)
    dr.note(8, pt.KICK, 0.3, 66)
    dr.note(8, pt.RIDE, 3, 58)
    return _sting_produce(s, {"lead": 0, "keys": -2, "gtr": -4, "bass": -4, "drums": -4},
                          {"lead": 0.35, "keys": 0.3, "gtr": 0.2, "drums": 0.2, "bass": 0.03}, fade_out=2.0, length=8.0)


# --------------------------------------------------------------------------
# Midnight theme: the main theme's intro + A, slowed to 80 %, warped and
# partly reversed. 20 source bars -> 62.5 s seamless loop (76.8 BPM).
# --------------------------------------------------------------------------

def midnight_theme():
    src, s = main_theme(short=True)  # circular pre-tape mix, 50 s
    # drop the drums' brightness a little: simply dull the whole source
    src = mc.fft_eq(src, lambda f: mc.lp_resp(f, 5000, 2))
    n = len(src)
    m = int(round(n * 1.25))
    # circular FFT resample = tape slowed to 80 % (pitch down ~3.9 semitones)
    from scipy import signal as sg
    y = sg.resample(src, m, axis=0)
    bar = m // 20
    # reverse a few bars (crossfaded), like a tape flipped mid-reel
    xf = int(0.08 * mc.SR)
    w = np.sin(np.linspace(0, np.pi / 2, xf))[:, None] ** 2
    for b0, nb in ((6, 2), (13, 1), (17, 2)):
        a, e = b0 * bar, (b0 + nb) * bar
        seg = y[a:e][::-1].copy()
        new = y.copy()
        new[a:e] = seg
        # crossfade in and out of the reversed chunk
        new[a:a + xf] = y[a:a + xf] * (1 - w) + seg[:xf] * w
        new[e - xf:e] = seg[-xf:] * (1 - w) + y[e - xf:e] * w
        y = new
    # reverse-reverb swells: reverb the reversed signal, reverse back
    irs = mc.make_ir(3.5, 2500, seed=9)
    sw = mc.conv_circ(y[::-1].copy(), irs)[::-1]
    y = y + 0.35 * sw
    y = y + 0.4 * mc.conv_circ(y, mc.make_ir(4.0, 3000, seed=10))
    out = mc.tape(y, seed=909, age=3.0, wow=0.0028, lp_hz=6500, hiss_db=-46, drive=1.6,
                  width=0.6, dropouts=2.0, bump_db=3.0)
    return mc.finish(out, True)
