"""Core of the music generator: MIDI writing, harmony helpers, FluidSynth
rendering, mixing and the worn-VHS tape chain.

Everything here is deterministic. Compositions live in music_tracks*.py and
call into this module; gen_music.py is the entry point.

Timing model: a Song has a constant tempo. Parts hold notes in beats. All
MIDI is offset by one bar of pre-roll so humanised notes may land slightly
early. Loops are folded circularly (anything rendered past the loop end, such
as release and reverb tails, is added back onto the head), and every effect in
the chain is circular for loops, so the join is seamless by construction.
"""
from __future__ import annotations

import hashlib
import os
import struct
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import fft as sfft
from scipy import signal

import sfxlib

SR = sfxlib.SR
SF2 = "/usr/share/sounds/sf2/FluidR3_GM.sf2"
PPQ = 960
CACHE = Path(tempfile.gettempdir()) / "music500_stem_cache"

# --------------------------------------------------------------------------
# Pitch and chord helpers
# --------------------------------------------------------------------------

_PC = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}


def pc_of(name: str) -> int:
    name = name.strip().lower()
    v = _PC[name[0]]
    for ch in name[1:]:
        if ch == "#":
            v += 1
        elif ch == "b":
            v -= 1
    return v % 12


def midi(name: str) -> int:
    """'c4' -> 60, 'f#5' -> 78, 'bb3' -> 58."""
    name = name.strip().lower()
    i = 1
    while i < len(name) and name[i] in "#b":
        i += 1
    base = _PC[name[0]] + sum(1 if c == "#" else -1 for c in name[1:i])
    octv = int(name[i:])
    return 12 * (octv + 1) + base


# Intervals in priority order for voicing: guide tones first, then colour,
# then fifth and root. Value = semitones above root (may exceed 12).
QUALITIES = {
    "": [4, 7, 0],
    "maj": [4, 7, 0],
    "m": [3, 7, 0],
    "6": [4, 9, 7, 0],
    "69": [4, 9, 14, 7, 0],
    "m6": [3, 9, 7, 0],
    "m69": [3, 9, 14, 7, 0],
    "maj7": [4, 11, 7, 0],
    "maj9": [4, 11, 14, 7, 0],
    "maj7#11": [4, 11, 18, 14, 7, 0],
    "maj13": [4, 11, 14, 21, 7, 0],
    "m7": [3, 10, 7, 0],
    "m9": [3, 10, 14, 7, 0],
    "m11": [3, 10, 14, 17, 7, 0],
    "mmaj7": [3, 11, 7, 0],
    "mmaj9": [3, 11, 14, 7, 0],
    "m7b5": [3, 10, 6, 0],
    "dim7": [3, 9, 6, 0],
    "7": [4, 10, 7, 0],
    "9": [4, 10, 14, 7, 0],
    "13": [4, 10, 21, 14, 0],
    "7b9": [4, 10, 13, 7, 0],
    "7#9": [4, 10, 15, 7, 0],
    "7b13": [4, 10, 20, 14, 0],
    "7#11": [4, 10, 18, 14, 0],
    "7sus4": [5, 10, 7, 0],
    "9sus4": [5, 10, 14, 7, 0],
    "13sus4": [5, 10, 21, 14, 0],
    "sus2": [2, 7, 0],
    "sus4": [5, 7, 0],
    "add9": [4, 14, 7, 0],
    "madd9": [3, 14, 7, 0],
    "5": [7, 0],
    "aug": [4, 8, 0],
}


class Chord:
    def __init__(self, sym: str):
        self.sym = sym
        s = sym
        bass = None
        if "/" in s:
            s, b = s.split("/")
            bass = pc_of(b)
        i = 1
        while i < len(s) and s[i] in "#b":
            i += 1
        self.root = pc_of(s[:i])
        q = s[i:]
        if q not in QUALITIES:
            raise ValueError(f"unknown chord quality {q!r} in {sym}")
        self.ivs = QUALITIES[q]
        self.bass = self.root if bass is None else bass
        self.minor = q.startswith("m") and not q.startswith("maj")

    def pcs(self):
        return [(self.root + i) % 12 for i in self.ivs]

    def fifth_pc(self):
        for i in self.ivs:
            if i % 12 in (7, 6, 8):
                return (self.root + i) % 12
        return (self.root + 7) % 12

    def scale(self):
        """A plausible 7-note scale for melodic fills over this chord."""
        third = 3 if self.minor else 4
        sev = 10
        for i in self.ivs:
            if i % 12 == 11:
                sev = 11
        sixth = 9
        if any(i % 12 == 8 for i in self.ivs):
            sixth = 8
        sec = 1 if any(i % 12 == 1 for i in self.ivs) else 2
        four = 6 if any(i % 12 == 6 for i in self.ivs) and third == 4 else 5
        fifth = 6 if any(i == 6 for i in self.ivs) else 7
        return sorted({(self.root + i) % 12 for i in (0, sec, third, four, fifth, sixth, sev)})

    def __repr__(self):
        return f"Chord({self.sym})"


