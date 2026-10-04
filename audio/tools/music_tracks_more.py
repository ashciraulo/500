"""Radio Cinquecento (day), Notte FM (night), home, time trial, storm and
midnight pieces."""
from __future__ import annotations

import numpy as np

import music_core as mc
import music_patterns as pt
from music_core import Song

MANDOLIN = dict(program=25, bank=16)
ACCORDION = dict(program=21, bank=8)

# --------------------------------------------------------------------------
# Cinquecento 01 "Passeggiata": G major, 108 BPM light swing, mandolin lead
# --------------------------------------------------------------------------

C1_INTRO = ["Gmaj7", "Em7", "Am7", "D7"]
C1_A = ["Gmaj7", "Em7", "Am7", "D7", "Bm7", "E7b9", "Am9", "D7sus4 D7",
        "Gmaj7", "G7", "Cmaj7", "Cm6", "Bm7", "E7", "Am7 D7", "G6"]
C1_B = ["Em9", "B7b9", "Em9", "A9", "Am7", "D7", "Gmaj7", "E7b9",
        "Am9", "Cm6", "Bm7", "Bbdim7", "Am7", "D7sus4", "D7", "D7b9"]
C1_CODA = ["Cmaj7", "Cm6", "Bm7", "E7b9", "Am9", "D7b9", "Gmaj9", "Gmaj9"]
C1_MEL_A = ("d5/1 g5/1 f#5/1 d5/1 | e5/1.5 g5/.5 b4/2 | c5/1 e5/1 a5/1 g5/1 | f#5/3 r/1 |"
            " d5/1 f#5/1 a5/1 f#5/1 | g#5/1.5 f5/.5 d5/2 | c5/1 b4/1 a4/1 e5/1 | g4/2 f#4/2 |"
            " d5/1 g5/1 b5/1 a5/1 | f5/2 d5/1 b4/1 | e5/1.5 g5/.5 b5/2 | a5/1.5 g5/.5 eb5/2 |"
            " d5/1 f#5/1 b5/1 a5/1 | g#5/2 e5/1 d5/1 | c5/1 e5/1 d5/1 c5/1 | b4/3 r/1")
C1_MEL_A_END = " d5/1 f#5/1 b5/1 a5/1 | g#5/2 e5/1 d5/1 | c5/1 e5/1 a5/1 f#5/1 | g5/3 r/1"
C1_MEL_B = ("g5/2 f#5/1 e5/1 | d#5/2 c5/1 b4/1 | e5/1 f#5/1 g5/1 b5/1 | c#6/3 b5/1 |"
            " c6/2 b5/1 a5/1 | f#5/2 e5/1 c5/1 | d5/3 b4/1 | g#4/2 b4/1 d5/1 |"
            " e5/1.5 c5/.5 a4/2 | g4/1 a4/1 c5/1 eb5/1 | d5/3 b4/1 | c#5/2 e5/2 |"
            " g5/2 e5/1 c5/1 | d5/4 | c5/2 a4/1 f#4/1 | eb5/1 c5/1 a4/1 f#4/1")
C1_MEL_CODA = ("e5/1.5 g5/.5 b5/2 | a5/1.5 g5/.5 eb5/2 | d5/1 f#5/1 a5/1 d6/1 | b5/2 g#5/2 |"
               " c6/2 b5/1 a5/1 | f#5/2 eb5/2 | d5/4 | r/4")


