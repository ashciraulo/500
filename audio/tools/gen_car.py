#!/usr/bin/env python3
"""Car sound effects: doors, boot/bonnet, indicators, horns, wipers, radio,
handbrake, ignition, windows, soft-top roof, trim rattle, cargo, seat/belt and
parking sensor. Writes audio/car/*.ogg.

    python3 audio/tools/gen_car.py

Everything is synthesised from noise bursts and decaying modes (sums of damped
sines) shaped after the physics of the real object, except the horns, which
are cut from CC0 recordings (run fetch_sources.py first). Seeds are fixed, so
the output is identical on every run.
"""
from __future__ import annotations

import sys
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402
from scipy import signal  # noqa: E402

from sfxlib import (SR, bp, env_exp, fade, hp, load, lp, noise, peak_eq, place,  # noqa: E402
                    resonator, reverb, rng, save, secs, smooth_noise, softclip,
                    t_axis)

OUT = "car"

# --------------------------------------------------------------------------
# Small helpers shared by the sounds below
# --------------------------------------------------------------------------


def burst(dur, decay, seed, attack=0.0003):
    """White-noise burst with an exponential decay: the raw 'hit'."""
    n = secs(dur)
    return noise(n, seed) * env_exp(n, decay, attack)


def modal(dur, modes, seed, attack=0.0006):
    """Sum of damped sines, modes = [(freq_hz, decay_s, amp), ...].
    This is how struck panels, latches and bells ring."""
    n = secs(dur)
    t = t_axis(n)
    r = rng(seed)
    out = np.zeros(n)
    for f, d, a in modes:
        if f < SR / 2 * 0.95:
            out += a * np.sin(2 * np.pi * f * t + r.uniform(0, 2 * np.pi)) * np.exp(-t / d)
    ia = max(1, secs(attack))
    out[:ia] *= np.linspace(0, 1, ia)
    return out


def add(*xs):
    """Sum signals of different lengths (shorter ones are zero-padded)."""
    out = np.zeros(max(len(x) for x in xs))
    for x in xs:
        out[:len(x)] += x
    return out


def mix(dur, parts):
    """parts = [(time_s, signal, gain), ...] summed into a buffer of dur seconds."""
    out = np.zeros(secs(dur))
    for at, sig, g in parts:
        place(out, g * sig, secs(at))
    return out


def room(x, size=0.25, wet=0.15, damp=4000, seed=3):
    """Short mono reflection tail (street/garage walls), keeps it a point source."""
    return reverb(x, size_s=size, damp_hz=damp, wet=wet, predelay_s=0.004, seed=seed).mean(axis=1)


def periodic(x, fn):
    """Run a causal filter over a periodic signal so its output still loops:
    filter three copies end to end and keep the middle one."""
    n = len(x)
    return fn(np.concatenate([x, x, x]))[n:2 * n]


def check_loop(name, x):
    """Seam test: the wrap-around jump must be no bigger than the ordinary
    sample steps (global 99.9th percentile, or the largest step near the join)."""
    m = x.mean(axis=1) if x.ndim == 2 else x
    d = np.abs(np.diff(m))
    local = np.concatenate([d[:200], d[-200:]]).max()  # steps right around the join
    ratio = abs(m[-1] - m[0]) / (max(np.percentile(d, 99.9), local) + 1e-12)
    print(f"  loop {name}: seam/typical step = {ratio:.2f}", file=sys.stderr)
    assert ratio < 1.0, f"{name}: loop seam too big"
    return x


def tick(seed, f_ring=3200, f_body=900, amp=1.0, bright=1.0):
    """Generic small mechanical click: broadband snap + tiny ring + housing."""
    r = rng(seed)
    snap = hp(burst(0.02, 0.0007 * bright, seed), 1500) * 0.6
    ring = modal(0.05, [(f_ring * r.uniform(0.97, 1.03), 0.012, 0.25),
                        (f_ring * 1.62 * r.uniform(0.97, 1.03), 0.007, 0.15)], seed + 1)
    body = modal(0.05, [(f_body * r.uniform(0.95, 1.05), 0.008, 0.25)], seed + 2)
    return amp * add(snap, ring, body)


def plastic_click(seed, amp=1.0, f=1400):
    """Dull plastic switch: band-limited snap plus a short low housing knock."""
    r = rng(seed)
    a = bp(burst(0.04, 0.0015, seed), 800, 6000) * 0.8
    b = modal(0.05, [(f * r.uniform(0.9, 1.1), 0.006, 0.4), (f * 0.45, 0.01, 0.3)], seed + 5)
    return amp * add(a, b)


# --------------------------------------------------------------------------
# Doors (modern 500 / classic 500)
# --------------------------------------------------------------------------


def door_close_modern(v):
    """Modern door close: air cushion -> two-stage latch click -> low body
    thunk (~90-115 Hz) -> panel modes -> trim tick -> short reflection."""
    r = rng(1100 + v)
    force = [1.0, 0.8, 1.2, 0.9][v]
    t0 = 0.05
    a = secs(0.05)
    air = lp(noise(a, 1110 + v), 300, 2) * np.linspace(0, 1, a) ** 2 * 0.25
    gap = r.uniform(0.006, 0.012)
    latch1 = add(bp(burst(0.03, 0.002, 1120 + v), 1800, 9000) * 0.9, modal(
        0.06, [(r.uniform(2800, 3400), 0.007, 0.4), (r.uniform(4600, 5200), 0.004, 0.2)], 1130 + v))
    latch2 = add(bp(burst(0.03, 0.0015, 1140 + v), 2000, 9000) * 0.3, modal(
        0.05, [(r.uniform(3500, 3900), 0.005, 0.12)], 1150 + v))
    f0 = r.uniform(88, 115)
    thunk = modal(0.5, [(f0, 0.05, 0.7), (f0 * 1.52, 0.035, 0.4), (f0 * 2.13, 0.025, 0.35)], 1160 + v, 0.002)
    thud = lp(burst(0.3, 0.02, 1170 + v), 220, 2) * 1.8
    panel = modal(0.4, [(r.uniform(225, 260), 0.04, 0.45), (r.uniform(330, 380), 0.03, 0.38),
                        (r.uniform(500, 560), 0.025, 0.3), (r.uniform(760, 820), 0.018, 0.22),
                        (r.uniform(1100, 1250), 0.012, 0.14)], 1180 + v)
    trim = hp(burst(0.06, 0.008, 1190 + v), 2500) * 0.06
    x = mix(0.9, [(t0 - 0.05, air, force), (t0, latch1, 1.0), (t0 + gap, latch2, 1.0),
                  (t0 + 0.002, add(thunk, thud), force), (t0 + 0.003, panel, 1.6 * force),
                  (t0 + 0.018, trim, 1.0)])
    return fade(room(x, 0.3, 0.14, 3500, 7 + v), fout=0.05)