def nearest(pc: int, target: float, lo: int = 0, hi: int = 127) -> int:
    best = None
    for p in range(lo, hi + 1):
        if p % 12 == pc and (best is None or abs(p - target) < abs(best - target)):
            best = p
    if best is None:
        best = int(target)
    return best


def voicing(ch: Chord, lo: int, hi: int, n: int = 4, prev=None, root=False,
            centre=None) -> list[int]:
    """Choose an n-note voicing in [lo, hi] that leads smoothly from prev."""
    ivs = list(ch.ivs)
    if not root and len([i for i in ivs if i % 12]) >= n:
        ivs = [i for i in ivs if i % 12 != 0]
    pcs = []
    for i in ivs:
        pc = (ch.root + i) % 12
        if pc not in pcs:
            pcs.append(pc)
    pcs = pcs[:n]
    opts = []
    for pc in pcs:
        o = [p for p in range(lo, hi + 1) if p % 12 == pc]
        opts.append(o if o else [nearest(pc, (lo + hi) / 2)])
    import itertools
    centre = (lo + hi) / 2 if centre is None else centre
    best, bcost = None, 1e9
    for combo in itertools.product(*opts):
        v = sorted(combo)
        if len(set(v)) < len(v):
            continue
        if v[-1] - v[0] > 19:
            continue
        cost = 0.0
        for a, b in zip(v, v[1:]):
            d = b - a
            if d == 1:
                cost += 4 if a > 60 else 8
            if d < 3 and a < 50:
                cost += 6
        if v[-1] - v[0] < 5 and n >= 3:
            cost += 3
        if prev:
            pv = sorted(prev)
            if len(pv) == len(v):
                cost += sum(abs(a - b) for a, b in zip(v, pv)) * 0.7
            else:
                cost += abs(np.mean(v) - np.mean(pv)) * 1.5
        cost += abs(np.mean(v) - centre) * 0.35
        if cost < bcost:
            best, bcost = v, cost
    return best


# --------------------------------------------------------------------------
# Song / Part model
# --------------------------------------------------------------------------

class Part:
    def __init__(self, song, name, program, stem, bank=0, vol=100, pan=0.0,
                 drum=False, ht=0.008, hv=6, lag=0.0, swing=None, legato=1.0,
                 detune=0.0, drift=0.0, expr=False):
        self.song, self.name, self.program, self.stem = song, name, program, stem
        self.bank, self.vol, self.pan, self.drum = bank, vol, pan, drum
        self.ht, self.hv, self.lag = ht, hv, lag
        self.swing = song.swing if swing is None else swing
        self.legato = legato
        self.detune = detune  # cents, static pitch bend
        self.drift = drift  # cents, slow random pitch drift (night pads)
        self.expr = expr  # CC11 swells on long notes
        self.notes = []  # (beat, pitch, dur, vel)
        self.ccs = []  # (beat, cc, val)

    # basic events ---------------------------------------------------------
    def note(self, beat, pitch, dur, vel=80):
        if pitch is None:
            return
        self.notes.append((float(beat), int(pitch), float(dur), float(vel)))

    def chord(self, beat, pitches, dur, vel=70, strum=0.0):
        for k, p in enumerate(pitches):
            self.note(beat + k * strum, p, dur - k * strum, vel - k * 1.5)

    def cc(self, beat, num, val):
        self.ccs.append((float(beat), int(num), int(np.clip(val, 0, 127))))

    def ramp(self, b0, b1, num, v0, v1, step=0.25):
        n = max(1, int((b1 - b0) / step))
        for k in range(n + 1):
            self.cc(b0 + (b1 - b0) * k / n, num, v0 + (v1 - v0) * k / n)

    # melody notation ------------------------------------------------------
    def melody(self, bar, text, vel=80, shift=0, tremolo=0.0, trem_min=0.99,
               check=True, stacc=1.0, bpb=None):
        """Bars separated by '|'. Tokens 'pitch/dur' (dur in beats), 'r/dur'.
        Prefix '>' accents, suffix "'" is staccato, suffix '_' holds full
        length (legato). Returns the beat after the last note."""
        bpb = bpb or self.song.bpb
        beat = bar * bpb
        bars = [b for b in text.split("|")]
        bars = [b for b in bars if b.strip()]
        for bt in bars:
            start = beat
            for tok in bt.split():
                p, d = tok.split("/")
                d = float(eval(d))
                v = vel
                if p.startswith(">"):
                    p, v = p[1:], vel + 14
                st = stacc
                if p.endswith("'"):
                    p, st = p[:-1], 0.45
                if p.endswith("_"):
                    p, st = p[:-1], 1.02
                if p != "r":
                    pitch = midi(p) + shift
                    if tremolo and d >= trem_min:
                        k, n = 0, int(round(d / tremolo))
                        for k in range(n):
                            vv = v - 10 + (8 if k % 2 == 0 else 0) - 6 * (k / max(n, 1))
                            self.note(beat + k * tremolo, pitch, tremolo * 0.95, vv)
                    else:
                        self.note(beat, pitch, d * st, v)
                beat += d
            if check and abs(beat - start - bpb) > 1e-6:
                raise ValueError(f"{self.song.name}/{self.name}: bar at {start / bpb:.0f} "
                                 f"sums to {beat - start} beats: {bt!r}")
        return beat


