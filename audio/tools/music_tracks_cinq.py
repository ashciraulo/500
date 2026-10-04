"""Radio Cinquecento, second batch: ten more day-station pieces (06-15).

Same pipeline and conventions as music_tracks_more.py (Song / part / melody /
chords, pattern helpers, mc.produce with the worn-tape chain). Each piece has
its own key, tempo, groove and lead so the rotation does not tire:

  06 Alba         E major   112 bossa (soft)     piano, nylon guitar
  07 Colazione    C major   152 bright two-beat  whistle, xylophone, glockenspiel
  08 Polvere      D minor   100 western gallop   twang guitar, whistle, trumpet, choir
  09 Bar Sport    Bb major  120 organ shuffle    drawbar organ, jazz guitar
  10 Riviera      Ab major  118 cha-cha          alto sax, violin, piano montuno
  11 Onda         A major   140 surf pop         12-string guitar, steel guitar, organ
  12 Barocco      B minor   104 baroque pop      harpsichord, strings, oboe
  13 Tramonto     D major   6/8 serenade         mandolin tremolo, cello
  14 Pomeriggio   F minor   104 samba            flute, Rhodes
  15 Crepuscolo   Db major   66 ballad           muted trumpet, vibraphone

The station's time-of-day running order is audio/music/programme_cinquecento.json.
"""
from __future__ import annotations

import music_core as mc
import music_patterns as pt
from music_core import Chord, Song

bars = mc.bars

# extra GM drum keys
GUIRO_S, GUIRO_L = 73, 74
TIMB_H, TIMB_L = 65, 66
AGOGO_H, AGOGO_L = 67, 68
WOOD_H, WOOD_L = 76, 77

_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]


def _tr_sym(sym: str, n: int) -> str:
    def root(x):
        i = 1
        while i < len(x) and x[i] in "#b":
            i += 1
        return _NAMES[(mc.pc_of(x[:i]) + n) % 12] + x[i:]
    out = []
    for tok in sym.split():
        dur = ""
        if ":" in tok:
            tok, d = tok.split(":")
            dur = ":" + d
        ps = tok.split("/")
        t = root(ps[0])
        if len(ps) > 1:
            t += "/" + _NAMES[(mc.pc_of(ps[1]) + n) % 12]
        out.append(t + dur)
    return " ".join(out)


def tr(prog, n):
    """Transpose a list of chord-bar strings by n semitones."""
    return [_tr_sym(b, n) for b in prog]


def _starts(s):
    return {round(b, 4) for b, d, c in s.timeline}


def bass_fig(p, s, bar0, bar1, fig, vel=86, lo=28, hi=45):
    """Bass figure per bar: fig = [(offset, kind, dur)], kind is 'r' root,
    '5' fifth, '8' octave, 'a' chromatic approach to the next bar's root.
    A chord change landing on an offset always gets its root."""
    st = _starts(s)
    prev = None
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for off, kind, d in fig:
            t = b + off
            ch = s.chord_at(t + 0.01)
            rt = pt._bass_pitch(ch.bass, prev, lo, hi)
            if kind == "r" or (off > 0 and round(t, 4) in st and kind != "a"):
                pitch = rt
                prev = rt
            elif kind == "5":
                pitch = mc.nearest(ch.fifth_pc(), rt + 5, lo, hi + 7)
            elif kind == "8":
                pitch = rt + 12
            else:  # approach
                nxt = s.chord_at(b + s.bpb + 0.01)
                tgt = pt._bass_pitch(nxt.bass, rt, lo, hi)
                pitch = tgt - 1 if s.rng.random() < 0.6 else tgt + 1
            p.note(t, pitch, d, vel - (0 if off == 0 else 10))


def comp_hits(p, s, bar0, bar1, offs, lo=55, hi=74, n=4, vel=56, dur=0.4, strum=0.0,
              accent=(0,)):
    """Chord hits at fixed offsets in every bar, voice-led."""
    prev = None
    for bar in range(bar0, bar1):
        for off in offs:
            t = bar * s.bpb + off
            ch = s.chord_at(t + 0.01)
            v = mc.voicing(ch, lo, hi, n, prev)
            prev = v
            p.chord(t, v, dur, vel + (6 if off in accent else 0), strum)


def four_beat_gtr(p, s, bar0, bar1, vel=50):
    """Freddie Green style quarter-note chords."""
    prev = None
    for b, d, ch in s.segs(bar0, bar1):
        v = mc.voicing(ch, 50, 67, 4, prev, root=True)
        prev = v
        t, k = b, 0
        while t < b + d - 1e-6:
            p.chord(t, v, 0.6, vel + (6 if k % 2 == 1 else 0), strum=0.006)
            t += 1
            k += 1


def end_chord(p, s, bar, sym, lo, hi, n, dur, vel, strum=0.0):
    p.chord(bar * s.bpb, mc.voicing(Chord(sym), lo, hi, n), dur, vel, strum)


# ==========================================================================
# 06 "Alba": E major soft bossa, 112 BPM, piano and nylon guitar (dawn)
# ==========================================================================

C6_INTRO = ["Emaj9", "C#m9", "F#m9", "B9sus4"]
C6_A = ["Emaj9", "C#m9", "F#m9", "B13", "G#m7", "C#7b9", "F#m9", "B9sus4 B7b9",
        "Emaj9", "E9", "Amaj7", "Am6", "G#m7", "C#7b9", "F#m9 B13", "Emaj9"]
C6_B = ["Amaj7", "G#m7", "F#m9", "Emaj9", "Cmaj7#11", "B7sus4", "C#m9 F#9", "F#m9 B7b9"]
C6_CODA = ["Amaj7", "Am6", "Emaj9", "Emaj9"]
C6_MEL_A = ("g#5/1.5 f#5/.5 d#5/2 | e5/1 g#5/1 b5/1.5 g#5/.5 | a5/1.5 g#5/.5 e5/1 c#5/1 | d#5/3 r/1 |"
            " f#5/1.5 d#5/.5 b4/2 | f5/1 d5/1 b4/1 g#4/1 | a4/1 c#5/1 g#5/1.5 f#5/.5 | e5/2 d#5/1 c5/1 |"
            " b4/1 e5/1 g#5/1 b5/1 | d6/2 b5/1 g#5/1 | c#6/1.5 b5/.5 a5/1 e5/1 | c6/2 a5/1 f#5/1 |"
            " b5/1.5 a5/.5 g#5/1 d#5/1 | f5/1.5 d5/.5 b4/2 | c#5/1 e5/1 d#5/1 g#5/1 | e5/3 r/1")
C6_MEL_B = ("e5/1 a5/1 c#6/2 | b5/1.5 g#5/.5 d#5/2 | a5/1 g#5/1 f#5/1 c#5/1 | d#5/1.5 e5/.5 b4/2 |"
            " e5/1 g5/1 b5/1 f#5/1 | e5/2 a5/1 f#5/1 | g#5/1 e5/1 a#5/1 g#5/1 | a5/1 g#5/1 f#5/1 c5/1")
C6_MEL_CODA = "c#6/2 b5/1 a5/1 | c6/2 a5/1 f#5/1 | g#5/4 | r/4"


def cinquecento_06():
    s = Song("mus_cinquecento_06", bpm=112, bpb=4, loop=False, seed=406)
    bar = s.chords(0, C6_INTRO)
    A1 = bar; bar = s.chords(bar, C6_A)
    A2 = bar; bar = s.chords(bar, C6_A)
    B1 = bar; bar = s.chords(bar, C6_B)
    B2 = bar; bar = s.chords(bar, C6_B)
    A3 = bar; bar = s.chords(bar, C6_A)
    CODA = bar; bar = s.chords(bar, C6_CODA)
    END = CODA + 3
    pno = s.part("piano", 0, "lead", vol=104, pan=-0.05, ht=0.012, hv=5)
    ng = s.part("nylon_lead", 24, "lead2", vol=112, pan=0.12, ht=0.010, hv=5)
    gtr = s.part("guitar", 24, "gtr", vol=100, pan=-0.35, ht=0.007, hv=5)
    pc = s.part("piano_comp", 0, "keys", vol=86, pan=0.3, ht=0.012, hv=4)
    bas = s.part("bass", 32, "bass", vol=106, ht=0.008, hv=4)
    dr = s.part("drums", 40, "drums", drum=True, vol=100, ht=0.008, hv=4)
    st = s.part("strings", 49, "pad", vol=84, pan=0.2)
    # intro: guitar alone, then the band
    pt.bossa_guitar(gtr, s, 0, END, vel=54)
    pt.bass_bossa(bas, s, A1, END, vel=80)
    pt.brush_bossa(dr, s, 2, A1, vel=40, clave=False, kick=False)
    pt.brush_bossa(dr, s, A1, CODA + 2, vel=50, clave=True, kick=True)
    pno.melody(A1, C6_MEL_A, vel=72)
    ng.melody(A2, C6_MEL_A, vel=82)
    pt.organ_comp(pc, s, A2, B1, lo=57, hi=74, vel=40, style="push")
    pno.melody(B1, C6_MEL_B, vel=76)
    pt.pad(st, s, B1, B2 + 8, lo=55, hi=74, n=3, vel=40)
    ng.melody(B2, C6_MEL_B, vel=84)
    pt.organ_comp(pc, s, B2, A3, lo=57, hi=74, vel=38, style="hold")
    pno.melody(A3, C6_MEL_A, vel=76)
    ng.melody(A3 + 8, bars(C6_MEL_A, 8, 16), vel=60, shift=-12)
    pt.pad(st, s, A3, END, lo=55, hi=74, n=4, vel=42)
    pno.melody(CODA, C6_MEL_CODA, vel=70)
    for b0 in (A2, B1, B2, A3, CODA):
        pt.fill(dr, s, b0 - 1, vel=52)
    end = (CODA + 3) * s.bpb
    pno.chord(end, [mc.midi(n) for n in ("e3", "b3", "d#4", "f#4", "g#4", "b4", "e5")], 6, 58, strum=0.1)
    bas.note(end, mc.midi("e1"), 5, 70)
    return mc.produce(s, gains={"lead": 1, "lead2": -1, "gtr": -7, "keys": -6, "bass": -4, "drums": -2, "pad": -7},
                      sends={"lead": 0.38, "lead2": 0.3, "gtr": 0.2, "keys": 0.35, "bass": 0.03, "drums": 0.2, "pad": 0.5},
                      rev_size=2.4, eqs={"lead": lambda f: mc.hp_resp(f, 100, 2) * mc.bell_resp(f, 300, -2.5, 0.8),
                           "gtr": lambda f: mc.hp_resp(f, 130, 2) * mc.bell_resp(f, 280, -3, 0.8) * mc.bell_resp(f, 2500, 1.5, 1.0),
                           "keys": lambda f: mc.hp_resp(f, 160, 2) * mc.bell_resp(f, 300, -3, 0.8) * mc.lp_resp(f, 6500, 1)},
                      tape_kw={"lp_hz": 9500})