def door_open_modern(v):
    """Modern door open: handle lever click, latch releases with a metallic
    'chunk', the rubber seal unpeels, then the check-strap detent clicks."""
    r = rng(1200 + v)
    handle = plastic_click(1210 + v, 0.6, 1500)
    release = modal(0.2, [(r.uniform(380, 430), 0.025, 0.5), (r.uniform(640, 700), 0.02, 0.35),
                          (r.uniform(1050, 1200), 0.015, 0.2), (150, 0.03, 0.4)], 1220 + v)
    release = add(release, bp(burst(0.05, 0.003, 1230 + v), 1500, 8000) * 0.4)
    n = secs(0.22)
    seal_env = np.sin(np.linspace(0, np.pi, n)) ** 2
    crackle = (rng(1240 + v).random(n) < 0.004) * rng(1241 + v).standard_normal(n) * 3
    seal = bp(noise(n, 1250 + v) + crackle, 250, 3000) * seal_env * 0.18
    detent = tick(1260 + v, 2400, 600, 0.35)
    t_rel = r.uniform(0.07, 0.11)
    x = mix(0.9, [(0.02, handle, 1.0), (t_rel, release, 1.0), (t_rel + 0.01, seal, 1.0),
                  (t_rel + r.uniform(0.3, 0.38), detent, 1.0)])
    return fade(room(x, 0.25, 0.12, 4000, 11 + v), fout=0.05)


def door_close_classic(v):
    """Classic 500 door close: thin steel, so the body ring sits higher and
    lasts longer (tinny clang), with a chunky old latch and glass rattle."""
    r = rng(1300 + v)
    t0 = 0.03
    latch = modal(0.1, [(r.uniform(1800, 2100), 0.02, 0.4), (r.uniform(3000, 3300), 0.015, 0.3),
                        (r.uniform(4400, 4800), 0.01, 0.2)], 1310 + v)
    latch = add(latch, bp(burst(0.04, 0.002, 1320 + v), 1200, 9000) * 0.6)
    f0 = r.uniform(150, 175)
    body = modal(1.0, [(f0, 0.07, 0.8), (f0 * 1.9, 0.12, 0.45), (r.uniform(430, 470), 0.15, 0.4),
                       (r.uniform(640, 690), 0.12, 0.35), (r.uniform(910, 960), 0.1, 0.25),
                       (r.uniform(1330, 1400), 0.08, 0.18), (r.uniform(2150, 2300), 0.05, 0.1)],
                 1330 + v, 0.001)
    thud = lp(burst(0.2, 0.02, 1340 + v), 300, 2) * 1.6
    # loose window glass chattering in its channel
    n = secs(0.18)
    chat = np.zeros(n)
    for k in range(int(r.integers(4, 7))):
        place(chat, hp(burst(0.02, 0.0015, 1350 + 10 * v + k), 2500) * 0.25 * (0.75 ** k),
              int(k * r.uniform(0.018, 0.03) * SR))
    x = mix(1.1, [(t0, latch, 1.0), (t0 + 0.004, add(body, thud), 1.0), (t0 + 0.015, chat, 1.0)])
    return fade(room(x, 0.3, 0.15, 4500, 15 + v), fout=0.06)


def door_open_classic(v):
    """Classic door open: push-button handle clack, latch spring twang and a
    dry hinge creak as the door swings."""
    r = rng(1400 + v)
    button = modal(0.08, [(r.uniform(2300, 2600), 0.012, 0.4), (r.uniform(1200, 1300), 0.02, 0.3)], 1410 + v)
    button = add(button, bp(burst(0.03, 0.0015, 1420 + v), 1500, 9000) * 0.5)
    spring = modal(0.3, [(r.uniform(520, 560), 0.06, 0.3), (r.uniform(1490, 1560), 0.05, 0.25),
                         (r.uniform(2700, 2900), 0.03, 0.15)], 1430 + v)
    spring = add(spring, bp(burst(0.05, 0.003, 1440 + v), 800, 6000) * 0.4)
    # hinge creak: stick-slip pulse train with a wandering rate, through steel resonances
    n = secs(0.45)
    t = t_axis(n)
    rate = r.uniform(180, 240) * (1 + 0.25 * np.sin(2 * np.pi * 1.6 * t + r.uniform(0, 6)))
    ph = np.cumsum(rate / SR)
    pulses = np.diff(np.floor(ph), prepend=0) * (0.6 + 0.4 * rng(1450 + v).random(n))
    creak = resonator(pulses, 1100, 6) + resonator(pulses, 2300, 8) * 0.6 + resonator(pulses, 650, 5) * 0.5
    creak *= np.sin(np.linspace(0, np.pi, n)) ** 1.5 * 0.9
    x = mix(1.0, [(0.02, button, 1.0), (0.09, spring, 1.0), (0.2, creak, 1.0)])
    return fade(room(x, 0.25, 0.12, 4500, 19 + v), fout=0.05)


def boot_close():
    """Modern hatch close: bigger, slower panel than a door, so a lower thunk
    (~70 Hz) with the latch and a rattle of the parcel shelf."""
    r = rng(1500)
    latch = add(bp(burst(0.03, 0.002, 1501), 1800, 9000) * 0.4, modal(0.06, [(3100, 0.006, 0.2)], 1502))
    thunk = modal(0.7, [(72, 0.11, 1.0), (108, 0.07, 0.6), (165, 0.05, 0.35)], 1503, 0.003)
    thud = lp(burst(0.3, 0.04, 1504), 200, 2) * 2.6
    panel = modal(0.5, [(210, 0.06, 0.3), (330, 0.045, 0.25), (590, 0.03, 0.16), (920, 0.02, 0.1)], 1505)
    shelf = np.zeros(secs(0.15))
    for k in range(4):
        place(shelf, bp(burst(0.03, 0.003, 1510 + k), 600, 4000) * 0.15 * 0.7 ** k, secs(k * r.uniform(0.025, 0.04)))
    x = mix(1.0, [(0.03, latch, 1.0), (0.032, add(thunk, thud), 1.0), (0.034, panel, 1.0), (0.05, shelf, 1.0)])
    return fade(room(x, 0.3, 0.14, 3500, 23), fout=0.05)


def boot_open():
    """Hatch open: electric release solenoid clunk, gas struts hiss as the lid rises."""
    sol = modal(0.15, [(240, 0.03, 0.6), (520, 0.02, 0.4), (1300, 0.01, 0.2)], 1520)
    sol = add(sol, bp(burst(0.04, 0.003, 1521), 1000, 7000) * 0.4)
    n = secs(1.1)
    strut_env = np.clip(np.linspace(0, 1.4, n), 0, 1) * np.linspace(1, 0.2, n)
    strut = bp(noise(n, 1522), 2500, 9000) * strut_env * 0.05
    stop = modal(0.2, [(180, 0.04, 0.3), (450, 0.03, 0.2)], 1523)
    x = mix(1.6, [(0.02, sol, 1.0), (0.08, strut, 1.0), (1.15, stop, 1.0)])
    return fade(room(x, 0.25, 0.12, 4000, 29), fout=0.05)