class Song:
    def __init__(self, name, bpm, bpb=4, loop=False, seed=1, swing=0.0):
        self.name, self.bpm, self.bpb, self.loop = name, bpm, bpb, loop
        self.seed = seed
        self.rng = np.random.default_rng(seed)
        self.swing = swing
        self.parts: list[Part] = []
        self.timeline = []  # (beat, dur, Chord)
        self.nbars = 0
        self.tail_s = 6.0

    @property
    def spb(self):
        return 60.0 / self.bpm

    def part(self, *a, **k) -> Part:
        p = Part(self, *a, **k)
        self.parts.append(p)
        return p

    def chords(self, bar, bars):
        """Register a list of bar strings ('Dmaj7' or 'Em7 A7' or 'Em7:3 A7:1')
        starting at bar. Returns the bar after the last."""
        for k, s in enumerate(bars):
            toks = s.split()
            start = (bar + k) * self.bpb
            if all(":" in t for t in toks):
                b = start
                for t in toks:
                    sym, d = t.split(":")
                    self.timeline.append((b, float(d), Chord(sym)))
                    b += float(d)
            else:
                d = self.bpb / len(toks)
                for j, t in enumerate(toks):
                    self.timeline.append((start + j * d, d, Chord(t)))
        self.timeline.sort(key=lambda x: x[0])
        self.nbars = max(self.nbars, bar + len(bars))
        return bar + len(bars)

    def chord_at(self, beat) -> Chord:
        cur = self.timeline[0][2]
        for b, d, c in self.timeline:
            if b <= beat + 1e-6:
                cur = c
            else:
                break
        return cur

    def segs(self, bar0, bar1):
        """Chord segments between bars (clipped)."""
        b0, b1 = bar0 * self.bpb, bar1 * self.bpb
        out = []
        for b, d, c in self.timeline:
            s, e = max(b, b0), min(b + d, b1)
            if e > s + 1e-6:
                out.append((s, e - s, c))
        return out

    # MIDI -----------------------------------------------------------------
    def midi_bytes(self, stem: str) -> bytes:
        parts = [p for p in self.parts if p.stem == stem]
        rng = np.random.default_rng(abs(hash_str(self.name + stem)) % (2 ** 32))
        pre = self.bpb * self.spb  # seconds of pre-roll
        tps = PPQ * self.bpm / 60.0  # ticks per second
        tracks = []
        chan = 0
        end_s = pre + self.nbars * self.bpb * self.spb + self.tail_s
        for p in parts:
            if p.drum:
                ch = 9
            else:
                if chan == 9:
                    chan += 1
                ch = chan
                chan += 1
            if ch > 15:
                raise ValueError("too many parts in stem " + stem)
            ev = []  # (tick, order, bytes)
            ev.append((0, 0, bytes([0xB0 | ch, 0, p.bank if not p.drum else 0])))
            ev.append((0, 0, bytes([0xB0 | ch, 32, 0])))
            ev.append((0, 1, bytes([0xC0 | ch, p.program])))
            ev.append((0, 1, bytes([0xB0 | ch, 7, int(p.vol)])))
            ev.append((0, 1, bytes([0xB0 | ch, 10, int(np.clip(64 + p.pan * 63, 0, 127))])))
            ev.append((0, 1, bytes([0xB0 | ch, 11, 127])))
            ev.append((0, 1, bytes([0xB0 | ch, 91, 0])))
            ev.append((0, 1, bytes([0xB0 | ch, 93, 0])))
            # pitch bend: static detune + slow drift
            if p.detune or p.drift:
                n = int(end_s * 20)
                if p.drift:
                    w = np.cumsum(rng.standard_normal(n + 400))
                    w = signal.sosfiltfilt(signal.butter(2, 0.02, output="sos"), w)[200:200 + n]
                    w = (w - w.mean()) / (w.std() + 1e-9) * p.drift
                else:
                    w = np.zeros(n)
                cents = p.detune + w
                last = None
                for k in range(0 if p.drift else 1):
                    pass
                for k in range(n if p.drift else 1):
                    val = int(np.clip(8192 + cents[k] / 200 * 8192, 0, 16383))
                    if val == last:
                        continue
                    last = val
                    ev.append((int(k / 20 * tps), 1, bytes([0xE0 | ch, val & 127, val >> 7])))
            for b, num, val in p.ccs:
                t = pre + b * self.spb
                ev.append((int(t * tps), 1, bytes([0xB0 | ch, num, val])))
            # notes with humanisation
            notes = sorted(p.notes)
            timed = []
            for b, pitch, d, v in notes:
                t = b * self.spb
                frac = (b * 2) % 2
                if p.swing and abs(frac - 1.0) < 1e-3 and d >= 0.3:
                    t += p.swing * 0.5 * self.spb
                jit = np.clip(rng.standard_normal(), -2.5, 2.5) * p.ht
                t = pre + t + p.lag + jit
                dur = max(0.03, d * self.spb * p.legato)
                vel = int(np.clip(v + rng.standard_normal() * p.hv, 1, 127))
                timed.append([t, pitch, dur, vel])
                if p.expr and d * self.spb >= 1.2:
                    # gentle swell over long notes
                    t0, t1 = t, t + dur
                    k = 6
                    for j in range(k + 1):
                        x = j / k
                        e = 96 + 31 * np.sin(np.pi * min(1, x * 1.4)) ** 0.8 - 20 * x
                        ev.append((int((t0 + (t1 - t0) * x) * tps), 1, bytes([0xB0 | ch, 11, int(np.clip(e, 0, 127))])))
            # avoid overlaps of identical pitches
            byp = {}
            for n_ in timed:
                byp.setdefault(n_[1], []).append(n_)
            for lst in byp.values():
                lst.sort()
                for a, c in zip(lst, lst[1:]):
                    if a[0] + a[2] > c[0] - 0.004:
                        a[2] = max(0.01, c[0] - a[0] - 0.004)
            for t, pitch, dur, vel in timed:
                t = max(t, 0.0)
                ev.append((int(t * tps), 2, bytes([0x90 | ch, pitch, vel])))
                ev.append((int((t + dur) * tps), 0, bytes([0x80 | ch, pitch, 0])))
            ev.append((int(end_s * tps), 3, bytes([0xB0 | ch, 110, 0])))
            tracks.append(ev)
        # tempo track
        tempo = int(round(60e6 / self.bpm))
        t0 = [(0, 0, b"\xff\x51\x03" + tempo.to_bytes(3, "big"))]
        tracks.insert(0, t0)
        out = b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), PPQ)
        for ev in tracks:
            ev.sort(key=lambda e: (e[0], e[1]))
            chunks = []
            last = 0
            for t, _, by in ev:
                chunks.append(varlen(t - last) + by)
                last = t
            chunks.append(b"\x00\xff\x2f\x00")
            data = b"".join(chunks)
            out += b"MTrk" + struct.pack(">I", len(data)) + data
        return out

    def stems(self):
        names = []
        for p in self.parts:
            if p.stem not in names:
                names.append(p.stem)
        return names