def cinquecento_01(storm=False):
    name = "mus_storm_01" if storm else "mus_cinquecento_01"
    bpm = 90 if storm else 108
    s = Song(name, bpm=bpm, bpb=4, loop=False, seed=401 + (50 if storm else 0), swing=0.0 if storm else 0.22)
    bar = s.chords(0, C1_INTRO)
    A1 = bar
    bar = s.chords(bar, C1_A)
    B1 = bar
    bar = s.chords(bar, C1_B)
    A2 = bar
    bar = s.chords(bar, C1_A)
    INT = bar
    bar = s.chords(bar, C1_A[:8])   # accordion interlude, half chorus
    A3 = bar
    bar = s.chords(bar, C1_A[:12])
    CODA = bar
    bar = s.chords(bar, C1_CODA)
    sh = -5 if storm else 0  # storm: down a fourth to D major-ish, darker

    if storm:
        man = s.part("lead", 24, "lead", vol=100, pan=-0.1, ht=0.012, hv=5)  # nylon, low
        acc = s.part("acc", 71, "lead2", vol=90, pan=0.2, ht=0.012, hv=4, expr=True)  # clarinet
    else:
        man = s.part("mandolin", MANDOLIN["program"], "lead", bank=16, vol=104, pan=-0.12, ht=0.010, hv=6)
        acc = s.part("accordion", ACCORDION["program"], "lead2", bank=8, vol=88, pan=0.22, ht=0.010, hv=4)
    gtr = s.part("guitar", 24, "gtr", vol=100, pan=-0.35, ht=0.007, hv=5)
    bas = s.part("bass", 32, "bass", vol=110, ht=0.008, hv=5)
    dr = s.part("drums", 40, "drums", drum=True, vol=100, ht=0.008, hv=5)
    org = s.part("organ", 16 if not storm else 19, "keys", vol=74, pan=0.3, ht=0.008, hv=3)
    if storm:
        pad = s.part("pad", 89, "pad", vol=90, drift=6, detune=-4)
    else:
        pad = s.part("strings", 48, "pad", vol=80, pan=0.25)

    trem = 1 / 6 if not storm else 0.0
    tv = 0 if not storm else -12
    bars = mc.bars
    # intro: accordion vamp over guitar
    acc.melody(0, "r/2 d5/1 b4/1 | g4/2 r/2 | r/2 c5/1 e5/1 | f#5/3 r/1", vel=62 + tv)
    # A: mandolin tune over a two-feel
    man.melody(A1, C1_MEL_A, vel=84 + tv, tremolo=trem, trem_min=1.0)
    # B: accordion takes the tune, mandolin tremolo chords behind
    acc.melody(B1, C1_MEL_B, vel=76 + tv)
    # A2: mandolin again with a new ending
    man.melody(A2, bars(C1_MEL_A, 0, 12) + " | " + C1_MEL_A_END, vel=86 + tv, tremolo=trem, trem_min=1.0)
    # interlude: accordion plays the first half; then mandolin, then the coda
    acc.melody(INT, bars(C1_MEL_A, 0, 8), vel=74 + tv)
    man.melody(A3, bars(C1_MEL_A, 0, 12), vel=82 + tv, tremolo=trem, trem_min=1.0)
    man.melody(CODA, C1_MEL_CODA, vel=80 + tv, tremolo=trem, trem_min=1.0)

    # rhythm section (transposition applies to chords via shifting pitches)
    for b0, b1, walk in ((0, A1, False), (A1, B1, False), (B1, A2, True), (A2, INT, True),
                         (INT, A3, False), (A3, CODA, True), (CODA, CODA + 6, False)):
        if walk and not storm:
            pt.bass_walk(bas, s, b0, b1, vel=82)
        else:
            pt.bass_two(bas, s, b0, b1, vel=82, push=0.4)
        if storm:
            pt.brush_ballad(dr, s, max(b0, A1), b1, vel=44) if b1 > A1 else None
        else:
            if b0 >= A1:
                pt.brush_swing(dr, s, b0, b1, vel=58, ride=(b0 in (B1, A3)))
    # guitar: four-to-the-bar soft chords ("Freddie Green" style) / storm: sparse
    prev = None
    for b, d, ch in s.segs(0, CODA + 6):
        v = mc.voicing(ch, 50, 67, 4, prev, root=True)
        prev = v
        if storm:
            gtr.chord(b, v, d - 0.1, 46, strum=0.04)
        else:
            k = 0
            t = b
            while t < b + d - 1e-6:
                gtr.chord(t, v, 0.6, 50 + (6 if k % 2 == 1 else 0), strum=0.006)
                t += 1
                k += 1
    pt.organ_comp(org, s, B1, A2, lo=55, hi=72, vel=40)
    pt.organ_comp(org, s, CODA, CODA + 8, lo=55, hi=72, vel=42)
    pt.pad(pad, s, A2, INT, lo=55, hi=74, n=4, vel=44 if not storm else 52)
    if storm:
        pt.pad(pad, s, 0, CODA + 8, lo=50, hi=70, n=4, vel=50)
    pt.tremolo_chord(man, s, B1, A2, lo=62, hi=79, n=2, vel=40 + tv, rate=trem or 0.5)
    pt.tremolo_chord(man, s, INT, A3, lo=62, hi=79, n=2, vel=40 + tv, rate=trem or 0.5)
    # final chord
    end = (CODA + 6) * s.bpb
    acc.chord(end, [mc.midi("b4"), mc.midi("d5"), mc.midi("f#5")], 6, 54 + tv)
    bas.note(end, mc.midi("g1"), 6, 80)
    dr.note(end, pt.RIDE, 4, 50)
    dr.note(end, pt.KICK, 0.4, 56)
    mc.transpose(s, sh)
    gains = {"lead": 0, "lead2": -2, "gtr": -6, "bass": -4, "drums": 1, "keys": 1, "pad": -6}
    tape_kw = {}
    if storm:
        gains.update({"drums": -6, "pad": -3, "lead": -1})
        tape_kw = {"lp_hz": 7000, "age": 1.6, "hiss_db": -48, "bump_db": 3}
    return mc.produce(s, gains=gains,
                      sends={"lead": 0.35, "lead2": 0.35, "gtr": 0.18, "bass": 0.03, "drums": 0.2,
                             "keys": 0.3, "pad": 0.5},
                      rev_size=2.0 if not storm else 3.2, tape_kw=tape_kw)


TRACKS = {
    "mus_cinquecento_01": lambda: {"mus_cinquecento_01": (cinquecento_01(), False)},
}


# --------------------------------------------------------------------------
# Cinquecento 02 "Spiaggia": A minor bossa, 132 BPM, wordless voice + flute
# --------------------------------------------------------------------------

C2_A = ["Am9", "Am9", "Dm9", "G13", "Cmaj7", "Fmaj7#11", "Bm7b5", "E7b9",
        "Am9", "Am7/G", "F#m7b5", "Fmaj7", "Bm7b5", "E7b9", "Am9", "E7#9"]
C2_B = ["Fmaj7", "Fm6", "Em7", "A7b9", "Dm9", "G13", "Cmaj7", "E7b9"]
C2_MEL_A = ("e5/3 c5/1 | b4/4 | r/1 a4/1 c5/1 e5/1 | f5/3 e5/1 |"
            " g5/3 e5/1 | b5/2 a5/1 g5/1 | a5/2 f5/1 d5/1 | f5/2 e5/1 d5/1 |"
            " c5/3 b4/1 | r/.5 a4/.5 c5/.5 e5/1 g5/1.5 | a5/2 f#5/1 e5/1 | e5/3 c5/1 |"
            " d5/2 f5/1 a5/1 | g#5/2 f5/1 d5/1 | e5/1 b4/1 c5/2 | g5/2 e5/1 r/1")
C2_MEL_B = ("a5/2 g5/1 e5/1 | ab5/2 f5/1 d5/1 | g5/2 e5/1 b4/1 | c#5/2 bb4/2 |"
            " f5/1.5 e5/.5 c5/2 | e5/1.5 d5/.5 b4/2 | e5/4 | d5/2 b4/1 g#4/1")


