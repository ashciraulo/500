#!/usr/bin/env python3
"""Tyre, road-surface and impact sounds. Writes audio/tyre/*.ogg and
audio/impact/*.ogg.

    python3 audio/tools/gen_tyres.py

Loops are built periodically (FFT-domain filtering, wrapped event placement,
whole-cycle frequencies) so they join without a click. Tyre roll speed layers
are rendered as one set and share a single gain so their relative loudness is
kept. Seeds are fixed, so the output is identical on every run.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402
import pyloudnorm  # noqa: E402

from sfxlib import (SR, bp, circ_filter, circ_lp, env_exp, fade,  # noqa: E402
                    hp, lp, noise, pink, place, resonator, reverb, rng, save, secs,
                    smooth_noise, softclip, t_axis, true_peak)

# --------------------------------------------------------------------------
# Small helpers (same family as gen_car.py)
# --------------------------------------------------------------------------


def burst(dur, decay, seed, attack=0.0003):
    """White-noise burst with an exponential decay: the raw 'hit'."""
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


def room(x, size=0.3, wet=0.12, damp=4000, seed=3):
    """Short mono outdoor reflection tail (kerbs, walls, parked cars)."""
    return reverb(x, size_s=size, damp_hz=damp, wet=wet, predelay_s=0.006, seed=seed).mean(axis=1)


def periodic(x, fn):
    """Run a causal filter over a periodic signal so its output still loops."""
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


def band(n, lo, hi, order=2):
    """Magnitude response of a band-pass, for circ_filter."""
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = 1e-9
    return 1 / np.sqrt(1 + (lo / f) ** (2 * order)) / np.sqrt(1 + (f / hi) ** (2 * order))


def peak_resp(n, fc, bw):
    """Broad resonant hump centred on fc (Lorentzian), for circ_filter."""
    f = np.fft.rfftfreq(n, 1 / SR)
    return 1 / (1 + ((f - fc) / bw) ** 2)


def snap(f, L):
    """Round a frequency to a whole number of cycles in an L-sample loop."""
    T = L / SR
    return max(1, round(f * T)) / T


def sparse(L, rate, seed, sigma=0.8):
    """Poisson impulse train (rate per s) with log-normal amplitudes: the
    raw material for grit, gravel and droplets. Periodic by construction."""
    r = rng(seed)
    x = np.zeros(L)
    k = r.poisson(rate * L / SR)
    idx = r.integers(0, L, k)
    np.add.at(x, idx, np.minimum(r.lognormal(0, sigma, k), 3.0) * r.choice([-1, 1], k))
    return x


def norm_rms(x):
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)


# --------------------------------------------------------------------------
# Tyre roll / skid (loops)
# --------------------------------------------------------------------------


def tyre_roll(kmh, seed, L=secs(8.0)):
    """Dry asphalt roll at a given speed. Layers: air pumping out of the tread
    (broad hump that rises in pitch with speed), road-texture rumble, the
    smeared tread-block tone (v / 30 mm pitch), a once-per-wheel-turn swell,
    sparse grit ticks and a faint high hiss. Level grows ~ v^1.2."""
    v = kmh / 3.6
    fc = 450 + 7 * kmh
    pump = circ_filter(pink(L, seed), peak_resp(L, fc, 250 + 4 * kmh) * band(L, 80, 9000))
    rumble = circ_filter(pink(L, seed + 1), band(L, 40, 220 + kmh))
    tread_f = v / 0.03
    tread = circ_filter(noise(L, seed + 2), peak_resp(L, tread_f, tread_f * 0.06))
    fr = snap(v / 1.85, L)
    t = t_axis(L)
    swell = 1 + 0.12 * np.sin(2 * np.pi * fr * t) + 0.06 * smooth_noise(L, 2, seed + 3)
    grit = circ_filter(sparse(L, 25 * v, seed + 4, 1.0), band(L, 1500, 9000))
    grit = grit / np.max(np.abs(grit))
    x = (norm_rms(pump) * (0.5 + kmh / 200) + norm_rms(rumble) * 0.9 + norm_rms(tread) * 0.25
         + grit * 0.5 * (1 + kmh / 100)
         + norm_rms(circ_filter(noise(L, seed + 5), band(L, 2500, 8000))) * 0.1 * kmh / 50) * swell
    return x * (kmh / 50) ** 1.2


def squeal_voice(L, f0, seed, periodic=True, hop_depth=0.12, jitter=0.004, contour=None, fhi=9000):
    """One stick-slip squeal voice. The rubber sticks and slips at a pitch
    that wanders slowly, wobbles a little, hops between stick-slip modes
    (random steps held 0.1-0.6 s, edges smoothed) and jitters cycle to cycle.
    Its harmonics are weighted by two drifting tread/belt resonances, so the
    loudest partial keeps shifting. periodic=True keeps every modulation
    circular and the mean pitch on a whole number of cycles (seamless loop)."""
    r = rng(seed)

    def sm(rate, s):
        return smooth_noise(L, rate, s, periodic=periodic)

    steps = np.zeros(L)
    pos = 0
    while pos < L:
        ln = secs(r.uniform(0.1, 0.6))
        steps[pos:pos + ln] = r.choice([-1.0, -0.4, 0.0, 0.0, 0.5, 1.0])
        pos += ln
    steps = circ_lp(steps, 9, 2) if periodic else lp(steps, 9, 2)
    logf = 0.035 * sm(3, seed + 1) + 0.012 * sm(9, seed + 6) + hop_depth * steps + jitter * sm(300, seed + 2)
    f = f0 * np.exp(logf - logf.mean())
    if contour is not None:
        f = f * contour
    if periodic:
        f *= snap(f.mean(), L) / f.mean()
    ph = 2 * np.pi * np.cumsum(f) / SR
    fa = 1300 * np.exp(0.25 * sm(1.5, seed + 3))
    fb = 2300 * np.exp(0.2 * sm(2.2, seed + 4))
    wb = 0.6 + 0.4 * sm(4, seed + 5)
    out = np.zeros(L)
    for k in range(1, 16):
        fk = k * f
        if fk.min() > fhi:
            break
        g = (1 / k ** 0.9) * (1 / (1 + ((fk - fa) / 500) ** 2) + wb / (1 + ((fk - fb) / 700) ** 2) + 0.12)
        out += g * (fk < fhi) * np.sin(k * ph + r.uniform(0, 2 * np.pi))
    return out


def squeal_flutter(L, seed, periodic=True):
    """Level of a squeal voice: 12-35 Hz stick-slip chatter, a slow swell and
    the odd brief loss of grip where the tone nearly drops out."""
    def sm(rate, s):
        return smooth_noise(L, rate, s, periodic=periodic)
    drop = np.clip(sm(5, seed + 2) - 1.2, 0, None)
    return np.clip(0.75 + 0.25 * sm(30, seed) + 0.25 * sm(2, seed + 1) - 0.9 * drop, 0.05, None)


def skid_squeal_loop(L=secs(4.0)):
    """Dry-tarmac skid: two tyres' stick-slip squeals (~1050 and ~1390 Hz)
    plus a weak high mode (~2150 Hz), each wavering, hopping and fluttering
    on its own, softly clipped together; over gritty scrub (rubber tearing on
    asphalt, louder where the squeal loses grip) and a little rumble. All
    modulation is circular and pitches whole-cycle, so it loops seamlessly."""
    out = np.zeros(L)
    level = np.zeros(L)
    for f0, g, s in [(1050, 1.0, 4400), (1390, 0.65, 4410), (2150, 0.22, 4420)]:
        a = squeal_flutter(L, s + 50)
        out += g * norm_rms(squeal_voice(L, f0, s)) * a
        level += g * a
    out = softclip(out * 0.35, 1.5)
    lvl = level / level.mean()
    grit = circ_filter(sparse(L, 4000, 4450, 1.0), band(L, 600, 7000))
    hiss = circ_filter(noise(L, 4451), band(L, 250, 4500))
    scrub = (norm_rms(grit) * 0.5 + norm_rms(hiss) * 0.6) * (1.25 - 0.35 * np.clip(lvl, 0, 2))
    rumble = norm_rms(circ_lp(pink(L, 4452), 220)) * 0.22
    return check_loop("skid_dry", norm_rms(out) + 0.32 * scrub + rumble)


def skid_chirp(v):
    """Short squeal chirp (a quick turn-in or brake dab): a scrub transient,
    then a stick-slip squeal that grabs fast, rises as the patch sticks and
    sags as it lets go, with the loop's wavering, shifting partials."""
    r = rng(4500 + v)
    dur = [0.18, 0.3, 0.25, 0.4][v]
    n = secs(dur)
    t = t_axis(n)
    u = t / dur
    bend = np.exp(0.18 * np.sin(np.pi * u ** 0.7) - 0.08 * u)
    sq = squeal_voice(n, r.uniform(950, 1250), 4510 + v, False, hop_depth=0.06, jitter=0.006, contour=bend)
    env = (1 - np.exp(-t / 0.008)) * np.sin(np.pi * u) ** 0.5 * np.exp(-u * 0.7)
    x = softclip(norm_rms(sq) * env * squeal_flutter(n, 4520 + v, False) * 0.4, 1.5)
    scrub = bp(noise(n, 4530 + v), 300, 5000) * (np.exp(-t / 0.05) * 0.25) + bp(noise(n, 4531 + v), 300, 5000) * env * 0.1
    x = norm_rms(x) + scrub
    return fade(room(np.concatenate([x, np.zeros(secs(0.3))]), 0.35, 0.15, 5000, 4540 + v), 0.003, 0.05)