# ==========================================================================
# 07 "Colazione": C major bright two-beat, 152 BPM, whistle and xylophone
# ==========================================================================

C7_INTRO = ["C6", "Am7", "Dm7", "G7"]
C7_A = ["C6", "Am7", "Dm7", "G7", "C6", "A7", "Dm7", "G7",
        "Em7", "A7", "Dm7", "Fm6", "C/G", "A7", "Dm7 G7", "C6"]
C7_B = ["Fmaj7", "Fm6", "Em7", "A7", "D9", "G7", "Em7 A7", "Dm7 G7"]
C7_B_MOD = C7_B[:7] + ["Em7 A7"]   # leads up a tone into D
C7_CODA = ["Fmaj7", "Fm6", "C6", "C6"]
C7_MEL_A = ("e5/1 g5/1 a5/1.5 g5/.5 | c6/2 a5/1 e5/1 | f5/1 a5/1 c6/1 a5/1 | b5/3 g5/1 |"
            " e5/1 g5/1 a5/1.5 g5/.5 | c#6/2 a5/1 g5/1 | f5/1.5 e5/.5 d5/1 a5/1 | g5/3 r/1 |"
            " g5/1 b5/1 d6/1.5 b5/.5 | c#6/2 e6/1 c#6/1 | d6/1 c6/1 a5/1 f5/1 | ab5/2 f5/1 d5/1 |"
            " e5/1 g5/1 c6/1.5 e6/.5 | e6/1 c#6/1 a5/1 g5/1 | f5/1 a5/1 b5/1 d6/1 | c6/3 r/1")
C7_MEL_B = ("a5/1 c6/1 e6/2 | d6/1.5 c6/.5 ab5/2 | g5/1 b5/1 e6/1.5 d6/.5 | c#6/2 a5/2 |"
            " f#5/1 a5/1 e6/1.5 c6/.5 | b5/2 g5/1 f5/1 | e5/1 g5/1 c#5/1 e5/1 | f5/1 a5/1 g5/1 b5/1")
C7_MEL_B_MOD_END = " e5/1 g5/1 a5/1 c#6/1"
C7_INTRO_XYL = ("e5/.5 g5/.5 c6/1 r/2 | e5/.5 a5/.5 c6/1 r/2 | f5/.5 a5/.5 d6/1 r/2 |"
                " g5/.5 b5/.5 d6/.5 f6/.5 g6/1 r/1")
C7_MEL_CODA = "a5/1 c6/1 e6/2 | d6/1.5 c6/.5 ab5/2 | g5/1 e5/1 c5/1 e5/1 | c6/2 r/2"


def cinquecento_07():
    s = Song("mus_cinquecento_07", bpm=152, bpb=4, loop=False, seed=407)
    bar = s.chords(0, C7_INTRO)
    A1 = bar; bar = s.chords(bar, C7_A)
    A2 = bar; bar = s.chords(bar, C7_A)
    B1 = bar; bar = s.chords(bar, C7_B)
    A3 = bar; bar = s.chords(bar, C7_A)
    B2 = bar; bar = s.chords(bar, C7_B_MOD)
    A4 = bar; bar = s.chords(bar, tr(C7_A, 2))
    CODA = bar; bar = s.chords(bar, tr(C7_CODA, 2))
    END = CODA + 4
    wh = s.part("whistle", 78, "lead", vol=104, pan=0.0, ht=0.010, hv=5, expr=True)
    gl = s.part("glock", 9, "lead2", vol=80, pan=0.3, ht=0.006, hv=4)
    xy = s.part("xylophone", 13, "lead2", vol=100, pan=-0.2, ht=0.006, hv=5)
    gtr = s.part("guitar", 25, "gtr", vol=96, pan=-0.35, ht=0.006, hv=5)
    pz = s.part("pizz", 45, "keys", vol=96, pan=0.35, ht=0.008, hv=4)
    bas = s.part("bass", 32, "bass", vol=110, ht=0.006, hv=4)
    dr = s.part("kit", 8, "drums", drum=True, vol=100, ht=0.006, hv=5)
    st = s.part("strings", 48, "pad", vol=80, pan=0.2)
    # two-beat: bass on 1 and 3, guitar and pizzicato on 2 and 4
    bass_fig(bas, s, 0, END, [(0, "r", 0.85), (2, "5", 0.85)], vel=86)
    comp_hits(gtr, s, 0, END, (1, 3), lo=52, hi=69, n=4, vel=54, dur=0.35, strum=0.012, accent=())
    comp_hits(pz, s, A2, END, (1, 3), lo=57, hi=74, n=3, vel=58, dur=0.3, accent=())
    for bar_ in range(A1, END):
        b = bar_ * s.bpb
        for k in range(8):
            dr.note(b + k * 0.5, pt.HH, 0.2, 52 + (8 if k % 2 == 0 else -6))
        dr.note(b, pt.KICK, 0.3, 64)
        dr.note(b + 2, pt.KICK, 0.3, 58)
        dr.note(b + 1, pt.STICK, 0.2, 58)
        dr.note(b + 3, pt.STICK, 0.2, 60)
        if bar_ >= A4:
            dr.note(b + 1, pt.CLAP, 0.2, 50)
            dr.note(b + 3, pt.CLAP, 0.2, 52)
        if bar_ >= A3:
            dr.note(b + 1, pt.TAMB, 0.2, 46)
            dr.note(b + 3, pt.TAMB, 0.2, 48)
    for b0 in (A1, A2, B1, A3, B2, A4, CODA):
        pt.fill(dr, s, b0 - 1, vel=64, kind="kit" if b0 in (A4, CODA) else "brush")
        pt.crash(dr, s, b0, vel=52)
    xy.melody(0, C7_INTRO_XYL, vel=74)
    wh.melody(A1, C7_MEL_A, vel=84, stacc=0.9)
    xy.melody(A2, C7_MEL_A, vel=82)
    gl.melody(A2 + 8, bars(C7_MEL_A, 8, 16), vel=56, shift=12)
    wh.melody(B1, C7_MEL_B, vel=86, stacc=0.9)
    pt.pad(st, s, B1, A3, lo=55, hi=74, n=4, vel=44)
    wh.melody(A3, C7_MEL_A, vel=86, stacc=0.9)
    gl.melody(A3, C7_MEL_A, vel=50, shift=12)
    xy.melody(B2, bars(C7_MEL_B, 0, 7) + " | " + C7_MEL_B_MOD_END, vel=84)
    pt.pad(st, s, B2, END, lo=55, hi=74, n=4, vel=44)
    wh.melody(A4, C7_MEL_A, vel=88, shift=2, stacc=0.9)
    xy.melody(A4 + 8, bars(C7_MEL_A, 8, 16), vel=62, shift=2 - 12)
    wh.melody(CODA, C7_MEL_CODA, vel=84, shift=2)
    end = END * s.bpb
    xy.melody(CODA + 3, "r/2 d5/.5 f#5/.5 a5/.5 d6/.5", vel=70)
    for p_, lo, hi in ((gtr, 50, 69), (pz, 57, 74)):
        p_.chord(end, mc.voicing(Chord("D6"), lo, hi, 4), 1.5, 66)
    gl.note(end, mc.midi("d7"), 2, 60)
    wh.note(end, mc.midi("d6"), 1.5, 84)
    bas.note(end, mc.midi("d2"), 1.5, 90)
    dr.note(end, pt.KICK, 0.3, 80)
    dr.note(end, pt.CRASH, 3, 70)
    return mc.produce(s, gains={"lead": -6, "lead2": 0, "gtr": -3, "keys": -6, "bass": 1, "drums": -1, "pad": -7},
                      sends={"lead": 0.3, "lead2": 0.3, "gtr": 0.15, "keys": 0.2, "bass": 0.03, "drums": 0.15, "pad": 0.45},
                      rev_size=1.6,
                      eqs={"lead": lambda f: mc.hp_resp(f, 200, 2) * mc.bell_resp(f, 2500, -3, 0.8) * mc.lp_resp(f, 7000, 2),
                           "lead2": lambda f: mc.hp_resp(f, 200, 2) * mc.lp_resp(f, 6000, 2)})


# ==========================================================================
# 08 "Polvere": D minor western gallop, 100 BPM, twang guitar / whistle / trumpet
# ==========================================================================

C8_INTRO = ["Dm", "Dm", "Dm", "A7"]
C8_A = ["Dm", "Dm", "C", "C", "Bb", "Bb", "A7", "A7",
        "Dm", "F", "C", "Gm", "Bb", "Gm6", "A7sus4", "A7"]