def cinquecento_02():
    s = Song("mus_cinquecento_02", bpm=132, bpb=4, loop=False, seed=402)
    bar = s.chords(0, ["Am9", "Dm9", "Am9", "E7#9"])
    secs = []
    for name, prog in (("A", C2_A), ("B", C2_B), ("A", C2_A), ("B", C2_B), ("A", C2_A)):
        secs.append((name, bar))
        bar = s.chords(bar, prog)
    CODA = bar
    bar = s.chords(bar, ["Fmaj7", "E7b9", "Am9", "Am9"])
    voc = s.part("voice", 53, "lead", vol=112, pan=-0.05, ht=0.012, hv=4, expr=True, lag=0.012)
    flu = s.part("flute", 73, "lead2", vol=100, pan=0.18, ht=0.012, hv=5, expr=True, lag=0.008)
    gtr = s.part("guitar", 24, "gtr", vol=105, pan=-0.3, ht=0.006, hv=6)
    bas = s.part("bass", 32, "bass", vol=110, ht=0.006, hv=5)
    dr = s.part("drums", 40, "drums", drum=True, vol=100, ht=0.006, hv=5)
    ep = s.part("rhodes", 4, "keys", vol=86, pan=0.3, ht=0.008, hv=4)
    st = s.part("strings", 49, "pad", vol=84, pan=0.2)
    pt.bossa_guitar(gtr, s, 0, bar, vel=56)
    pt.bass_bossa(bas, s, 2, bar, vel=84)
    pt.brush_bossa(dr, s, 0, 4, vel=48, clave=True, kick=False)
    pt.brush_bossa(dr, s, 4, CODA, vel=58, clave=True)
    pt.brush_bossa(dr, s, CODA, CODA + 3, vel=50, clave=True, kick=False)
    for k, (name, b0) in enumerate(secs):
        if name == "A":
            if k == 4:
                flu.melody(b0, C2_MEL_A, vel=82)
                pt.pad(st, s, b0, b0 + 16, lo=55, hi=74, n=3, vel=44)
            else:
                voc.melody(b0, C2_MEL_A, vel=84)
            pt.fill(dr, s, b0 + 15, vel=60)
        else:
            (flu if k == 3 else voc).melody(b0, C2_MEL_B, vel=82)
            if k == 3:
                pt.pad(st, s, b0, b0 + 8, lo=55, hi=74, n=4, vel=46)
            pt.fill(dr, s, b0 + 7, vel=60)
        # rhodes: soft held chords, a little push on the B sections
        pt.organ_comp(ep, s, b0, b0 + (16 if name == "A" else 8), lo=57, hi=74, vel=42,
                      style="hold" if name == "A" else "push")
    voc.melody(CODA, "a5/2 g5/1 e5/1 | f5/2 e5/1 d5/1 | e5/4 | r/4", vel=74)
    end = (CODA + 3) * s.bpb
    gtr.chord(end, mc.voicing(mc.Chord("Am9"), 52, 71, 5), 4, 50, strum=0.08)
    bas.note(end, mc.midi("a1"), 4, 76)
    dr.note(end, pt.RIDE, 3, 46)
    return mc.produce(s, gains={"lead": 0, "lead2": -1, "gtr": -3, "bass": -4, "drums": 0, "keys": -3, "pad": -6},
                      sends={"lead": 0.45, "lead2": 0.35, "gtr": 0.2, "bass": 0.03, "drums": 0.2, "keys": 0.3, "pad": 0.5},
                      rev_size=2.4)


# --------------------------------------------------------------------------
# Cinquecento 03 "Autostrada": E dorian library funk, 100 BPM, Rhodes lead
# --------------------------------------------------------------------------

C3_A = ["Em9", "Em9", "A9", "A9", "Em9", "Em9", "A13", "A7#9"]
C3_B = ["Cmaj7", "Bm7", "Am9", "D9", "Gmaj7", "F#m7b5 B7b9", "Em9", "Em9"]
C3_MEL_A = ("r/1 b4/.5 d5/.5 e5/.5 g5/1 e5/.5 | f#5/1.5 e5/.5 d5/1 b4/1 |"
            " r/1 c#5/.5 e5/.5 g5/.5 a5/1 g5/.5 | f#5/1.5 e5/.5 c#5/1 r/1 |"
            " r/1 b4/.5 d5/.5 e5/.5 g5/1 b5/.5 | a5/1.5 g5/.5 f#5/1 d5/1 |"
            " e5/1 f#5/.5 g5/.5 c#6/2 | c6/1 b5/.5 g5/.5 e5/2")
C3_MEL_B = ("e5/1.5 g5/.5 b5/2 | a5/1.5 f#5/.5 d5/2 | c5/1 e5/1 g5/1 b5/1 | a5/2 f#5/1 e5/1 |"
            " d5/1.5 f#5/.5 b5/2 | a5/1 c5/1 d#5/1 a4/1 | b4/1 e5/1 f#5/1 g5/1 | f#5/2 r/2")


def cinquecento_03():
    s = Song("mus_cinquecento_03", bpm=100, bpb=4, loop=False, seed=403)
    bar = s.chords(0, ["Em9"] * 4)
    plan = []
    for name, prog in (("A", C3_A), ("A2", C3_A), ("B", C3_B), ("A", C3_A), ("BRK", ["Em9"] * 8),
                       ("A2", C3_A), ("B", C3_B), ("A", C3_A)):
        plan.append((name, bar))
        bar = s.chords(bar, prog)
    END = bar
    bar = s.chords(bar, ["Em9", "Em9"])
    rh = s.part("rhodes", 4, "lead", vol=110, pan=-0.1, ht=0.006, hv=6)
    org = s.part("organ", 17, "lead2", vol=90, pan=0.2, ht=0.006, hv=4)
    fl = s.part("flute", 73, "lead2", vol=92, pan=0.3, ht=0.01, hv=4, expr=True)
    wah = s.part("wah", 28, "gtr", bank=8, vol=96, pan=-0.4, ht=0.004, hv=6)
    clv = s.part("clav", 7, "keys", vol=84, pan=0.4, ht=0.004, hv=5)
    bas = s.part("bass", 33, "bass", vol=112, ht=0.004, hv=5)
    dr = s.part("kit", 8, "drums", drum=True, vol=100, ht=0.004, hv=5)
    pc = s.part("perc", 8, "drums", drum=True, vol=100, ht=0.006, hv=5)
    # intro: drums + bass, then guitar
    pt.kit_funk(dr, s, 0, END, vel=74)
    pt.bass_funk(bas, s, 0, END, vel=92)
    for k, (name, b0) in enumerate(plan):
        L = 8
        if name == "A":
            rh.melody(b0, C3_MEL_A, vel=88)
        elif name == "A2":
            rh.melody(b0, C3_MEL_A, vel=84)
            if k > 4:
                fl.melody(b0, C3_MEL_A, vel=66, shift=12)
        elif name == "B":
            org.melody(b0, C3_MEL_B, vel=82)
            pt.latin_perc(pc, s, b0, b0 + L, vel=56)
        elif name == "BRK":
            # breakdown: bongos and flute improvisation over the vamp
            pt.latin_perc(pc, s, b0, b0 + L, vel=58)
            pt.sparse_melody(fl, s, b0, b0 + L, lo=67, hi=86, density=0.55, vel=70,
                             durs=(0.5, 0.5, 1, 1.5, 0.75))
        pt.fill(dr, s, b0 + L - 1, vel=70, kind="kit")
        pt.crash(dr, s, b0, vel=62)
    # wah guitar chicken-scratch and clav stabs throughout (after the intro)
    for bar in range(2, END):
        b = bar * s.bpb
        ch = s.chord_at(b + 0.01)
        v = mc.voicing(ch, 55, 70, 3, root=True)
        for k in range(16):
            off = k * 0.25
            if k in (2, 6, 7, 10, 14):
                wah.chord(b + off, v, 0.12, 64 + (8 if k in (6, 14) else 0), strum=0.004)
            elif k % 2 == 1:
                wah.note(b + off, v[0], 0.06, 30)
        if bar >= 4:
            v2 = mc.voicing(ch, 60, 76, 3)
            for off in (0.5, 1.75, 2.5):
                clv.chord(b + off, v2, 0.18, 58)
    end = END * s.bpb
    rh.chord(end, mc.voicing(mc.Chord("Em9"), 52, 74, 5), 6, 70)
    bas.note(end, mc.midi("e1"), 4, 90)
    dr.note(end, pt.CRASH, 4, 70)
    dr.note(end, pt.KICK, 0.3, 80)
    return mc.produce(s, gains={"lead": 0, "lead2": -1, "gtr": -9, "keys": -9, "bass": -3, "drums": -3},
                      sends={"lead": 0.25, "lead2": 0.3, "gtr": 0.12, "keys": 0.15, "bass": 0.02, "drums": 0.12},
                      rev_size=1.6, eqs={"gtr": lambda f: mc.hp_resp(f, 250, 2) * mc.bell_resp(f, 1200, 4, 1.2)})