def wet_roll_loop(L=secs(8.0)):
    """Wet road: high spray hiss thrown off the tread, mid water swish that
    sloshes as the film depth varies, a little dry-tyre roar underneath, and
    droplet ticks hitting the arches."""
    hiss = norm_rms(circ_filter(noise(L, 4200), band(L, 1800, 10000))) * (1 + 0.3 * smooth_noise(L, 1.2, 4201))
    swish = norm_rms(circ_filter(pink(L, 4202), band(L, 350, 2200))) * (1 + 0.4 * smooth_noise(L, 3, 4203))
    roar = norm_rms(tyre_roll(50, 4204, L)) * 0.35
    drops = norm_rms(circ_filter(sparse(L, 300, 4205, 0.9), band(L, 1200, 7000))) * 0.15
    return check_loop("wet_roll", hiss * 0.5 + swish * 0.4 + roar + drops)


def wet_skid_loop(L=secs(4.0)):
    """Wet skid: no clean squeal - water is squeegeed out as a loud broadband
    hiss with a gritty scrub and a faint smeared squeal underneath."""
    hiss = norm_rms(circ_filter(noise(L, 4300), band(L, 900, 9000))) * (1 + 0.35 * smooth_noise(L, 8, 4301))
    scrub = norm_rms(circ_filter(pink(L, 4302), band(L, 150, 1500))) * (1 + 0.4 * smooth_noise(L, 14, 4303))
    f0 = snap(780, L)
    fm = smooth_noise(L, 3, 4304)
    fm -= fm.mean()
    ph = 2 * np.pi * np.cumsum(f0 * (1 + 0.04 * fm)) / SR
    squeal = sum(np.sin(k * ph) / k for k in range(1, 5)) * np.clip(smooth_noise(L, 6, 4305), 0, None) * 0.15
    return check_loop("wet_skid", hiss * 0.55 + scrub * 0.45 + squeal)


# --------------------------------------------------------------------------
# Water one-shots
# --------------------------------------------------------------------------


def droplet(seed, amp=1.0):
    """One drop landing: a tiny tick plus a Minnaert bubble 'plink' whose
    pitch rises as the bubble closes."""
    r = rng(seed)
    n = secs(0.03)
    t = t_axis(n)
    f0 = r.uniform(900, 4000)
    plink = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 4 * t)) / SR) * np.exp(-t / r.uniform(0.004, 0.012))
    tickn = hp(burst(0.01, 0.0006, seed + 1), 2000) * 0.5
    return amp * add(plink * r.uniform(0.2, 0.7), tickn)