def bonnet_open():
    """Bonnet: cable release pop (from the cabin), then the safety catch
    clack and the lid lifting on a squeaky prop."""
    pop = modal(0.2, [(130, 0.05, 0.9), (260, 0.04, 0.5), (700, 0.02, 0.3)], 1530)
    pop = add(pop, lp(burst(0.1, 0.01, 1531), 600) * 1.2)
    catch = add(modal(0.08, [(2200, 0.012, 0.3), (3500, 0.008, 0.2)], 1532), bp(burst(0.03, 0.002, 1533), 1500, 8000) * 0.4)
    n = secs(0.4)
    lift = bp(noise(n, 1534), 300, 2000) * np.sin(np.linspace(0, np.pi, n)) * 0.06
    x = mix(1.3, [(0.02, pop, 1.0), (0.55, catch, 1.0), (0.6, lift, 1.0)])
    return fade(room(x, 0.25, 0.12, 4000, 31), fout=0.05)


def bonnet_close():
    """Bonnet drop from a short height: big thin panel thunk + latch + ring."""
    latch = add(bp(burst(0.03, 0.002, 1541), 1800, 9000) * 0.45, modal(0.06, [(2900, 0.007, 0.2)], 1542))
    thunk = modal(0.8, [(82, 0.1, 1.0), (125, 0.08, 0.6), (240, 0.09, 0.4), (395, 0.07, 0.3),
                        (610, 0.05, 0.2), (1010, 0.03, 0.1)], 1543, 0.002)
    thud = lp(burst(0.25, 0.03, 1544), 250, 2) * 2.4
    x = mix(1.0, [(0.03, latch, 1.0), (0.031, add(thunk, thud), 1.0)])
    return fade(room(x, 0.3, 0.15, 3500, 37), fout=0.05)


def passenger_door_seat_belt():
    """Getting in: door opens, seat foam/vinyl creaks under the body, seatbelt
    webbing slides out and the tongue clicks into the buckle."""
    door = door_open_modern(1)
    # seat creak: slow stick-slip of vinyl/leather, low formants
    n = secs(0.7)
    t = t_axis(n)
    rate = 55 + 25 * np.sin(2 * np.pi * 0.9 * t)
    pulses = np.diff(np.floor(np.cumsum(rate / SR)), prepend=0) * (0.5 + rng(1601).random(n))
    creak = resonator(pulses, 420, 4) + resonator(pulses, 900, 5) * 0.6 + resonator(pulses, 1900, 6) * 0.3
    creak = creak * np.sin(np.linspace(0, np.pi, n)) * 1.5
    foam = lp(noise(n, 1602), 400) * np.sin(np.linspace(0, np.pi, n)) ** 2 * 0.08
    # belt webbing: noisy zip with the retractor's ratchet ticks
    n2 = secs(0.6)
    web = bp(noise(n2, 1603), 1500, 8000) * np.sin(np.linspace(0, np.pi, n2)) ** 2 * 0.05
    for k in range(9):
        place(web, tick(1610 + k, 4200, 1800, 0.05), secs(0.05 + k * 0.055))
    buckle = add(tick(1620, 3800, 1300, 0.9), modal(0.08, [(5200, 0.01, 0.2), (2600, 0.015, 0.3)], 1621))
    buckle2 = tick(1622, 4100, 1500, 0.5)
    x = mix(3.4, [(0.0, door, 1.0), (0.8, creak + foam, 1.0), (1.9, web, 1.0),
                  (2.65, buckle, 1.0), (2.658, buckle2, 1.0)])
    return fade(x, fout=0.05)


def seatbelt_click():
    """Just the buckle: tongue latches with a two-part click."""
    x = mix(0.25, [(0.01, tick(1630, 3800, 1300, 0.9), 1.0), (0.018, tick(1631, 4100, 1500, 0.5), 1.0)])
    return fade(room(x, 0.15, 0.1, 5000, 41), fout=0.02)


# --------------------------------------------------------------------------
# Indicators
# --------------------------------------------------------------------------


def indicator_modern():
    """Relay indicator, 80 flashes/min: relay closes (sharp two-part click,
    armature then contact bounce, tiny ring) and opens (softer tock)."""
    period = 0.75
    cycles = 4
    L = secs(period * cycles)
    out = np.zeros(L)
    for c in range(cycles):
        r = rng(1700 + c)
        on = tick(1710 + c, 3300, 950, 1.0) + 0.45 * np.roll(tick(1720 + c, 4100, 1200, 1.0), secs(0.0018))
        off = tick(1730 + c, 2600, 700, 0.62, 1.4) + 0.3 * np.roll(tick(1740 + c, 3000, 800, 1.0), secs(0.0022))
        g = r.uniform(0.95, 1.05)
        place(out, g * on, secs(c * period), wrap=True)
        place(out, g * off, secs(c * period + period / 2), wrap=True)
    out = periodic(out, lambda s: room(s, 0.12, 0.1, 5000, 43))
    return check_loop("indicator_modern", out)


def indicator_classic():
    """Thermal (bimetal) flasher: a heavier, duller 'clack' as the strip snaps,
    slightly irregular timing because it depends on heating."""
    cycles = 8
    period = 0.8
    r = rng(1750)
    gaps = r.uniform(0.94, 1.06, cycles)
    gaps *= cycles * period / gaps.sum()
    L = secs(cycles * period)
    out = np.zeros(L)
    t = 0.0
    for c in range(cycles):
        on = modal(0.06, [(r.uniform(1300, 1450), 0.012, 0.5), (r.uniform(2600, 2900), 0.008, 0.3),
                          (r.uniform(480, 540), 0.015, 0.4)], 1760 + c)
        on = add(on, bp(burst(0.03, 0.0012, 1770 + c), 700, 6000) * 0.6)
        off = modal(0.06, [(r.uniform(1100, 1250), 0.01, 0.35), (r.uniform(420, 470), 0.012, 0.35)], 1780 + c)
        off = add(off, bp(burst(0.03, 0.001, 1790 + c), 600, 5000) * 0.4)
        duty = r.uniform(0.45, 0.55)
        place(out, on, secs(t), wrap=True)
        place(out, off * 0.8, secs(t + gaps[c] * period * duty), wrap=True)
        t += gaps[c] * period
    out = periodic(out, lambda s: room(s, 0.12, 0.1, 4500, 47))
    return check_loop("indicator_classic", out)


# --------------------------------------------------------------------------
# Horns
# --------------------------------------------------------------------------


# Horns are cut from CC0 recordings of real horns (audio/CREDITS.md, "Horns"),
# fetched by fetch_sources.py into build/sources/. The helpers below are also
# used by gen_traffic.py for the traffic, bus and train horns.

HORN_SRC = Path(__file__).resolve().parents[2] / "build" / "sources"
_horn_mem: dict[str, np.ndarray] = {}


class MissingHornSource(Exception):
    """A horn recording hasn't been fetched (audio/tools/fetch_sources.py)."""


def horn_src(key):
    """A horn recording, mono 48 kHz, rumble removed."""
    if key not in _horn_mem:
        f = HORN_SRC / f"{key}.mp3"
        if not f.exists():
            raise MissingHornSource(f"missing {f}: run audio/tools/fetch_sources.py first (the horns are recordings)")
        _horn_mem[key] = hp(load(f, mono=True), 40, 2)
    return _horn_mem[key]