# --------------------------------------------------------------------------
# Cinquecento 04 "Valzer del Molo": F major musette waltz, 132 BPM, accordion
# --------------------------------------------------------------------------

C4_INTRO = ["F", "F", "C7", "C7", "C7", "C7", "F", "F"]
C4_A = ["F", "Fmaj7", "Gm7", "C7", "Gm7", "C7", "F", "F6",
        "F7", "Bb", "Bbm6", "F", "D7", "G9", "C7", "F"]
C4_B = ["Dm", "Dm", "A7", "A7", "A7b9", "A7b9", "Dm", "Dm",
        "Gm", "Gm", "Dm", "Dm", "Em7b5", "A7b9", "Dm", "C7"]
C4_CODA = ["Bb", "Bbm6", "F/C", "D7", "Gm7", "C7", "F", "F"]
C4_MEL_A = ("c5/1 f5/1 a5/1 | g5/2 e5/1 | f5/1 d5/1 bb4/1 | c5/1 e5/1 g5/1 |"
            " bb5/2 a5/1 | g5/1 e5/1 c5/1 | a5/2 g5/1 | f5/3 |"
            " c5/1 eb5/1 a5/1 | d6/2 c6/1 | db6/2 bb5/1 | a5/3 |"
            " f#5/1 a5/1 c6/1 | b5/2 a5/1 | g5/1 bb5/1 e5/1 | f5/2 r/1")
C4_MEL_B = ("a5/1 f5/1 d5/1 | e5/2 f5/1 | g5/2 e5/1 | c#5/3 |"
            " e5/1 g5/1 bb5/1 | a5/2 g5/1 | f5/1 e5/1 d5/1 | a4/3 |"
            " bb4/1 d5/1 g5/1 | a5/2 g5/1 | f5/2 e5/1 | d5/3 |"
            " g5/1 bb5/1 d6/1 | c#6/2 bb5/1 | d6/1 a5/1 f5/1 | e5/1 g5/1 bb5/1")
C4_MEL_CODA = "d6/2 c6/1 | db6/2 bb5/1 | a5/3 | f#5/1 a5/1 c6/1 | bb5/2 a5/1 | g5/1 e5/1 c5/1 | f5/3 | r/3"


def cinquecento_04():
    s = Song("mus_cinquecento_04", bpm=132, bpb=3, loop=False, seed=404)
    bar = s.chords(0, C4_INTRO)
    A1 = bar; bar = s.chords(bar, C4_A)
    A2 = bar; bar = s.chords(bar, C4_A)
    B1 = bar; bar = s.chords(bar, C4_B)
    B2 = bar; bar = s.chords(bar, C4_B)
    A3 = bar; bar = s.chords(bar, C4_A)
    CODA = bar; bar = s.chords(bar, C4_CODA)
    acc = s.part("accordion", 21, "lead", bank=8, vol=104, pan=-0.05, ht=0.008, hv=5)
    vln = s.part("violin", 40, "lead2", vol=96, pan=0.2, ht=0.012, hv=4, expr=True, lag=0.01)
    man = s.part("mandolin", 25, "lead2", bank=16, vol=90, pan=-0.25, ht=0.008, hv=5)
    gtr = s.part("guitar", 24, "gtr", vol=100, pan=0.3, ht=0.006, hv=5)
    bas = s.part("bass", 32, "bass", vol=110, ht=0.006, hv=4)
    dr = s.part("drums", 40, "drums", drum=True, vol=100, ht=0.006, hv=4)
    accomp = s.part("acc_chords", 21, "keys", bank=8, vol=80, pan=0.15, ht=0.006, hv=4)
    pt.bass_waltz(bas, s, 0, CODA + 7, vel=84)
    pt.strum_waltz(gtr, s, 0, CODA + 7, vel=52)
    pt.brush_waltz(dr, s, 4, CODA + 7, vel=56)
    pt.tremolo_chord(man, s, 0, 8, lo=62, hi=77, n=2, vel=44, rate=1 / 4)
    acc.melody(A1, C4_MEL_A, vel=84)
    vln.melody(A2, C4_MEL_A, vel=80)
    pt.strum_waltz(accomp, s, A2, B1, lo=60, hi=76, n=3, vel=44)
    acc.melody(B1, C4_MEL_B, vel=82)
    vln.melody(B2, C4_MEL_B, vel=78)
    pt.strum_waltz(accomp, s, B2, A3, lo=60, hi=76, n=3, vel=44)
    acc.melody(A3, C4_MEL_A, vel=86)
    man.melody(A3, C4_MEL_A, vel=66, tremolo=1 / 4, trem_min=1.0, shift=12)
    acc.melody(CODA, C4_MEL_CODA, vel=80)
    vln.melody(CODA, C4_MEL_CODA, vel=64, shift=-12)
    end = (CODA + 7) * s.bpb
    acc.chord(end, [mc.midi(n) for n in ("a4", "c5", "f5")], 5, 66)
    bas.note(end, mc.midi("f1"), 5, 80)
    gtr.chord(end, mc.voicing(mc.Chord("F6"), 52, 71, 4), 5, 50, strum=0.06)
    return mc.produce(s, gains={"lead": 0, "lead2": -2, "gtr": -5, "bass": -4, "drums": -1, "keys": -6},
                      sends={"lead": 0.3, "lead2": 0.35, "gtr": 0.2, "bass": 0.03, "drums": 0.2, "keys": 0.25},
                      rev_size=1.8,
                      eqs={"lead": lambda f: mc.hp_resp(f, 150, 2) * mc.bell_resp(f, 3000, -5, 0.7) * mc.lp_resp(f, 6500, 2),
                           "lead2": lambda f: mc.hp_resp(f, 150, 2) * mc.bell_resp(f, 3000, -4, 0.7) * mc.lp_resp(f, 7000, 2),
                           "keys": lambda f: mc.hp_resp(f, 150, 2) * mc.bell_resp(f, 3000, -4, 0.7)})