def splash(big, v):
    """Tyre into a puddle: water slaps the tyre and arch (low thump), a sheet
    of spray whooshes out (broadband noise), then droplets rain back down."""
    r = rng(4400 + 10 * big + v)
    dur = 2.0 if big else 1.0
    n = secs(dur)
    slap = add(lp(burst(0.2, 0.03 if big else 0.015, 4410 + v), 220 if big else 350) * 3.0,
               bp(burst(0.1, 0.008, 4411 + v), 400, 6000) * 0.6)
    wn = secs(1.0 if big else 0.5)
    wt = t_axis(wn)
    wash_env = np.minimum(1, wt / 0.012) * np.exp(-wt / (0.25 if big else 0.1))
    wash = add(bp(noise(wn, 4412 + v), 600, 9000) * 0.5, bp(noise(wn, 4413 + v), 150, 1200) * 0.8) * wash_env
    parts = [(0.01, slap, 1.0), (0.012, wash, 1.0)]
    for i in range(int(r.integers(80, 140) if big else r.integers(30, 60))):
        at = 0.03 + r.gamma(2.0, 0.18 if big else 0.08)
        if at < dur - 0.05:
            parts.append((at, droplet(4500 + 100 * v + 1000 * big + i, r.uniform(0.05, 0.3)), 1.0))
    return fade(room(mix(dur, parts), 0.3, 0.12, 6000, 4420 + v), fout=0.08)


def passing_spray(v):
    """A car passing through standing water: tyre hiss and spray swell and
    fade (point source going by), brighter at closest approach, tyre tone
    dropping in pitch (Doppler)."""
    r = rng(4600 + v)
    dur = 4.0
    n = secs(dur)
    t = t_axis(n)
    tc = r.uniform(1.6, 2.0)
    w = r.uniform(0.35, 0.5)
    prox = 1 / (1 + ((t - tc) / w) ** 2)
    spray = bp(noise(n, 4610 + v), 1500, 10000)
    roar = bp(pink(n, 4611 + v), 120, 1500)
    dark = lp(spray, 2500)
    sweep = norm_rms(spray) * prox ** 1.5 * 0.6 + norm_rms(dark) * prox * 0.4 + norm_rms(roar) * prox ** 1.2 * 0.6
    dop = 1 + 0.06 * np.tanh(-(t - tc) / w)
    tone = np.sin(2 * np.pi * np.cumsum(450 * dop) / SR) * prox ** 2 * 0.08
    splashes = np.zeros(n)
    for i in range(30):
        at = int(r.normal(tc, w * 0.6) * SR)
        if 0 < at < n - secs(0.05):
            place(splashes, droplet(4700 + 50 * v + i, r.uniform(0.1, 0.3) * prox[at]), at)
    return fade(sweep + tone + splashes, 0.2, 0.3)


# --------------------------------------------------------------------------
# Impacts
# --------------------------------------------------------------------------


def debris(dur, count, seed, start=0.05, spread=0.25, high=True):
    """Bits falling and bouncing after a hit: random small knocks/tings
    whose timing thins out exponentially."""
    r = rng(seed)
    out = np.zeros(secs(dur))
    for i in range(count):
        at = start + r.exponential(spread)
        if at > dur - 0.1:
            continue
        a = r.uniform(0.05, 0.25) * np.exp(-at / (spread * 2))
        if high and r.random() < 0.4:
            f = r.uniform(1800, 4500)
            hit = modal(0.08, [(f, 0.02, 1.0), (f * 2.4, 0.01, 0.5)], seed + 10 + i)
        else:
            f = r.uniform(300, 1200)
            hit = add(modal(0.06, [(f, 0.01, 1.0), (f * 1.7, 0.006, 0.4)], seed + 10 + i),
                      bp(burst(0.02, 0.002, seed + 500 + i), 500, 5000) * 0.5)
        place(out, a * hit, secs(at))
    return out


def crumple(dur, density, seed, decay):
    """Sheet metal crumpling: a dense cluster of tiny buckling clicks through
    panel resonances, plus tearing noise."""
    n = secs(dur)
    r = rng(seed)
    t = t_axis(n)
    imp = np.zeros(n)
    k = int(density * dur)
    idx = (r.exponential(decay, k) * SR).astype(int)
    idx = idx[idx < n]
    np.add.at(imp, idx, r.lognormal(0, 0.8, len(idx)))
    body = sum(resonator(imp, f, q) * g for f, q, g in
               [(r.uniform(180, 260), 8, 1.0), (r.uniform(420, 560), 10, 0.8), (r.uniform(900, 1200), 12, 0.6),
                (r.uniform(1900, 2400), 15, 0.4), (r.uniform(3200, 4200), 15, 0.25)])
    tear = bp(noise(n, seed + 1), 800, 7000) * np.exp(-t / decay) * 0.08
    return body * 3 + tear


def impact_light(v):
    """Light bump (parking tap): soft low thud as the bumper absorbs it, a
    hollow plastic knock, a small rattle of a loose clip."""
    r = rng(5000 + v)
    thud = add(lp(burst(0.2, 0.025, 5010 + v), 180) * 2.0,
               modal(0.3, [(r.uniform(70, 95), 0.05, 0.6), (r.uniform(150, 190), 0.03, 0.3)], 5020 + v, 0.003))
    knock = modal(0.15, [(r.uniform(320, 420), 0.02, 0.4), (r.uniform(700, 900), 0.012, 0.25),
                         (r.uniform(1400, 1700), 0.008, 0.12)], 5030 + v)
    rattle = debris(0.3, 4, 5040 + v, 0.02, 0.05, high=False) * 0.6
    return fade(room(mix(0.8, [(0.01, thud, 1.0), (0.012, knock, 1.0), (0.02, rattle, 1.0)]), seed=5050 + v), fout=0.05)