def repitch(x, ratio):
    """Pitch change by resampling (ratio 1.06 = 6% higher and 6% shorter)."""
    if ratio == 1:
        return x
    fr = Fraction(1 / ratio).limit_denominator(500)
    return signal.resample_poly(x, fr.numerator, fr.denominator)


def honk(key, start, end, tail=0.12, pre=0.004, ratio=1.0):
    """One honk as recorded: from just before `start` to `end`, then its own
    release and room tail faded out over `tail` s (which hides the street)."""
    x = horn_src(key)
    t, p = max(secs(tail), secs(0.004)), secs(pre)
    seg = x[secs(start) - p:secs(end) + t].copy()
    seg[:p] *= np.linspace(0, 1, p) ** 2
    seg[-t:] *= np.linspace(1, 0, t) ** 2
    return repitch(seg, ratio)


def _ncc(ref, y):
    """Normalised cross-correlation of ref against every window of y."""
    n = len(ref)
    num = signal.correlate(y, ref, mode="valid", method="fft")
    e = np.concatenate([[0], np.cumsum(y ** 2)])
    return num / (np.sqrt((e[n:] - e[:-n]) * np.dot(ref, ref)) + 1e-12)


def splice(a, b, xf=0.02, search=0.06):
    """a then b, joined by a short crossfade at the point in b whose waveform
    best matches the end of a, so a steady tone carries on in phase."""
    n = secs(xf)
    lag = int(np.argmax(_ncc(a[-n:], b[:secs(search) + n])))
    w = np.linspace(0, 1, n)
    return np.concatenate([a[:-n], a[-n:] * (1 - w) + b[lag:lag + n] * w, b[lag + n:]])


def shortened_honk(key, start, cut_at, release, end, fadeout=0.1, pre=0.004, ratio=1.0):
    """A honk held for less time than in the recording: its steady part up to
    `cut_at`, spliced in phase onto the real let-go (from `release` to `end`)."""
    x = horn_src(key)
    p = secs(pre)
    a = x[secs(start) - p:secs(cut_at)].copy()
    a[:p] *= np.linspace(0, 1, p) ** 2
    out = splice(a, x[secs(release) - secs(0.06):secs(end)])
    f = secs(fadeout)
    out[-f:] *= np.linspace(1, 0, f) ** 2
    return repitch(out, ratio)


def splice_loop(a, b, length, xf=0.03, search=0.15, step=2):
    """Exactly `length` samples that loop seamlessly, starting in steady
    recording a and finishing in steady recording b: one crossfade a->b in
    the middle, one from b's continuation into a's head at the wrap. The
    start in a and the entry into b are searched together so both joins land
    in phase (no level dip, no beating at either join)."""
    n, s = secs(xf), secs(search)
    ca = len(a) - n
    q1 = _ncc(a[ca:], b[:2 * s + n])
    best = (-9.0, 0, 0)
    for s0 in range(0, 2 * s, step):
        rest = length - (ca - s0)
        if rest + 2 * s + n > len(b):
            continue
        q2 = _ncc(a[s0:s0 + n], b[rest:rest + 2 * s + n])
        q = np.minimum(q1[:len(q2)], q2[:len(q1)])
        k = int(np.argmax(q))
        if q[k] > best[0]:
            best = (q[k], s0, k)
    q, s0, lb = best
    rest = length - (ca - s0)
    w = np.linspace(0, 1, n)
    out = np.concatenate([a[s0:ca], a[ca:] * (1 - w) + b[lb:lb + n] * w, b[lb + n:lb + rest]])
    out[:n] = b[lb + rest:lb + rest + n] * (1 - w) + out[:n] * w
    print(f"  loop splice match {q:.2f}", file=sys.stderr)
    return out


def horn_drive(x, drive):
    """Peak-normalise and saturate a little: a horn is a dense, loud sound."""
    return softclip(x / np.max(np.abs(x)) * drive, 1.0)


def horn_modern_tap():
    """Short courtesy tap on a twin disc horn (~395 + 485 Hz, a major third):
    one quick honk from the same recording as the held horn."""
    return horn_drive(honk("horn_wanaki", 0.345, 0.495, tail=0.25), 1.5)


def horn_modern_loop():
    """Held twin-tone horn, 2 s seamless loop: the steady middles of the
    recording's two long blasts, joined in phase."""
    x = horn_src("horn_wanaki")
    a, b = x[secs(5.05):secs(6.66)], x[secs(0.80):secs(1.96)]
    b = b * np.sqrt(np.mean(a ** 2) / np.mean(b ** 2))
    out = horn_drive(splice_loop(a, b, secs(2.0)), 1.5)
    return check_loop("horn_modern_loop", out)


def horn_classic_meep():
    """Classic 500 'meep': a small, thin, buzzy single disc horn, nudged up
    to ~460 Hz, with no low end."""
    return hp(honk("horn_small", 0.19, 0.42, tail=0.14, ratio=1.07), 300, 2)


def horn_abarth():
    """Abarth: a brighter, brassier twin (~545 + 655 Hz), driven harder,
    with a short street reflection."""
    x = horn_drive(honk("horn_twin_hi", 0.398, 0.708, tail=0.0, pre=0.003, ratio=0.93), 2.5)
    return room(np.concatenate([x, np.zeros(secs(0.35))]), 0.35, 0.12, 3500, 61)


# --------------------------------------------------------------------------
# Wipers
# --------------------------------------------------------------------------


def wipers(period, cycles, seed, swish_gain=1.0):
    """Wiper loop: worm-gear motor whir (hum + gear whine, loaded mid-sweep),
    rubber swish on wet glass following blade speed, blade flip and linkage
    knock at each reversal. Built periodically so it loops seamlessly."""
    L = secs(period * cycles)
    T = L / SR
    t = t_axis(L)
    phase = 2 * np.pi * t / period
    speed = np.abs(np.sin(phase))
    # motor: hum harmonics + whine; frequencies snapped to whole cycles per loop
    snap = lambda f: round(f * T) / T  # noqa: E731
    load = 1 + 0.08 * np.sin(2 * phase)  # zero-mean wobble, keeps phase periodic
    motor = np.zeros(L)
    for k, a in [(1, 0.5), (2, 0.35), (3, 0.2), (5, 0.1)]:
        motor += a * np.sin(2 * np.pi * np.cumsum(np.full(L, snap(95 * k)) * load) / SR)
    whine = np.sin(2 * np.pi * np.cumsum(np.full(L, snap(1240)) * load) / SR) * 0.12
    motor = (motor + whine) * (0.6 + 0.4 * speed)
    motor = periodic(motor, lambda s: lp(s, 2000, 2)) * 0.07
    # swish: wet rubber dragging water; two directions sound slightly different
    sw = noise(L, seed)
    up = (np.sin(phase) > 0).astype(float)
    sw = periodic(sw, lambda s: bp(s, 700, 6000, 2)) * (0.75 + 0.25 * up) \
        + periodic(noise(L, seed + 1), lambda s: bp(s, 250, 1500, 2)) * 0.6 * (1 - up)
    chatter = 1 + 0.25 * smooth_noise(L, 40, seed + 2, periodic=True)
    swish = sw * speed ** 1.2 * chatter * 0.12 * swish_gain
    # reversals: blade flips over (soft rubber thock) and linkage knocks
    events = np.zeros(L)
    for c in range(cycles):
        for half in (0, 1):
            at = secs((c + half / 2) * period)
            s = seed + 10 + 2 * c + half
            flop = modal(0.08, [(rng(s).uniform(320, 380), 0.02, 0.4), (rng(s).uniform(800, 900), 0.012, 0.25)], s)
            flop = add(flop, bp(burst(0.03, 0.003, s + 100), 400, 3000) * 0.3)
            place(events, flop * (0.6 if half else 0.45), at, wrap=True)
    x = motor + swish + events
    return check_loop(f"wipers {period}", x)


