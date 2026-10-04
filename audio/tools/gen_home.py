#!/usr/bin/env python3
"""Home sounds (the player's flat): footsteps, doors, kitchen, fridge,
aircon, clock, record player, bed, intercom, cat, rain on the windows, a
couple of oddities and the 'day ends' sting. Writes audio/home/*.ogg.

    python3 audio/tools/gen_home.py

Small, dry room character: a short (~0.2-0.3 s), lightly mixed reflection
tail. Point sources are mono; the rain-on-windows bed and the sting are
stereo. Uses the rain drop field from gen_weather.py and the instruments
from gen_ui.py so styles match. Seeds are fixed.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402

import gen_ui as ui  # noqa: E402
import gen_weather as wx  # noqa: E402
from sfxlib import (SR, bp, circ_filter, circ_lp, env_exp, fade, hp, lp, noise,  # noqa: E402
                    pink, place, resonator, reverb, rng, save, secs,
                    smooth_noise, softclip, t_axis)

OUT = "home"

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
    out = np.zeros(max(len(x) for x in xs))
    for x in xs:
        out[:len(x)] += x
    return out


def mix(dur, parts):
    out = np.zeros(secs(dur))
    for at, sig, g in parts:
        place(out, g * sig, secs(at))
    return out


def room(x, size=0.25, wet=0.12, damp=5000, seed=3):
    """Small, dry room: short mono reflection tail."""
    return reverb(x, size_s=size, damp_hz=damp, wet=wet, predelay_s=0.003, seed=seed).mean(axis=1)


def periodic(x, fn):
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
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = 1e-9
    return 1 / np.sqrt(1 + (lo / f) ** (2 * order)) / np.sqrt(1 + (f / hi) ** (2 * order))


def norm_rms(x):
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)


def stick_slip(dur, rate_fn, res, seed, jitter=0.3):
    """Creaks and squeaks: a pulse train (one pulse per slip) whose rate
    follows rate_fn(t), rung through resonances res=[(f, q, gain)]."""
    n = secs(dur)
    t = t_axis(n)
    pulses = np.diff(np.floor(np.cumsum(rate_fn(t) / SR)), prepend=0)
    pulses *= 1 + jitter * rng(seed).standard_normal(n)
    return sum(resonator(pulses, f, q) * g for f, q, g in res)


# --------------------------------------------------------------------------
# Footsteps (one step per file)
# --------------------------------------------------------------------------


def step_timber(v):
    """Timber floorboards over joists: heel thump that rings the hollow
    boards (~110-260 Hz), shoe-heel tap, toe roll ~90 ms later, the odd
    board creak."""
    r = rng(10000 + v)
    heel = add(lp(burst(0.15, 0.012, 10010 + v), 400) * 0.6,
               modal(0.3, [(r.uniform(105, 125), 0.05, 0.4), (r.uniform(180, 220), 0.035, 0.45),
                           (r.uniform(260, 320), 0.025, 0.35), (r.uniform(430, 520), 0.018, 0.2)], 10020 + v),
               bp(burst(0.02, 0.0012, 10030 + v), 1500, 7000) * 0.45)
    toe = add(lp(burst(0.1, 0.008, 10040 + v), 500) * 0.5, bp(burst(0.03, 0.003, 10050 + v), 800, 5000) * 0.12)
    parts = [(0.01, heel, 1.0), (0.01 + r.uniform(0.07, 0.11), toe, 1.0)]
    if v in (1, 4):
        cr = stick_slip(0.18, lambda t: 140 + 60 * np.sin(np.pi * t / 0.18), [(700, 6, 1.0), (1500, 8, 0.5)], 10060 + v)
        parts.append((0.06, cr * np.hanning(len(cr)) * 0.15, 1.0))
    return fade(room(mix(0.45, parts), 0.25, 0.12, 5000, 10070 + v), fout=0.04)


def step_carpet(v):
    """Carpet over underlay: a soft muffled thud and a fibre scuff, no ring."""
    r = rng(10100 + v)
    heel = add(lp(burst(0.12, 0.018, 10110 + v), 220) * 1.2, modal(0.15, [(r.uniform(70, 90), 0.025, 0.3)], 10120 + v))
    n = secs(0.12)
    scuff = bp(noise(n, 10130 + v), 400, 2500) * np.hanning(n) * 0.06
    toe = lp(burst(0.08, 0.012, 10140 + v), 260) * 0.5
    x = mix(0.4, [(0.01, heel, 1.0), (0.03, scuff, 1.0), (0.01 + r.uniform(0.08, 0.12), toe, 1.0)])
    return fade(room(x, 0.2, 0.08, 4000, 10150 + v), fout=0.04)


def step_stairs(v):
    """Carpeted stairs: heavier footfall onto a hollow stair box (deeper,
    longer resonance than a floor), carpet-muffled, slight tread creak."""
    r = rng(10200 + v)
    thump = add(lp(burst(0.2, 0.025, 10210 + v), 250) * 1.6,
                modal(0.35, [(r.uniform(85, 100), 0.07, 0.6), (r.uniform(150, 175), 0.05, 0.4), (r.uniform(230, 260), 0.03, 0.2)],
                      10220 + v, 0.002))
    n = secs(0.1)
    scuff = bp(noise(n, 10230 + v), 400, 2500) * np.hanning(n) * 0.05
    parts = [(0.01, thump, 1.0), (0.02, scuff, 1.0)]
    if v % 2 == 0:
        cr = stick_slip(0.2, lambda t: 110 + 50 * np.sin(np.pi * t / 0.2), [(520, 5, 1.0), (1150, 7, 0.4)], 10240 + v)
        parts.append((0.1, cr * np.hanning(len(cr)) * 0.1, 1.0))
    return fade(room(mix(0.5, parts), 0.25, 0.1, 4000, 10250 + v), fout=0.04)


def step_brick(v):
    """Brick courtyard outside: a crisp hard heel click (no hollow ring),
    a gritty sand scuff between the pavers, toe tap after."""
    r = rng(10300 + v)
    heel = add(bp(burst(0.04, 0.002, 10310 + v), 700, 8000) * 1.0, lp(burst(0.05, 0.004, 10311 + v), 300) * 0.6,
               modal(0.05, [(r.uniform(1100, 1600), 0.004, 0.15)], 10312 + v))
    n = secs(0.12)
    grit = np.zeros(n)
    k = 30
    np.add.at(grit, rng(10313 + v).integers(0, n, k), rng(10314 + v).lognormal(0, 0.6, k))
    grit = bp(grit, 2000, 9000) * np.hanning(n) * 0.25
    toe = add(bp(burst(0.03, 0.0015, 10315 + v), 900, 7000) * 0.45, lp(burst(0.03, 0.003, 10316 + v), 300) * 0.2)
    x = mix(0.4, [(0.01, heel, 1.0), (0.02, grit, 1.0), (0.01 + r.uniform(0.08, 0.12), toe, 1.0)])
    x = reverb(x, size_s=0.4, damp_hz=6000, wet=0.08, predelay_s=0.008, seed=10317 + v).mean(axis=1)
    return fade(x, fout=0.04)


# --------------------------------------------------------------------------
# Doors
# --------------------------------------------------------------------------


def front_door_open():
    """Heavy front door: lever handle turns against its spring, the big
    latch bolt clacks back, the door unsticks from the weather seal and the
    hinges give a low groan."""
    r = rng(10400)
    lever = add(stick_slip(0.15, lambda t: 300 + 0 * t, [(1800, 10, 0.3), (3200, 12, 0.2)], 10401) * np.hanning(secs(0.15)),
                bp(burst(0.05, 0.004, 10402), 1000, 6000) * 0.2)
    bolt = add(modal(0.15, [(r.uniform(1300, 1500), 0.02, 0.5), (r.uniform(2600, 2900), 0.012, 0.3), (r.uniform(480, 560), 0.025, 0.4)], 10403),
               bp(burst(0.03, 0.002, 10404), 1000, 8000) * 0.6)
    n = secs(0.2)
    unstick = bp(noise(n, 10405), 200, 2000) * np.hanning(n) ** 2 * 0.2
    groan = stick_slip(0.8, lambda t: 60 + 30 * np.sin(np.pi * t / 0.8), [(260, 5, 1.0), (620, 7, 0.5), (1300, 9, 0.2)], 10406)
    groan *= np.hanning(len(groan)) * 0.2
    x = mix(1.6, [(0.02, lever, 1.0), (0.18, bolt, 1.0), (0.3, unstick, 1.0), (0.4, groan, 1.0)])
    return fade(room(x, 0.35, 0.14, 4000, 10407), fout=0.05)


def front_door_close():
    """Heavy front door close: solid-core slab thud (~75-90 Hz, felt in the
    floor), heavy latch snaps in, the letterbox flap rattles, hallway ring."""
    r = rng(10500)
    thud = add(lp(burst(0.4, 0.035, 10501), 200) * 2.2,
               modal(0.6, [(r.uniform(75, 90), 0.08, 1.0), (r.uniform(130, 150), 0.05, 0.5), (r.uniform(210, 240), 0.035, 0.3),
                           (r.uniform(380, 420), 0.02, 0.15)], 10502, 0.002))
    latch = add(modal(0.12, [(r.uniform(1400, 1600), 0.018, 0.5), (r.uniform(2900, 3200), 0.01, 0.3)], 10503),
                bp(burst(0.03, 0.0015, 10504), 1500, 9000) * 0.7)
    flap = np.zeros(secs(0.25))
    for k in range(5):
        place(flap, modal(0.05, [(r.uniform(900, 1200), 0.01, 1.0), (r.uniform(2200, 2600), 0.006, 0.5)], 10510 + k) * 0.25 * 0.7 ** k,
              secs(k * r.uniform(0.03, 0.05)))
    x = mix(1.2, [(0.02, latch, 1.0), (0.022, thud, 1.0), (0.04, flap, 1.0)])
    return fade(room(x, 0.45, 0.18, 3500, 10511), fout=0.06)


def internal_door_open():
    """Internal hollow-core door: light handle click, latch tongue slides
    out, quick light hinge squeak."""
    r = rng(10600)
    handle = add(modal(0.08, [(r.uniform(2000, 2300), 0.01, 0.4), (r.uniform(900, 1000), 0.015, 0.3)], 10601),
                 bp(burst(0.03, 0.0015, 10602), 1500, 8000) * 0.4)
    latch = add(modal(0.08, [(r.uniform(1700, 1900), 0.012, 0.35)], 10603), bp(burst(0.03, 0.002, 10604), 1000, 7000) * 0.3)
    squeak = stick_slip(0.3, lambda t: 500 + 200 * np.sin(np.pi * t / 0.3), [(1400, 8, 1.0), (2900, 10, 0.4)], 10605)
    squeak *= np.hanning(len(squeak)) * 0.08
    swish = bp(noise(secs(0.4), 10606), 200, 1500) * np.hanning(secs(0.4)) * 0.04
    x = mix(1.0, [(0.02, handle, 1.0), (0.1, latch, 1.0), (0.2, squeak, 1.0), (0.2, swish, 1.0)])
    return fade(room(x, 0.25, 0.12, 5000, 10607), fout=0.05)


def internal_door_close():
    """Internal hollow-core door close: a lighter, hollow 'thock' (two thin
    skins over a frame ring ~150-300 Hz) and the latch clicking home."""
    r = rng(10700)
    thock = add(lp(burst(0.25, 0.015, 10701), 350) * 1.4,
                modal(0.4, [(r.uniform(140, 165), 0.04, 0.7), (r.uniform(240, 280), 0.035, 0.5), (r.uniform(420, 470), 0.025, 0.3),
                            (r.uniform(700, 780), 0.015, 0.15)], 10702))
    latch = add(modal(0.08, [(r.uniform(1800, 2100), 0.012, 0.45), (r.uniform(3300, 3600), 0.008, 0.25)], 10703),
                bp(burst(0.03, 0.0015, 10704), 1500, 9000) * 0.6)
    x = mix(0.9, [(0.02, latch, 1.0), (0.023, thock, 1.0)])
    return fade(room(x, 0.3, 0.14, 4500, 10705), fout=0.05)


def door_creak_slow():
    """Oddity: a door creaking slowly open on dry hinges (~3.5 s): the slip
    rate drifts so the pitch wanders and catches, then it bumps the wall."""
    dur = 3.5
    r = rng(10800)
    sm = smooth_noise(secs(dur), 1.5, 10801, periodic=False)
    tt = t_axis(secs(dur))

    def rate(t):
        return np.clip(90 + 70 * np.interp(t, tt, sm) + 40 * np.sin(2 * np.pi * 0.4 * t), 15, None)

    cr = stick_slip(dur, rate, [(380, 5, 1.0), (840, 7, 0.6), (1700, 9, 0.35), (2600, 10, 0.15)], 10802, 0.2)
    env = np.clip(0.5 + 0.6 * np.interp(t_axis(len(cr)), tt, smooth_noise(secs(dur), 0.8, 10803, periodic=False)), 0.05, 1)
    cr = cr * env * np.minimum(1, np.minimum(tt / 0.2, (dur - tt) / 0.3))
    bump = add(lp(burst(0.2, 0.02, 10804), 300) * 0.6, modal(0.2, [(r.uniform(150, 180), 0.03, 0.3)], 10805))
    cr = cr / (np.percentile(np.abs(cr), 99.5) + 1e-9)
    x = mix(dur + 0.6, [(0.0, cr, 1.0), (dur - 0.05, bump, 0.5)])
    return fade(room(x, 0.3, 0.14, 4500, 10806), fout=0.05)


def wall_tapping():
    """Oddity: someone tapping behind a wall - knuckle knocks heard through
    plasterboard (muffled, hollow cavity ~160 Hz), an uneven pattern."""
    r = rng(10900)
    pattern = [0.0, 0.22, 0.44, 1.2, 1.32, 2.3, 2.42, 2.54, 2.66]
    parts = []
    for i, at in enumerate(pattern):
        k = add(lp(burst(0.15, 0.01, 10910 + i), 500) * 1.0,
                modal(0.2, [(r.uniform(150, 175), 0.04, 0.6), (r.uniform(320, 360), 0.02, 0.3)], 10930 + i))
        parts.append((0.05 + at, k * r.uniform(0.6, 1.0), 1.0))
    return fade(room(lp(mix(3.3, parts), 900), 0.3, 0.15, 3000, 10950), fout=0.1)


# --------------------------------------------------------------------------
# Kitchen
# --------------------------------------------------------------------------


def kettle_boil():
    """Electric kettle (~21 s): the element ticks as it expands, a rising
    hiss/roar as vapour bubbles collapse ('singing'), which then softens
    into a rolling bubbling boil; the switch snaps off at ~19 s."""
    dur = 21.0
    n = secs(dur)
    t = t_axis(n)
    r = rng(11000)
    sing = np.clip((t - 1.5) / 8, 0, 1) ** 1.5 * np.clip((15 - t) / 3, 0.25, 1)
    sing *= np.where(t > 19.2, np.exp(-(t - 19.2) / 0.6), 1)
    roar = bp(noise(n, 11001), 300, 4000)
    roar = resonator(roar, 1400, 2) * 0.5 + roar * 0.6
    crackle = np.zeros(n)
    k = int(dur * 1500)
    idx = r.integers(0, n, k)
    np.add.at(crackle, idx, r.lognormal(0, 0.7, k) * sing[idx])
    crackle = bp(crackle, 800, 7000) * 0.5
    boil = np.clip((t - 12) / 4, 0, 1) * np.where(t > 19.2, np.exp(-(t - 19.2) / 1.2), 1)
    bubbles = np.zeros(n)
    for i in range(int(9 * 30)):
        at = r.uniform(12, dur - 0.2)
        a = boil[secs(at)]
        if a <= 0.01:
            continue
        m = secs(0.05)
        tb = t_axis(m)
        f0 = r.uniform(250, 900)
        b = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 3 * tb)) / SR) * np.exp(-tb / 0.015)
        place(bubbles, b * a * r.uniform(0.1, 0.4), secs(at))
    ticks = np.zeros(n)
    for i in range(14):
        at = r.uniform(0.3, 7)
        place(ticks, modal(0.05, [(r.uniform(2500, 4500), 0.008, 1.0)], 11010 + i) * r.uniform(0.05, 0.2), secs(at))
    rumble = lp(noise(n, 11002), 200) * (0.3 * sing + 0.5 * boil)
    switch = add(modal(0.1, [(1600, 0.015, 0.5), (3100, 0.01, 0.3), (600, 0.02, 0.4)], 11003),
                 bp(burst(0.03, 0.0015, 11004), 1000, 8000) * 0.6)
    x = roar * sing * 0.25 + crackle + bubbles + ticks + rumble * 0.5
    x = mix(dur, [(0.0, x, 1.0), (19.2, switch, 0.9)])
    return fade(room(x, 0.25, 0.1, 5000, 11005), 0.3, 0.5)


def coffee_pot():
    """Stovetop moka pot (~8 s): a quiet hiss of steam, then the coffee
    erupts into the top chamber in gurgling, spitting bursts that grow into
    the final hissy sputter."""
    dur = 8.0
    n = secs(dur)
    t = t_axis(n)
    r = rng(11100)
    hiss = bp(noise(n, 11101), 2000, 8000) * np.clip((t - 0.5) / 4, 0, 1) * 0.05
    out = hiss
    at = 1.5
    while at < dur - 0.6:
        lvl = np.clip((at - 1.5) / 5, 0.15, 1)
        m = secs(r.uniform(0.08, 0.3))
        tb = t_axis(m)
        gurgle = bp(noise(m, int(at * 1000)), 200, 2500) * (0.5 + 0.5 * np.sin(2 * np.pi * r.uniform(15, 35) * tb)) ** 2
        spit = np.zeros(m)
        np.add.at(spit, r.integers(0, m, 8), r.lognormal(0, 0.7, 8))
        burst_ = (gurgle * 0.5 + bp(spit, 1500, 8000) * 0.4) * np.hanning(m)
        out = add(out, np.concatenate([np.zeros(secs(at)), burst_ * lvl]))
        at += r.exponential(0.35 / (0.3 + lvl))
    sputter = bp(noise(secs(1.0), 11102), 600, 7000) * np.hanning(secs(1.0)) * 0.15
    out = mix(dur, [(0.0, out, 1.0), (dur - 1.4, sputter, 1.0)])
    return fade(room(out, 0.25, 0.1, 5000, 11103), 0.3, 0.4)


def mug_down(v):
    """Ceramic mug set down on a timber table: a short ceramic clack with a
    high ring, and a soft knock through the tabletop."""
    r = rng(11200 + v)
    clack = add(modal(0.2, [(r.uniform(1900, 2400), 0.03, 0.4), (r.uniform(4200, 5000), 0.015, 0.25), (r.uniform(6800, 7600), 0.008, 0.1)], 11210 + v),
                bp(burst(0.02, 0.0008, 11220 + v), 1500, 9000) * 0.5)
    knock = add(lp(burst(0.1, 0.008, 11230 + v), 400) * 0.6, modal(0.15, [(r.uniform(180, 230), 0.03, 0.3)], 11240 + v))
    second = clack * 0.3 if v == 1 else np.zeros(1)
    x = mix(0.5, [(0.01, clack, 1.0), (0.01, knock, 1.0), (0.025, second, 1.0)])
    return fade(room(x, 0.2, 0.1, 6000, 11250 + v), fout=0.04)


def fridge_open():
    """Fridge open: the magnetic seal unpeels with a soft suction 'thwuck',
    bottles in the door clink."""
    r = rng(11300)
    n = secs(0.18)
    t = t_axis(n)
    thwuck = add(lp(noise(n, 11301), 600) * np.exp(-t / 0.04) * np.minimum(1, t / 0.01) * 0.6,
                 bp(noise(n, 11302), 500, 3000) * np.exp(-t / 0.05) * 0.15)
    clinks = np.zeros(secs(0.3))
    for i in range(3):
        f = r.uniform(1800, 3000)
        place(clinks, modal(0.15, [(f, 0.04, 1.0), (f * 2.4, 0.02, 0.5)], 11310 + i) * r.uniform(0.08, 0.2), secs(i * r.uniform(0.04, 0.09)))
    x = mix(0.9, [(0.02, thwuck, 1.0), (0.15, clinks, 1.0)])
    return fade(room(x, 0.25, 0.1, 5000, 11320), fout=0.05)


def fridge_close():
    """Fridge close: a soft padded thump with a puff of air and a rattle of
    the bottles in the door."""
    r = rng(11400)
    thump = add(lp(burst(0.25, 0.02, 11401), 220) * 1.4, modal(0.3, [(r.uniform(110, 130), 0.04, 0.4), (r.uniform(260, 300), 0.02, 0.2)], 11402))
    puff = lp(burst(0.1, 0.02, 11403), 800) * 0.2
    clinks = np.zeros(secs(0.3))
    for i in range(4):
        f = r.uniform(1800, 3200)
        place(clinks, modal(0.15, [(f, 0.04, 1.0), (f * 2.4, 0.02, 0.5)], 11410 + i) * r.uniform(0.08, 0.25) * 0.75 ** i, secs(i * r.uniform(0.03, 0.06)))
    x = mix(0.9, [(0.0, puff, 1.0), (0.02, thump, 1.0), (0.04, clinks, 1.0)])
    return fade(room(x, 0.25, 0.1, 5000, 11420), fout=0.05)


# --------------------------------------------------------------------------
# Room tones / loops
# --------------------------------------------------------------------------


def fridge_hum():
    """Fridge compressor running as room tone (20 s loop): 50 Hz mains motor
    hum with harmonics (100 Hz strongest), a little beating, the condenser
    fan whir, and the quiet room."""
    L = secs(20.0)
    T = L / SR
    t = t_axis(L)
    hum = np.zeros(L)
    for k, a in [(1, 0.4), (2, 1.0), (3, 0.3), (4, 0.25), (6, 0.1), (8, 0.05)]:
        f = round(50 * k * T) / T
        hum += a * np.sin(2 * np.pi * f * t + k)
    beat = 1 + 0.15 * np.sin(2 * np.pi * round(0.35 * T) / T * t)
    fan = norm_rms(circ_filter(noise(L, 11501), band(L, 150, 1500))) * (1 + 0.05 * smooth_noise(L, 1, 11502))
    roomtone = norm_rms(circ_lp(pink(L, 11503), 600))
    x = norm_rms(hum * beat) * 0.5 + fan * 0.2 + roomtone * 0.12
    return check_loop("fridge_hum", x)


def aircon():
    """Split-system aircon indoor unit (20 s loop): cross-flow fan whoosh
    (broad, soft), faint blade tone ~110 Hz, louvre air hiss."""
    L = secs(20.0)
    T = L / SR
    t = t_axis(L)
    whoosh = norm_rms(circ_filter(pink(L, 11601), band(L, 80, 2500))) * (1 + 0.04 * smooth_noise(L, 0.5, 11602))
    hiss = norm_rms(circ_filter(noise(L, 11603), band(L, 2000, 8000)))
    blade = np.sin(2 * np.pi * round(112 * T) / T * t) + 0.3 * np.sin(2 * np.pi * round(224 * T) / T * t)
    x = whoosh * 0.6 + hiss * 0.08 + blade * 0.03
    return check_loop("aircon", x)


def clock_loop():
    """Mechanical wall clock (4 s loop, 1 tick/s): escapement tick and tock
    alternate (slightly different pitch), each ringing the wooden case."""
    L = secs(4.0)
    x = np.zeros(L)
    r = rng(11700)
    for i in range(4):
        f = 2600 if i % 2 == 0 else 2250
        tk = add(modal(0.1, [(f * r.uniform(0.99, 1.01), 0.006, 0.6), (f * 1.9, 0.004, 0.3), (r.uniform(700, 800), 0.02, 0.3)], 11710 + i),
                 bp(burst(0.02, 0.0006, 11720 + i), 1500, 9000) * 0.5)
        place(x, tk * r.uniform(0.9, 1.0), secs(i * 1.0), wrap=True)
    x = periodic(x, lambda s: room(s, 0.2, 0.1, 6000, 11730))
    return check_loop("clock", x)


def vinyl_crackle(L, seed, rev_s=1.8):
    """Vinyl surface: fine crackle, occasional pops, groove hiss, and a
    swish once per revolution (33 1/3 rpm = 1.8 s) - periodic."""
    r = rng(seed)
    t = t_axis(L)
    fine = np.zeros(L)
    k = int(L / SR * 120)
    np.add.at(fine, r.integers(0, L, k), r.lognormal(0, 0.6, k) * r.choice([-1, 1], k))
    fine = circ_filter(fine, band(L, 1500, 9000))
    pops = np.zeros(L)
    for i in range(int(L / SR * 1.2)):
        place(pops, lp(burst(0.01, 0.0008, seed + 10 + i), 3000) * r.uniform(0.5, 1.5), int(r.integers(0, L)), wrap=True)
    hiss = norm_rms(circ_filter(noise(L, seed + 1), band(L, 2000, 10000)))
    rev = 1 + 0.4 * np.sin(2 * np.pi * t / rev_s) ** 8
    rumble = norm_rms(circ_filter(noise(L, seed + 2), band(L, 15, 60)))
    return fine * 0.6 * rev + periodic(pops, lambda s: s) * 0.6 + hiss * 0.02 * rev + rumble * 0.006


def record_crackle_loop():
    """Record playing between songs: just the surface noise (7.2 s = 4 revs)."""
    L = secs(7.2)
    return check_loop("vinyl", vinyl_crackle(L, 11800))


def runout_groove_loop():
    """Locked run-out groove at the end of a side: the stylus swings across
    the lead-out every revolution - a soft 'thump-swish' every 1.8 s - over
    surface crackle."""
    L = secs(7.2)
    x = vinyl_crackle(L, 11900)
    for i in range(4):
        m = secs(0.35)
        tm = t_axis(m)
        thump = lp(noise(m, 11910 + i), 120) * np.exp(-tm / 0.05) * 1.5 + bp(noise(m, 11920 + i), 500, 4000) * np.sin(np.pi * tm / 0.35) ** 2 * 0.12
        place(x, thump, secs(i * 1.8 + 0.3), wrap=True)
    return check_loop("runout", x)


def needle_drop():
    """Needle drop: the tonearm lands (amplified low thump and a scrape as
    the stylus finds the groove), then the lead-in crackle starts."""
    m = secs(0.15)
    tm = t_axis(m)
    land = lp(noise(m, 12001), 150) * np.exp(-tm / 0.04) * 2.0 + np.sin(2 * np.pi * 45 * tm) * np.exp(-tm / 0.06) * 0.6
    n = secs(0.25)
    scrape = bp(noise(n, 12002), 800, 6000) * np.exp(-t_axis(n) / 0.08) * 0.25
    crack = vinyl_crackle(secs(2.5), 12003)
    crack *= np.minimum(1, t_axis(len(crack)) / 0.2)
    x = mix(2.8, [(0.02, land, 1.0), (0.025, scrape, 1.0), (0.1, crack, 1.0)])
    return fade(x, fout=0.4)


def intercom_buzz():
    """Door intercom buzzer: a harsh electromagnetic 'bzzzt' (~100 Hz
    clapper hammering a plate) through a tiny speaker grille."""
    dur = 1.2
    n = secs(dur)
    t = t_axis(n)
    ph = (100 * t) % 1.0
    clap = np.exp(-ph / 0.08) - 0.3
    x = add(resonator(clap, 900, 3) * 2 + resonator(clap, 2400, 5) + clap * 0.3, bp(noise(n, 12101), 2000, 6000) * 0.05)
    x = softclip(x / np.std(x) * 0.5, 2.5)
    x = bp(x, 300, 5000) * np.minimum(1, np.minimum(t / 0.01, (dur - t) / 0.02))
    return fade(room(np.concatenate([x, np.zeros(secs(0.2))]), 0.2, 0.1, 5000, 12102), fout=0.03)


def intercom_static():
    """Intercom line open (6 s loop): telephone-band hiss (300-3400 Hz),
    a faint 50 Hz mains buzz and the odd crackle."""
    L = secs(6.0)
    T = L / SR
    t = t_axis(L)
    hiss = norm_rms(circ_filter(noise(L, 12201), band(L, 300, 3400, 3))) * (1 + 0.15 * smooth_noise(L, 2, 12202))
    buzz = sum(np.sin(2 * np.pi * round(50 * k * T) / T * t) / k for k in (1, 2, 3, 5, 7)) * 0.08
    crk = np.zeros(L)
    r = rng(12203)
    np.add.at(crk, r.integers(0, L, 25), r.lognormal(0, 0.8, 25))
    crk = circ_filter(crk, band(L, 500, 4000)) * 3
    return check_loop("intercom_static", hiss * 0.3 + buzz + crk)


def intercom_handset():
    """Intercom handset lifted: plastic handset knocks out of its cradle,
    the hook switch clicks, the line opens with a short burst of hiss."""
    r = rng(12300)
    knock = add(modal(0.12, [(r.uniform(700, 900), 0.015, 0.5), (r.uniform(1700, 1900), 0.01, 0.3)], 12301),
                bp(burst(0.04, 0.003, 12302), 500, 6000) * 0.5)
    hook = add(modal(0.06, [(3200, 0.006, 0.3)], 12303), hp(burst(0.02, 0.0008, 12304), 2000) * 0.4)
    n = secs(0.6)
    line = bp(noise(n, 12305), 300, 3400) * np.minimum(1, t_axis(n) / 0.02) * np.exp(-t_axis(n) / 0.3) * 0.08
    x = mix(1.0, [(0.02, knock, 1.0), (0.09, hook, 1.0), (0.1, line, 1.0)])
    return fade(room(x, 0.2, 0.1, 5000, 12306), fout=0.05)


def rain_windows():
    """Rain heard indoors (40 s stereo loop): drops tapping the window
    glass and drumming on the balcony's metal roof, both muffled by the
    walls, plus the soft outside wash."""
    L = secs(40.0)
    swell = np.clip(1 + 0.2 * smooth_noise(L, 0.08, 12401), 0.3, None)
    glass = wx.drop_field(L, 120, wx.kernels_windscreen(12402, 8), 12403, width=0.9, mod=swell)
    glass = circ_filter(glass, band(L, 300, 3500))
    roof = wx.drop_field(L, 500, wx.kernels_metal_roof(12404, 8), 12405, width=0.6, mod=swell)
    roof = circ_filter(roof, band(L, 80, 2000))
    wash = wx.stereo_bed(L, 150, 2500, 12406, 0.4) * swell[:, None]
    x = norm_rms(glass) * 0.5 + norm_rms(roof) * 0.7 + norm_rms(wash) * 0.35
    # the loop is periodic, so rotating it is free: put the join at a quiet moment
    m = x.mean(axis=1)
    e = np.convolve(m ** 2, np.ones(480), mode="same")
    x = np.roll(x, -int(np.argmin(e)), axis=0)
    return check_loop("rain_windows", x)


# --------------------------------------------------------------------------
# Bed, garden, cat
# --------------------------------------------------------------------------


def rustle(dur, seed, bright=1.0, crinkle=300):
    """Fabric/leaf rustle: band noise with fast fluttering level plus a
    scatter of crinkle clicks."""
    n = secs(dur)
    r = rng(seed)
    x = bp(noise(n, seed), 600 * bright, 6000 * bright)
    x *= np.clip(0.6 + 0.6 * smooth_noise(n, 12, seed + 1, periodic=False), 0, None)
    c = np.zeros(n)
    k = int(crinkle * dur)
    np.add.at(c, r.integers(0, n, k), r.lognormal(0, 0.7, k) * r.choice([-1, 1], k))
    return x * 0.15 + bp(c, 1500 * bright, 9000) * 0.3


def bed_get_in():
    """Getting into bed (~3 s): weight onto the mattress (soft thump and
    a squeak of the springs), sheets dragged, duvet settles."""
    r = rng(12500)
    thump = lp(burst(0.3, 0.05, 12501), 180) * 1.2
    springs = stick_slip(0.4, lambda t: 40 + 30 * np.sin(np.pi * t / 0.4), [(900, 12, 0.6), (1900, 14, 0.4), (3100, 16, 0.2)], 12502)
    springs *= np.hanning(len(springs)) * 0.25
    sheets = rustle(1.6, 12503, 0.8, 120) * np.hanning(secs(1.6))
    duvet = lp(burst(0.3, 0.06, 12504), 500) * 0.4
    x = mix(3.0, [(0.05, thump, 1.0), (0.08, springs, 1.0), (0.4, sheets, 1.0), (2.0, duvet, 1.0)])
    del r
    return fade(room(x, 0.2, 0.08, 4000, 12505), fout=0.1)


def sheets_rustle():
    """Sheets rustle (~2 s): turning over in bed."""
    x = rustle(2.0, 12600, 0.8, 100) * np.hanning(secs(2.0)) ** 0.7
    x = add(x, lp(burst(0.4, 0.08, 12601), 300) * 0.3)
    return fade(room(x, 0.2, 0.08, 4000, 12602), 0.02, 0.1)


def leaves_brush(v):
    """Brushing past a shrub / leaves: crisp dry-leaf rustle swelling and
    fading, twig ticks."""
    dur = [1.6, 2.2][v]
    x = rustle(dur, 12700 + v, 1.0, 600) * np.hanning(secs(dur)) ** 0.8
    return fade(room(x, 0.25, 0.06, 6000, 12710 + v), 0.02, 0.1)


def watering_can():
    """Watering can (~4.5 s): the rose sprinkles on leaves and soil (dense
    small drops) while water gurgles inside the can as it tips."""
    dur = 4.5
    n = secs(dur)
    t = t_axis(n)
    env = np.minimum(1, t / 0.3) * np.minimum(1, (dur - t) / 0.6)
    r = rng(12800)
    drops = np.zeros(n)
    k = int(dur * 1200)
    np.add.at(drops, r.integers(0, n, k), r.lognormal(0, 0.6, k))
    drops = bp(drops, 600, 6000) * 0.3 + bp(noise(n, 12801), 800, 5000) * 0.06
    inside = bp(noise(n, 12802), 150, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(5 + 3 * smooth_noise(n, 1, 12803, periodic=False)) / SR)) ** 2
    x = (drops + resonator(inside, 380, 4) * 0.4) * env
    return fade(room(x, 0.3, 0.05, 6000, 12804), fout=0.2)


def cat_voice(dur, f0_curve, f1_curve, f2_curve, seed, breath=0.08):
    """Cat vocal tract: harmonics of a time-varying f0, each weighted by two
    moving formants (mouth opening m-e-o-w), plus breath noise."""
    n = secs(dur)
    t = t_axis(n)
    f0 = f0_curve(t)
    ph = 2 * np.pi * np.cumsum(f0) / SR
    F1, F2 = f1_curve(t), f2_curve(t)
    x = np.zeros(n)
    for k in range(1, 24):
        fk = k * f0
        a = np.exp(-0.5 * ((fk - F1) / 220) ** 2) + 0.6 * np.exp(-0.5 * ((fk - F2) / 350) ** 2) + 0.03
        x += a * np.sin(k * ph) / k ** 0.3 * (fk < 16000)
    x += bp(noise(n, seed), 1500, 6000) * breath
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.6
    return x * env


def cat_meow(v):
    """Meow: f0 rises then falls (~500-800 Hz), mouth opens (F1 up to
    ~1 kHz) and closes at the end ('-ow')."""
    r = rng(12900 + v)
    dur = [0.75, 0.55, 1.0][v]
    base = r.uniform(480, 600)
    peak = base * r.uniform(1.25, 1.5)

    def f0(t):
        u = t / dur
        return base + (peak - base) * np.sin(np.pi * np.clip(u * 1.1, 0, 1)) + 15 * np.sin(2 * np.pi * 6 * t)

    def f1(t):
        u = t / dur
        return 500 + 600 * np.sin(np.pi * np.clip(u * 1.2, 0, 1)) ** 1.5

    def f2(t):
        u = t / dur
        return 1600 + 900 * np.sin(np.pi * np.clip(u * 1.1, 0, 1)) - 600 * np.clip(u - 0.7, 0, 1)

    x = cat_voice(dur, f0, f1, f2, 12910 + v)
    x = np.concatenate([np.zeros(secs(0.02)), x, np.zeros(secs(0.2))])
    return fade(room(x, 0.25, 0.1, 5000, 12920 + v), fout=0.05)


def cat_purr_loop():
    """Purr (8 s loop): ~26 laryngeal pulses/s, louder on the out-breath,
    quieter and slightly faster on the in-breath; breath cycle ~2 s."""
    L = secs(8.0)
    x = np.zeros(L)
    r = rng(13000)
    t = 0.0
    while t < 8.0 - 1e-6:
        cyc = (t % 2.0) / 2.0
        out_breath = cyc < 0.6
        rate = 25 if out_breath else 28
        amp = (np.sin(np.pi * cyc / 0.6) if out_breath else 0.5 * np.sin(np.pi * (cyc - 0.6) / 0.4)) ** 0.5
        m = secs(0.03)
        p = lp(noise(m, int(t * 1000) + 13001), 600 if out_breath else 900) * np.hanning(m) * amp * r.uniform(0.8, 1.0)
        place(x, p, secs(t), wrap=True)
        t += 1 / rate
    x = periodic(x, lambda s: lp(hp(s, 30), 1500))
    return check_loop("purr", x)


def cat_food_bowl():
    """Cat food: dry kibble poured into a ceramic bowl (a stream of small
    hard clicks, each ringing the bowl a little), then the bowl set down."""
    dur = 2.2
    n = secs(dur)
    r = rng(13100)
    x = np.zeros(n)
    for i in range(160):
        at = r.uniform(0.05, 1.3) if r.random() < 0.85 else r.uniform(1.3, 1.6)
        f = r.uniform(2500, 6000)
        k = add(hp(burst(0.01, 0.0005, 13110 + i), 1500) * 0.5, modal(0.04, [(f, 0.004, 0.2)], 13400 + i))
        place(x, k * r.uniform(0.1, 0.6), secs(at))
    bowl_ring = resonator(x, 1450, 15) * 0.6 + resonator(x, 3300, 20) * 0.4
    x = x + bowl_ring
    down = add(modal(0.3, [(1450, 0.05, 0.4), (3300, 0.03, 0.2), (620, 0.03, 0.3)], 13101), lp(burst(0.1, 0.01, 13102), 400) * 0.6)
    x = mix(dur, [(0.0, x, 1.0), (1.8, down, 1.0)])
    return fade(room(x, 0.2, 0.1, 6000, 13103), fout=0.1)


def cat_steps(v):
    """Little cat footsteps on timber: soft pad pats (a tiny low thump with
    a whisper of floorboard ring) and occasional claw ticks; 4 pats."""
    r = rng(13200 + v)
    parts = []
    t = 0.02
    for i in range(4):
        pat = add(lp(burst(0.06, 0.006, 13210 + 10 * v + i), 350) * 0.6,
                  modal(0.1, [(r.uniform(160, 220), 0.02, 0.15)], 13250 + 10 * v + i))
        parts.append((t, pat * r.uniform(0.6, 1.0), 1.0))
        if r.random() < 0.4:
            parts.append((t + 0.01, hp(burst(0.01, 0.0005, 13290 + 10 * v + i), 3000) * 0.15, 1.0))
        t += r.uniform(0.12, 0.22)
    return fade(room(mix(t + 0.3, parts), 0.2, 0.08, 5000, 13299 + v), fout=0.05)


def day_ends():
    """'Day ends' sting (~4 s): a gentle descending vibe line over a soft
    Rhodes D major 7 to G major 7 - like a lullaby ending - warm tape."""
    ev = []
    mel = [ui.A5, ui.Fs5, ui.E5, ui.D5]
    for i, m in enumerate(mel):
        ev.append((0.32 * i, ui.vibe(ui.hz(m), 0.3 if i < 3 else 1.6, 0.7, 13300 + i), 0.45, 0.2 - 0.13 * i))
    ev += ui.chord(0.0, [ui.D4, ui.Fs4, ui.A4, ui.Cs5], ui.epiano, 0.9, 0.5, 0.15, strum=0.03, seed=13310)
    ev += ui.chord(0.96, [ui.D4, ui.G4, ui.B4, ui.Fs5 - 12], ui.epiano, 0.6, 0.45, 0.14, strum=0.03, seed=13320)
    ev += ui.chord(1.6, [ui.D4, ui.Fs4, ui.A4, ui.E5], ui.epiano, 1.8, 0.45, 0.15, strum=0.04, seed=13330)
    ev.append((0.0, ui.bass(ui.hz(ui.D3), 0.9, 0.7), 0.3, 0.0))
    ev.append((0.96, ui.bass(ui.hz(ui.G2), 0.6, 0.7), 0.3, 0.0))
    ev.append((1.6, ui.bass(ui.hz(ui.D2 + 12), 1.8, 0.7), 0.3, 0.0))
    return ui.finish(ui.render(3.8, ev), 13340, wet=0.25, size=1.6, wow=2.0, tail=0.8)


# --------------------------------------------------------------------------


def main():
    for v in range(5):
        save(f"{OUT}/home_step_timber_{v + 1:02d}", step_timber(v))
        save(f"{OUT}/home_step_carpet_{v + 1:02d}", step_carpet(v))
        save(f"{OUT}/home_step_stairs_{v + 1:02d}", step_stairs(v))
        save(f"{OUT}/home_step_brick_{v + 1:02d}", step_brick(v))
    save(f"{OUT}/home_front_door_open", front_door_open())
    save(f"{OUT}/home_front_door_close", front_door_close())
    save(f"{OUT}/home_internal_door_open", internal_door_open())
    save(f"{OUT}/home_internal_door_close", internal_door_close())
    save(f"{OUT}/home_fridge_hum", fridge_hum(), norm="amb")
    save(f"{OUT}/home_fridge_open", fridge_open())
    save(f"{OUT}/home_fridge_close", fridge_close())
    save(f"{OUT}/home_aircon", aircon(), norm="amb")
    save(f"{OUT}/home_clock_tick", clock_loop())
    save(f"{OUT}/home_kettle_boil", kettle_boil())
    save(f"{OUT}/home_coffee_pot", coffee_pot())
    for v in range(3):
        save(f"{OUT}/home_mug_down_{v + 1:02d}", mug_down(v))
    save(f"{OUT}/home_record_needle_drop", needle_drop())
    save(f"{OUT}/home_record_crackle", record_crackle_loop(), norm="amb")
    save(f"{OUT}/home_record_runout", runout_groove_loop(), norm="amb")
    save(f"{OUT}/home_bed_get_in", bed_get_in())
    save(f"{OUT}/home_bed_sheets_rustle", sheets_rustle())
    save(f"{OUT}/home_intercom_buzz", intercom_buzz())
    save(f"{OUT}/home_intercom_static", intercom_static(), norm="amb")
    save(f"{OUT}/home_intercom_handset", intercom_handset())
    save(f"{OUT}/home_rain_windows", rain_windows(), norm="amb")
    save(f"{OUT}/home_watering_can", watering_can())
    for v in range(2):
        save(f"{OUT}/home_leaves_brush_{v + 1:02d}", leaves_brush(v))
    for v in range(3):
        save(f"{OUT}/home_cat_meow_{v + 1:02d}", cat_meow(v))
    save(f"{OUT}/home_cat_purr", cat_purr_loop(), norm="amb")
    save(f"{OUT}/home_cat_food_bowl", cat_food_bowl())
    for v in range(4):
        save(f"{OUT}/home_cat_steps_{v + 1:02d}", cat_steps(v))
    save(f"{OUT}/home_odd_wall_tapping", wall_tapping())
    save(f"{OUT}/home_odd_door_creak", door_creak_slow())
    save(f"{OUT}/home_day_ends", day_ends())


if __name__ == "__main__":
    main()