def bars(text: str, a: int = 0, b: int | None = None) -> str:
    """Slice a melody string by bar index."""
    bs = [x for x in text.split("|") if x.strip()]
    return " | ".join(bs[a:b])


def transpose(song: Song, semis: int):
    for p in song.parts:
        if not p.drum:
            p.notes = [(b, pi + semis, d, v) for b, pi, d, v in p.notes]


def varlen(v: int) -> bytes:
    v = max(0, int(v))
    out = [v & 0x7F]
    v >>= 7
    while v:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    return bytes(reversed(out))


def hash_str(s: str) -> int:
    return int(hashlib.md5(s.encode()).hexdigest()[:8], 16)


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

def _fluid(mid: bytes, gain: float) -> np.ndarray:
    CACHE.mkdir(parents=True, exist_ok=True)
    key = hashlib.md5(mid + f"{gain}".encode() + b"v2").hexdigest()
    wav = CACHE / f"{key}.wav"
    if not wav.exists():
        with tempfile.TemporaryDirectory() as td:
            mp = Path(td) / "x.mid"
            mp.write_bytes(mid)
            tmpwav = Path(td) / "x.wav"
            subprocess.run(["fluidsynth", "-ni", "-q", "-R", "0", "-C", "0",
                            "-o", "synth.polyphony=1024", "-O", "float",
                            "-F", str(tmpwav), "-r", str(SR), "-g", str(gain),
                            SF2, str(mp)], check=True, capture_output=True)
            os.replace(tmpwav, wav)
    x, sr = sf.read(wav, dtype="float64", always_2d=True)
    assert sr == SR
    return x