# --------------------------------------------------------------------------
# Cinquecento 05 "Ballata": Eb major slow ballad, 72 BPM, piano lead
# --------------------------------------------------------------------------

C5_A = ["Ebmaj7", "Cm9", "Fm9", "Bb13", "Gm7", "C7b9", "Fm9", "Bb7sus4 Bb7"]
C5_A2 = ["Ebmaj7", "Cm9", "Fm9", "Bb13", "Abmaj7", "Abm6", "Gm7 C7b9", "Fm9 Bb7"]
C5_B = ["Abmaj7", "Gm7", "Fm9", "Ebmaj7", "Dbmaj7", "C7b9", "Fm9", "Bb13sus4 Bb7b9"]
C5_MEL_A = ("g5/1.5 f5/.5 eb5/1 bb4/1 | d5/2 c5/1 g4/1 | ab4/1 c5/1 g5/1.5 f5/.5 | d5/1 g5/3 |"
            " bb5/1.5 g5/.5 f5/1 d5/1 | e5/1.5 db5/.5 bb4/2 | c5/1 eb5/1 g5/1 ab5/1 | f5/2 d5/2")
C5_MEL_A2_END = (" c6/1.5 bb5/.5 g5/2 | b5/1.5 ab5/.5 f5/2 | d5/1 f5/1 e5/1 db5/1 | c5/1 g5/1 f5/2")
C5_MEL_B = ("eb5/1 g5/1 c6/2 | bb5/2 f5/2 | ab5/1.5 g5/.5 f5/1 c5/1 | d5/1 eb5/1 g5/2 |"
            " f5/1.5 ab5/.5 c6/2 | bb5/1.5 g5/.5 e5/2 | g5/1.5 ab5/.5 c6/2 | eb6/2 d6/1 b5/1")
C5_MEL_CODA = "c6/2 bb5/1 g5/1 | b5/2 ab5/1 f5/1 | g5/4 | r/4"


def cinquecento_05():
    s = Song("mus_cinquecento_05", bpm=72, bpb=4, loop=False, seed=405)
    bar = s.chords(0, ["Abmaj7", "Bb13sus4"])
    A1 = bar; bar = s.chords(bar, C5_A)
    A2 = bar; bar = s.chords(bar, C5_A2)
    B1 = bar; bar = s.chords(bar, C5_B)
    A3 = bar; bar = s.chords(bar, C5_A2[:7] + ["Fm9 Bb13"])
    CODA = bar; bar = s.chords(bar, ["Abmaj7", "Abm6", "Ebmaj9", "Ebmaj9"])
    pno = s.part("piano", 0, "lead", vol=110, ht=0.014, hv=6)
    lh = s.part("piano_lh", 0, "keys", vol=96, ht=0.014, hv=5)
    cel = s.part("celesta", 8, "lead2", vol=86, pan=0.3, ht=0.01, hv=4)
    st = s.part("strings", 49, "pad", vol=90, pan=0.15)
    bas = s.part("bass", 32, "bass", vol=104, ht=0.01, hv=4)
    dr = s.part("drums", 40, "drums", drum=True, vol=100, ht=0.01, hv=4)
    pno.melody(A1, C5_MEL_A, vel=74)
    pno.melody(A2, mc.bars(C5_MEL_A, 0, 4) + " | " + C5_MEL_A2_END, vel=78)
    pno.melody(B1, C5_MEL_B, vel=82)
    pno.melody(A3, mc.bars(C5_MEL_A, 0, 4) + " | " + mc.bars(C5_MEL_A2_END, 0, 3) + " | c5/2 g5/2", vel=76,
               shift=0)
    pno.melody(CODA, C5_MEL_CODA, vel=70)
    pt.ballad_piano(lh, s, 0, CODA + 3, hi=67, vel=54)
    pt.pad(st, s, A2, CODA + 3, lo=53, hi=72, n=4, vel=46)
    pt.bass_two(bas, s, A2, CODA + 3, vel=76, push=0.2)
    pt.brush_ballad(dr, s, A2, CODA + 2, vel=50)
    pt.sparse_melody(cel, s, B1, B1 + 8, lo=76, hi=91, density=0.25, vel=50, durs=(1, 1.5, 2))
    end = (CODA + 3) * s.bpb
    pno.chord(end, [mc.midi(n) for n in ("eb3", "bb3", "f4", "g4", "d5", "g5")], 6, 62, strum=0.09)
    bas.note(end, mc.midi("eb1"), 6, 70)
    st.chord(end, mc.voicing(mc.Chord("Ebmaj9"), 53, 72, 4), 6, 42)
    return mc.produce(s, gains={"lead": 0, "keys": -5, "lead2": -6, "pad": -7, "bass": -6, "drums": -4},
                      sends={"lead": 0.35, "keys": 0.35, "lead2": 0.5, "pad": 0.5, "bass": 0.03, "drums": 0.25},
                      rev_size=2.6, eqs={"lead": lambda f: mc.hp_resp(f, 90, 2)})