C8_B = ["F", "C/E", "Dm", "Am", "Bb", "F/A", "Gm7", "A7",
        "F", "C/E", "Dm", "Am", "Bb", "Gm6", "A7sus4", "A7"]
C8_CODA = ["Bb", "A7", "Dm", "Dm"]
C8_MEL_A = ("d3/.5 e3/.5 f3/.5 a3/.5 d4/2 | c4/1 a3/1 f3/2 | e3/.5 g3/.5 c4/1 e4/2 | d4/1 c4/1 g3/2 |"
            " d4/.5 c4/.5 bb3/.5 a3/.5 f3/2 | bb3/1 d4/1 f4/2 | e4/1.5 c#4/.5 a3/2 | g3/2 a3/2 |"
            " a3/1 d4/1 f4/1.5 e4/.5 | f4/1 c4/1 a3/1 c4/1 | g4/2 e4/1 c4/1 | d4/1.5 bb3/.5 g3/2 |"
            " f4/1 d4/1 bb3/1 d4/1 | e4/2 d4/1 bb3/1 | d4/2 a3/2 | c#4/2 e4/1 a3/1")
C8_MEL_B = ("a4/1 c5/1 f5/2 | e5/1.5 d5/.5 c5/2 | d5/1 f5/1 a5/2 | g5/1.5 e5/.5 c5/2 |"
            " bb4/1 d5/1 f5/1 bb5/1 | a5/2 g5/1 f5/1 | f5/1 d5/1 bb4/1 d5/1 | e5/3 r/1 |"
            " a4/1 c5/1 f5/2 | e5/1.5 d5/.5 c5/2 | d5/1 f5/1 a5/2 | g5/1.5 e5/.5 c5/2 |"
            " d5/1 f5/1 bb5/2 | g5/1.5 e5/.5 d5/2 | d5/2 a4/2 | e5/1 g5/1 a5/2")
C8_INTRO_GTR = "r/2 a2/.5 d3/.5 f3/.5 e3/.5 | d3/4 | r/2 a2/.5 d3/.5 f3/.5 a3/.5 | c#3/2 e3/2"
C8_MEL_CODA = "f5/2 d5/2 | e5/2 c#5/2 | d5/4 | r/4"


def cinquecento_08():
    s = Song("mus_cinquecento_08", bpm=100, bpb=4, loop=False, seed=408)
    bar = s.chords(0, C8_INTRO)
    A1 = bar; bar = s.chords(bar, C8_A)
    A2 = bar; bar = s.chords(bar, C8_A)
    B1 = bar; bar = s.chords(bar, C8_B)
    A3 = bar; bar = s.chords(bar, C8_A)
    CODA = bar; bar = s.chords(bar, C8_CODA)
    END = CODA + 3
    tw = s.part("twang", 27, "lead", vol=112, pan=-0.1, ht=0.008, hv=5)
    wh = s.part("whistle", 78, "lead2", vol=96, pan=0.15, ht=0.012, hv=4, expr=True)
    tp = s.part("trumpet", 56, "lead2", vol=100, pan=0.1, ht=0.010, hv=5, expr=True, lag=0.008)
    ag = s.part("gallop_gtr", 25, "gtr", vol=96, pan=0.35, ht=0.005, hv=5)
    bas = s.part("bass", 33, "bass", vol=108, ht=0.006, hv=4)
    dr = s.part("kit", 8, "drums", drum=True, vol=100, ht=0.006, hv=5)
    ch = s.part("choir", 52, "pad", vol=92, pan=-0.15, expr=True)
    st = s.part("strings", 48, "pad", vol=80, pan=0.2)
    tim = s.part("timpani", 47, "keys", vol=100, ht=0.006, hv=3)
    bell = s.part("bell", 14, "keys", vol=80, pan=0.3)
    # gallop: "dum da-da" on every beat
    for bar_ in range(0, END):
        b = bar_ * s.bpb
        c = s.chord_at(b + 0.01)
        v = mc.voicing(c, 50, 67, 4, root=True)
        for k in range(4):
            vv = 54 if bar_ >= A1 else 46
            for off, d, acc in ((0, 0.4, 6), (0.5, 0.2, 0), (0.75, 0.2, -2)):
                cc = s.chord_at(b + k + off + 0.01)
                vv2 = mc.voicing(cc, 50, 67, 4, root=True) if cc is not c else v
                ag.chord(b + k + off, vv2 if off == 0 else vv2[1:], d, vv + acc, strum=0.006)
        dr.note(b, pt.KICK, 0.3, 66)
        dr.note(b + 2, pt.KICK, 0.3, 60)
        if bar_ >= A1:
            dr.note(b + 1, pt.STICK, 0.2, 56)
            dr.note(b + 3, pt.STICK, 0.2, 58)
        if A2 <= bar_ < CODA:
            # coconut hooves
            for k in range(4):
                dr.note(b + k, WOOD_L, 0.1, 50)
                dr.note(b + k + 0.5, WOOD_H, 0.1, 40)
                dr.note(b + k + 0.75, WOOD_H, 0.1, 36)
    bass_fig(bas, s, 0, END, [(0, "r", 1.4), (1.5, "r", 0.4), (2, "5", 1.4), (3.5, "a", 0.4)], vel=86)
    # intro: bell tolls, timpani, twang riff
    for k in (0, 2):
        bell.note(k * 4, mc.midi("d4"), 6, 70)
    bell.note(3 * 4, mc.midi("a3"), 4, 64)
    tim.melody(0, "d2/4 | r/4 | d2/4 | a1/2 a1/2", vel=72)
    tw.melody(0, C8_INTRO_GTR, vel=84)
    tw.melody(A1, C8_MEL_A, vel=92)
    wh.melody(A2, C8_MEL_A, vel=82, shift=24)
    tw.melody(A2 + 8, "r/4 | r/2 c4/.5 a3/.5 f3/1 | r/4 | r/2 g3/.5 bb3/.5 d4/1 |"
                      " r/4 | r/2 g3/.5 bb3/.5 e4/1 | r/4 | a3/.5 c#4/.5 e4/.5 g4/.5 a4/2", vel=80)
    pt.pad(ch, s, A2, B1, lo=55, hi=72, n=3, vel=50)
    tp.melody(B1, C8_MEL_B, vel=86)
    pt.pad(ch, s, B1, A3, lo=55, hi=74, n=4, vel=54)
    pt.pad(st, s, B1, A3, lo=50, hi=67, n=3, vel=48)
    for k in range(B1, A3, 2):
        c = s.chord_at(k * 4 + 0.01)
        tim.note(k * 4, mc.nearest(c.bass, 43, 38, 50), 1.5, 66)
    tw.melody(A3, C8_MEL_A, vel=94)
    wh.melody(A3, C8_MEL_A, vel=78, shift=24)
    pt.pad(ch, s, A3, END, lo=55, hi=74, n=4, vel=50)
    tp.melody(CODA, C8_MEL_CODA, vel=84)
    for b0 in (A1, A2, B1, A3, CODA):
        pt.crash(dr, s, b0, vel=56)
        pt.fill(dr, s, b0 - 1, vel=66, kind="kit")
    end = END * s.bpb
    for k in range(16):
        tim.note(end - 2 + k * 0.125, mc.midi("d2"), 0.12, 40 + 3 * k)
    tim.note(end, mc.midi("d2"), 3, 92)
    bell.note(end, mc.midi("d4"), 6, 76)
    tw.chord(end, [mc.midi(n) for n in ("d3", "a3", "d4", "f4")], 6, 86, strum=0.05)
    bas.note(end, mc.midi("d1"), 4, 90)
    dr.note(end, pt.CRASH, 4, 64)
    return mc.produce(s, gains={"lead": 0, "lead2": -4, "gtr": -8, "keys": -4, "bass": 0, "drums": -3, "pad": -6},
                      sends={"lead": 0.45, "lead2": 0.45, "gtr": 0.15, "keys": 0.4, "bass": 0.03, "drums": 0.2, "pad": 0.55},
                      rev_size=3.0, rev_gain=1.1,
                      eqs={"lead": lambda f: mc.hp_resp(f, 90, 2) * mc.bell_resp(f, 1500, 1.5, 1.0) * mc.lp_resp(f, 6000, 2),
                           "lead2": lambda f: mc.hp_resp(f, 150, 2) * mc.bell_resp(f, 3000, -4, 0.7) * mc.lp_resp(f, 6500, 2)})


# ==========================================================================
# 09 "Bar Sport": Bb organ-trio shuffle, 120 BPM, drawbar organ and jazz guitar
# ==========================================================================

C9_INTRO = ["Bb7", "G7", "Cm7", "F7"]
C9_A = ["Bb7", "Eb9", "Bb7", "Fm7 Bb7", "Eb9", "Edim7", "Bb7/F G7", "Cm7 F7"]
C9_A_END = ["Bb7", "Eb9", "Bb7", "Fm7 Bb7", "Eb9", "Edim7", "Cm7 F7", "Bb6"]
C9_B = ["Ebmaj7", "Ebm6", "Dm7", "G7b9", "Cm7", "F7", "Dm7 G7", "Cm7 F7"]
C9_MEL_A = ("r/.5 f4/.5 ab4/.5 bb4/.5 d5/1 bb4/1 | db5/1.5 bb4/.5 g4/1 f4/1 |"
            " r/.5 f4/.5 ab4/.5 bb4/.5 d5/1 f5/1 | eb5/1 c5/1 d5/1 ab4/1 |"
            " g5/1.5 f5/.5 eb5/1 db5/1 | e5/1.5 db5/.5 bb4/2 | d5/1 bb4/1 b4/1 d5/1 | eb5/1 c5/1 a4/1 c5/1")