def render(song: Song, gain=0.4) -> dict[str, np.ndarray]:
    names = song.stems()
    mids = [song.midi_bytes(n) for n in names]
    with ThreadPoolExecutor(4) as ex:
        outs = list(ex.map(lambda m: _fluid(m, gain), mids))
    n = max(len(o) for o in outs)
    res = {}
    for name, o in zip(names, outs):
        y = np.zeros((n, 2))
        y[: len(o)] = o
        res[name] = y
    return res


def loop_len(song: Song) -> int:
    return int(round(song.nbars * song.bpb * song.spb * SR))


def arrange(song: Song, x: np.ndarray) -> np.ndarray:
    """Cut the pre-roll and, for loops, fold everything circularly onto the
    exact loop length. Non-loops keep their tail."""
    pre = int(round(song.bpb * song.spb * SR))
    if song.loop:
        L = loop_len(song)
        out = np.zeros((L, 2))
        # anything early (humanised before bar 0) goes to the loop end
        out[L - pre:] += x[:pre]
        k = pre
        while k < len(x):
            seg = x[k:k + L]
            out[: len(seg)] += seg
            k += L
        return out
    lead = int(0.03 * SR)
    return x[pre - lead:]


# --------------------------------------------------------------------------
# Effects (circular so loops stay seamless)
# --------------------------------------------------------------------------

def fft_eq(x: np.ndarray, fn) -> np.ndarray:
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    g = fn(np.maximum(f, 1e-3))
    X = sfft.rfft(x, axis=0, workers=4)
    return sfft.irfft(X * (g[:, None] if x.ndim == 2 else g), n, axis=0, workers=4)


def lp_resp(f, fc, order=2):
    return 1 / np.sqrt(1 + (f / fc) ** (2 * order))


def hp_resp(f, fc, order=2):
    return 1 / np.sqrt(1 + (fc / f) ** (2 * order))


def bell_resp(f, f0, db, q=1.0):
    # log-frequency gaussian bell, cheap and smooth
    oct_ = np.log2(f / f0)
    bw = 1.0 / q
    return 10 ** (db / 20 * np.exp(-0.5 * (oct_ / (bw * 0.6)) ** 2))


def shelf_resp(f, fc, db):
    """High shelf (db>0 boost, <0 cut) above fc, smooth."""
    s = 1 / (1 + (fc / f) ** 2)
    return 10 ** (db / 20 * s)


def make_ir(size_s=2.0, damp=4500, seed=3, predelay=0.012, er=True):
    r = np.random.default_rng(seed)
    n = int(size_s * SR)
    t = np.arange(n) / SR
    irs = []
    for c in range(2):
        lo = sfxlib.lp(r.standard_normal(n), 1200, 2) * np.exp(-6.9 * t / size_s)
        hi = sfxlib.hp(r.standard_normal(n), 1200, 2) * np.exp(-6.9 * t / (size_s * 0.45))
        ir = lo * 1.3 + hi
        ir = sfxlib.lp(ir, damp, 2)
        ir[: int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))
        if er:
            for k in range(7):
                d = int(r.uniform(0.007, 0.045) * SR)
                ir[d] += r.uniform(0.3, 0.8) * (1 if r.random() > 0.5 else -1) * 3
        ir = np.concatenate([np.zeros(int(predelay * SR)), ir])
        irs.append(ir / np.sqrt(np.sum(ir ** 2)))
    return irs


def conv_circ(x: np.ndarray, irs) -> np.ndarray:
    n = len(x)
    out = np.zeros_like(x)
    for c in range(2):
        k = np.zeros(n)
        m = min(n, len(irs[c]))
        k[:m] = irs[c][:m]
        out[:, c] = sfft.irfft(sfft.rfft(x[:, c], workers=4) * sfft.rfft(k, workers=4), n, workers=4)
    return out


def rms(x):
    return float(np.sqrt(np.mean(x ** 2)) + 1e-12)