TRACKS.update({
    "mus_cinquecento_02": lambda: {"mus_cinquecento_02": (cinquecento_02(), False)},
    "mus_cinquecento_03": lambda: {"mus_cinquecento_03": (cinquecento_03(), False)},
    "mus_cinquecento_04": lambda: {"mus_cinquecento_04": (cinquecento_04(), False)},
    "mus_cinquecento_05": lambda: {"mus_cinquecento_05": (cinquecento_05(), False)},
})


# --------------------------------------------------------------------------
# Notte FM: slow detuned pads, drones and sparse electric piano
# --------------------------------------------------------------------------

def _notte(name, bpm, prog, reps, seed, pad_prog, hi_prog, drone_pcs, ep_prog,
           ep_range=(60, 79), ep_density=0.3, det=7.0, drift=5.0, arp_prog=None,
           beat=False, bass_prog=None, transpose=0, tape_kw=None, outro_chord=None,
           extra=None):
    s = Song(name, bpm=bpm, bpb=4, loop=False, seed=seed)
    bar = 0
    for _ in range(reps):
        bar = s.chords(bar, prog)
    END = bar
    end_sym = outro_chord or prog[0]
    bar = s.chords(bar, [end_sym, end_sym])
    N = bar
    # two detuned copies of the main pad, slowly drifting apart and back
    pa = s.part("padA", pad_prog, "pad", vol=100, pan=-0.45, detune=+det, drift=drift, ht=0.03, hv=3)
    pb = s.part("padB", pad_prog, "pad", vol=100, pan=0.45, detune=-det, drift=drift, ht=0.03, hv=3)
    hi = s.part("hi", hi_prog, "pad2", vol=90, pan=0.2, detune=-det / 2, drift=drift * 1.5, ht=0.05, hv=3)
    dr = s.part("drone", pad_prog if bass_prog is None else bass_prog, "drone", vol=96, detune=-3, drift=3)
    ep = s.part("ep", ep_prog, "lead", vol=100, pan=-0.1, ht=0.03, hv=6, detune=-5, drift=4)
    fade_bars = 2
    pt.pad(pa, s, 0, N, lo=50, hi=70, n=4, vel=52, gap=0.0)
    pt.pad(pb, s, 0, N, lo=50, hi=70, n=4, vel=50, gap=0.0)
    L = len(prog)
    pt.pad(hi, s, L, END, lo=66, hi=84, n=3, vel=40, gap=0.0)
    pt.drone(dr, s, 0, N, drone_pcs, lo=31, vel=62, dur_bars=4)
    # electric piano enters after the first pass, rests in the middle pass
    for k in range(1, reps):
        b0 = k * L
        if k == reps // 2 + 1 and reps > 3:
            continue
        pt.sparse_melody(ep, s, b0, b0 + L, lo=ep_range[0], hi=ep_range[1], density=ep_density,
                         vel=54 + 4 * (k % 2), motif_bars=2, durs=(1, 1.5, 2, 3, 0.5))
    if arp_prog is not None:
        ar = s.part("arp", arp_prog, "arp", vol=90, pan=0.35, detune=6, drift=4, ht=0.006, hv=8)
        pt.arp(ar, s, L, END - L // 2, lo=57, hi=81, pattern=(0, 2, 1, 3, 2, 4, 1, 3), step=0.5,
               vel=40, gate=0.7, n=4)
    if beat:
        d = s.part("beat", 25 if beat == "808" else 40, "drums", drum=True, vol=100, ht=0.012, hv=5)
        for bb in range(L, END - 2):
            b = bb * s.bpb
            d.note(b, pt.KICK, 0.3, 58)
            d.note(b + 2.5, pt.KICK, 0.3, 42)
            d.note(b + 1, pt.STICK, 0.2, 46)
            d.note(b + 3, pt.STICK, 0.2, 48)
            for k in range(8):
                d.note(b + k * 0.5, pt.SHAKER if beat == "808" else pt.BR_TAP, 0.1, 30 + (8 if k % 2 == 0 else 0))
    if extra:
        extra(s, L, END, N)
    # let the last chord die away on its own
    for p in (pa, pb, hi, dr):
        p.ramp(END * s.bpb, N * s.bpb, 11, 127, 0, 0.25)
    mc.transpose(s, transpose)
    kw = {"age": 1.7, "lp_hz": 8500, "hiss_db": -47, "drive": 1.3, "width": 0.7, "dropouts": 1.5, "bump_db": 2.5}
    kw.update(tape_kw or {})
    return mc.produce(s, gains={"pad": 0, "pad2": -6, "drone": -1, "lead": 0, "arp": -8, "drums": -9},
                      sends={"pad": 0.55, "pad2": 0.7, "drone": 0.3, "lead": 0.55, "arp": 0.6, "drums": 0.25},
                      eqs={"pad": lambda f: mc.hp_resp(f, 110, 2) * mc.lp_resp(f, 6000, 2) * mc.bell_resp(f, 300, -2.5, 0.8),
                           "pad2": lambda f: mc.hp_resp(f, 300, 2) * mc.lp_resp(f, 5000, 2),
                           "drone": lambda f: mc.lp_resp(f, 600, 2) * mc.hp_resp(f, 30, 2),
                           "lead": lambda f: mc.lp_resp(f, 5000, 1),
                           "arp": lambda f: mc.lp_resp(f, 2500, 2) * mc.hp_resp(f, 200, 1)},
                      rev_size=4.5, rev_damp=3500, tape_kw=kw, fade_in=3.0, fade_out=4.0)


def notte_01():
    return _notte("mus_nottefm_01", 64, ["Dbmaj9", "Dbmaj9", "Bbm9", "Bbm9", "Gbmaj7#11", "Gbmaj7#11",
                                         "Ab9sus4", "Ab9sus4"], 5, 501, pad_prog=89, hi_prog=94,
                  drone_pcs=[1, 8], ep_prog=4, ep_range=(60, 80), det=7, bass_prog=88)