def wiper_squeak(v):
    """Dry-glass squeak: rubber stick-slip, a pulse train whose rate follows
    blade speed, ringing glass/rubber resonances, chattering on and off."""
    r = rng(1900 + v)
    dur = [0.7, 0.55, 0.9][v]
    n = secs(dur)
    t = t_axis(n)
    shape = np.sin(np.pi * t / dur)
    f = r.uniform(650, 900) * (0.8 + 0.3 * shape) * (1 + 0.02 * smooth_noise(n, 15, 1910 + v, periodic=False))
    ph = np.cumsum(f / SR)
    jitter = 1 + 0.3 * rng(1920 + v).standard_normal(n)
    pulses = np.diff(np.floor(ph), prepend=0) * jitter
    sq = resonator(pulses, f.mean(), 3) * 3 + resonator(pulses, 2200, 8) + resonator(pulses, 3600, 10) * 0.6
    sq = softclip(sq / (np.std(sq) + 1e-9) * 0.5, 2)
    gate = np.clip(smooth_noise(n, 12, 1930 + v, periodic=False) + 0.8, 0, 1) ** 0.5
    rub = bp(noise(n, 1940 + v), 300, 3000) * 0.08
    x = (sq * gate + rub) * shape ** 0.7
    return fade(room(np.concatenate([x, np.zeros(secs(0.2))]), 0.15, 0.1, 5000, 67 + v), 0.005, 0.05)


# --------------------------------------------------------------------------
# Radio
# --------------------------------------------------------------------------


def speaker(x):
    """Small door speaker: no deep bass, soft top, a little honk at 2.5 kHz."""
    return peak_eq(lp(hp(x, 160, 2), 6500, 2), 2500, 4, 1.2)


def static(n, seed, crackle=0.004):
    """Radio static: hiss plus random crackle impulses."""
    r = rng(seed)
    hiss = noise(n, seed) * 0.25
    imp = (r.random(n) < crackle) * r.standard_normal(n) * 2.0
    return hiss + bp(imp, 500, 8000)


def babble(n, seed):
    """Garbled station content: a voiced pulse source through formant pairs
    that jump at syllable rate, or a few chord tones if it's a music station."""
    r = rng(seed)
    t = t_axis(n)
    if r.random() < 0.5:
        f0 = r.uniform(110, 190) * (1 + 0.08 * smooth_noise(n, 3, seed, periodic=False))
        src = np.diff(np.floor(np.cumsum(f0 / SR)), prepend=0) + 0.03 * noise(n, seed + 1)
        out = np.zeros(n)
        seg = secs(0.09)
        for i in range(0, n, seg):
            s = src[max(0, i - secs(0.02)):i + seg]
            y = resonator(s, r.uniform(300, 800), 5) + resonator(s, r.uniform(900, 2300), 7) * 0.6
            y = y[i - max(0, i - secs(0.02)):]
            place(out, y * np.hanning(len(y) + 2)[1:-1] * 2, i)
        am = np.clip(smooth_noise(n, 5, seed + 2, periodic=False) + 0.5, 0, None)
        return out * am
    root = r.uniform(180, 300)
    out = sum(np.sin(2 * np.pi * root * m * t) for m in (1, 1.26, 1.5, 2))
    return softclip(out * 0.3, 1.5) * (0.7 + 0.3 * np.sin(2 * np.pi * r.uniform(1.5, 3) * t))


def radio_tuning_sweep():
    """2 s dial sweep: static changing colour, three stations drifting past,
    each with a heterodyne whistle gliding through zero beat."""
    n = secs(2.0)
    t = t_axis(n)
    st = static(n, 2000)
    tone = 0.5 + 0.5 * np.sin(2 * np.pi * 0.9 * t)
    st = lp(st, 2500) * tone + hp(st, 2500) * (1 - tone) * 1.3
    out = st * 0.6
    for i, tc in enumerate((0.38, 0.98, 1.6)):
        w = np.exp(-0.5 * ((t - tc) / 0.07) ** 2)
        content = babble(n, 2010 + i)
        content = content / (np.std(content[w > 0.3]) + 1e-9) * 0.35
        fw = 2500 * np.abs(t - tc) / 0.15 + 40
        whistle = np.sin(2 * np.pi * np.cumsum(fw) / SR) * np.exp(-0.5 * ((t - tc) / 0.12) ** 2) * 0.15
        out = out * (1 - 0.6 * w) + content * w + whistle
    return fade(speaker(out), 0.02, 0.08)


def radio_station_change():
    """Preset button: firm mechanical click and a short muted static blip."""
    click = plastic_click(2100, 1.0, 1600) + tick(2101, 3000, 900, 0.4)
    n = secs(0.12)
    blip = speaker(static(n, 2102, 0.02)) * np.hanning(n) * 0.25
    x = mix(0.35, [(0.01, click, 1.0), (0.03, blip, 1.0)])
    return fade(x, fout=0.03)


def radio_on():
    """Power on: knob/button click, speaker cone thump as the amp wakes, a short
    bloom of hiss settling to quiet."""
    click = plastic_click(2110, 1.0, 1300)
    n = secs(0.06)
    thump = np.sin(np.pi * np.linspace(0, 1, n)) * np.hanning(n) * 0.12
    thump = hp(lp(np.concatenate([thump, np.zeros(secs(0.1))]), 300), 40)
    m = secs(0.6)
    env = np.minimum(np.linspace(0, 1, m) * 20, 1) * (0.25 + 0.75 * np.exp(-t_axis(m) / 0.08)) * np.linspace(1, 0, m)
    hiss = speaker(static(m, 2111, 0.001)) * env * 0.18
    return fade(mix(0.8, [(0.01, click, 1.0), (0.04, thump, 1.0), (0.05, hiss, 1.0)]), fout=0.05)