def mix(song: Song, stems: dict, gains: dict, sends: dict | None = None,
        eqs: dict | None = None, rev_size=2.0, rev_damp=4500, rev_seed=3,
        rev_gain=1.0) -> np.ndarray:
    """Sum arranged stems with gains (dB), optional per-stem EQ fns, and a
    shared reverb fed by per-stem sends (0..1)."""
    sends = sends or {}
    eqs = eqs or {}
    arr = {k: arrange(song, v) for k, v in stems.items()}
    n = max(len(v) for v in arr.values())
    if not song.loop:
        n = sfft.next_fast_len(n + int(rev_size * SR), real=True)
    dry = np.zeros((n, 2))
    wet = np.zeros((n, 2))
    levels = {}
    for k, v in arr.items():
        g = 10 ** (gains.get(k, 0.0) / 20)
        if k in eqs:
            v = fft_eq(v, eqs[k])
        y = np.zeros((n, 2))
        y[: len(v)] = v * g
        if os.environ.get("MUSIC_DEBUG"):
            levels[k] = rms(fft_eq(y[:: 4], lambda f: hp_resp(f * 4, 100, 1) * shelf_resp(f * 4, 1500, 4)))
        dry += y
        wet += y * sends.get(k, 0.2)
    if os.environ.get("MUSIC_DEBUG"):
        tot = rms(fft_eq(dry[:: 4], lambda f: hp_resp(f * 4, 100, 1) * shelf_resp(f * 4, 1500, 4)))
        print("   stems: " + " ".join(f"{k}={20 * np.log10(v / tot):.1f}" for k, v in levels.items()))
    irs = make_ir(rev_size, rev_damp, rev_seed)
    wet = fft_eq(wet, lambda f: hp_resp(f, 180, 1) * lp_resp(f, 7000, 1))
    return dry + conv_circ(wet, irs) * rev_gain


# --------------------------------------------------------------------------
# Tape chain
# --------------------------------------------------------------------------

def _cyc(f, n):
    """Quantise a modulation rate so it has whole cycles over n samples."""
    dur = n / SR
    return max(1, round(f * dur)) / dur


def periodic_smooth(n, rate, seed):
    r = np.random.default_rng(seed)
    x = r.standard_normal(n)
    y = sfft.irfft(sfft.rfft(x, workers=4) * lp_resp(np.fft.rfftfreq(n, 1 / SR), rate, 2), n, workers=4)
    return y / (np.std(y) + 1e-12)


def wow_flutter(x, seed, wow=0.0020, flutter=0.00045, drift=0.0012):
    """Fractional-delay pitch modulation. Values are peak pitch deviation
    (fraction, 0.002 = 0.2 % ~ 3.5 cents)."""
    n = len(x)
    t = np.arange(n) / SR
    fw = _cyc(0.5, n)
    ff = _cyc(6.0, n)
    r = np.random.default_rng(seed)
    # delay in seconds; pitch deviation = -d'(t) = 2*pi*f*A
    d = (wow / (2 * np.pi * fw)) * np.sin(2 * np.pi * fw * t + r.uniform(0, 6.28))
    d += (flutter / (2 * np.pi * ff)) * np.sin(2 * np.pi * ff * t + r.uniform(0, 6.28))
    # slow irregular drift (~0.15 Hz) so it doesn't sound like an LFO
    sm = periodic_smooth(n, 0.25, seed + 1)
    d += np.cumsum(sm - sm.mean()) / SR * drift * 0.5
    d -= d.min()
    d += 0.002
    pos = np.arange(n) - d * SR
    i = np.floor(pos).astype(np.int64)
    fr = pos - i
    out = np.zeros_like(x)
    # cubic Hermite (Catmull-Rom) interpolation, wrapping round for loops
    im1, i0, i1, i2 = (i - 1) % n, i % n, (i + 1) % n, (i + 2) % n
    for c in range(x.shape[1]):
        y = x[:, c]
        a, b, cc, dd = y[im1], y[i0], y[i1], y[i2]
        out[:, c] = b + 0.5 * fr * (cc - a + fr * (2 * a - 5 * b + 4 * cc - dd + fr * (3 * (b - cc) + dd - a)))
    return out


def limiter(x, ceiling=0.89, release_s=0.08):
    """Circular look-ahead peak limiter (no state across the loop join)."""
    from scipy.ndimage import minimum_filter1d, uniform_filter1d
    pk = np.max(np.abs(x), axis=1)
    g = np.minimum(1.0, ceiling / np.maximum(pk, 1e-9))
    w = int(0.004 * SR)
    g = minimum_filter1d(g, size=2 * w + 1, mode="wrap")
    g = uniform_filter1d(g, size=w, mode="wrap")
    g = minimum_filter1d(g, size=w + 1, mode="wrap")
    g = uniform_filter1d(g, size=w, mode="wrap")
    return x * g[:, None]