def impact_medium(v):
    """Medium crash: a bang of several panels at once (low body thump +
    inharmonic metal modes), crumpling, a plastic crack, a few glass bits and
    debris settling."""
    r = rng(5100 + v)
    boom = add(lp(burst(0.4, 0.04, 5110 + v), 200) * 2.5,
               modal(0.6, [(r.uniform(60, 80), 0.08, 0.8), (r.uniform(110, 140), 0.06, 0.5)], 5111 + v, 0.002))
    bang = modal(0.8, [(r.uniform(230, 280), 0.09, 0.5), (r.uniform(410, 470), 0.08, 0.4), (r.uniform(640, 760), 0.06, 0.35),
                       (r.uniform(1050, 1250), 0.05, 0.25), (r.uniform(1700, 2000), 0.04, 0.18), (r.uniform(2900, 3300), 0.03, 0.1)],
                 5112 + v)
    crk = hp(burst(0.05, 0.004, 5113 + v), 1200) * 0.7
    cr = crumple(0.6, 600, 5114 + v, 0.08)
    deb = debris(1.6, 18, 5115 + v, 0.15, 0.3)
    x = mix(2.0, [(0.01, boom, 1.0), (0.01, bang, 1.0), (0.012, cr, 0.6), (0.03, crk, 1.0), (0.0, deb, 1.0)])
    return fade(room(x, 0.4, 0.15, 4500, 5120 + v), fout=0.1)


def impact_heavy(v):
    """Heavy crash: two big hits (front impact, then the body slams), deep
    boom, long crumple, windscreen/headlight glass shattering, long debris."""
    r = rng(5200 + v)
    boom = add(lp(burst(0.6, 0.07, 5210 + v), 150) * 3.0,
               modal(1.0, [(r.uniform(42, 55), 0.15, 1.0), (r.uniform(80, 100), 0.1, 0.6)], 5211 + v, 0.003))
    bang = modal(1.2, [(r.uniform(150, 190), 0.15, 0.6), (r.uniform(300, 360), 0.12, 0.5), (r.uniform(520, 620), 0.1, 0.4),
                       (r.uniform(880, 990), 0.08, 0.3), (r.uniform(1400, 1600), 0.06, 0.2), (r.uniform(2300, 2700), 0.05, 0.12)],
                 5212 + v)
    cr = crumple(1.2, 1100, 5213 + v, 0.18)
    second = add(lp(burst(0.3, 0.04, 5214 + v), 250) * 1.5, modal(0.5, [(r.uniform(200, 250), 0.08, 0.4)], 5215 + v))
    glass = np.zeros(secs(1.5))
    for i in range(60):
        at = r.exponential(0.2)
        if at < 1.3:
            f = r.uniform(2000, 6000)
            place(glass, modal(0.1, [(f, 0.03, 1.0), (f * 2.3, 0.015, 0.5)], 5300 + 100 * v + i) * r.uniform(0.05, 0.25) * np.exp(-at / 0.5), secs(at))
    glass = add(glass, hp(burst(0.4, 0.06, 5216 + v), 3000) * 0.35)
    deb = debris(3.0, 35, 5217 + v, 0.2, 0.5)
    x = mix(3.5, [(0.01, boom, 1.0), (0.01, bang, 1.0), (0.012, cr, 0.7), (0.03, glass, 1.0),
                  (r.uniform(0.12, 0.2), second, 1.0), (0.0, deb, 1.0)])
    return fade(room(x, 0.5, 0.18, 4000, 5220 + v), fout=0.15)


def impact_plastic_bumper(v):
    """Plastic bumper knock: a hollow, quickly-damped polypropylene shell
    (modes 250-1200 Hz) with a little flex crack."""
    r = rng(5400 + v)
    shell = modal(0.25, [(r.uniform(240, 300), 0.03, 0.8), (r.uniform(480, 560), 0.02, 0.5),
                         (r.uniform(820, 950), 0.015, 0.35), (r.uniform(1300, 1500), 0.01, 0.2)], 5410 + v)
    knock = bp(burst(0.05, 0.004, 5411 + v), 300, 4000) * 0.8
    thud = lp(burst(0.15, 0.02, 5412 + v), 200) * 0.8
    crack = hp(burst(0.03, 0.0015, 5413 + v), 2500) * (0.5 if v != 1 else 0.15)
    x = mix(0.6, [(0.01, shell, 1.0), (0.01, knock, 1.0), (0.01, thud, 1.0), (0.012 + 0.01 * v, crack, 1.0)])
    return fade(room(x, 0.25, 0.1, 5000, 5420 + v), fout=0.05)


def impact_glass_crack(v):
    """Windscreen crack (laminated, it doesn't shatter): a sharp tick, then
    the crack running as a quick series of tiny snaps, with a faint glass ring."""
    r = rng(5500 + v)
    first = add(hp(burst(0.03, 0.0008, 5510 + v), 2000) * 1.0,
                modal(0.4, [(r.uniform(1800, 2400), 0.08, 0.15), (r.uniform(4200, 5200), 0.05, 0.1)], 5511 + v))
    run = np.zeros(secs(0.5))
    t = 0.0
    for i in range(int(r.integers(10, 20))):
        t += r.exponential(0.015)
        if t > 0.4:
            break
        place(run, hp(burst(0.01, 0.0004, 5520 + 50 * v + i), 3000) * r.uniform(0.1, 0.5) * np.exp(-t / 0.2), secs(t))
    thud = lp(burst(0.1, 0.01, 5530 + v), 300) * 0.4
    x = mix(0.9, [(0.01, first, 1.0), (0.01, thud, 1.0), (0.015, run, 1.0)])
    return fade(room(x, 0.2, 0.1, 7000, 5540 + v), fout=0.05)