C9_MEL_A_END = " eb5/1 c5/1 a4/1 eb5/1 | d5/3 r/1"
C9_MEL_B = ("g4/1 bb4/1 d5/1.5 bb4/.5 | c5/2 gb4/1 eb4/1 | f4/1 a4/1 c5/1.5 a4/.5 | b4/2 ab4/1 f4/1 |"
            " eb5/1 g5/1 bb5/1.5 g5/.5 | a5/2 f5/1 eb5/1 | d5/1 c5/1 b4/1 d5/1 | c5/1 bb4/1 a4/1 f4/1")


def _shuffle_kit(d, s, bar0, bar1, vel=58):
    r = s.rng
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for k in range(4):
            d.note(b + k, pt.RIDE, 0.4, vel - 6 + (4 if k % 2 == 1 else 0))
            if k % 2 == 1:
                d.note(b + k + 0.5, pt.RIDE, 0.3, vel - 18)
                d.note(b + k, pt.PEDAL, 0.2, vel - 12)
                d.note(b + k, pt.SNARE, 0.2, vel - 14)
            d.note(b + k, pt.KICK, 0.3, vel - 24)
        for gk in (0.5, 1.5, 2.5, 3.5):
            if r.random() < 0.3:
                d.note(b + gk, pt.SNARE, 0.3, vel - 34)


def cinquecento_09():
    s = Song("mus_cinquecento_09", bpm=120, bpb=4, loop=False, seed=409, swing=0.33)
    bar = s.chords(0, C9_INTRO)
    plan = []
    for name, prog in (("A", C9_A), ("A", C9_A), ("B", C9_B), ("A", C9_A),
                       ("Ag", C9_A), ("A2", C9_A), ("B2", C9_B), ("AE", C9_A_END)):
        plan.append((name, bar))
        bar = s.chords(bar, prog)
    TAG = bar
    bar = s.chords(bar, ["Bb6", "Bb6"])
    END = TAG + 1
    org = s.part("organ", 16, "lead", vol=104, pan=-0.05, ht=0.006, hv=5)
    jg = s.part("jazz_gtr", 26, "lead2", vol=108, pan=0.25, ht=0.008, hv=5)
    gtr = s.part("guitar_comp", 26, "gtr", vol=96, pan=0.4, ht=0.006, hv=5)
    oc = s.part("organ_comp", 17, "keys", vol=84, pan=-0.3, ht=0.006, hv=4)
    bas = s.part("bass", 32, "bass", vol=112, ht=0.006, hv=5)
    dr = s.part("kit", 32, "drums", drum=True, vol=100, ht=0.006, hv=5)
    pt.bass_walk(bas, s, 0, END, vel=84)
    _shuffle_kit(dr, s, 0, END, vel=60)
    four_beat_gtr(gtr, s, 0, END, vel=46)
    org.melody(3, "r/2 eb5/1 c5/1", vel=78)
    for name, b0 in plan:
        if name == "A":
            org.melody(b0, C9_MEL_A, vel=84)
            pt.organ_comp(oc, s, b0, b0 + 8, lo=50, hi=65, n=3, vel=40, style="stabs")
        elif name == "B":
            jg.melody(b0, C9_MEL_B, vel=84)
            pt.organ_comp(oc, s, b0, b0 + 8, lo=55, hi=70, n=4, vel=44, style="hold")
        elif name == "Ag":
            jg.melody(b0, C9_MEL_A, vel=86, shift=12)
            pt.organ_comp(org, s, b0, b0 + 8, lo=58, hi=74, n=4, vel=48, style="push")
        elif name == "A2":
            org.melody(b0, C9_MEL_A, vel=86)
            jg.melody(b0, C9_MEL_A, vel=66, shift=-12)
            pt.organ_comp(oc, s, b0, b0 + 8, lo=50, hi=65, n=3, vel=40, style="stabs")
        elif name == "B2":
            org.melody(b0, C9_MEL_B, vel=86, shift=12)
            pt.organ_comp(oc, s, b0, b0 + 8, lo=55, hi=70, n=4, vel=44, style="hold")
        elif name == "AE":
            org.melody(b0, bars(C9_MEL_A, 0, 6) + " | " + C9_MEL_A_END, vel=88)
            jg.melody(b0, bars(C9_MEL_A, 0, 6) + " | " + C9_MEL_A_END, vel=70)
            pt.organ_comp(oc, s, b0, b0 + 8, lo=50, hi=65, n=3, vel=40, style="stabs")
        pt.fill(dr, s, b0 + 7, vel=62)
    end = END * s.bpb
    org.chord(end - 4, [mc.midi(n) for n in ("d4", "g4", "c5", "f5")], 3.5, 74)
    org.chord(end, [mc.midi(n) for n in ("ab3", "d4", "g4", "c5", "f5")], 5, 80)
    jg.note(end, mc.midi("d5"), 4, 66)
    bas.note(end, mc.midi("bb1"), 4, 84)
    dr.note(end, pt.RIDE, 4, 60)
    dr.note(end, pt.CRASH, 4, 56)
    dr.note(end, pt.KICK, 0.3, 66)
    return mc.produce(s, gains={"lead": 0, "lead2": -1, "gtr": -9, "keys": -8, "bass": -3, "drums": -2},
                      sends={"lead": 0.25, "lead2": 0.25, "gtr": 0.15, "keys": 0.25, "bass": 0.03, "drums": 0.15},
                      rev_size=1.5,
                      eqs={"lead": lambda f: mc.hp_resp(f, 120, 2) * mc.lp_resp(f, 6000, 2),
                           "keys": lambda f: mc.hp_resp(f, 140, 2) * mc.lp_resp(f, 4500, 2)})


# ==========================================================================
# 10 "Riviera": Ab major cha-cha, 118 BPM, alto sax, violin, piano montuno
# ==========================================================================

C10_INTRO = ["Abmaj7", "Bbm7 Eb7", "Abmaj7", "Bbm7 Eb7"]
C10_A = ["Abmaj7", "Fm7", "Bbm7", "Eb7", "Cm7", "F7b9", "Bbm7 Eb7", "Ab6"]
C10_A2 = ["Abmaj7", "Ab7", "Dbmaj7", "Dbm6", "Cm7", "F7b9", "Bbm7 Eb7", "Ab6"]
C10_B = ["Dbmaj7", "Gb9", "Cm7", "F7", "Bbm7", "Eb9", "Abmaj7", "Eb7#9"]
C10_CODA = ["Dbmaj7", "Dbm6", "Abmaj7", "Abmaj7"]
C10_MEL_A = ("c5/1 eb5/1 g5/1 f5/.5 eb5/.5 | ab5/2 r/1 c5/.5 c5/.5 | db5/1 f5/1 ab5/1 g5/.5 f5/.5 |"
             " g5/2 r/1 bb4/.5 bb4/.5 | eb5/1 g5/1 bb5/1 ab5/.5 g5/.5 | a5/2 gb5/1 eb5/1 |"
             " f5/1 db5/1 g5/1 eb5/1 | ab5/2 f5/1 r/1")
C10_MEL_A2 = ("c5/1 eb5/1 g5/1 f5/.5 eb5/.5 | gb5/2 r/1 eb5/.5 eb5/.5 | f5/1 ab5/1 c6/1 bb5/.5 ab5/.5 |"
              " e5/2 r/1 db5/.5 db5/.5 | eb5/1 g5/1 bb5/1 ab5/.5 g5/.5 | a5/1 c6/1 gb5/1 eb5/1 |"
              " db5/1 f5/1 g5/1 bb5/1 | ab5/3 r/1")
C10_MEL_B = ("f5/2 ab5/1 c6/1 | bb5/3 ab5/1 | g5/2 eb5/1 g5/1 | a5/3 c6/1 |"
             " db6/2 bb5/1 f5/1 | g5/2 f5/1 db5/1 | c5/1 eb5/1 g5/1 ab5/1 | bb5/2 gb5/1 g5/1")
C10_MEL_CODA = "f5/2 ab5/1 c6/1 | e5/2 r/1 db5/.5 db5/.5 | c5/2 r/1 ab4/.5 ab4/.5 | r/4"


def _montuno(p, s, bar0, bar1, lo=60, hi=79, vel=56):
    prev = None
    offs = ((0, "c", 0.4), (0.5, "t", 0.3), (1, "l", 0.3), (1.5, "c", 0.4),
            (2.5, "t", 0.3), (3, "c", 0.4), (3.5, "l", 0.3))
    for bar in range(bar0, bar1):
        for off, kind, d in offs:
            t = bar * s.bpb + off
            ch = s.chord_at(t + 0.01)
            v = mc.voicing(ch, lo, hi, 3, prev)
            prev = v
            top = v[-1]
            if kind == "c":
                p.chord(t, v + [top - 12], d, vel + (6 if off == 0 else 0))
            elif kind == "t":
                p.chord(t, [top - 12, top], d, vel - 4)
            else:
                p.chord(t, v[:-1], d, vel - 8)


def _chacha_perc(d, s, bar0, bar1, vel=60):
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for k in range(4):
            d.note(b + k, pt.COWBELL, 0.2, vel - 8 + (8 if k in (0, 2) else 0))
        d.note(b, GUIRO_L, 0.45, vel - 6)
        d.note(b + 2, GUIRO_L, 0.45, vel - 8)
        for off in (1, 1.5, 3, 3.5):
            d.note(b + off, GUIRO_S, 0.2, vel - 14)
        d.note(b + 1, pt.CONGA_M, 0.2, vel - 4)
        d.note(b + 3, pt.CONGA_O, 0.2, vel - 2)
        d.note(b + 3.5, pt.CONGA_L, 0.2, vel - 2)
        d.note(b + 3, TIMB_L, 0.2, vel - 18)
        d.note(b + 3.5, TIMB_L, 0.2, vel - 18)
        d.note(b, pt.KICK, 0.3, vel - 10)


def _timb_fill(d, s, bar, vel=64):
    b = bar * s.bpb
    for k in range(8):
        d.note(b + 2 + k * 0.25, TIMB_H if k < 4 else TIMB_L, 0.1, vel - 10 + 2 * k)