def tape(x, seed=1, wow=0.0020, flutter=0.00045, drift=0.0012, hiss_db=-52.0,
         lp_hz=10000.0, bump_db=2.0, drive=1.5, width=0.78, dropouts=1.0,
         age=1.0, hum=False, scale=None):
    """The worn-VHS chain. x is a stereo mix (any level). Circular.
    scale: input gain into the saturator (default: bring RMS to 0.11)."""
    n = len(x)
    x = x * (0.11 / rms(x) if scale is None else scale)
    # gentle tape saturation (slightly asymmetric for even harmonics)
    y = np.tanh(drive * (x + 0.04 * x ** 2)) / drive
    y -= y.mean(axis=0)
    y = wow_flutter(y, seed, wow * age, flutter * age, drift * age)
    # head bump, HF roll-off, slight presence dip, sub cut
    y = fft_eq(y, lambda f: bell_resp(f, 85, bump_db, 0.9) * lp_resp(f, lp_hz, 2)
               * shelf_resp(f, lp_hz * 0.55, -1.5) * bell_resp(f, 3200, -1.0, 0.8)
               * hp_resp(f, 28, 2))
    music_rms = rms(y)
    # dropouts: brief level and treble dips, placed deterministically
    if dropouts > 0:
        r = np.random.default_rng(seed + 11)
        env = np.zeros(n)
        k = int(max(1, round(n / SR / 50 * dropouts)))
        for _ in range(k):
            c = r.integers(0, n)
            L = int(r.uniform(0.05, 0.22) * SR)
            depth = r.uniform(0.18, 0.45)
            w = np.hanning(L) ** 0.7 * depth
            idx = (np.arange(L) + c) % n
            env[idx] = np.maximum(env[idx], w)
        dull = fft_eq(y, lambda f: lp_resp(f, 2500, 2))
        y = y * (1 - env[:, None]) + dull * env[:, None] * 0.6
    # stereo narrowing
    m = (y[:, 0] + y[:, 1]) / 2
    s = (y[:, 0] - y[:, 1]) / 2 * width
    y = np.stack([m + s, m - s], axis=1)
    # hiss: shaped stereo noise, slightly modulated so it breathes
    r = np.random.default_rng(seed + 23)
    h = r.standard_normal((n, 2))
    h[:, 1] = 0.6 * h[:, 0] + 0.8 * h[:, 1]
    h = fft_eq(h, lambda f: hp_resp(f, 900, 1) * lp_resp(f, lp_hz * 0.95, 2) * bell_resp(f, 5000, 3, 0.6))
    h *= (1 + 0.15 * periodic_smooth(n, 0.3, seed + 5))[:, None]
    h = h / rms(h) * music_rms * 10 ** (hiss_db / 20)
    y = y + h
    if hum:
        t = np.arange(n) / SR
        hm = (np.sin(2 * np.pi * _cyc(50, n) * t) + 0.3 * np.sin(2 * np.pi * _cyc(150, n) * t))
        y += (hm * music_rms * 10 ** (-58 / 20))[:, None]
    return y


def lufs_gain(x, target=-16.0):
    import pyloudnorm
    meter = pyloudnorm.Meter(SR)
    data = x if len(x) > SR else np.concatenate([x, np.zeros((SR, 2))])
    return 10 ** ((target - meter.integrated_loudness(data)) / 20)


def finish(x, loop: bool, fade_in=0.0, fade_out=0.0, trim_tail=True, gain=None,
           length=None):
    """Peak control so -16 LUFS fits under -1 dBTP, plus end handling."""
    if length:
        x = x[: int(length * SR)]
        trim_tail = False
    x = x * (lufs_gain(x) if gain is None else gain)
    x = limiter(x, 0.80)
    if not loop:
        if trim_tail:
            env = np.max(np.abs(x), axis=1)
            thr = 10 ** (-62 / 20)
            idx = np.nonzero(env > thr)[0]
            end = min(len(x), idx[-1] + int(0.3 * SR)) if len(idx) else len(x)
            x = x[:end]
        if fade_in:
            x = sfxlib.fade(x, fin=fade_in)
        fo = fade_out or 0.25
        x = sfxlib.fade(x, fout=fo)
        x[: int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))[:, None]
    return x


# --------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------