def radio_off():
    """Power off: click, an inverted cone pop, hiss cut with a falling
    'bloop' as the amp's supply drains."""
    click = plastic_click(2120, 1.0, 1250)
    n = secs(0.05)
    pop = -hp(lp(np.concatenate([np.sin(np.pi * np.linspace(0, 1, n)) * 0.1, np.zeros(secs(0.1))]), 300), 40)
    m = secs(0.18)
    hiss = speaker(static(m, 2121, 0.001)) * np.exp(-t_axis(m) / 0.04) * 0.15
    k = secs(0.12)
    fdrop = 220 * np.exp(-t_axis(k) / 0.04) + 30
    bloop = np.sin(2 * np.pi * np.cumsum(fdrop) / SR) * np.exp(-t_axis(k) / 0.05) * 0.2
    return fade(mix(0.5, [(0.01, click, 1.0), (0.03, pop, 1.0), (0.03, hiss, 1.0),
                          (0.03, bloop, 1.0)]), fout=0.04)


# --------------------------------------------------------------------------
# Handbrake, ignition, chime, windows, roof, trim, cargo, parking sensor
# --------------------------------------------------------------------------


def ratchet_click(seed, amp=1.0):
    """One pawl tooth: a bright steel tick with a plastic console knock."""
    r = rng(seed)
    return amp * add(tick(seed, r.uniform(3600, 4200), r.uniform(1300, 1600), 1.0),
                     modal(0.04, [(r.uniform(500, 600), 0.01, 0.25)], seed + 3))


def handbrake_up():
    """Lever pulled: pawl clicks over ~8 teeth (getting slower as the cable
    tightens), cable creak, final hold."""
    r = rng(2200)
    parts = []
    t = 0.03
    gap = 0.035
    for k in range(8):
        parts.append((t, ratchet_click(2210 + k, 0.8 + 0.03 * k), 1.0))
        t += gap * r.uniform(0.9, 1.1)
        gap *= 1.12
    n = secs(t)
    creak = bp(noise(n, 2220), 200, 1200) * np.linspace(0, 1, n) ** 2 * 0.05
    parts.append((0.03, creak, 1.0))
    return fade(room(mix(t + 0.3, parts), 0.15, 0.1, 5000, 71), fout=0.04)


def handbrake_release():
    """Lift a little (one click), thumb button pressed (pawl clear, plastic
    slide), lever drops to its stop with a dull clunk and spring twang."""
    button = plastic_click(2230, 0.6, 1100)
    one = ratchet_click(2231, 0.7)
    n = secs(0.18)
    slide = bp(noise(n, 2232), 500, 4000) * np.hanning(n) * 0.06
    clunk = modal(0.3, [(140, 0.04, 0.7), (310, 0.03, 0.4), (720, 0.02, 0.25)], 2233)
    clunk = add(clunk, lp(burst(0.1, 0.015, 2234), 500) * 0.9)
    twang = modal(0.4, [(410, 0.12, 0.08), (1230, 0.06, 0.04)], 2235)
    x = mix(0.8, [(0.02, one, 1.0), (0.09, button, 1.0), (0.13, slide, 1.0), (0.29, clunk, 1.0), (0.3, twang, 1.0)])
    return fade(room(x, 0.15, 0.1, 5000, 73), fout=0.05)


def ignition_key_in():
    """Key slides into the barrel: scratchy metal slide over 5 spring pins
    (little ticks), seats with a soft click."""
    n = secs(0.3)
    slide = bp(noise(n, 2300), 2500, 10000) * np.linspace(0.3, 1, n) * 0.06
    parts = [(0.02, slide, 1.0)]
    for k in range(5):
        parts.append((0.05 + k * 0.045, tick(2310 + k, 5200, 2600, 0.25), 1.0))
    parts.append((0.33, tick(2320, 3200, 1100, 0.8), 1.0))
    return fade(room(mix(0.6, parts), 0.12, 0.08, 6000, 79), fout=0.04)


def ignition_key_turn():
    """Key turned: two sprung detents (ACC, ON) with a little lock-cylinder rub."""
    n = secs(0.25)
    rub = bp(noise(n, 2330), 1500, 7000) * np.hanning(n) * 0.04
    x = mix(0.6, [(0.0, rub, 1.0), (0.08, tick(2331, 2800, 1000, 0.8), 1.0),
                  (0.24, tick(2332, 3100, 1100, 1.0), 1.0)])
    return fade(room(x, 0.12, 0.08, 6000, 83), fout=0.04)


def dash_chime():
    """Modern dash chime: a soft synthesized 'bong' through the cluster's
    small speaker (bell partials ratio 1 : 2.76 : 5.4)."""
    f = 1046.5
    x = modal(1.2, [(f, 0.35, 1.0), (f * 2.0, 0.2, 0.25), (f * 2.76, 0.12, 0.15), (f * 5.4, 0.05, 0.05),
                    (f * 0.5, 0.25, 0.15)], 2340, 0.003)
    return fade(room(peak_eq(hp(x, 300), 2500, 3, 1), 0.12, 0.1, 6000, 89), fout=0.1)


def parking_sensor_loop():
    """Parking sensor beeps (cabin piezo, so a clean square-ish tone here is
    the real object): mid-distance rate ~4 beeps/s."""
    period = 0.25
    beeps = 8
    L = secs(period * beeps)
    out = np.zeros(L)
    n = secs(0.07)
    t = t_axis(n)
    tone = np.sign(np.sin(2 * np.pi * 2400 * t)) * 0.3 + np.sin(2 * np.pi * 2400 * t) * 0.7
    env = np.minimum(1, np.minimum(t / 0.003, (t[-1] - t) / 0.004))
    beep = lp(tone * env, 9000)
    for b in range(beeps):
        place(out, beep, secs(b * period), wrap=True)
    out = periodic(out, lambda s: room(s, 0.1, 0.08, 6000, 97))
    return check_loop("parking_sensor", out)


def window_motor_modern(direction):
    """Electric window: DC motor whine (rising as it spins up, labouring a
    little as glass drags in the felt channel), then the stall at the end."""
    dur = 3.2
    n = secs(dur)
    t = t_axis(n)
    spin = 1 - np.exp(-t / 0.08)
    drag = 1 - (0.06 if direction == "up" else 0.03) * (t / dur)
    f = 175 * spin * drag * (1 + 0.01 * smooth_noise(n, 4, 2400, periodic=False))
    ph = 2 * np.pi * np.cumsum(f) / SR
    motor = sum(a * np.sin(k * ph) for k, a in [(1, 0.6), (2, 0.4), (3, 0.25), (6, 0.15), (12, 0.08)])
    brush = bp(noise(n, 2401), 2000, 7000) * 0.05 * (1 + 0.5 * np.sin(ph * 4))
    felt = bp(noise(n, 2402), 300, 2500) * 0.1 * (1 + 0.5 * smooth_noise(n, 8, 2403, periodic=False))
    body = lp(motor, 3000) * 0.18 + brush + felt
    env = np.minimum(1, t / 0.02) * np.where(t > dur - 0.25, np.clip((dur - t) / 0.25, 0, 1) ** 0.5, 1)
    x = body * env
    end = add(modal(0.2, [(160, 0.04, 0.5), (420, 0.03, 0.3)], 2404), lp(burst(0.1, 0.01, 2405), 500) * 0.6)
    if direction == "up":
        x = mix(dur + 0.4, [(0, x, 1.0), (dur - 0.22, end, 0.8)])
    else:
        x = mix(dur + 0.4, [(0, x, 1.0), (dur - 0.22, end, 0.4)])
    return fade(room(x, 0.15, 0.1, 5000, 101), 0.005, 0.05)