def metal_scrape_loop(L=secs(4.0)):
    """Body panel dragged along a barrier: noise through narrow metal
    resonances whose strengths wander, grinding grit, sparks crackle."""
    out = np.zeros(L)
    r = rng(5600)
    src = noise(L, 5601)
    for i, f in enumerate(r.uniform(400, 4500, 9)):
        q = r.uniform(25, 60)
        resp = peak_resp(L, f, f / q)
        g = np.clip(0.6 + 0.6 * smooth_noise(L, r.uniform(2, 6), 5610 + i), 0, None)
        out += norm_rms(circ_filter(src, resp)) * g * r.uniform(0.3, 1.0)
    grind = norm_rms(circ_filter(noise(L, 5602), band(L, 200, 6000))) * (1 + 0.5 * smooth_noise(L, 25, 5603)) * 0.8
    sparks = norm_rms(circ_filter(sparse(L, 400, 5604, 1.2), band(L, 4000, 14000))) * 0.25
    rumble = norm_rms(circ_lp(pink(L, 5605), 200)) * 0.4
    return check_loop("metal_scrape", out * 0.35 + grind + sparks + rumble)


# --------------------------------------------------------------------------
# Road surfaces (loops) - layered over the asphalt roll in game
# --------------------------------------------------------------------------


def gravel_loop(L=secs(8.0)):
    """Gravel: thousands of stones clicking and crunching under the tread,
    in three size classes, with the tyre rumble and stones pinging the arch."""
    r = rng(5700)
    x = np.zeros(L)
    for i, (rate, lo, hi, g) in enumerate([(2500, 2500, 9000, 0.6), (900, 700, 4000, 0.9), (250, 200, 1200, 1.0)]):
        grains = circ_filter(sparse(L, rate, 5710 + i, 1.0), band(L, lo, hi))
        swell = np.clip(1 + 0.4 * smooth_noise(L, 4, 5720 + i), 0.2, None)
        x += norm_rms(grains) * g * swell
    rumble = norm_rms(circ_lp(pink(L, 5730), 180)) * 0.8
    pings = np.zeros(L)
    for i in range(14):
        f = r.uniform(1800, 3500)
        place(pings, modal(0.08, [(f, 0.015, 1.0), (f * 2.2, 0.008, 0.4)], 5740 + i) * r.uniform(0.6, 1.5),
              int(r.integers(0, L)), wrap=True)
    return check_loop("gravel", x + rumble + pings * 3)


def grass_loop(L=secs(8.0)):
    """Grass/verge: soft blades whipping under the tyre (fluttering mid hiss),
    a soft low ground rumble and the odd twig snap."""
    r = rng(5800)
    swish = norm_rms(circ_filter(noise(L, 5801), band(L, 900, 6000)))
    flutter = np.clip(1 + 0.5 * smooth_noise(L, 22, 5802) + 0.3 * smooth_noise(L, 1.5, 5803), 0.1, None)
    rustle = norm_rms(circ_filter(sparse(L, 1500, 5804, 0.6), band(L, 1500, 8000)))
    rumble = norm_rms(circ_lp(pink(L, 5805), 150)) * 0.35
    snaps = np.zeros(L)
    for i in range(5):
        place(snaps, hp(burst(0.03, 0.002, 5810 + i), 1500) * r.uniform(0.5, 1.0), int(r.integers(0, L)), wrap=True)
    snaps = periodic(snaps, lambda s: s)
    return check_loop("grass", swish * flutter * 0.35 + rustle * 0.2 + rumble + snaps * 2.0)


def sand_loop(L=secs(8.0)):
    """Sand/beach track: a soft, muffled hiss of grains squeezing, dense
    low crunch, and deep wallowing rumble as the tyre sinks."""
    hiss = norm_rms(circ_filter(noise(L, 5900), band(L, 400, 3500))) * (1 + 0.3 * smooth_noise(L, 3, 5901))
    crunch = norm_rms(circ_filter(sparse(L, 3000, 5902, 0.7), band(L, 150, 1800)))
    rumble = norm_rms(circ_lp(pink(L, 5903), 120)) * (1 + 0.3 * smooth_noise(L, 0.8, 5904))
    return check_loop("sand", hiss * 0.3 + crunch * 0.5 + rumble * 1.0)


def brick_loop(L=None):
    """Red herringbone brick lane at ~20 km/h: each wheel drops into the
    mortar joints in a repeating herringbone spacing pattern (a lumpy
    rhythmic thrum), rear wheels repeat it a wheelbase later, over coarse
    tyre roar."""
    v = 20 / 3.6
    pattern = np.array([0.11, 0.08, 0.16, 0.08, 0.11, 0.155])  # metres between joints
    reps = 13
    dist = pattern.sum() * reps
    L = secs(dist / v)
    r = rng(6000)
    x = np.zeros(L)
    pos = np.cumsum(np.tile(pattern, reps))
    for side, delay in [(0, 0.0), (1, 2.3 / v)]:
        for i, p in enumerate(pos):
            for wheel in (0, 1):  # left and right tyre hit their joints at slightly different times
                at = int(((p / v) + delay + wheel * 0.013) * SR) % L
                hit = add(lp(burst(0.05, 0.006, 6010 + i * 4 + side * 2 + wheel), 250) * 1.5,
                          modal(0.06, [(r.uniform(90, 130), 0.012, 0.6), (r.uniform(300, 450), 0.006, 0.3)],
                                6500 + i * 4 + side * 2 + wheel),
                          bp(burst(0.02, 0.0015, 7000 + i * 4 + side * 2 + wheel), 1000, 6000) * 0.2)
                place(x, hit * r.uniform(0.7, 1.0) * (0.8 if side else 1.0), at, wrap=True)
    roar = norm_rms(tyre_roll(25, 6020, L))
    x = norm_rms(x) * 1.0 + roar * 0.5
    return check_loop("brick", x)