def cinquecento_10():
    s = Song("mus_cinquecento_10", bpm=118, bpb=4, loop=False, seed=410)
    bar = s.chords(0, C10_INTRO)
    plan = []
    for name, prog in (("A", C10_A), ("A2", C10_A2), ("B", C10_B), ("A", C10_A), ("A2", C10_A2),
                       ("Bs", C10_B), ("A", C10_A), ("A2v", C10_A2)):
        plan.append((name, bar))
        bar = s.chords(bar, prog)
    CODA = bar
    bar = s.chords(bar, C10_CODA)
    END = CODA + 3
    sx = s.part("sax", 65, "lead", vol=100, pan=-0.05, ht=0.010, hv=5, expr=True, lag=0.006)
    vn = s.part("violin", 40, "lead2", vol=100, pan=0.2, ht=0.012, hv=4, expr=True, lag=0.008)
    pno = s.part("piano", 0, "keys", vol=100, pan=0.25, ht=0.005, hv=5)
    bas = s.part("bass", 32, "bass", vol=110, ht=0.006, hv=4)
    dr = s.part("perc", 0, "drums", drum=True, vol=100, ht=0.006, hv=5)
    st = s.part("strings", 48, "pad", vol=80, pan=-0.2)
    _montuno(pno, s, 0, END, vel=54)
    bass_fig(bas, s, 0, END, [(0, "r", 1.4), (2, "5", 0.9), (3, "r", 0.45), (3.5, "a", 0.45)], vel=84)
    _chacha_perc(dr, s, 0, END, vel=62)
    for name, b0 in plan:
        if name == "A":
            sx.melody(b0, C10_MEL_A, vel=82)
        elif name == "A2":
            sx.melody(b0, C10_MEL_A2, vel=84)
        elif name == "A2v":
            sx.melody(b0, C10_MEL_A2, vel=86)
            vn.melody(b0, C10_MEL_A2, vel=66, shift=12)
        elif name == "B":
            vn.melody(b0, C10_MEL_B, vel=82)
            pt.pad(st, s, b0, b0 + 8, lo=53, hi=70, n=4, vel=46)
        elif name == "Bs":
            sx.melody(b0, C10_MEL_B, vel=84)
            vn.melody(b0, C10_MEL_B, vel=58, shift=-12)
            pt.pad(st, s, b0, b0 + 8, lo=55, hi=74, n=4, vel=44)
        _timb_fill(dr, s, b0 + 7, vel=66)
    sx.melody(CODA, C10_MEL_CODA, vel=82)
    vn.melody(CODA, C10_MEL_CODA, vel=60, shift=12)
    end = END * s.bpb
    pno.chord(end, [mc.midi(n) for n in ("ab3", "eb4", "g4", "c5", "ab5")], 1.0, 74)
    sx.note(end, mc.midi("ab4"), 1.0, 86)
    vn.note(end, mc.midi("ab5"), 1.0, 70)
    bas.note(end, mc.midi("ab1"), 1.0, 90)
    dr.note(end, TIMB_L, 0.3, 74)
    dr.note(end, pt.KICK, 0.3, 70)
    dr.note(end, pt.CRASH, 2, 54)
    return mc.produce(s, gains={"lead": 0, "lead2": -2, "keys": -5, "bass": -4, "drums": -3, "pad": -8},
                      sends={"lead": 0.3, "lead2": 0.35, "keys": 0.2, "bass": 0.03, "drums": 0.15, "pad": 0.5},
                      rev_size=1.8,
                      eqs={"lead": lambda f: mc.hp_resp(f, 150, 2) * mc.bell_resp(f, 3000, -3, 0.8),
                           "lead2": lambda f: mc.hp_resp(f, 200, 2) * mc.bell_resp(f, 3000, -3, 0.7) * mc.lp_resp(f, 7000, 2)})


# ==========================================================================
# 11 "Onda": A major sunny surf pop, 140 BPM, 12-string and steel guitar
# ==========================================================================

C11_INTRO = ["A6", "A6", "D/A", "E7"]
C11_A = ["A6", "A6", "D/A", "A6", "F#m7", "B7", "Bm7", "E7",
         "A6", "C#7", "F#m7", "A7", "D6", "Dm6", "A6 F#m7", "Bm7 E7"]
C11_A_END = C11_A[:15] + ["A6"]
C11_B = ["Dmaj7", "E/D", "C#m7", "F#m7", "Bm7", "Fmaj7", "E7sus4", "E7"]
C11_CODA = ["D6", "Dm6", "A6", "A6"]
C11_MEL_A = ("e5/1 c#5/.5 e5/.5 f#5/1 e5/1 | a5/3 r/1 | f#5/1 d5/.5 f#5/.5 a5/1 f#5/1 | e5/3 r/1 |"
             " c#5/1 e5/1 a5/1 c#6/1 | d#6/2 b5/1 a5/1 | f#5/1.5 d5/.5 b4/1 d5/1 | g#5/3 r/1 |"
             " e5/1 c#5/.5 e5/.5 f#5/1 a5/1 | g#5/2 f5/1 c#5/1 | f#5/1 a5/1 c#6/1 e6/1 | g5/2 e5/1 c#5/1 |"
             " f#5/1.5 a5/.5 b5/2 | a5/1.5 f5/.5 d5/2 | c#5/1 e5/1 f#5/1 a5/1 | b5/2 g#5/2")
C11_MEL_A_END = bars(C11_MEL_A, 0, 15) + " | a5/3 r/1"
C11_MEL_B = ("a5/2 f#5/1 c#6/1 | b5/3 g#5/1 | e5/2 g#5/1 b5/1 | a5/3 r/1 |"
             " d6/2 b5/1 f#5/1 | e5/1 a5/1 c6/2 | b5/2 a5/2 | g#5/2 e5/1 d5/1")
C11_MEL_CODA = "f#5/1.5 a5/.5 b5/2 | a5/1.5 f5/.5 d5/2 | c#5/4 | r/4"


def _surf_kit(d, s, bar0, bar1, vel=70):
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for k in range(8):
            d.note(b + k * 0.5, pt.HH, 0.2, vel - 14 + (6 if k % 2 == 0 else -4))
        d.note(b, pt.KICK, 0.3, vel)
        d.note(b + 1.5, pt.KICK, 0.3, vel - 12)
        d.note(b + 2, pt.KICK, 0.3, vel - 4)
        d.note(b + 1, pt.SNARE, 0.3, vel - 4)
        d.note(b + 3, pt.SNARE, 0.3, vel - 2)
        d.note(b + 1, pt.TAMB, 0.2, vel - 18)
        d.note(b + 3, pt.TAMB, 0.2, vel - 16)


def cinquecento_11():
    s = Song("mus_cinquecento_11", bpm=140, bpb=4, loop=False, seed=411)
    bar = s.chords(0, C11_INTRO)
    A1 = bar; bar = s.chords(bar, C11_A)
    A2 = bar; bar = s.chords(bar, C11_A)
    B1 = bar; bar = s.chords(bar, C11_B)
    A3 = bar; bar = s.chords(bar, C11_A)
    B2 = bar; bar = s.chords(bar, C11_B)
    A4 = bar; bar = s.chords(bar, C11_A_END)
    CODA = bar; bar = s.chords(bar, C11_CODA)
    END = CODA + 3
    tw = s.part("twelve", 25, "lead", bank=8, vol=110, pan=-0.08, ht=0.008, hv=5)
    stl = s.part("steel", 26, "lead2", bank=8, vol=104, pan=0.2, ht=0.010, hv=4, expr=True)
    org = s.part("organ_lead", 17, "lead2", vol=92, pan=-0.2, ht=0.006, hv=4)
    rg = s.part("rhythm", 27, "gtr", vol=96, pan=0.38, ht=0.004, hv=5)
    bas = s.part("bass", 33, "bass", vol=110, ht=0.005, hv=4)
    dr = s.part("kit", 8, "drums", drum=True, vol=100, ht=0.005, hv=5)
    pad = s.part("organ_pad", 16, "pad", vol=80, pan=-0.25)
    _surf_kit(dr, s, 2, END, vel=70)
    for b0 in (A1, A2, B1, A3, B2, A4, CODA):
        pt.crash(dr, s, b0, vel=60)
        pt.fill(dr, s, b0 - 1, vel=70, kind="kit")
    comp_hits(rg, s, 0, END, (0, 1.5, 2, 3, 3.5), lo=55, hi=71, n=4, vel=50, dur=0.3, strum=0.01,
              accent=(0, 2))
    bass_fig(bas, s, 2, END, [(0, "r", 0.9), (1, "r", 0.4), (1.5, "5", 0.4), (2, "r", 0.9),
                              (3, "8", 0.4), (3.5, "5", 0.4)], vel=84)
    pt.arp(tw, s, 0, A1, lo=57, hi=79, pattern=(0, 1, 2, 3, 4, 3, 2, 1), step=0.5, vel=62, n=4, gate=1.2)
    tw.melody(A1, C11_MEL_A, vel=86)
    tw.melody(A2, C11_MEL_A, vel=86)
    pt.pad(pad, s, A2, A3, lo=55, hi=72, n=4, vel=40)
    stl.melody(B1, C11_MEL_B, vel=84)
    tw.melody(A3, C11_MEL_A, vel=88)
    pt.pad(pad, s, A3, A4, lo=55, hi=72, n=4, vel=36)
    org.melody(B2, C11_MEL_B, vel=82)
    stl.melody(B2, C11_MEL_B, vel=58, shift=-12)
    tw.melody(A4, C11_MEL_A_END, vel=84, tremolo=0.25, trem_min=1.0)
    stl.melody(A4 + 8, bars(C11_MEL_A_END, 8, 16), vel=56, shift=-12)
    pt.pad(pad, s, A4, END, lo=55, hi=72, n=4, vel=40)
    tw.melody(CODA, C11_MEL_CODA, vel=84, tremolo=0.25, trem_min=1.0)
    end = END * s.bpb
    tw.chord(end, mc.voicing(Chord("A6"), 57, 79, 5), 6, 78, strum=0.07)
    stl.note(end, mc.midi("e5"), 6, 70)
    bas.note(end, mc.midi("a1"), 4, 90)
    dr.note(end, pt.CRASH, 4, 66)
    dr.note(end, pt.KICK, 0.3, 76)
    return mc.produce(s, gains={"lead": 0, "lead2": -2, "gtr": -7, "bass": 0, "drums": -3, "pad": -8},
                      sends={"lead": 0.45, "lead2": 0.4, "gtr": 0.3, "bass": 0.03, "drums": 0.15, "pad": 0.4},
                      rev_size=2.2, rev_gain=1.15,
                      eqs={"lead": lambda f: mc.hp_resp(f, 160, 2) * mc.bell_resp(f, 3000, -2, 0.8) * mc.lp_resp(f, 6000, 2),
                           "drums": lambda f: mc.hp_resp(f, 40, 2) * mc.shelf_resp(f, 5000, -6)})