def window_crank_classic():
    """Hand-crank window: gear teeth tick at the crank rate and a dry, squeaky
    felt drag with a periodic squeak once per crank turn."""
    dur = 3.0
    n = secs(dur)
    t = t_axis(n)
    turn_rate = 1.6  # turns/s
    out = bp(noise(n, 2410), 400, 3000) * 0.05 * (1 + 0.5 * np.sin(2 * np.pi * turn_rate * t))
    teeth_rate = turn_rate * 14
    for k in range(int(dur * teeth_rate)):
        place(out, tick(2420 + k, 3000, 1400, 0.12 * rng(2420 + k).uniform(0.6, 1.0)), secs(k / teeth_rate))
    for k in range(int(dur * turn_rate)):
        m = secs(0.18)
        tt = t_axis(m)
        f = 900 + 300 * np.sin(np.pi * tt / 0.18)
        pulses = np.diff(np.floor(np.cumsum(f / SR)), prepend=0)
        sq = resonator(pulses, 1100, 4) + resonator(pulses, 2600, 8) * 0.5
        place(out, sq * np.hanning(m) * 0.5 * rng(2450 + k).uniform(0.5, 1), secs(k / turn_rate + 0.2))
    out *= np.minimum(1, np.minimum(t / 0.05, (dur - t) / 0.1))
    return fade(room(np.concatenate([out, np.zeros(secs(0.2))]), 0.15, 0.1, 5000, 103), fout=0.05)


def roof_electric_500c():
    """500C fabric roof: motor drive whine through the cable runners, canvas
    folding in soft pleats (low cloth flaps), end-stop clunk."""
    dur = 6.0
    n = secs(dur)
    t = t_axis(n)
    f = 120 * (1 - np.exp(-t / 0.1))
    ph = 2 * np.pi * np.cumsum(f) / SR
    motor = sum(a * np.sin(k * ph) for k, a in [(1, 0.5), (2, 0.3), (4, 0.2), (8, 0.1)]) * 0.15
    cable = bp(noise(n, 2500), 1500, 6000) * 0.03
    cloth = np.zeros(n)
    for k in range(6):  # each pleat folds over
        m = secs(0.35)
        flap = bp(noise(m, 2510 + k), 150, 2000) * np.hanning(m) ** 2 * 0.25
        place(cloth, flap, secs(0.6 + k * 0.85))
    env = np.minimum(1, np.minimum(t / 0.05, (dur - t) / 0.08))
    x = (motor + cable) * env + cloth
    stop = modal(0.3, [(120, 0.05, 0.5), (300, 0.04, 0.3), (800, 0.02, 0.2)], 2520)
    return fade(room(mix(dur + 0.5, [(0, x, 1.0), (dur - 0.05, stop, 0.8)]), 0.25, 0.12, 4000, 107), fout=0.08)


def roof_canvas_manual():
    """Classic canvas roof pulled back by hand: two latch clacks, a long
    slithering canvas drag with folds, a final cloth thump."""
    latch1 = add(modal(0.08, [(1900, 0.015, 0.4), (3100, 0.01, 0.2)], 2530), bp(burst(0.03, 0.002, 2531), 1000, 8000) * 0.5)
    latch2 = add(modal(0.08, [(2050, 0.015, 0.4), (3300, 0.01, 0.2)], 2532), bp(burst(0.03, 0.002, 2533), 1000, 8000) * 0.5)
    n = secs(1.6)
    t = t_axis(n)
    drag = bp(noise(n, 2534), 250, 4000) * np.sin(np.pi * t / 1.6) ** 1.5 * 0.15
    drag *= 1 + 0.6 * np.clip(smooth_noise(n, 10, 2535, periodic=False), -1, 1)
    folds = np.zeros(n)
    for k in range(4):
        m = secs(0.2)
        place(folds, bp(noise(m, 2540 + k), 120, 1500) * np.hanning(m) ** 2 * 0.3, secs(0.3 + 0.32 * k))
    thump = lp(burst(0.2, 0.03, 2550), 300) * 1.2
    x = mix(3.2, [(0.05, latch1, 1.0), (0.4, latch2, 1.0), (0.8, drag + folds, 1.0), (2.4, thump, 1.0)])
    return fade(room(x, 0.2, 0.1, 4500, 109), fout=0.05)


def canvas_flap_loop():
    """Canvas roof at speed: fabric drumming against the bows at a few
    10s of Hz, gusting, over wind roar. Built from periodic parts."""
    L = secs(8.0)
    rate_mod = smooth_noise(L, 0.6, 2560, periodic=True)
    amp = np.clip(0.6 + 0.35 * rate_mod, 0.1, None)
    # periodic flutter: zero-mean modulated phase closing over the loop
    base = round(22 * 8) / 8
    fm = smooth_noise(L, 0.8, 2561, periodic=True)
    fm -= fm.mean()
    ph = 2 * np.pi * np.cumsum(base * (1 + 0.15 * fm)) / SR
    flutter = (0.5 + 0.5 * np.sin(ph)) ** 6
    cloth = np.fft.irfft(np.fft.rfft(noise(L, 2562)) * _band(L, 100, 1800), L)
    roar = np.fft.irfft(np.fft.rfft(noise(L, 2563)) * _band(L, 40, 600), L)
    x = cloth / np.std(cloth) * flutter * amp * 0.5 + roar / np.std(roar) * 0.2 * (0.8 + 0.2 * rate_mod)
    return check_loop("canvas_flap", x)


def _band(n, lo, hi):
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = 1e-9
    return 1 / np.sqrt(1 + (lo / f) ** 4) / np.sqrt(1 + (f / hi) ** 4)


def trim_rattle_classic():
    """Loose trim on a classic 500 over road vibration: random small plastic
    and metal taps, clustered by low-frequency body shake. Seamless loop."""
    L = secs(6.0)
    out = np.zeros(L)
    shake = smooth_noise(L, 3, 2600, periodic=True)
    r = rng(2601)
    rate = 18
    k = 0
    for i in range(int(6.0 * rate * 2)):
        at = int(r.uniform(0, L))
        p = np.clip(0.5 + 0.5 * shake[at], 0, 1) ** 2
        if r.random() < p:
            if r.random() < 0.6:
                hit = plastic_click(2610 + i, r.uniform(0.2, 0.6), r.uniform(900, 1800))
            else:
                hit = modal(0.05, [(r.uniform(2400, 3800), 0.01, 0.4), (r.uniform(900, 1300), 0.008, 0.3)], 2700 + i)
            place(out, hit, at, wrap=True)
            k += 1
    return check_loop("trim_rattle", out)