def rumble_strip_loop(L=secs(4.0)):
    """Rumble strip at ~80 km/h: milled grooves every 0.3 m make the tyre
    thump ~74 times a second - a loud, coarse, pitched low buzz."""
    rate = snap(80 / 3.6 / 0.3, L)
    t = t_axis(L)
    ph = (rate * t) % 1.0
    pulse = np.exp(-ph / 0.18) - np.exp(-ph / 0.02)
    pulse *= 1 + 0.1 * smooth_noise(L, 3, 6101)
    buzz = periodic(pulse, lambda s: lp(hp(s, 30), 900, 2))
    grit = norm_rms(circ_filter(noise(L, 6102), band(L, 500, 4000))) * (0.6 + 0.4 * (ph < 0.3))
    roar = norm_rms(tyre_roll(80, 6103, L))
    return check_loop("rumble_strip", norm_rms(buzz) + grit * 0.25 + roar * 0.4)


def cats_eye_loop(L=None):
    """Raised reflective road markers at ~60 km/h: front then rear tyre
    clip each one ('bd-dunk'), one marker every ~0.8 s. Events only, for
    layering over the roll loop."""
    v = 60 / 3.6
    spacing = 12.0
    count = 5
    L = secs(spacing * count / v)
    x = np.zeros(L)
    r = rng(6200)
    for i in range(count):
        for k, delay in enumerate((0.0, 2.3 / v)):
            hit = add(lp(burst(0.06, 0.008, 6210 + 2 * i + k), 300) * 1.4,
                      modal(0.08, [(r.uniform(160, 200), 0.015, 0.5), (r.uniform(700, 900), 0.006, 0.3)], 6220 + 2 * i + k),
                      bp(burst(0.02, 0.001, 6230 + 2 * i + k), 1500, 7000) * 0.25)
            place(x, hit * (1.0 if k == 0 else 0.8) * r.uniform(0.85, 1.0), secs(i * spacing / v + delay + 0.05), wrap=True)
    return check_loop("cats_eye", x)


# --------------------------------------------------------------------------
# Road one-shots
# --------------------------------------------------------------------------


def wheel_hit(seed, size=1.0):
    """A tyre striking a bump edge: low rubber thud + suspension knock."""
    r = rng(seed)
    return add(lp(burst(0.25, 0.02 * size, seed), 180) * 2.0,
               modal(0.3, [(r.uniform(55, 80), 0.04 * size, 0.6), (r.uniform(140, 200), 0.025, 0.35),
                           (r.uniform(450, 650), 0.012, 0.15)], seed + 1, 0.002))


def metal_plate(v):
    """Steel road plate rocking on its bed: each wheel gives a ringing clank
    (thick plate modes) as the plate slaps down, front then rear."""
    r = rng(6300 + v)
    parts = []
    for k, at in enumerate((0.02, 0.02 + r.uniform(0.12, 0.18))):
        clank = add(modal(0.6, [(r.uniform(180, 220), 0.06, 0.6), (r.uniform(420, 480), 0.08, 0.5), (r.uniform(760, 840), 0.07, 0.35),
                                (r.uniform(1250, 1350), 0.05, 0.25), (r.uniform(2100, 2300), 0.03, 0.12)], 6310 + 10 * v + k),
                    wheel_hit(6320 + 10 * v + k), bp(burst(0.03, 0.002, 6330 + 10 * v + k), 1000, 8000) * 0.4)
        parts.append((at, clank, 1.0 if k == 0 else 0.75))
    return fade(room(mix(1.0, parts), 0.3, 0.12, 5000, 6340 + v), fout=0.08)


def expansion_joint(v):
    """Bridge expansion joint 'ka-thunk': each axle crosses two steel edges
    ~10 ms apart (ka-), a hollow thump through the deck (-thunk); rear axle
    repeats it ~0.1 s later at 80 km/h."""
    r = rng(6400 + v)
    parts = []
    gap = r.uniform(0.09, 0.13)
    for k, at in enumerate((0.02, 0.02 + gap)):
        for e, de in enumerate((0.0, r.uniform(0.008, 0.012))):
            edge = add(bp(burst(0.03, 0.0015, 6410 + 10 * v + 2 * k + e), 800, 7000) * 0.6,
                       modal(0.1, [(r.uniform(900, 1300), 0.015, 0.25)], 6420 + 10 * v + 2 * k + e))
            parts.append((at + de, edge, 1.0 if k == 0 else 0.8))
        deck = add(wheel_hit(6430 + 10 * v + k, 1.3), modal(0.4, [(r.uniform(90, 120), 0.08, 0.4)], 6440 + 10 * v + k, 0.003))
        parts.append((at + 0.005, deck, 1.0 if k == 0 else 0.85))
    return fade(room(mix(0.9, parts), 0.4, 0.15, 4000, 6450 + v), fout=0.08)


def kerb_hit(v):
    """Kerb strike: the sidewall smacks concrete (hard low thud), rubber
    scrubs briefly, suspension bangs its stop and the body rattles."""
    r = rng(6500 + v)
    smack = add(wheel_hit(6510 + v, 1.4) * 1.3, bp(burst(0.05, 0.004, 6511 + v), 300, 5000) * 0.6)
    n = secs(0.12)
    scrub = bp(noise(n, 6512 + v), 400, 3000) * np.hanning(n) * 0.2
    stop = modal(0.3, [(r.uniform(180, 240), 0.03, 0.5), (r.uniform(520, 640), 0.02, 0.3), (r.uniform(1300, 1500), 0.01, 0.15)], 6513 + v)
    rattle = debris(0.4, 5, 6514 + v, 0.03, 0.06, high=False) * 0.7
    x = mix(1.0, [(0.01, smack, 1.0), (0.02, scrub, 1.0), (r.uniform(0.05, 0.08), stop, 1.0), (0.04, rattle, 1.0)])
    return fade(room(x, 0.3, 0.12, 4500, 6520 + v), fout=0.08)


def speed_bump():
    """Speed hump: front wheels thump up and settle (suspension creak), the
    rear axle repeats it 0.35 s later."""
    parts = []
    for k, at in enumerate((0.03, 0.38)):
        parts.append((at, wheel_hit(6600 + k, 1.6), 1.0 if k == 0 else 0.8))
        n = secs(0.25)
        tt = t_axis(n)
        f = 70 + 30 * np.sin(np.pi * tt / 0.25)
        pulses = np.diff(np.floor(np.cumsum(f / SR)), prepend=0)
        creak = (resonator(pulses, 600, 5) + resonator(pulses, 1400, 7) * 0.5) * np.hanning(n) * 0.4
        parts.append((at + 0.08, creak, 1.0))
    return fade(room(mix(1.1, parts), 0.3, 0.12, 4000, 6610), fout=0.08)