# ==========================================================================
# 12 "Barocco": B minor baroque pop, 104 BPM, harpsichord, strings, oboe
# ==========================================================================

C12_INTRO = ["Bm", "Bm/A", "G", "F#7"]
C12_A = ["Bm", "Bm/A", "G", "D/F#", "Em7", "Bm/D", "C#m7b5", "F#7"]
C12_A2 = ["Bm", "Bm/A", "G", "D/F#", "Em7", "A7", "Dmaj7", "F#7"]
C12_B = ["Dmaj7", "A/C#", "Bm7", "F#m/A", "Gmaj7", "D/F#", "Em7", "F#7sus4 F#7"]
C12_CODA = ["Em7", "F#7sus4 F#7", "B", "B"]
C12_MEL_A = ("f#5/.5 d5/.5 b4/.5 d5/.5 f#5/1 b5/1 | a5/.5 f#5/.5 d5/.5 f#5/.5 a5/1 c#6/1 |"
             " b5/1 g5/.5 b5/.5 d6/1 b5/1 | a5/2 f#5/1 d5/1 | e5/.5 g5/.5 b5/.5 e6/.5 d6/1 b5/1 |"
             " f#5/1 d5/.5 f#5/.5 b5/2 | g5/1 e5/1 c#5/1 b4/1 | a#4/1 c#5/1 e5/1 f#5/1")
C12_MEL_A2 = bars(C12_MEL_A, 0, 4) + (" | g5/.5 b5/.5 e6/.5 g5/.5 b5/1 g5/1 | c#6/1 a5/.5 g5/.5 e5/2 |"
                                       " f#5/1 a5/1 c#6/1 d6/1 | c#6/2 a#5/2")
C12_MEL_B = ("f#5/2 a5/2 | e5/2 a5/1 c#6/1 | d6/2 c#6/1 b5/1 | a5/2 f#5/2 |"
             " g5/1 b5/1 d6/1 f#6/1 | e6/2 d6/1 a5/1 | b5/1 g5/1 e5/1 b5/1 | b5/2 a#5/2")
C12_MEL_CODA = "g5/1 e5/1 b5/1 e6/1 | b5/2 a#5/2 | b5/4 | r/4"


def cinquecento_12():
    s = Song("mus_cinquecento_12", bpm=104, bpb=4, loop=False, seed=412)
    bar = s.chords(0, C12_INTRO)
    plan = []
    for name, prog in (("A", C12_A), ("A2", C12_A2), ("B", C12_B), ("Ao", C12_A), ("A2o", C12_A2),
                       ("Bo", C12_B), ("A2s", C12_A2)):
        plan.append((name, bar))
        bar = s.chords(bar, prog)
    CODA = bar
    bar = s.chords(bar, C12_CODA)
    END = CODA + 3
    hp = s.part("harpsichord", 6, "lead", bank=8, vol=100, pan=-0.1, ht=0.004, hv=4)
    ob = s.part("oboe", 68, "lead2", vol=100, pan=0.15, ht=0.010, hv=4, expr=True, lag=0.008)
    sl = s.part("string_lead", 48, "lead2", vol=104, pan=0.1, ht=0.012, hv=4, expr=True, lag=0.01)
    ha = s.part("harpsi_arp", 6, "keys", vol=90, pan=0.3, ht=0.004, hv=4)
    bas = s.part("bass", 34, "bass", vol=108, ht=0.004, hv=4)
    dr = s.part("kit", 8, "drums", drum=True, vol=100, ht=0.005, hv=5)
    st = s.part("strings", 49, "pad", vol=84, pan=-0.2)
    A0 = plan[0][1]
    pt.arp(ha, s, 0, A0, lo=59, hi=83, pattern=(0, 1, 2, 3, 2, 1, 2, 3), step=0.25, vel=56, n=4, gate=1.0)
    bass_fig(bas, s, A0, END, [(0, "r", 0.9), (1, "r", 0.45), (1.5, "8", 0.4), (2, "r", 0.9),
                               (3, "r", 0.45), (3.5, "8", 0.4)], vel=82)
    for bar_ in range(A0, END):
        b = bar_ * s.bpb
        for k in range(8):
            dr.note(b + k * 0.5, pt.HH, 0.2, 50 + (6 if k % 2 == 0 else -4))
        dr.note(b, pt.KICK, 0.3, 66)
        dr.note(b + 2.5, pt.KICK, 0.3, 56)
        dr.note(b + 1, pt.SNARE, 0.3, 58)
        dr.note(b + 3, pt.SNARE, 0.3, 60)
        dr.note(b + 1, pt.TAMB, 0.2, 40)
        dr.note(b + 3, pt.TAMB, 0.2, 42)
    for name, b0 in plan:
        if name == "A":
            hp.melody(b0, C12_MEL_A, vel=80)
            pt.arp(ha, s, b0, b0 + 8, lo=55, hi=72, pattern=(0, 2, 1, 2), step=0.5, vel=44, n=3, gate=1.0)
        elif name == "A2":
            hp.melody(b0, C12_MEL_A2, vel=82)
            pt.pad(st, s, b0, b0 + 8, lo=50, hi=67, n=3, vel=44)
        elif name == "B":
            sl.melody(b0, C12_MEL_B, vel=82)
            pt.arp(ha, s, b0, b0 + 8, lo=59, hi=83, pattern=(0, 1, 2, 3, 2, 1, 2, 3), step=0.25, vel=48, n=4,
                   gate=1.0)
            pt.pad(st, s, b0, b0 + 8, lo=50, hi=67, n=3, vel=40)
        elif name == "Ao":
            ob.melody(b0, C12_MEL_A, vel=80)
            pt.arp(ha, s, b0, b0 + 8, lo=55, hi=76, pattern=(0, 1, 2, 3), step=0.5, vel=46, n=4, gate=1.0)
        elif name == "A2o":
            hp.melody(b0, C12_MEL_A2, vel=82)
            ob.melody(b0, C12_MEL_A2, vel=68, shift=-12)
            pt.pad(st, s, b0, b0 + 8, lo=50, hi=67, n=3, vel=44)
        elif name == "Bo":
            ob.melody(b0, C12_MEL_B, vel=82)
            sl.melody(b0, C12_MEL_B, vel=60, shift=-12)
            pt.arp(ha, s, b0, b0 + 8, lo=59, hi=83, pattern=(0, 1, 2, 3, 2, 1, 2, 3), step=0.25, vel=48, n=4,
                   gate=1.0)
        elif name == "A2s":
            hp.melody(b0, C12_MEL_A2, vel=84)
            sl.melody(b0, C12_MEL_A2, vel=66, shift=-12)
            pt.pad(st, s, b0, b0 + 8, lo=50, hi=67, n=3, vel=44)
        pt.fill(dr, s, b0 + 7, vel=64, kind="kit")
    sl.melody(CODA, C12_MEL_CODA, vel=74)
    hp.melody(CODA, C12_MEL_CODA, vel=74)
    pt.pad(st, s, CODA, END, lo=50, hi=67, n=3, vel=44)
    end = END * s.bpb
    hp.chord(end, [mc.midi(n) for n in ("b2", "f#3", "b3", "d#4", "f#4", "b4")], 5, 80, strum=0.06)
    st.chord(end, mc.voicing(Chord("B"), 54, 71, 3), 5, 50)
    sl.note(end, mc.midi("b5"), 5, 66)
    bas.note(end, mc.midi("b1"), 4, 86)
    dr.note(end, pt.CRASH, 4, 60)
    dr.note(end, pt.KICK, 0.3, 70)
    return mc.produce(s, gains={"lead": 3, "lead2": -3, "keys": -6, "bass": 0, "drums": -3, "pad": -7},
                      sends={"lead": 0.3, "lead2": 0.4, "keys": 0.3, "bass": 0.03, "drums": 0.15, "pad": 0.5},
                      rev_size=2.0,
                      eqs={"lead": lambda f: mc.hp_resp(f, 150, 2) * mc.bell_resp(f, 3500, -3, 0.8) * mc.lp_resp(f, 7500, 2),
                           "keys": lambda f: mc.hp_resp(f, 180, 2) * mc.bell_resp(f, 3500, -3, 0.8) * mc.lp_resp(f, 6500, 2)})


# ==========================================================================
# 13 "Tramonto": D major 6/8 serenade (eighth = 126), mandolin and cello
# ==========================================================================