def cargo_boxes_slide(v):
    """Cardboard boxes sliding in the boot: rough scrape noise (cardboard on
    carpet) with a bump into the side at the end."""
    r = rng(2800 + v)
    dur = r.uniform(0.5, 0.9)
    n = secs(dur)
    t = t_axis(n)
    env = np.sin(np.pi * t / dur) ** 0.7 * (1 + 0.4 * smooth_noise(n, 20, 2810 + v, periodic=False))
    scrape = (bp(noise(n, 2820 + v), 300, 3000) * 0.15 + lp(noise(n, 2821 + v), 300) * 0.1) * env
    bump = add(lp(burst(0.2, 0.025, 2830 + v), 400) * 0.8, modal(0.2, [(r.uniform(140, 190), 0.04, 0.4), (r.uniform(380, 450), 0.02, 0.2)], 2840 + v))
    x = mix(dur + 0.4, [(0, scrape, 1.0), (dur - 0.03, bump, 1.0)])
    return fade(room(x, 0.12, 0.08, 4000, 113 + v), 0.01, 0.05)


def glass_ting(seed, amp=1.0):
    """One bottle/jar knock: a thin glass shell's inharmonic high modes."""
    r = rng(seed)
    f = r.uniform(1800, 3200)
    return amp * add(modal(0.3, [(f, 0.06, 0.5), (f * 2.32, 0.04, 0.3), (f * 4.1, 0.02, 0.2), (f * 0.62, 0.05, 0.2)], seed),
                     hp(burst(0.02, 0.0005, seed + 1), 3000) * 0.3)


def cargo_glass_clink_loop():
    """Jars/bottles in a crate clinking with road bumps: random clinks
    clustered on bumps (from a periodic shake curve). Seamless loop."""
    L = secs(8.0)
    out = np.zeros(L)
    shake = smooth_noise(L, 1.5, 2900, periodic=True)
    r = rng(2901)
    for i in range(70):
        at = int(r.uniform(0, L))
        if r.random() < np.clip(0.3 + 0.5 * shake[at], 0, 1):
            place(out, glass_ting(2910 + i, r.uniform(0.15, 0.6)), at, wrap=True)
            if r.random() < 0.4:  # quick double clink
                place(out, glass_ting(3010 + i, r.uniform(0.1, 0.3)), at + secs(r.uniform(0.02, 0.06)), wrap=True)
    out = periodic(out, lambda s: lp(s, 9000))
    return check_loop("cargo_glass_clink", out)


def glass_smash(v):
    """Glass smash: big crack transient, then dozens of shards ringing and
    skittering down over ~1 s (a decaying random cloud of glass tings)."""
    r = rng(3100 + v)
    dur = 1.6
    crack = add(hp(burst(0.15, 0.01, 3110 + v), 1500) * 1.2, lp(burst(0.15, 0.02, 3111 + v), 400) * 0.6)
    parts = [(0.02, crack, 1.0)]
    for i in range(int(r.integers(45, 70))):
        at = 0.02 + r.exponential(0.25)
        if at < dur - 0.3:
            parts.append((at, glass_ting(3120 + 100 * v + i, r.uniform(0.1, 0.6) * np.exp(-at / 0.6)), 1.0))
    sizzle = hp(noise(secs(0.8), 3115 + v), 4000) * np.exp(-t_axis(secs(0.8)) / 0.2) * 0.15
    parts.append((0.03, sizzle, 1.0))
    return fade(room(mix(dur, parts), 0.25, 0.12, 6000, 117 + v), fout=0.1)


# --------------------------------------------------------------------------


def main():
    for v in range(4):
        save(f"{OUT}/car_door_close_modern_{v + 1:02d}", door_close_modern(v))
    for v in range(2):
        save(f"{OUT}/car_door_open_modern_{v + 1:02d}", door_open_modern(v))
    for v in range(3):
        save(f"{OUT}/car_door_close_classic_{v + 1:02d}", door_close_classic(v))
    for v in range(2):
        save(f"{OUT}/car_door_open_classic_{v + 1:02d}", door_open_classic(v))
    save(f"{OUT}/car_boot_open", boot_open())
    save(f"{OUT}/car_boot_close", boot_close())
    save(f"{OUT}/car_bonnet_open", bonnet_open())
    save(f"{OUT}/car_bonnet_close", bonnet_close())
    save(f"{OUT}/car_passenger_door_seat_belt", passenger_door_seat_belt())
    save(f"{OUT}/car_seatbelt_click", seatbelt_click())
    save(f"{OUT}/car_indicator_modern", indicator_modern())
    save(f"{OUT}/car_indicator_classic", indicator_classic())
    try:
        horns = [("car_horn_modern_tap", horn_modern_tap()), ("car_horn_modern_hold", horn_modern_loop()),
                 ("car_horn_classic_meep", horn_classic_meep()), ("car_horn_abarth", horn_abarth())]
        for name, x in horns:
            save(f"{OUT}/{name}", x)
    except MissingHornSource as e:
        print(f"skipping the horns, keeping the committed ones: {e}")
    save(f"{OUT}/car_wipers_slow", wipers(1.5, 4, 3200, 0.8))
    save(f"{OUT}/car_wipers_fast", wipers(0.95, 6, 3300, 1.0))
    for v in range(3):
        save(f"{OUT}/car_wiper_squeak_{v + 1:02d}", wiper_squeak(v))
    save(f"{OUT}/car_radio_tuning_sweep", radio_tuning_sweep())
    save(f"{OUT}/car_radio_station_change", radio_station_change())
    save(f"{OUT}/car_radio_on", radio_on())
    save(f"{OUT}/car_radio_off", radio_off())
    save(f"{OUT}/car_handbrake_up", handbrake_up())
    save(f"{OUT}/car_handbrake_release", handbrake_release())
    save(f"{OUT}/car_ignition_key_in", ignition_key_in())
    save(f"{OUT}/car_ignition_key_turn", ignition_key_turn())
    save(f"{OUT}/car_dash_chime", dash_chime())
    save(f"{OUT}/car_parking_sensor", parking_sensor_loop())
    save(f"{OUT}/car_window_modern_up", window_motor_modern("up"))
    save(f"{OUT}/car_window_modern_down", window_motor_modern("down"))
    save(f"{OUT}/car_window_crank_classic", window_crank_classic())
    save(f"{OUT}/car_roof_electric_500c", roof_electric_500c())
    save(f"{OUT}/car_roof_canvas_manual", roof_canvas_manual())
    save(f"{OUT}/car_roof_canvas_flap", canvas_flap_loop(), norm="lufs:-20")
    save(f"{OUT}/car_trim_rattle_classic", trim_rattle_classic())
    for v in range(3):
        save(f"{OUT}/car_cargo_boxes_slide_{v + 1:02d}", cargo_boxes_slide(v))
    save(f"{OUT}/car_cargo_glass_clink", cargo_glass_clink_loop())
    for v in range(3):
        save(f"{OUT}/car_cargo_glass_smash_{v + 1:02d}", glass_smash(v))


if __name__ == "__main__":
    main()