def notte_02(storm=False):
    prog = ["Em9", "Em9", "Cmaj7#11", "Cmaj7#11", "Am9", "Am9", "B7sus4", "B7sus4"]

    def thunder(s, L, END, N):
        # distant rolls: soft timpani tremolo swells
        t = s.part("rumble", 47, "drone", vol=100, ht=0.01, hv=3)
        for b0 in range(L, END, 6):
            for k in range(24):
                t.note(b0 * s.bpb + k * 0.125, mc.midi("e2"), 0.12, 30 + 26 * np.sin(np.pi * k / 24))
        cb = s.part("contrabass", 43, "drone", vol=100, detune=-5, drift=4)
        pt.drone(cb, s, 0, N, [4], lo=28, vel=48, dur_bars=4)

    if storm:
        return _notte("mus_storm_02", 52, prog, 4, 652, pad_prog=92, hi_prog=50, drone_pcs=[4, 11],
                      ep_prog=11, ep_range=(55, 72), ep_density=0.22, det=9, drift=7, transpose=-3,
                      tape_kw={"lp_hz": 5200, "age": 2.2, "hiss_db": -45, "bump_db": 3.5},
                      extra=thunder)
    return _notte("mus_nottefm_02", 60, prog, 4, 502, pad_prog=92, hi_prog=95, drone_pcs=[4, 11],
                  ep_prog=5, ep_range=(62, 81), ep_density=0.28, det=8, drift=6)


def notte_03():
    return _notte("mus_nottefm_03", 75, ["Amaj9", "Amaj9", "F#m9", "F#m9", "Dmaj9", "Dmaj9",
                                         "E13sus4", "E13sus4"], 5, 503, pad_prog=90, hi_prog=94,
                  drone_pcs=[9], ep_prog=4, ep_range=(62, 81), ep_density=0.32, det=6, drift=4,
                  arp_prog=98, beat="808", bass_prog=38)


def notte_04():
    return _notte("mus_nottefm_04", 56, ["Fmaj7#11", "Fmaj7#11", "G/F", "G/F", "Am9", "Am9",
                                         "Dm9", "Csus2"], 4, 504, pad_prog=91, hi_prog=50,
                  drone_pcs=[5, 0], ep_prog=11, ep_range=(64, 84), ep_density=0.26, det=8, drift=6,
                  outro_chord="Fmaj7#11")


TRACKS.update({
    "mus_nottefm_01": lambda: {"mus_nottefm_01": (notte_01(), False)},
    "mus_nottefm_02": lambda: {"mus_nottefm_02": (notte_02(), False)},
    "mus_nottefm_03": lambda: {"mus_nottefm_03": (notte_03(), False)},
    "mus_nottefm_04": lambda: {"mus_nottefm_04": (notte_04(), False)},
})


# --------------------------------------------------------------------------
# Home theme: F major, 80 BPM, clarinet + nylon guitar, heard from next room
# --------------------------------------------------------------------------

H_A = ["Fmaj7", "Dm9", "Gm9", "C13", "Am7", "D7b9", "Gm9", "C7sus4"]
H_A2 = ["Fmaj7", "Dm9", "Gm9", "C13", "Bbmaj7", "Bbm6", "Am7", "Gm7 C7"]
H_B = ["Bbmaj7", "C/Bb", "Am7", "Dm9", "Gm9", "Bbm6", "Fmaj7", "C7sus4"]
H_TAG = ["Bbmaj7", "Bbm6", "Am7", "D7b9", "Gm9", "C9sus4", "Fmaj9", "C7sus4"]
H_MEL_A = ("a4/1.5 c5/.5 e5/2 | f5/1.5 e5/.5 d5/1 a4/1 | bb4/1 d5/1 a5/2 | a5/1 g5/2 r/1 |"
           " e5/1.5 g5/.5 c5/2 | f#5/1.5 eb5/.5 c5/2 | d5/1 f5/1 a5/1 bb5/1 | g5/2 f5/2")
H_MEL_A2_END = " d5/1.5 f5/.5 a5/2 | g5/1.5 f5/.5 db5/2 | c5/2 e5/1 a4/1 | bb4/2 e5/1 c5/1"
H_MEL_B = ("f5/2 d5/1 bb4/1 | e5/2 g5/1 c5/1 | e5/1 g5/1 c6/2 | a5/1.5 f5/.5 e5/2 |"
           " d5/1 bb4/1 a4/1 d5/1 | g5/2 f5/1 db5/1 | c5/1 e5/1 a5/2 | g5/4")


def _next_room(x):
    """Small-speaker-through-a-wall: band-limit, dull, add a short room."""
    y = mc.fft_eq(x, lambda f: mc.lp_resp(f, 2600, 2) * mc.hp_resp(f, 90, 2) * mc.bell_resp(f, 250, 2.0, 1.0))
    irs = mc.make_ir(0.7, 2200, seed=77, predelay=0.006)
    return y * 0.6 + mc.conv_circ(y, irs) * 0.55


def home_theme():
    s = Song("mus_home_theme", bpm=80, bpb=4, loop=True, seed=601, swing=0.12)
    bar = 0
    A1 = bar; bar = s.chords(bar, H_A)
    A2 = bar; bar = s.chords(bar, H_A2)
    B1 = bar; bar = s.chords(bar, H_B)
    A3 = bar; bar = s.chords(bar, H_A2)
    TAG = bar; bar = s.chords(bar, H_TAG)
    cl = s.part("clarinet", 71, "lead", vol=100, pan=-0.05, ht=0.014, hv=4, expr=True, lag=0.01)
    vib = s.part("vibes", 11, "lead2", vol=90, pan=0.25, ht=0.012, hv=5)
    gtr = s.part("guitar", 24, "gtr", vol=104, pan=-0.3, ht=0.008, hv=6)
    bas = s.part("bass", 32, "bass", vol=104, ht=0.01, hv=4)
    dr = s.part("drums", 40, "drums", drum=True, vol=100, ht=0.01, hv=4)
    org = s.part("organ", 16, "keys", vol=70, pan=0.3)
    cl.melody(A1, H_MEL_A, vel=74)
    cl.melody(A2, mc.bars(H_MEL_A, 0, 4) + " | " + H_MEL_A2_END, vel=76)
    vib.melody(B1, H_MEL_B, vel=72)
    cl.melody(A3, mc.bars(H_MEL_A, 0, 4) + " | " + H_MEL_A2_END, vel=74)
    pt.sparse_melody(vib, s, TAG, TAG + 8, lo=65, hi=81, density=0.3, vel=58)
    # fingerpicked nylon guitar: bass on 1 and 3, arpeggio on the eighths
    pt.arp(gtr, s, 0, bar, lo=52, hi=72, pattern=(0, 2, 3, 1, 2, 3, 1, 3), step=0.5, vel=50, n=4, gate=2.0,
           accent_every=4)
    pt.bass_two(bas, s, 0, bar, vel=72, push=0.25)
    pt.brush_ballad(dr, s, A2, bar, vel=44)
    pt.organ_comp(org, s, B1, bar, lo=55, hi=72, vel=38)
    return mc.produce(s, gains={"lead": 0, "lead2": -2, "gtr": -3, "bass": -4, "drums": -4, "keys": -6},
                      sends={"lead": 0.3, "lead2": 0.3, "gtr": 0.2, "bass": 0.03, "drums": 0.2, "keys": 0.3},
                      rev_size=1.4, post=_next_room,
                      tape_kw={"lp_hz": 8000, "hiss_db": -50, "drive": 1.3})