C13_INTRO = ["D", "A7sus4"]
C13_A = ["D", "Bm7", "Em7", "A7", "F#m7", "Bm7", "G Gm6", "D/A A7"]
C13_A2 = ["D", "Bm7", "Em7", "A7", "F#m7", "Bm7", "G Gm6", "D"]
C13_B = ["Gmaj7", "F#m7", "Em7", "D/F#", "Gmaj7", "C9", "Em7 A7sus4", "A7"]
C13_CODA = ["G Gm6", "D", "D"]
C13_MEL_A = ("f#5/3 e5/1 d5/1 e5/1 | f#5/2 a5/1 d6/3 | b5/3 g5/2 e5/1 | a5/4 g5/1 e5/1 |"
             " c#5/3 e5/1 f#5/1 a5/1 | d6/4 c#6/1 b5/1 | b5/2 a5/1 bb5/2 g5/1 | f#5/3 e5/3")
C13_MEL_A2 = bars(C13_MEL_A, 0, 6) + " | b5/2 d6/1 bb5/2 e5/1 | d5/6"
C13_MEL_B = ("b3/3 d4/2 f#4/1 | a4/4 f#4/1 e4/1 | g4/3 b3/2 e4/1 | f#4/4 e4/1 d4/1 |"
             " d4/2 g4/1 b4/3 | bb4/3 g4/2 e4/1 | g4/3 d4/3 | c#4/3 e4/2 a3/1")
C13_MEL_CODA = "b5/3 bb5/3 | a5/6 | r/6"


def cinquecento_13():
    s = Song("mus_cinquecento_13", bpm=126, bpb=6, loop=False, seed=413)
    bar = s.chords(0, C13_INTRO)
    A1 = bar; bar = s.chords(bar, C13_A)
    A2 = bar; bar = s.chords(bar, C13_A2)
    B1 = bar; bar = s.chords(bar, C13_B)
    A3 = bar; bar = s.chords(bar, C13_A)
    B2 = bar; bar = s.chords(bar, C13_B)
    A4 = bar; bar = s.chords(bar, C13_A2)
    CODA = bar; bar = s.chords(bar, C13_CODA)
    END = CODA + 2
    trem = 1 / 6
    man = s.part("mandolin", 25, "lead", bank=16, vol=106, pan=-0.08, ht=0.010, hv=5)
    mt = s.part("mandolin_trem", 25, "lead2", bank=16, vol=84, pan=0.3, ht=0.008, hv=4)
    vc = s.part("cello", 42, "lead2", vol=104, pan=0.1, ht=0.014, hv=4, expr=True, lag=0.012)
    gtr = s.part("guitar", 24, "gtr", vol=104, pan=-0.3, ht=0.008, hv=5)
    bas = s.part("bass", 32, "bass", vol=100, ht=0.01, hv=4)
    dr = s.part("drums", 40, "drums", drum=True, vol=100, ht=0.01, hv=4)
    st = s.part("strings", 49, "pad", vol=86, pan=0.2)
    pt.arp(gtr, s, 0, END, lo=47, hi=69, pattern=(0, 1, 2, 3, 2, 1), step=1, vel=50, n=4, gate=1.8,
           accent_every=3)
    bass_fig(bas, s, A1, END, [(0, "r", 2.8), (3, "5", 2.8)], vel=74)
    for bar_ in range(A2, END):
        b = bar_ * s.bpb
        dr.note(b, pt.BR_SWIRL, 2.9, 34)
        dr.note(b + 3, pt.BR_SWIRL, 2.9, 30)
        dr.note(b, pt.KICK, 0.3, 36)
        dr.note(b + 3, pt.BR_TAP, 0.2, 34)
    man.melody(A1, C13_MEL_A, vel=82, tremolo=trem, trem_min=1.5)
    man.melody(A2, C13_MEL_A2, vel=84, tremolo=trem, trem_min=1.5)
    vc.melody(B1, C13_MEL_B, vel=84)
    pt.tremolo_chord(mt, s, B1, A3, lo=62, hi=77, n=2, vel=40, rate=trem)
    pt.pad(st, s, B1, END, lo=53, hi=72, n=4, vel=42)
    man.melody(A3, C13_MEL_A, vel=84, tremolo=trem, trem_min=1.5)
    vc.melody(A3, bars(C13_MEL_A, 0, 8), vel=56, shift=-24)
    man.melody(B2, C13_MEL_B, vel=82, shift=12, tremolo=trem, trem_min=1.5)
    vc.melody(B2, C13_MEL_B, vel=66)
    man.melody(A4, C13_MEL_A2, vel=86, tremolo=trem, trem_min=1.5)
    vc.melody(A4, C13_MEL_A2, vel=62, shift=-12)
    man.melody(CODA, C13_MEL_CODA, vel=78, tremolo=trem, trem_min=1.5)
    end = END * s.bpb
    gtr.chord(end, [mc.midi(n) for n in ("d2", "a2", "d3", "f#3", "a3", "d4")], 8, 60, strum=0.12)
    mt.chord(end, [mc.midi("f#5"), mc.midi("a5")], 4, 50)
    vc.note(end, mc.midi("d3"), 8, 64)
    st.chord(end, mc.voicing(Chord("D"), 54, 74, 4), 8, 42)
    bas.note(end, mc.midi("d1"), 8, 70)
    return mc.produce(s, gains={"lead": 0, "lead2": -2, "gtr": -2, "bass": 0, "drums": -6, "pad": -7},
                      sends={"lead": 0.35, "lead2": 0.4, "gtr": 0.25, "bass": 0.03, "drums": 0.25, "pad": 0.5},
                      rev_size=2.6, eqs={"lead": lambda f: mc.hp_resp(f, 150, 2) * mc.lp_resp(f, 6000, 2),
                           "lead2": lambda f: mc.hp_resp(f, 70, 2) * mc.lp_resp(f, 6500, 2)})


# ==========================================================================
# 14 "Pomeriggio": F minor samba, 104 BPM, flute and Rhodes
# ==========================================================================

C14_INTRO = ["Fm9", "Bb13", "Fm9", "Bb13"]
C14_A = ["Fm9", "Bb13", "Fm9", "Bb13", "Ebm9", "Ab13", "Dbmaj7", "C7#9",
         "Fm9", "Bb13", "Abmaj7", "Dbmaj7", "Gm7b5", "C7b9", "Fm9", "C7#9"]
C14_B = ["Dbmaj7", "Gb9", "Bbm9", "Eb13", "Abmaj7", "Dbmaj7", "Gm7b5", "C7b9"]
C14_CODA = ["Dbmaj7", "C7#9", "Fm9", "Fm9"]
C14_MEL_A = ("r/.5 c6/1 ab5/.5 g5/1 f5/1 | ab5/1.5 g5/.5 d5/2 | r/.5 c6/1 eb6/.5 c6/1 ab5/1 | g5/3 r/1 |"
             " r/.5 bb5/1 db6/.5 bb5/1 gb5/1 | f5/1.5 eb5/.5 c5/2 | r/.5 f5/1 ab5/.5 c6/1 db6/1 |"
             " bb5/1.5 g5/.5 e5/2 |"
             " r/.5 c6/1 ab5/.5 g5/1 f5/1 | ab5/1.5 g5/.5 d5/2 | r/.5 eb5/1 g5/.5 c6/1 bb5/1 | ab5/3 f5/1 |"
             " r/.5 bb5/1 db6/.5 bb5/1 f5/1 | e5/1.5 g5/.5 db6/2 | c6/1 ab5/1 g5/1 f5/1 | e5/3 r/1")
C14_MEL_B = ("f5/1.5 ab5/.5 c6/2 | bb5/1.5 ab5/.5 e5/2 | db5/1 f5/1 c6/1.5 ab5/.5 | g5/2 db5/2 |"
             " c5/1 eb5/1 g5/1 bb5/1 | ab5/2 f5/2 | db6/1.5 bb5/.5 f5/2 | e5/1 g5/1 bb5/1 db6/1")
C14_MEL_CODA = "f5/1.5 ab5/.5 c6/2 | bb5/1.5 g5/.5 e5/2 | f5/4 | r/4"


def _samba_kit(d, s, bar0, bar1, vel=62, agogo=False):
    tam = (0, 0.75, 1.5, 2.25, 2.75, 3.5)
    for bar in range(bar0, bar1):
        b = bar * s.bpb
        for k in range(16):
            d.note(b + k * 0.25, pt.SHAKER, 0.1, vel - 26 + (10 if k % 4 == 3 else 0) + (4 if k % 4 == 0 else 0))
        for k, kv in ((0, -14), (1, 2), (2, -14), (3, 2)):
            d.note(b + k, pt.KICK, 0.3, vel + kv)
        d.note(b + 0.75, pt.KICK, 0.2, vel - 22)
        d.note(b + 2.75, pt.KICK, 0.2, vel - 22)
        for off in tam:
            d.note(b + off, pt.STICK, 0.1, vel - 10)
        for k in range(4):
            d.note(b + k + 0.5, pt.PEDAL, 0.1, vel - 24)
        if agogo:
            for off, n_ in ((0, AGOGO_L), (0.5, AGOGO_H), (1.5, AGOGO_H), (2, AGOGO_L), (2.75, AGOGO_H), (3.5, AGOGO_H)):
                d.note(b + off, n_, 0.1, vel - 18)


