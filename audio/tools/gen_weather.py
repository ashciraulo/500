#!/usr/bin/env python3
"""Weather sounds: rain beds (outside, on a metal roof, on a fabric roof, on
the windscreen), thunder, wind, gusts, buffeting, cicadas and drips.
Writes audio/weather/*.ogg.

    python3 audio/tools/gen_weather.py

Rain is built the physical way: thousands of individual drop impacts (each a
short filtered burst, tick or bubble 'plink', chosen from a bank of kernels)
at random times and pan positions, over filtered pink-noise wash. Drops are
placed with wrap-around and rendered with circular convolution, so every bed
loops seamlessly. Seeds are fixed, so output is identical on every run.

Thunder is cut from real CC0 recordings (run fetch_sources.py first; see
CREDITS.md), with a sub boom and building echoes added to the close strikes.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402

from sfxlib import (SR, bp, circ_convolve, circ_filter, circ_lp, env_exp, fade,  # noqa: E402
                    hp, lp, noise, pink, place, reverb, rng, save, secs,
                    smooth_noise, t_axis)

OUT = "weather"


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------


def burst(dur, decay, seed, attack=0.0003):
    n = secs(dur)
    return noise(n, seed) * env_exp(n, decay, attack)


def modal(dur, modes, seed, attack=0.0006):
    """Sum of damped sines, modes = [(freq_hz, decay_s, amp), ...]."""
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
    out = np.zeros((max(len(x) for x in xs),) + xs[0].shape[1:])
    for x in xs:
        out[:len(x)] += x
    return out


def band(n, lo, hi, order=2):
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = 1e-9
    return 1 / np.sqrt(1 + (lo / f) ** (2 * order)) / np.sqrt(1 + (f / hi) ** (2 * order))


def norm_rms(x):
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)


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


def stereo_bed(L, lo, hi, seed, corr=0.4, pinkish=True):
    """Stereo filtered noise wash with partial L/R correlation, periodic."""
    gen = pink if pinkish else noise
    mid = gen(L, seed)
    out = np.stack([np.sqrt(corr) * mid + np.sqrt(1 - corr) * gen(L, seed + 1 + c) for c in range(2)], axis=1)
    return circ_filter(out, band(L, lo, hi))


def drop_field(L, rate, kernels, seed, width=0.9, mod=None, sigma=0.6):
    """Stereo field of `rate` drops per second. Each drop gets a random time
    (wrapping round the loop), level, pan and one kernel from the bank; each
    kernel's impulse trains are circularly convolved, so it loops cleanly.
    `mod` (length L, >=0) scales drop levels over time, e.g. for gusts."""
    r = rng(seed)
    out = np.zeros((L, 2))
    k = r.poisson(rate * L / SR)
    idx = r.integers(0, L, k)
    cls = r.integers(0, len(kernels), k)
    amp = np.minimum(r.lognormal(0, sigma, k), 4.0)
    if mod is not None:
        amp *= mod[idx]
    ang = (r.uniform(-width, width, k) + 1) * np.pi / 4
    gains = (np.cos(ang), np.sin(ang))
    for c, ker in enumerate(kernels):
        sel = cls == c
        for ch in range(2):
            train = np.zeros(L)
            np.add.at(train, idx[sel], amp[sel] * gains[ch][sel])
            out[:, ch] += circ_convolve(train, ker)
    return out


# --------------------------------------------------------------------------
# Drop kernels: what a single raindrop sounds like on each surface
# --------------------------------------------------------------------------


def kernels_outside(seed, count=16):
    """Drops outside on mixed surfaces: hard-surface ticks, wet splats,
    occasional bubble plinks in puddles, softer taps on leaves."""
    r = rng(seed)
    ks = []
    for i in range(count):
        kind = i % 4
        s = seed + 10 + i
        if kind == 0:  # tick on paving / car body
            k = bp(burst(0.02, r.uniform(0.0005, 0.0015), s), r.uniform(1500, 4000), r.uniform(6000, 12000))
        elif kind == 1:  # splat
            k = bp(burst(0.03, r.uniform(0.003, 0.008), s), r.uniform(600, 1500), r.uniform(4000, 8000)) * 0.7
        elif kind == 2:  # puddle bubble plink, pitch rising as the bubble closes
            n = secs(0.03)
            t = t_axis(n)
            f0 = r.uniform(1200, 4000)
            k = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 3 * t)) / SR) * np.exp(-t / r.uniform(0.004, 0.01)) * 0.35
            k = add(k, hp(burst(0.01, 0.0005, s), 2000) * 0.3)
        else:  # leaf / soft ground
            k = bp(burst(0.03, r.uniform(0.005, 0.012), s), r.uniform(250, 600), r.uniform(1500, 3000)) * 0.8
        ks.append(k)
    return ks


def kernels_metal_roof(seed, count=12):
    """Drop on a thin steel roof heard from inside: a 'tik' that excites a
    handful of inharmonic panel modes; the headliner damps the top end."""
    r = rng(seed)
    ks = []
    for i in range(count):
        modes = [(f, r.uniform(0.01, 0.05), r.uniform(0.2, 1.0) / (1 + f / 1500))
                 for f in r.uniform(180, 3200, 7)]
        k = add(modal(0.12, modes, seed + 10 + i, 0.0003), bp(burst(0.02, 0.001, seed + 50 + i), 1500, 6000) * 0.5)
        ks.append(lp(k, 4500, 2))
    return ks


def kernels_fabric_roof(seed, count=10):
    """Drop on a taut canvas roof from inside: a soft, drummy 'pat' - a
    low membrane resonance (120-260 Hz) and dull, damped highs."""
    r = rng(seed)
    ks = []
    for i in range(count):
        f = r.uniform(120, 260)
        k = add(modal(0.1, [(f, 0.018, 1.0), (f * 1.59, 0.01, 0.4), (f * 2.14, 0.007, 0.25)], seed + 10 + i, 0.001),
                lp(burst(0.03, 0.004, seed + 40 + i), 900) * 0.8)
        ks.append(k)
    return ks


def kernels_windscreen(seed, count=12):
    """Drops hitting the windscreen close up: a crisp glass tap with a
    short high ring, some with a wet splat."""
    r = rng(seed)
    ks = []
    for i in range(count):
        f = r.uniform(2500, 5000)
        k = add(modal(0.04, [(f, 0.004, 0.4), (f * 1.7, 0.003, 0.2)], seed + 10 + i, 0.0002),
                hp(burst(0.02, r.uniform(0.0004, 0.001), seed + 30 + i), 1500) * 0.7)
        if i % 3 == 0:
            k = add(k, bp(burst(0.03, 0.006, seed + 60 + i), 500, 5000) * 0.4)
        ks.append(k)
    return ks


# --------------------------------------------------------------------------
# Rain beds (stereo loops)
# --------------------------------------------------------------------------


LOOP_S = 40.0


def rain_outside(heavy):
    """Rain outside. Light: sparse distinct drops over a soft hiss.
    Heavy: dense pelting drops, louder wash, a low roar of water on every
    surface, intensity swelling slowly."""
    L = secs(LOOP_S)
    seed = 8000 if heavy else 8100
    swell = np.clip(1 + (0.25 if heavy else 0.15) * smooth_noise(L, 0.08, seed + 1), 0.3, None)
    drops = drop_field(L, 2600 if heavy else 260, kernels_outside(seed + 2), seed + 3, mod=swell)
    near = drop_field(L, 40 if heavy else 18, kernels_outside(seed + 4, 8), seed + 5, sigma=0.4, mod=swell)
    wash = stereo_bed(L, 500, 12000, seed + 6, 0.3) * swell[:, None]
    roar = stereo_bed(L, 80, 900, seed + 7, 0.6) * swell[:, None]
    if heavy:
        x = norm_rms(drops) * 1.0 + norm_rms(near) * 0.35 + norm_rms(wash) * 0.8 + norm_rms(roar) * 0.45
    else:
        x = norm_rms(drops) * 1.0 + norm_rms(near) * 0.6 + norm_rms(wash) * 0.45 + norm_rms(roar) * 0.15
    return check_loop(f"rain_outside heavy={heavy}", x)


def rain_roof(heavy, fabric=False):
    """Rain on the car roof heard from inside. Metal: ringing ticks and a
    drummed low rumble of the panel when it's heavy. Fabric: soft drummy
    pats. Under it, the outside rain comes through the glass muffled."""
    L = secs(LOOP_S)
    seed = 8200 + (100 if heavy else 0) + (500 if fabric else 0)
    swell = np.clip(1 + 0.2 * smooth_noise(L, 0.08, seed + 1), 0.3, None)
    ks = kernels_fabric_roof(seed + 2) if fabric else kernels_metal_roof(seed + 2)
    drops = drop_field(L, 1800 if heavy else 180, ks, seed + 3, width=0.7, mod=swell)
    drum = circ_filter(drops, band(L, 40, 300)) if heavy else np.zeros_like(drops)
    outside = rain_outside_muffled(L, heavy, seed + 4) * swell[:, None]
    cabin = stereo_bed(L, 40, 250, seed + 5, 0.8) * swell[:, None]
    x = norm_rms(drops) + norm_rms(outside) * (0.35 if heavy else 0.25) + norm_rms(cabin) * (0.3 if heavy else 0.12)
    if heavy:
        x += norm_rms(drum) * 0.3
    return check_loop(f"rain_roof heavy={heavy} fabric={fabric}", x)


def rain_outside_muffled(L, heavy, seed):
    """Outside rain through glass: same drop field, heavily low-passed."""
    drops = drop_field(L, 1200 if heavy else 150, kernels_outside(seed, 8), seed + 1)
    wash = stereo_bed(L, 200, 6000, seed + 2, 0.3)
    return circ_filter(norm_rms(drops) + norm_rms(wash) * 0.6, band(L, 60, 1400))


def rain_windscreen():
    """Rain hitting the windscreen, a close layer for in-car views: crisp
    taps across the glass, a thin film-water fizz, the odd rivulet."""
    L = secs(30.0)
    seed = 8700
    swell = np.clip(1 + 0.2 * smooth_noise(L, 0.1, seed + 1), 0.3, None)
    drops = drop_field(L, 220, kernels_windscreen(seed + 2), seed + 3, width=0.8, mod=swell)
    fizz = stereo_bed(L, 3000, 12000, seed + 4, 0.2) * swell[:, None]
    rivulet = np.zeros((L, 2))
    r = rng(seed + 5)
    for i in range(6):
        n = secs(r.uniform(0.6, 1.4))
        tr = bp(noise(n, seed + 10 + i), 1200, 5000) * np.hanning(n) * (1 + 0.6 * smooth_noise(n, 20, seed + 20 + i, periodic=False))
        p = r.uniform(-0.6, 0.6)
        a = (p + 1) * np.pi / 4
        at = int(r.integers(0, L))
        place(rivulet[:, 0], tr * np.cos(a), at, wrap=True)
        place(rivulet[:, 1], tr * np.sin(a), at, wrap=True)
    x = norm_rms(drops) + norm_rms(fizz) * 0.12 + norm_rms(rivulet) * 0.1
    return check_loop("rain_windscreen", x)


# --------------------------------------------------------------------------
# Thunder (stereo one-shots)
# --------------------------------------------------------------------------


# Recorded thunder (CC0, fetched by fetch_sources.py into build/sources/, see
# CREDITS.md): key -> (where to look for the strike in s, length kept in s).
SRC = Path(__file__).resolve().parents[2] / "build" / "sources"
THUNDER_CLOSE = [("thunder_close1", 0.0, 9.0), ("thunder_close2", 1.5, 11.0), ("thunder_close3", 6.0, 13.0)]
THUNDER_FAR = [("thunder_far1", 197.5, 8.0), ("thunder_far2", 0.4, 10.0), ("thunder_far3", 96.0, 12.0)]


def recording(key, start, dur):
    """dur seconds of a fetched recording from start, stereo 48 kHz,
    with sub-25 Hz rumble removed."""
    f = SRC / f"{key}.mp3"
    if not f.exists():
        raise FileNotFoundError(f"missing {f}: run audio/tools/fetch_sources.py first (thunder is recorded)")
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(f), "-ss", f"{start:.3f}",
                        "-t", f"{dur:.3f}", "-ar", str(SR), "-ac", "2", "-c:a", "pcm_f32le", tmp.name],
                       check=True)
        x, _ = sf.read(tmp.name, dtype="float64")
    return hp(x, 25, 2)


def strike_onset(x, thresh_db=6.0):
    """Sample index where the level first comes within thresh_db of the peak."""
    m = np.abs(x).mean(axis=1)
    hop = SR // 200
    k = len(m) // hop
    e = 20 * np.log10(np.sqrt(np.mean(m[: k * hop].reshape(k, hop) ** 2, 1)) + 1e-9)
    return int(np.argmax(e > e.max() - thresh_db)) * hop


def building_echoes(x, seed, n=6):
    """Slap-back echoes off buildings: darker copies of the whole strike
    arriving 0.1-0.9 s later, alternating left and right."""
    r = rng(seed)
    out = x.copy()
    for i in range(n):
        d = secs(r.uniform(0.1, 0.9))
        g = r.uniform(0.12, 0.3) * (1 - i / (n + 2)) * 1.4
        e = lp(x, r.uniform(1500, 3500), 2)
        a = (((i % 2) * 2 - 1) * r.uniform(0.4, 0.9) + 1) * np.pi / 4
        out[d:, 0] += g * e[:-d, 0] * np.cos(a)
        out[d:, 1] += g * e[:-d, 1] * np.sin(a)
    return out


def boom(n, seed):
    """Sub boom under the crack: a long low N-wave plus 30-90 Hz rumble."""
    t = t_axis(n)
    m = secs(0.09)
    nw = np.zeros(n)
    nw[:m] = np.linspace(1, -1, m)
    b = lp(nw, 120, 2) * 2.0 + lp(noise(n, seed), 90, 4) * (1 - np.exp(-t / 0.03)) * np.exp(-t / 0.9) * 3
    return hp(b, 28, 2)


def thunder_close(v):
    """Close strike from a real recording (crack, then the long roll), cut to
    start at the strike. The first 0.4 s gets extra top for a sharper rip, a
    sub boom fills the low end the field mic missed, and slap-back echoes
    off buildings make it a city strike."""
    key, look, dur = THUNDER_CLOSE[v]
    seed = 8800 + 10 * v
    x = recording(key, look, dur + 4.0)
    a = max(0, strike_onset(x) - secs(0.04))
    x = x[a:a + secs(dur)]
    x = x / np.sqrt(np.mean(x[: secs(3)] ** 2))
    t = t_axis(len(x))
    x = x + hp(x, 2500, 2) * np.exp(-np.clip(t - 0.04, 0, None) / 0.35)[:, None] * 0.6
    bm = boom(len(x), seed)
    bm *= 0.8 * np.sqrt(np.mean(lp(x[: secs(2)], 120, 2) ** 2) / np.mean(bm[: secs(2)] ** 2))
    x[secs(0.04):] += bm[: -secs(0.04), None]
    x = building_echoes(x, seed + 3)
    return fade(x, 0.005, 1.8)


def thunder_distant(v):
    """Distant thunder from a real recording of far-off rolls: no crack, and
    low-passed further as the air has eaten the highs."""
    key, start, dur = THUNDER_FAR[v]
    x = lp(recording(key, start, dur), 500, 2)
    x = reverb(x, size_s=3.0, damp_hz=1500, wet=0.2, predelay_s=0.05, seed=8900 + 10 * v + 2)
    return fade(x, 0.3, 1.5)


# --------------------------------------------------------------------------
# Wind
# --------------------------------------------------------------------------


def wind_bank(L, seed, intensity, periodic=True, howl_lo=250, howl_hi=900):
    """Wind = broadband rush (pink, low-heavy) plus a bank of narrow 'howl'
    bands whose levels wander independently, so the whistle seems to move
    in pitch. intensity (array, ~0..1.5) drives level and brightness."""
    r = rng(seed)
    gen = (lambda k: pink(L, k)) if periodic else (lambda k: lp(noise(L, k), 1200, 1))
    mid = gen(seed + 5)
    rush = np.stack([0.6 * mid + 0.8 * gen(seed + c) for c in range(2)], axis=1)
    lowr = circ_filter(rush, band(L, 30, 400))
    highr = circ_filter(rush, band(L, 400, 5000))
    howl = np.zeros((L, 2))
    f = np.fft.rfftfreq(L, 1 / SR)
    for i, fc in enumerate(np.geomspace(howl_lo, howl_hi, 8)):
        resp = 1 / (1 + ((f - fc) / (fc / 25)) ** 2)
        src = np.stack([noise(L, seed + 20 + 2 * i), noise(L, seed + 21 + 2 * i)], axis=1)
        b = norm_rms(circ_filter(src, resp))
        g = np.clip(smooth_noise(L, r.uniform(0.15, 0.4), seed + 40 + i, periodic=periodic) - 0.3, 0, None) ** 1.5
        g = g * np.clip(intensity - 0.2 + 0.15 * i / 8, 0, None) * 1.4
        howl += b * g[:, None]
    I = intensity[:, None]
    return norm_rms(lowr) * (0.6 + 0.6 * I) * I + norm_rms(highr) * 0.35 * I ** 2 + howl * 0.12


def wind_bed():
    """Steady wind, seamless 40 s: moderate breeze with slow gust cycles."""
    L = secs(LOOP_S)
    intensity = np.clip(0.75 + 0.25 * smooth_noise(L, 0.1, 9001) + 0.08 * smooth_noise(L, 0.6, 9002), 0.25, None)
    return check_loop("wind_bed", wind_bank(L, 9000, intensity))


def wind_gust(v):
    """Single gust: swells over ~1-2 s, peaks with the howl rising, leaves
    and grit hiss, then dies away; sweeps across the stereo field."""
    r = rng(9100 + v)
    dur = [5.0, 6.5, 4.5][v]
    n = secs(dur)
    t = t_axis(n)
    pk = r.uniform(0.35, 0.5) * dur
    env = np.where(t < pk, (t / pk) ** 2, np.exp(-(t - pk) / (dur * 0.22)))
    env = env * (1 + 0.15 * smooth_noise(n, 3, 9110 + v, periodic=False))
    intensity = 0.1 + 1.2 * np.clip(env, 0, None)
    x = wind_bank(n, 9120 + 50 * v, intensity, periodic=False, howl_lo=300, howl_hi=1300)
    leaves = bp(noise(n, 9130 + v), 2500, 9000) * (np.minimum(1, (rng(9140 + v).random(n) < 0.02) * 3 + 0.15)) * env ** 2
    pan = np.clip((t - pk) / dur * 1.5, -0.8, 0.8) * (1 if v % 2 else -1)
    a = (pan + 1) * np.pi / 4
    x = x * np.stack([0.6 + 0.4 * np.cos(a) * 1.41, 0.6 + 0.4 * np.sin(a) * 1.41], axis=1)
    x[:, 0] += leaves * 0.25 * np.cos(a)
    x[:, 1] += leaves * 0.25 * np.sin(a)
    return fade(x, 0.05, 0.3)


def wind_buffet_loop():
    """Wind buffeting at speed (window down): a low throbbing pressure pulse
    (cabin Helmholtz resonance ~18 Hz, wavering) plus turbulent roar that
    lurches 3-8 times a second. Built from periodic pieces."""
    L = secs(8.0)
    T = L / SR
    t = t_axis(L)
    f0 = round(18 * T) / T
    fm = smooth_noise(L, 0.7, 9201)
    fm -= fm.mean()
    ph = 2 * np.pi * np.cumsum(f0 * (1 + 0.12 * fm)) / SR
    throb = (np.sin(ph) + 0.4 * np.sin(2 * ph + 1)) * np.clip(0.7 + 0.4 * smooth_noise(L, 1.5, 9202), 0.1, None)
    roar = stereo_bed(L, 60, 3000, 9203, 0.5)
    lurch = np.clip(1 + 0.45 * smooth_noise(L, 6, 9204), 0.2, None)
    flutter = stereo_bed(L, 300, 2500, 9205, 0.2) * (0.5 + 0.5 * np.sin(ph)[:, None]) ** 2
    x = norm_rms(roar) * lurch[:, None] * 0.7 + throb[:, None] * 0.6 + norm_rms(flutter) * 0.25
    return check_loop("wind_buffet", x)


# --------------------------------------------------------------------------
# Cicadas and drips
# --------------------------------------------------------------------------


def cicadas():
    """Hot-day cicada chorus (Australian, e.g. green grocers / black princes):
    each insect's tymbals click a few hundred times a second, giving a
    harsh buzz centred around 4-7 kHz; individuals swell, pulse and drop out
    on their own cycles, some near, some far. Stereo, seamless 30 s."""
    L = secs(30.0)
    T = L / SR
    t = t_axis(L)
    r = rng(9300)
    out = np.zeros((L, 2))
    f = np.fft.rfftfreq(L, 1 / SR)
    for i in range(9):
        rate = round(r.uniform(180, 420) * T) / T
        ph = (rate * t + r.uniform(0, 1)) % 1.0
        clicks = np.exp(-ph / 0.12)  # tymbal buckling pulses
        fc = r.uniform(4000, 7000)
        resp = np.exp(-0.5 * ((f - fc) / (fc * 0.18)) ** 2)
        carrier = norm_rms(circ_filter(noise(L, 9310 + i), resp))
        style = i % 3
        if style == 0:  # steady drone with slow swells
            env = np.clip(0.6 + 0.5 * smooth_noise(L, 0.15, 9330 + i), 0, None)
        elif style == 1:  # rhythmic pulsing 3-7 Hz, phrases on/off
            pr = round(r.uniform(3, 7) * T) / T
            env = (0.5 + 0.5 * np.sin(2 * np.pi * pr * t)) ** 3 * np.clip(smooth_noise(L, 0.1, 9340 + i) + 0.4, 0, None)
        else:  # rising phrases that crescendo then cut out
            pr = round(r.uniform(0.15, 0.3) * T) / T
            saw = (pr * t + r.uniform(0, 1)) % 1.0
            env = np.where(saw < 0.8, (saw / 0.8) ** 2, 0.0)
            env = circ_lp(env, 40)
        dist = r.uniform(0.25, 1.0)
        voice = carrier * (0.4 + clicks) * env
        if dist < 0.5:
            voice = circ_lp(voice, 5000)
        p = r.uniform(-0.9, 0.9)
        a = (p + 1) * np.pi / 4
        out[:, 0] += voice * dist * np.cos(a)
        out[:, 1] += voice * dist * np.sin(a)
    air = stereo_bed(L, 200, 8000, 9390, 0.3)
    return check_loop("cicadas", out + norm_rms(air) * 0.05 * np.sqrt(np.mean(out ** 2)))


def drip(v):
    """Single drips: 1 into a puddle (bubble plink), 2 on a metal sill
    (tink), 3 on a leaf (soft tap), 4 into a bucket (deep hollow plonk)."""
    r = rng(9400 + v)
    n = secs(0.5)
    t = t_axis(n)
    if v == 0:
        f0 = r.uniform(1100, 1500)
        x = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 2.5 * t)) / SR) * np.exp(-t / 0.03)
        x = add(x, hp(burst(0.02, 0.0008, 9410), 2000) * 0.3)
    elif v == 1:
        x = add(modal(0.5, [(3150, 0.05, 0.5), (5400, 0.03, 0.3), (8100, 0.015, 0.15)], 9420, 0.0002),
                hp(burst(0.02, 0.0005, 9421), 2000) * 0.5)
    elif v == 2:
        x = add(bp(burst(0.1, 0.006, 9430), 400, 3000), modal(0.1, [(r.uniform(500, 700), 0.01, 0.3)], 9431))
    else:
        f0 = 420
        x = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 1.5 * t)) / SR) * np.exp(-t / 0.06) * 0.8
        x = add(x, modal(0.5, [(210, 0.08, 0.3), (590, 0.05, 0.2)], 9440), bp(burst(0.03, 0.002, 9441), 300, 4000) * 0.3)
    x = np.concatenate([x, np.zeros(secs(0.3))])
    return fade(reverb(x, 0.3, 4500, 0.12, 0.005, 9450 + v).mean(axis=1), fout=0.05)


# --------------------------------------------------------------------------


def main():
    save(f"{OUT}/weather_rain_light_outside", rain_outside(False), norm="amb")
    save(f"{OUT}/weather_rain_heavy_outside", rain_outside(True), norm="lufs:-20")
    save(f"{OUT}/weather_rain_light_roof_metal", rain_roof(False), norm="amb")
    save(f"{OUT}/weather_rain_heavy_roof_metal", rain_roof(True), norm="lufs:-20")
    save(f"{OUT}/weather_rain_light_roof_fabric", rain_roof(False, fabric=True), norm="amb")
    save(f"{OUT}/weather_rain_heavy_roof_fabric", rain_roof(True, fabric=True), norm="lufs:-20")
    save(f"{OUT}/weather_rain_windscreen", rain_windscreen(), norm="amb")
    try:
        thunder = [(f"weather_thunder_{kind}_{v + 1:02d}", fn(v))
                   for v in range(3) for kind, fn in (("close", thunder_close), ("distant", thunder_distant))]
        for name, x in thunder:
            save(f"{OUT}/{name}", x)
    except FileNotFoundError as e:
        print(f"skipping the thunder, keeping the committed files: {e}")
    save(f"{OUT}/weather_wind_bed", wind_bed(), norm="amb")
    for v in range(3):
        save(f"{OUT}/weather_wind_gust_{v + 1:02d}", wind_gust(v))
    save(f"{OUT}/weather_wind_buffet", wind_buffet_loop(), norm="lufs:-20")
    save(f"{OUT}/weather_cicadas", cicadas(), norm="amb")
    for v in range(4):
        save(f"{OUT}/weather_drip_{v + 1:02d}", drip(v))


if __name__ == "__main__":
    main()