# --------------------------------------------------------------------------
# Time trial: A major Italian beat / library chase, 144 BPM, brass + organ
# --------------------------------------------------------------------------

T_A = ["A6", "G6", "Dmaj7", "E7", "A6", "C#m7 F#7", "Bm7 E7", "A6 E7#9"]
T_B = ["Dmaj7", "Dm6", "C#m7", "F#7b9", "Bm9", "E13", "Cmaj7", "E7#9"]
T_TURN = ["A6", "G6", "Fmaj7", "E7#9"]
T_MEL_A = (">e5/.5 e5/.5 r/.5 c#5/.5 e5/1 f#5/1 | >d5/.5 d5/.5 r/.5 b4/.5 d5/1 e5/1 |"
           " f#5/1.5 a5/.5 c#6/1 a5/1 | g#5/1.5 e5/.5 d5/1 b4/1 |"
           " >e5/.5 e5/.5 r/.5 c#5/.5 e5/1 a5/1 | g#5/1 e5/1 a#5/1 f#5/1 |"
           " d5/1 f#5/1 g#5/1 b5/1 | a5/2 g5/1 e5/1")
T_MEL_B = ("a5/1.5 f#5/.5 c#6/2 | b5/1.5 a5/.5 f5/2 | g#5/1.5 e5/.5 b5/2 | a#5/1.5 g5/.5 e5/2 |"
           " d6/1.5 c#6/.5 b5/1 f#5/1 | g#5/1.5 c#6/.5 b5/2 | e5/1 g5/1 b5/1 c6/1 | g5/2 g#5/2")


def timetrial():
    s = Song("mus_timetrial_loop", bpm=144, bpb=4, loop=True, seed=701)
    bar = s.chords(0, ["A6", "G6", "A6", "E7#9"])
    A1 = bar; bar = s.chords(bar, T_A)
    A2 = bar; bar = s.chords(bar, T_A)
    B1 = bar; bar = s.chords(bar, T_B)
    B2 = bar; bar = s.chords(bar, T_B)
    A3 = bar; bar = s.chords(bar, T_A)
    TURN = bar; bar = s.chords(bar, T_TURN)
    N = bar
    br = s.part("brass", 61, "lead", vol=104, pan=0.1, ht=0.006, hv=5)
    tpt = s.part("trumpet", 56, "lead", vol=92, pan=-0.1, ht=0.008, hv=5)
    org = s.part("organ", 18, "lead2", vol=96, pan=-0.2, ht=0.005, hv=5)
    orgc = s.part("organ_comp", 16, "keys", vol=86, pan=0.25, ht=0.005, hv=4)
    gtr = s.part("guitar", 27, "gtr", vol=96, pan=-0.4, ht=0.004, hv=5)
    bas = s.part("bass", 33, "bass", vol=114, ht=0.004, hv=5)
    dr = s.part("kit", 8, "drums", drum=True, vol=100, ht=0.004, hv=5)
    pc = s.part("perc", 8, "drums", drum=True, vol=100, ht=0.005, hv=5)
    pt.kit_drive(dr, s, 0, N, vel=80)
    pt.bass_drive(bas, s, 0, N, vel=92)
    for b0 in (A1, A2, B1, B2, A3, TURN):
        pt.crash(dr, s, b0, vel=70)
        pt.fill(dr, s, b0 - 1, vel=74, kind="kit")
    br.melody(A1, T_MEL_A, vel=90)
    br.melody(A2, T_MEL_A, vel=94)
    org.melody(A2, T_MEL_A, vel=74, shift=12)
    org.melody(B1, T_MEL_B, vel=86)
    br.melody(B2, T_MEL_B, vel=92)
    tpt.melody(B2, T_MEL_B, vel=78, shift=-12)
    br.melody(A3, T_MEL_A, vel=96)
    tpt.melody(A3, T_MEL_A, vel=80)
    pt.latin_perc(pc, s, B1, A3, vel=60)
    # organ comping: short stabs on the offbeats; guitar double-stop chops
    prev = None
    for bar_ in range(0, N):
        b = bar_ * s.bpb
        for off in (0.5, 1.5, 2.5, 3.5):
            ch = s.chord_at(b + off)
            v = mc.voicing(ch, 57, 74, 4, prev)
            prev = v
            orgc.chord(b + off, v, 0.3, 58 if bar_ >= A1 else 50)
            gtr.chord(b + off, mc.voicing(ch, 62, 76, 3), 0.18, 56)
    # turnaround: brass hits
    for k, off in enumerate((0, 1.5, 3)):
        ch = s.chord_at(TURN * s.bpb + off)
        br.chord(TURN * s.bpb + off, mc.voicing(ch, 60, 76, 4), 0.6, 96)
    br.melody(TURN + 2, "a5/1 g5/1 e5/1 c5/1 | g5/2 g#5/2", vel=92)
    return mc.produce(s, gains={"lead": 0, "lead2": -1, "keys": -8, "gtr": -9, "bass": -3, "drums": -1},
                      sends={"lead": 0.25, "lead2": 0.25, "keys": 0.2, "gtr": 0.15, "bass": 0.02, "drums": 0.12},
                      rev_size=1.4, tape_kw={"drive": 1.7})


TRACKS.update({
    "mus_home_theme": lambda: {"mus_home_theme": (home_theme(), True)},
    "mus_timetrial_loop": lambda: {"mus_timetrial_loop": (timetrial(), True)},
    "mus_storm_01": lambda: {"mus_storm_01": (cinquecento_01(storm=True), False)},
    "mus_storm_02": lambda: {"mus_storm_02": (notte_02(storm=True), False)},
})