def cinquecento_14():
    s = Song("mus_cinquecento_14", bpm=104, bpb=4, loop=False, seed=414)
    bar = s.chords(0, C14_INTRO)
    A1 = bar; bar = s.chords(bar, C14_A)
    B1 = bar; bar = s.chords(bar, C14_B)
    A2 = bar; bar = s.chords(bar, C14_A)
    B2 = bar; bar = s.chords(bar, C14_B)
    A3 = bar; bar = s.chords(bar, C14_A)
    CODA = bar; bar = s.chords(bar, C14_CODA)
    END = CODA + 3
    fl = s.part("flute", 73, "lead", vol=104, pan=0.0, ht=0.010, hv=5, expr=True, lag=0.006)
    rl = s.part("rhodes_lead", 4, "lead2", vol=108, pan=-0.12, ht=0.008, hv=5)
    rc = s.part("rhodes_comp", 4, "keys", vol=92, pan=0.3, ht=0.006, hv=4)
    gtr = s.part("guitar", 24, "gtr", vol=96, pan=-0.35, ht=0.006, hv=5)
    bas = s.part("bass", 33, "bass", vol=110, ht=0.005, hv=4)
    dr = s.part("kit", 8, "drums", drum=True, vol=100, ht=0.005, hv=5)
    st = s.part("strings", 49, "pad", vol=80, pan=0.2)
    _samba_kit(dr, s, 0, A1, vel=54)
    _samba_kit(dr, s, A1, B1, vel=62)
    _samba_kit(dr, s, B1, A2, vel=62, agogo=True)
    _samba_kit(dr, s, A2, B2, vel=64)
    _samba_kit(dr, s, B2, A3, vel=64, agogo=True)
    _samba_kit(dr, s, A3, END, vel=64)
    for b0 in (A1, B1, A2, B2, A3, CODA):
        pt.fill(dr, s, b0 - 1, vel=64, kind="kit")
        pt.crash(dr, s, b0, vel=50)
    comp_hits(rc, s, 0, END, (0, 0.75, 1.5, 2.5, 3.25), lo=55, hi=72, n=4, vel=48, dur=0.35, accent=(0,))
    pt.bossa_guitar(gtr, s, A1, END, lo=52, hi=69, vel=46)
    bass_fig(bas, s, 0, END, [(0, "r", 0.7), (0.75, "5", 0.2), (1, "5", 0.9), (2, "r", 0.7),
                              (2.75, "5", 0.2), (3, "8", 0.45), (3.5, "a", 0.4)], vel=84)
    fl.melody(A1, C14_MEL_A, vel=84)
    rl.melody(B1, C14_MEL_B, vel=86)
    pt.pad(st, s, B1, A2, lo=55, hi=72, n=4, vel=40)
    fl.melody(A2, C14_MEL_A, vel=86)
    rl.melody(A2 + 8, bars(C14_MEL_A, 8, 16), vel=60, shift=-12)
    fl.melody(B2, C14_MEL_B, vel=86)
    pt.pad(st, s, B2, END, lo=55, hi=72, n=4, vel=40)
    rl.melody(A3, C14_MEL_A, vel=86)
    fl.melody(A3 + 8, bars(C14_MEL_A, 8, 16), vel=80, shift=12)
    fl.melody(CODA, C14_MEL_CODA, vel=80)
    end = END * s.bpb
    rl.chord(end, [mc.midi(n) for n in ("f3", "c4", "eb4", "g4", "ab4", "c5")], 6, 72, strum=0.03)
    fl.note(end, mc.midi("f5"), 3, 70)
    bas.note(end, mc.midi("f1"), 4, 86)
    dr.note(end, pt.RIDE, 4, 56)
    dr.note(end, pt.KICK, 0.3, 64)
    return mc.produce(s, gains={"lead": 0, "lead2": -1, "keys": -6, "gtr": -6, "bass": 0, "drums": -3, "pad": -8},
                      sends={"lead": 0.35, "lead2": 0.3, "keys": 0.25, "gtr": 0.2, "bass": 0.03, "drums": 0.15, "pad": 0.5},
                      rev_size=2.0, eqs={"lead": lambda f: mc.hp_resp(f, 200, 2) * mc.lp_resp(f, 8000, 2)})


# ==========================================================================
# 15 "Crepuscolo": Db major dusk ballad, 66 BPM, muted trumpet and vibes
# ==========================================================================

C15_INTRO = ["Gbmaj7", "Ab13sus4"]
C15_A = ["Dbmaj9", "Gb7#11", "Fm7", "Bbm9", "Ebm9", "Ab13", "Fm7 Bb7b9", "Ebm9 Ab7b9"]
C15_A2 = C15_A[:6] + ["Ebm9 Ab13", "Dbmaj9"]
C15_B = ["Bbm9", "Eb13", "Abmaj9", "Dbmaj7", "Gm7b5", "C7b9", "Fm7 E7#11", "Ebm9 Ab7b9"]
C15_CODA = ["Gbmaj7", "Ab13sus4", "Dbmaj9"]
C15_MEL_A = ("f5/1.5 eb5/.5 c5/2 | bb4/1 c5/1 e5/2 | eb5/1.5 c5/.5 ab4/2 | db5/1 f5/1 c6/2 |"
             " bb5/1.5 gb5/.5 f5/1 db5/1 | eb5/2 f5/1 gb5/1 | ab4/1 c5/1 d5/1 b4/1 | bb4/1 db5/1 c5/1 a4/1")
C15_MEL_A2 = bars(C15_MEL_A, 0, 6) + " | gb5/1 f5/1 f5/1 eb5/1 | db5/3 r/1"
C15_MEL_B = ("f5/1 ab5/1 c6/2 | db6/1.5 c6/.5 g5/2 | eb5/1 g5/1 bb5/2 | ab5/3 f5/1 |"
             " bb5/1.5 g5/.5 db5/2 | e5/1 g5/1 db6/1 bb5/1 | ab5/2 g#5/2 | gb5/2 c5/1 eb5/1")
C15_MEL_CODA = "bb5/2 ab5/1 f5/1 | eb5/4 | db5/4"


def cinquecento_15():
    s = Song("mus_cinquecento_15", bpm=66, bpb=4, loop=False, seed=415, swing=0.15)
    bar = s.chords(0, C15_INTRO)
    A1 = bar; bar = s.chords(bar, C15_A)
    A2 = bar; bar = s.chords(bar, C15_A2)
    B1 = bar; bar = s.chords(bar, C15_B)
    A3 = bar; bar = s.chords(bar, C15_A)
    A4 = bar; bar = s.chords(bar, C15_A2)
    CODA = bar; bar = s.chords(bar, C15_CODA)
    END = CODA + 3
    tp = s.part("muted_trumpet", 59, "lead", vol=108, pan=-0.05, ht=0.016, hv=5, expr=True, lag=0.015)
    vb = s.part("vibes", 11, "lead2", vol=96, pan=0.25, ht=0.012, hv=4)
    hp = s.part("harp", 46, "keys", vol=90, pan=0.3, ht=0.01, hv=4)
    gtr = s.part("jazz_gtr", 26, "gtr", vol=100, pan=-0.3, ht=0.012, hv=4)
    bas = s.part("bass", 32, "bass", vol=104, ht=0.012, hv=4)
    dr = s.part("drums", 40, "drums", drum=True, vol=100, ht=0.012, hv=4)
    st = s.part("strings", 49, "pad", vol=86, pan=0.15)
    pt.arp(hp, s, 0, A1, lo=53, hi=84, pattern=(0, 1, 2, 3, 4, 5, 4, 3), step=0.5, vel=50, n=4, gate=2.5)
    pt.pad(gtr, s, A1, END, lo=52, hi=69, n=4, vel=46, retrig=2, strum=0.03, gap=0.2)
    pt.bass_two(bas, s, A1, END, vel=72, push=0.2)
    pt.brush_ballad(dr, s, A1, CODA + 2, vel=46)
    tp.melody(A1, C15_MEL_A, vel=80)
    tp.melody(A2, C15_MEL_A2, vel=82)
    pt.pad(st, s, A2, B1, lo=53, hi=70, n=3, vel=40)
    tp.melody(B1, C15_MEL_B, vel=86)
    pt.pad(st, s, B1, END, lo=53, hi=72, n=4, vel=44)
    pt.arp(hp, s, B1 + 4, B1 + 8, lo=60, hi=84, pattern=(0, 1, 2, 3), step=0.5, vel=36, n=4, gate=2.0)
    vb.melody(A3, C15_MEL_A, vel=78)
    tp.melody(A4, C15_MEL_A2, vel=84)
    vb.melody(A4, C15_MEL_A2, vel=50, shift=12)
    tp.melody(CODA, C15_MEL_CODA, vel=76)
    pt.arp(hp, s, CODA, CODA + 2, lo=60, hi=88, pattern=(0, 1, 2, 3, 4, 5, 6, 7), step=0.5, vel=40, n=4,
           gate=2.5)
    end = (CODA + 2) * s.bpb
    vb.chord(end, [mc.midi(n) for n in ("f4", "ab4", "c5", "eb5")], 6, 60, strum=0.04)
    hp.chord(end, [mc.midi(n) for n in ("db3", "ab3", "eb4", "f4", "c5", "f5")], 6, 54, strum=0.12)
    bas.note(end, mc.midi("db1"), 6, 70)
    dr.note(end, pt.RIDE, 4, 44)
    return mc.produce(s, gains={"lead": 0, "lead2": -2, "keys": -7, "gtr": -3, "bass": 0, "drums": -4, "pad": -7},
                      sends={"lead": 0.4, "lead2": 0.4, "keys": 0.45, "gtr": 0.25, "bass": 0.03, "drums": 0.25, "pad": 0.55},
                      rev_size=2.8, eqs={"lead": lambda f: mc.hp_resp(f, 150, 2) * mc.bell_resp(f, 3200, -6, 0.7) * mc.lp_resp(f, 5000, 2)},
                      tape_kw={"lp_hz": 9000, "hiss_db": -50})


TRACKS = {
    f"mus_cinquecento_{k:02d}": (lambda fn=fn, k=k: {f"mus_cinquecento_{k:02d}": (fn(), False)})
    for k, fn in ((6, cinquecento_06), (7, cinquecento_07), (8, cinquecento_08), (9, cinquecento_09),
                  (10, cinquecento_10), (11, cinquecento_11), (12, cinquecento_12), (13, cinquecento_13),
                  (14, cinquecento_14), (15, cinquecento_15))
}