def pothole(v):
    """Pothole: the wheel drops in (soft thud), slams the far edge (hard
    hit), the damper bottoms out with a metallic knock, things rattle."""
    r = rng(6700 + v)
    size = [1.0, 1.4, 1.8][v]
    drop = lp(burst(0.15, 0.02, 6710 + v), 200) * 0.8
    edge = wheel_hit(6711 + v, size) * 1.5
    knock = modal(0.3, [(r.uniform(250, 320), 0.03, 0.5), (r.uniform(700, 900), 0.02, 0.3), (r.uniform(1800, 2200), 0.01, 0.15)], 6712 + v)
    rattle = debris(0.5, int(4 + 3 * v), 6713 + v, 0.05, 0.08, high=False) * 0.7
    gap = 0.03 + 0.015 * v
    x = mix(1.0, [(0.01, drop, 1.0), (0.01 + gap, edge, 1.0), (0.02 + gap, knock, size / 1.8), (0.03 + gap, rattle, 1.0)])
    return fade(room(x, 0.3, 0.12, 4500, 6720 + v), fout=0.08)


def wheelie_bin():
    """Wheelie bin knocked over: hollow HDPE body bonks (low, short), it
    topples and slaps the road, the lid flaps, rubbish rattles, a wheel
    scrapes."""
    r = rng(6800)
    hit = add(modal(0.4, [(150, 0.05, 0.8), (310, 0.04, 0.6), (520, 0.03, 0.4), (870, 0.02, 0.25)], 6801),
              lp(burst(0.2, 0.02, 6802), 300) * 1.5, bp(burst(0.04, 0.003, 6803), 500, 5000) * 0.5)
    slap = add(lp(burst(0.2, 0.015, 6804), 400) * 1.5, modal(0.3, [(180, 0.04, 0.6), (420, 0.03, 0.4)], 6805))
    lid = add(bp(burst(0.08, 0.006, 6806), 300, 5000) * 0.8, modal(0.2, [(260, 0.02, 0.5), (640, 0.015, 0.3)], 6807))
    junk = debris(1.2, 14, 6808, 0.0, 0.25, high=False)
    n = secs(0.6)
    scrape = bp(noise(n, 6809), 500, 4000) * np.linspace(1, 0, n) ** 2 * 0.15
    x = mix(2.6, [(0.02, hit, 1.0), (0.55, slap, 1.0), (0.62, lid, 0.8), (0.75, lid, 0.4), (0.55, junk, 1.0), (0.6, scrape, 1.0)])
    del r
    return fade(room(x, 0.35, 0.12, 4500, 6810), fout=0.1)


def traffic_cone():
    """Traffic cone: a thin hollow PVC 'bonk', then it tumbles and skitters
    along the road in quickening bounces."""
    r = rng(6900)
    bonk = add(modal(0.3, [(r.uniform(330, 360), 0.04, 0.8), (r.uniform(700, 760), 0.03, 0.5), (1250, 0.02, 0.3)], 6901),
               bp(burst(0.03, 0.002, 6902), 500, 5000) * 0.5, lp(burst(0.1, 0.01, 6903), 300) * 0.6)
    parts = [(0.02, bonk, 1.0)]
    t, gap, a = 0.3, 0.22, 0.6
    for i in range(10):
        b = add(modal(0.12, [(r.uniform(300, 420), 0.015, 0.6), (r.uniform(800, 1000), 0.01, 0.3)], 6910 + i),
                bp(burst(0.03, 0.002, 6930 + i), 800, 6000) * 0.4)
        parts.append((t, b, a))
        t += gap
        gap *= 0.78
        a *= 0.82
    n = secs(0.5)
    parts.append((t - 0.3, bp(noise(n, 6950), 800, 5000) * np.linspace(1, 0, n) ** 2 * 0.06, 1.0))
    return fade(room(mix(1.8, parts), 0.3, 0.12, 5000, 6960), fout=0.08)


def mesh_fence():
    """Chain-link fence hit: a post thump, then hundreds of wire crossings
    jingling against each other as the mesh shivers and settles."""
    r = rng(7100)
    thump = add(lp(burst(0.3, 0.03, 7101), 250) * 1.5, modal(0.4, [(95, 0.05, 0.5), (240, 0.04, 0.3)], 7102))
    jingle = np.zeros(secs(2.0))
    for i in range(260):
        at = r.exponential(0.35)
        if at > 1.8:
            continue
        f = r.uniform(2200, 7000)
        place(jingle, modal(0.04, [(f, 0.008, 1.0), (f * 1.8, 0.004, 0.5)], 7200 + i) * r.uniform(0.05, 0.3) * np.exp(-at / 0.5)
              * (1 + 0.6 * np.sin(2 * np.pi * 7 * at)), secs(at))
    wobble = lp(noise(secs(1.5), 7103), 150) * np.exp(-t_axis(secs(1.5)) / 0.3) * 0.5
    x = mix(2.2, [(0.01, thump, 1.0), (0.015, jingle, 1.0), (0.02, wobble, 1.0)])
    return fade(room(x, 0.35, 0.12, 6000, 7104), fout=0.1)


