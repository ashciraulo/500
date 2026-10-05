"""Music for bird-watching and fishing: slow, sparse, outdoors.

The rest of the score is the radio. These few pieces are for the quiet in
between, in the way Dredge scores its open water: a field-journal theme
that loops under the journal screen, a dawn cue and a dusk cue when the
light turns (played only while the radio is off), and a small figure for a
new species. They share one motif, the radio idents' four notes slowed
right down and spread out (D B G D), so the field feels part of the same
world as the stations.

    python3 audio/tools/gen_music.py mus_field_journal mus_field_dawn mus_field_dusk mus_field_new_species
"""
from __future__ import annotations

import music_core as mc
import music_patterns as pt
from music_core import Song
from music_tracks_main import _sting_produce, _sting_song

# Nylon guitar, vibes, a warm pad, fretless bass: no drums out here.
GUITAR, VIBES, CELESTA, HARP, WARM_PAD, FRETLESS, FLUTE = 24, 11, 8, 46, 89, 35, 73

JOURNAL = [
    "Gmaj7", "Em9", "Cmaj9", "D9sus4:2 D6:2",
    "Gmaj7", "Bm7", "Cmaj9", "Am9:2 D9sus4:2",
    "Em9", "Cmaj7", "Gmaj7/B", "Am7:2 D6:2",
    "Cmaj9", "Gmaj7/B", "Am9", "D9sus4:2 D6:2",
]
# The motif (D B G D) stretched over two bars, then answered.
MEL_A = "d5/3 b4/1 | g4/2 >d5/2 | r/4 | r/2 e5/1 d5/1"
MEL_B = "b4/3 g4/1 | a4/4 | r/4 | r/2 f#4/1 g4/1"
MEL_C = "e5/2 d5/2 | b4/4 | c5/2 b4/1 a4/1 | g4/2 r/2"
MEL_D = "r/4 | d5/3 b4/1 | g4/4 | a4/2 r/2"


def field_journal():
    s = Song("mus_field_journal", bpm=68, bpb=4, loop=True, seed=1201)
    s.chords(0, JOURNAL)
    gtr = s.part("guitar", GUITAR, "gtr", vol=96, pan=-0.3, ht=0.012, hv=6)
    vib = s.part("vibes", VIBES, "lead", vol=100, pan=0.15, ht=0.012, hv=5, lag=0.01)
    pad = s.part("pad", WARM_PAD, "pad", vol=76, pan=0.25, ht=0.01, hv=2, drift=4)
    bas = s.part("bass", FRETLESS, "bass", vol=96, ht=0.01, hv=4)
    pt.arp(gtr, s, 0, 16, lo=50, hi=74, pattern=(0, 2, 1, 3, 2, 4), step=0.5, vel=52, gate=2.4)
    pt.pad(pad, s, 0, 16, lo=55, hi=74, n=4, vel=44)
    vib.melody(0, MEL_A, vel=62)
    vib.melody(4, MEL_B, vel=58)
    vib.melody(8, MEL_C, vel=60)
    vib.melody(12, MEL_D, vel=56)
    for b, d, ch in s.segs(0, 16):
        bas.note(b, mc.nearest(ch.bass, 38, 31, 45), d - 0.1, 66)
    return mc.produce(s, gains={"gtr": 0, "lead": 0, "pad": -9, "bass": -11},
                      sends={"gtr": 0.35, "lead": 0.45, "pad": 0.6, "bass": 0.05},
                      rev_size=3.0, rev_damp=4000,
                      tape_kw={"dropouts": 0.0, "hiss_db": -54, "lp_hz": 9000})


def field_dawn():
    """First light: a pad opening up and the motif climbing on celesta."""
    s = _sting_song("mus_field_dawn", 1202, bpm=64)
    s.chords(0, ["Cmaj9", "D9sus4", "Gmaj9", "Gmaj9"])
    cel = s.part("celesta", CELESTA, "lead", vol=96, pan=0.2, ht=0.006, hv=3)
    flu = s.part("flute", FLUTE, "lead", vol=80, pan=-0.15, ht=0.01, hv=3, expr=True)
    pad = s.part("pad", WARM_PAD, "pad", vol=80, ht=0.01, hv=2)
    gtr = s.part("guitar", GUITAR, "gtr", vol=90, pan=-0.3)
    pt.pad(pad, s, 0, 4, lo=55, hi=76, n=4, vel=50, swell=True)
    cel.melody(0, "r/2 g4/1 b4/1 | d5/2 g5/2 | b5/4 | r/4", vel=64)
    flu.melody(1, "r/2 a5/2 | d6/4 | r/4", vel=56)
    gtr.chord(8, mc.voicing(mc.Chord("Gmaj9"), 50, 74, 6), 8, 50, strum=0.08)
    return _sting_produce(s, {"lead": 0, "pad": -6, "gtr": -4}, {"lead": 0.5, "pad": 0.6, "gtr": 0.4},
                          fade_out=3.0, length=16.0)


def field_dusk():
    """The light going: the motif falling, the last chord left open."""
    s = _sting_song("mus_field_dusk", 1203, bpm=60)
    s.chords(0, ["Em9", "Cmaj7", "Am9", "Bm7"])
    vib = s.part("vibes", VIBES, "lead", vol=96, pan=0.15, ht=0.01, hv=4)
    pad = s.part("pad", WARM_PAD, "pad", vol=80, ht=0.01, hv=2, drift=6)
    gtr = s.part("guitar", GUITAR, "gtr", vol=90, pan=-0.3)
    bas = s.part("bass", FRETLESS, "bass", vol=90)
    pt.pad(pad, s, 0, 4, lo=52, hi=72, n=4, vel=46)
    pt.arp(gtr, s, 0, 3, lo=47, hi=71, pattern=(0, 1, 2, 3), step=1.0, vel=46, gate=3.0)
    vib.melody(0, "d5/3 b4/1 | g4/4 | e4/2 d4/2 | r/4", vel=60)
    for b, d, ch in s.segs(0, 4):
        bas.note(b, mc.nearest(ch.root, 36, 28, 43), d - 0.1, 60)
    return _sting_produce(s, {"lead": 2, "pad": -7, "gtr": -3, "bass": -12},
                          {"lead": 0.5, "pad": 0.6, "gtr": 0.4, "bass": 0.05}, fade_out=3.5, length=17.0)


def field_new_species():
    """A new page in the journal: three notes of the motif on harp and celesta."""
    s = _sting_song("mus_field_new_species", 1204, bpm=84)
    s.chords(0, ["Gmaj9", "Gmaj9"])
    harp = s.part("harp", HARP, "keys", vol=100, pan=-0.2, ht=0.003, hv=3)
    cel = s.part("celesta", CELESTA, "lead", vol=96, pan=0.2, ht=0.004, hv=3)
    harp.chord(0, [55, 59, 62, 66, 69, 71], 6, 54, strum=0.07)
    cel.melody(0, "d6/.5 b5/.5 g5/.5 >d6/2.5 | r/4", vel=62)
    return _sting_produce(s, {"lead": 0, "keys": -3}, {"lead": 0.5, "keys": 0.45}, fade_out=1.5, length=6.0)


TRACKS = {
    "mus_field_journal": lambda: {"mus_field_journal": (field_journal(), True)},
    "mus_field_dawn": lambda: {"mus_field_dawn": (field_dawn(), False)},
    "mus_field_dusk": lambda: {"mus_field_dusk": (field_dusk(), False)},
    "mus_field_new_species": lambda: {"mus_field_new_species": (field_new_species(), False)},
}
