"""Station idents and the time pips for the car radio.

Each built-in station has a short sung or played signature it drops between
songs, the way real stations do: Radio Cinquecento's is four notes for
"Cin-que-cen-to" (D B G D, the last one held), Notte FM's is the same shape
slowed and turned down a third ("Not-te F-M"). No words: the "vocals" are a
small jingle-singer group on oohs, like a 1970s station ID package.

    python3 audio/tools/gen_music.py mus_ident_cinquecento mus_ident_nottefm mus_radio_pips
"""
from __future__ import annotations

import numpy as np

import music_core as mc
import music_patterns as pt
from music_core import Song
from music_tracks_main import _sting_produce, _sting_song

MANDOLIN = dict(program=25, bank=16)
ACCORDION = dict(program=21, bank=8)

# The four-note signatures (one bar of 4/4 each).
CINQ_MOTIF = "d5/.5 b4/.5 g4/.5 >d5/2.5"
NOTTE_MOTIF = "f5/1 db5/1 bb4/1 >f5/1"


def _ident(name, seed, bpm, length, gains, sends, fade_out=1.0):
    s = _sting_song(name, seed, bpm=bpm)
    return s, (lambda: _sting_produce(s, gains, sends, fade_out=fade_out, length=length))


def ident_cinq_01():
    """Jingle singers on oohs with vibes doubling, over a bossa guitar."""
    s, out = _ident("mus_ident_cinquecento_01", 801, 112, 5.0,
                    {"lead": 0, "pad": -1, "gtr": -5, "bass": -6, "drums": -9},
                    {"lead": 0.35, "pad": 0.45, "gtr": 0.2, "drums": 0.2, "bass": 0.04})
    s.chords(0, ["Gmaj9", "Gmaj9"])
    ch = s.part("choir", 53, "pad", vol=104, ht=0.008, hv=3)
    vib = s.part("vibes", 11, "lead", vol=96, pan=0.2, ht=0.004, hv=3)
    gtr = s.part("guitar", 24, "gtr", vol=96, pan=-0.3)
    bas = s.part("bass", 32, "bass", vol=104)
    dr = s.part("dr", 40, "drums", drum=True, vol=96)
    ch.melody(0, CINQ_MOTIF, vel=80)
    ch.melody(0, CINQ_MOTIF, vel=62, shift=-4)  # a third below
    vib.melody(0, CINQ_MOTIF, vel=70, shift=12)
    vib.note(4, mc.midi("g6"), 2, 52)
    pt.bossa_guitar(gtr, s, 0, 1, vel=50)
    gtr.chord(4, mc.voicing(mc.Chord("Gmaj9"), 52, 71, 5), 3, 48, strum=0.05)
    bas.melody(0, "g2/1.5 d2/.5 g2/2", vel=80)
    bas.note(4, mc.midi("g1"), 3, 80)
    dr.note(0, pt.BR_SWIRL, 3.5, 40)
    dr.note(4, pt.RIDE, 2, 46)
    return out()


def ident_cinq_02():
    """Mandolin tremolo and accordion, a little piazza flourish."""
    s, out = _ident("mus_ident_cinquecento_02", 802, 120, 4.5,
                    {"lead": 0, "keys": -3, "bass": -6, "drums": -9},
                    {"lead": 0.3, "keys": 0.3, "drums": 0.2, "bass": 0.04})
    s.chords(0, ["C6", "G6"])
    man = s.part("mandolin", MANDOLIN["program"], "lead", bank=16, vol=104, pan=0.15, ht=0.004, hv=3)
    acc = s.part("accordion", ACCORDION["program"], "keys", bank=8, vol=88, pan=-0.2)
    bas = s.part("bass", 32, "bass", vol=104)
    dr = s.part("dr", 40, "drums", drum=True, vol=96)
    man.melody(0, "e5/.25 f#5/.25 g5/.25 a5/.25 " + "c6/.5 a5/.5 r/.5 r/1.5 | " + CINQ_MOTIF.replace(">", ""),
               vel=74, tremolo=0.06)
    acc.chord(0, mc.voicing(mc.Chord("C6"), 55, 72, 4), 3.8, 54)
    acc.chord(4, mc.voicing(mc.Chord("G6"), 55, 74, 4), 4, 56)
    bas.melody(0, "c2/2 g1/2 | g1/4", vel=80, stacc=0.7)
    dr.note(4, pt.KICK, 0.3, 54)
    dr.note(4, pt.BR_SWIRL, 3, 40)
    return out()