def analyse(name, x, loop):
    import pyloudnorm
    meter = pyloudnorm.Meter(SR)
    loud = meter.integrated_loudness(x if len(x) > SR else np.concatenate([x, np.zeros((SR, 2))]))
    tp = sfxlib.true_peak(x)
    m = x.mean(axis=1)
    f = np.fft.rfftfreq(len(m), 1 / SR)
    P = np.abs(sfft.rfft(m, workers=4)) ** 2
    tot = P.sum() + 1e-20
    bands = {"<120": (0, 120), "120-500": (120, 500), "0.5-2k": (500, 2000),
             "2-6k": (2000, 6000), ">6k": (6000, 24000), ">12k": (12000, 24000)}
    bd = {k: 10 * np.log10(P[(f >= a) & (f < b)].sum() / tot + 1e-20) for k, (a, b) in bands.items()}
    # short-term loudness spread (density / silence check)
    blk = SR * 3
    st = []
    for k in range(0, len(x) - blk, blk):
        st.append(20 * np.log10(rms(x[k:k + blk]) + 1e-12))
    st = np.array(st) if st else np.array([0.0])
    seam = ""
    if loop:
        d = np.abs(np.diff(x, axis=0)).max(axis=1)
        j = np.abs(x[0] - x[-1]).max()
        seam = f" seam_jump={j:.4f} (p99 step {np.percentile(d, 99):.4f}, max {d.max():.4f})"
    sm = (x[:, 0] - x[:, 1]) / 2
    side = 20 * np.log10(rms(sm) / rms(m))
    print(f"[{name}] {len(x) / SR:6.1f}s LUFS={loud:5.1f} TP={20 * np.log10(tp):5.1f}dB "
          + " ".join(f"{k}:{v:5.1f}" for k, v in bd.items())
          + f" | 3s-RMS range {st.min():.0f}..{st.max():.0f} dB side={side:.1f}dB" + seam)
    return dict(lufs=loud, tp=tp, bands=bd)


# --------------------------------------------------------------------------
# One-call production helper
# --------------------------------------------------------------------------

STEM_EQ = {
    "bass": lambda f: lp_resp(f, 3000, 2) * hp_resp(f, 32, 2),
    "gtr": lambda f: hp_resp(f, 110, 2) * bell_resp(f, 2500, 1.5, 1.0),
    "keys": lambda f: hp_resp(f, 140, 2) * lp_resp(f, 6500, 1),
    "pad": lambda f: hp_resp(f, 160, 2) * lp_resp(f, 6000, 1),
    "drums": lambda f: hp_resp(f, 40, 2) * shelf_resp(f, 6000, -2),
    "lead": lambda f: hp_resp(f, 150, 2),
}


def produce(song: Song, gains: dict, sends: dict | None = None, eqs: dict | None = None,
            rev_size=2.0, rev_damp=4500, rev_gain=1.0, tape_kw: dict | None = None,
            post=None, fade_in=0.0, fade_out=0.0, return_mix=False, length=None):
    stems = render(song)
    e = dict(STEM_EQ)
    e.update(eqs or {})
    e = {k: v for k, v in e.items() if v is not None}
    x = mix(song, stems, gains, sends, e, rev_size, rev_damp, song.seed, rev_gain)
    pre_tape = x
    if not song.loop and length is None:
        from scipy.ndimage import uniform_filter1d
        env = np.sqrt(np.maximum(uniform_filter1d(np.mean(x ** 2, axis=1), int(0.3 * SR)), 0))
        ref = np.median(env[env > env.max() * 1e-3])
        idx = np.nonzero(env > ref * 10 ** (-32 / 20))[0]
        length = (idx[-1] / SR + 0.4) if len(idx) else None
        fade_out = fade_out or 0.8
    if post:
        x = post(x)
    x = tape(x, seed=song.seed, **(tape_kw or {}))
    y = finish(x, song.loop, fade_in, fade_out, length=length)
    if return_mix:
        return y, pre_tape
    return y


def audit(song: Song, parts=None, min_dur=0.9):
    """Debug: list long melody notes that make a minor 9th against a chord
    tone (the classic 'avoid note' clash)."""
    out = []
    for p in song.parts:
        if p.drum or (parts and p.name not in parts):
            continue
        for b, pitch, d, v in p.notes:
            if d < min_dur:
                continue
            ch = song.chord_at(b + 0.01)
            pcs = set(ch.pcs()) | {ch.bass}
            pc = pitch % 12
            if pc in pcs:
                continue
            bad = [(c) for c in pcs if (pc - c) % 12 == 1]
            if bad:
                out.append(f"{p.name}: bar {b / song.bpb + 1:.2f} {pitch} over {ch.sym}")
    return out