def signpost():
    """Steel signpost hit: a pipe clang with long inharmonic ring, the sign
    plate rattling as the pole wobbles (~6 Hz amplitude swing)."""
    r = rng(7300)
    n = secs(2.4)
    t = t_axis(n)
    ring = modal(2.4, [(r.uniform(430, 460), 0.5, 0.6), (r.uniform(1180, 1230), 0.35, 0.45), (r.uniform(2280, 2360), 0.22, 0.3),
                       (r.uniform(3700, 3850), 0.12, 0.15), (r.uniform(160, 180), 0.25, 0.4)], 7301)
    ring *= 1 + 0.35 * np.sin(2 * np.pi * 6 * t) * np.exp(-t / 0.8)
    hit = add(bp(burst(0.05, 0.003, 7302), 600, 8000) * 0.8, lp(burst(0.15, 0.015, 7303), 300) * 1.2)
    rattle = np.zeros(n)
    for i in range(14):
        at = i / 6.0 / 2 + 0.05
        place(rattle, modal(0.05, [(r.uniform(900, 1300), 0.01, 1.0), (r.uniform(2400, 2900), 0.006, 0.5)], 7310 + i) * 0.4 * np.exp(-at / 0.6), secs(at))
    x = mix(2.6, [(0.01, hit, 1.0), (0.01, ring, 1.0), (0.02, rattle, 1.0)])
    return fade(room(x, 0.35, 0.12, 6000, 7320), fout=0.15)


def shopping_trolley():
    """Shopping trolley hit: wire basket crash (a burst of metal rattles), it
    rolls away on rattling casters with a swivel flutter, then a kerb bump."""
    r = rng(7400)
    crash = add(lp(burst(0.2, 0.02, 7401), 300) * 1.2, bp(burst(0.1, 0.01, 7402), 1000, 9000) * 0.6)
    rattle = np.zeros(secs(0.8))
    for i in range(50):
        at = r.exponential(0.12)
        if at < 0.7:
            f = r.uniform(1200, 4500)
            place(rattle, modal(0.06, [(f, 0.012, 1.0), (f * 2.1, 0.006, 0.4)], 7410 + i) * r.uniform(0.1, 0.5), secs(at))
    roll_n = secs(2.0)
    tt = t_axis(roll_n)
    wheel_rate = 9 * np.exp(-tt / 1.5)
    clicks = np.diff(np.floor(np.cumsum(wheel_rate / SR)), prepend=0)
    casters = resonator(clicks, 1800, 6) * 2 + resonator(clicks, 700, 4)
    flutter = bp(noise(roll_n, 7403), 600, 4000) * (0.5 + 0.5 * np.sin(2 * np.pi * 23 * tt)) * np.exp(-tt / 1.0) * 0.12
    bump = add(lp(burst(0.1, 0.01, 7404), 300) * 0.8, bp(burst(0.05, 0.005, 7405), 1000, 7000) * 0.4)
    x = mix(3.0, [(0.01, crash, 1.0), (0.01, rattle, 1.0), (0.3, casters + flutter, 1.0), (2.2, bump, 0.6)])
    return fade(room(x, 0.35, 0.12, 5000, 7406), fout=0.1)


# --------------------------------------------------------------------------


LOOP = "lufs:-20"  # sustained loops share one loudness so they mix predictably


def main():
    # Tyre roll speed set: one shared gain so slow < mid < fast is preserved.
    layers = {name: tyre_roll(kmh, 3000 + i) for i, (name, kmh) in enumerate([("slow", 20), ("mid", 50), ("fast", 100)])}
    g = 10 ** ((-20 - pyloudnorm.Meter(SR).integrated_loudness(layers["mid"])) / 20)  # mid layer at -20 LUFS
    g = min(g, 10 ** (-1.5 / 20) / max(true_peak(x) for x in layers.values()))
    for name, x in layers.items():
        save(f"tyre/tyre_roll_dry_{name}", check_loop(f"roll {name}", x * g), norm="none")
    save("tyre/tyre_skid_dry", skid_squeal_loop(), norm=LOOP)
    for v in range(4):
        save(f"tyre/tyre_skid_chirp_{v + 1:02d}", skid_chirp(v))
    save("tyre/tyre_roll_wet", wet_roll_loop(), norm=LOOP)
    save("tyre/tyre_skid_wet", wet_skid_loop(), norm=LOOP)
    for v in range(3):
        save(f"tyre/tyre_splash_small_{v + 1:02d}", splash(False, v))
        save(f"tyre/tyre_splash_big_{v + 1:02d}", splash(True, v))
    for v in range(2):
        save(f"tyre/tyre_passing_spray_{v + 1:02d}", passing_spray(v))
    save("tyre/tyre_surface_gravel", gravel_loop(), norm=LOOP)
    save("tyre/tyre_surface_grass", grass_loop(), norm=LOOP)
    save("tyre/tyre_surface_sand", sand_loop(), norm=LOOP)
    save("tyre/tyre_surface_brick", brick_loop(), norm=LOOP)
    save("tyre/tyre_rumble_strip", rumble_strip_loop(), norm=LOOP)
    save("tyre/tyre_cats_eyes", cats_eye_loop())
    for v in range(3):
        save(f"tyre/tyre_metal_plate_{v + 1:02d}", metal_plate(v))
        save(f"tyre/tyre_expansion_joint_{v + 1:02d}", expansion_joint(v))
        save(f"tyre/tyre_kerb_hit_{v + 1:02d}", kerb_hit(v))
        save(f"tyre/tyre_pothole_{v + 1:02d}", pothole(v))
    save("tyre/tyre_speed_bump", speed_bump())

    for v in range(3):
        save(f"impact/impact_light_{v + 1:02d}", impact_light(v))
        save(f"impact/impact_medium_{v + 1:02d}", impact_medium(v))
        save(f"impact/impact_heavy_{v + 1:02d}", impact_heavy(v))
        save(f"impact/impact_plastic_bumper_{v + 1:02d}", impact_plastic_bumper(v))
        save(f"impact/impact_glass_crack_{v + 1:02d}", impact_glass_crack(v))
    save("impact/impact_metal_scrape", metal_scrape_loop(), norm=LOOP)
    save("impact/impact_wheelie_bin", wheelie_bin())
    save("impact/impact_traffic_cone", traffic_cone())
    save("impact/impact_mesh_fence", mesh_fence())
    save("impact/impact_signpost", signpost())
    save("impact/impact_shopping_trolley", shopping_trolley())


if __name__ == "__main__":
    main()