def ident_cinq_03():
    """Organ and a short brass hit: the afternoon drive-time version."""
    s, out = _ident("mus_ident_cinquecento_03", 803, 128, 4.0,
                    {"lead": 0, "keys": -2, "bass": -5, "drums": -6},
                    {"lead": 0.25, "keys": 0.25, "drums": 0.15, "bass": 0.03})
    s.chords(0, ["Em7 A7", "Gmaj7"])
    br = s.part("brass", 61, "lead", vol=96, ht=0.004, hv=3)
    org = s.part("organ", 17, "keys", vol=84, pan=-0.2)
    bas = s.part("bass", 33, "bass", vol=104)
    dr = s.part("dr", 0, "drums", drum=True, vol=100)
    org.melody(0, "r/2 a4/.5 b4/.5 c#5/.5 d5/.5 | " + CINQ_MOTIF.replace(">", ""), vel=74)
    br.chord(4, mc.voicing(mc.Chord("Gmaj7"), 55, 74, 4), 0.4, 74)
    br.chord(5.5, mc.voicing(mc.Chord("Gmaj7"), 59, 79, 4), 2.0, 70)
    bas.melody(0, "e2/1 e2/.5 a1/.5 a1/1 c#2/1 | g1/4", vel=86, stacc=0.6)
    for k in range(8):
        dr.note(k * 0.5, pt.HH, 0.1, 50 if k % 2 == 0 else 36)
    dr.note(0, pt.KICK, 0.3, 64)
    dr.note(2, pt.SNARE, 0.3, 56)
    dr.note(3.5, pt.SNARE, 0.3, 50)
    dr.note(4, pt.KICK, 0.3, 70)
    dr.note(4, pt.CRASH, 2.5, 52)
    return out()


def ident_cinq_04():
    """Morning: flute and harp over held strings, softly."""
    s, out = _ident("mus_ident_cinquecento_04", 804, 96, 5.5,
                    {"lead": 0, "pad": -4, "keys": -3, "bass": -8},
                    {"lead": 0.4, "pad": 0.5, "keys": 0.4, "bass": 0.05}, fade_out=1.6)
    s.chords(0, ["Dmaj9", "Gmaj9"])
    flu = s.part("flute", 73, "lead", vol=96, pan=0.15, ht=0.004, hv=3)
    hrp = s.part("harp", 46, "keys", vol=92, pan=-0.25)
    st = s.part("strings", 49, "pad", vol=78)
    bas = s.part("bass", 32, "bass", vol=96)
    for k, n in enumerate(("d4", "a4", "d5", "f#5", "a5", "d6")):
        hrp.note(k * 0.33, mc.midi(n), 2.5, 56 - k * 2)
    flu.melody(0, "r/1 d5/.5 b4/.5 g4/.5 >d5/1.5", vel=70)
    st.chord(0, mc.voicing(mc.Chord("Dmaj9"), 55, 72, 4), 3.9, 44)
    st.chord(4, mc.voicing(mc.Chord("Gmaj9"), 55, 74, 4), 4, 46)
    bas.note(0, mc.midi("d2"), 3.8, 66)
    bas.note(4, mc.midi("g1"), 4, 66)
    return out()


def ident_notte_01():
    """Notte FM: Rhodes signature over a warm pad, a brush swirl."""
    s, out = _ident("mus_ident_nottefm_01", 811, 70, 6.5,
                    {"lead": 0, "pad": -2, "bass": -6, "drums": -10},
                    {"lead": 0.5, "pad": 0.6, "drums": 0.3, "bass": 0.05}, fade_out=2.0)
    s.chords(0, ["Dbmaj9", "Dbmaj9"])
    ep = s.part("rhodes", 4, "lead", vol=100, ht=0.01, hv=3)
    pad = s.part("pad", 89, "pad", vol=84)
    bas = s.part("bass", 38, "bass", vol=96)
    dr = s.part("dr", 40, "drums", drum=True, vol=90)
    ep.melody(0, NOTTE_MOTIF, vel=66)
    ep.chord(4, mc.voicing(mc.Chord("Dbmaj9"), 56, 75, 5), 4, 48, strum=0.08)
    pad.chord(0, mc.voicing(mc.Chord("Dbmaj9"), 49, 68, 4), 8, 50)
    bas.note(0, mc.midi("db2"), 8, 66)
    dr.note(0, pt.BR_SWIRL, 4, 36)
    return out()


def ident_notte_02():
    """Vibraphone and soft voices, slower still."""
    s, out = _ident("mus_ident_nottefm_02", 812, 62, 7.0,
                    {"lead": 0, "pad": -1, "bass": -7},
                    {"lead": 0.5, "pad": 0.6, "bass": 0.05}, fade_out=2.4)
    s.chords(0, ["Bbm9", "Gbmaj7#11"])
    vib = s.part("vibes", 11, "lead", vol=100, ht=0.008, hv=3)
    ch = s.part("choir", 53, "pad", vol=88, pan=0.1)
    bas = s.part("bass", 32, "bass", vol=96)
    vib.melody(0, NOTTE_MOTIF, vel=62)
    vib.note(4.5, mc.midi("ab5"), 3, 44)
    ch.chord(0, mc.voicing(mc.Chord("Bbm9"), 53, 70, 4), 3.9, 46)
    ch.chord(4, mc.voicing(mc.Chord("Gbmaj7#11"), 53, 72, 4), 4, 48)
    bas.note(0, mc.midi("bb1"), 3.9, 62)
    bas.note(4, mc.midi("gb1"), 4, 62)
    return out()


def ident_notte_03():
    """Glassy synth arpeggio: the small-hours version, almost a whisper."""
    s, out = _ident("mus_ident_nottefm_03", 813, 76, 6.0,
                    {"lead": 0, "keys": -3, "pad": -3},
                    {"lead": 0.55, "keys": 0.5, "pad": 0.6}, fade_out=2.2)
    s.chords(0, ["Abmaj9", "Dbmaj9"])
    arp = s.part("crystal", 98, "keys", vol=84, pan=-0.2, ht=0.004)
    lead = s.part("lead", 88, "lead", vol=92, pan=0.15, ht=0.01, hv=2)
    pad = s.part("pad", 91, "pad", vol=78)
    for k in range(16):
        n = ("ab4", "c5", "eb5", "g5")[k % 4] if k < 8 else ("db5", "f5", "ab5", "c6")[k % 4]
        arp.note(k * 0.5, mc.midi(n), 0.45, 50 - (k % 4) * 3)
    lead.melody(0, NOTTE_MOTIF, vel=60, shift=-12)
    pad.chord(0, mc.voicing(mc.Chord("Abmaj9"), 51, 70, 4), 3.9, 44)
    pad.chord(4, mc.voicing(mc.Chord("Dbmaj9"), 51, 70, 4), 4, 46)
    return out()


def radio_pips():
    """The time signal at the top of the hour: five short pips and a long
    sixth, 1 kHz, as broadcast on Australian radio; slightly band-limited
    like the rest of the station."""
    import sfxlib as S
    sr = mc.SR
    y = np.zeros(int(6.4 * sr))
    for k in range(6):
        d = 0.5 if k == 5 else 0.1
        n = int(d * sr)
        t = np.arange(n) / sr
        tone = np.sin(2 * np.pi * 1000 * t) * S.fade(np.ones(n), 0.004, 0.004)
        at = int(k * sr)
        y[at:at + n] += tone
    y = S.bp(y, 300, 3400, 2)
    return np.stack([y, y], axis=1)


TRACKS = {
    "mus_ident_cinquecento_01": lambda: {"mus_ident_cinquecento_01": (ident_cinq_01(), False)},
    "mus_ident_cinquecento_02": lambda: {"mus_ident_cinquecento_02": (ident_cinq_02(), False)},
    "mus_ident_cinquecento_03": lambda: {"mus_ident_cinquecento_03": (ident_cinq_03(), False)},
    "mus_ident_cinquecento_04": lambda: {"mus_ident_cinquecento_04": (ident_cinq_04(), False)},
    "mus_ident_nottefm_01": lambda: {"mus_ident_nottefm_01": (ident_notte_01(), False)},
    "mus_ident_nottefm_02": lambda: {"mus_ident_nottefm_02": (ident_notte_02(), False)},
    "mus_ident_nottefm_03": lambda: {"mus_ident_nottefm_03": (ident_notte_03(), False)},
    "mus_radio_pips": lambda: {"mus_radio_pips": (radio_pips(), False, "lufs:-20")},
}
