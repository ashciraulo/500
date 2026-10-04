#!/usr/bin/env python3
"""Extra footstep surfaces for walking around the townhouse and its site, in
the same style as the timber/carpet/stairs/brick steps in gen_home.py:

    home_step_tile_01..05      ceramic floor tiles (kitchen, bathrooms)
    home_step_concrete_01..05  concrete slab (carport, shed, footpath)
    home_step_mulch_01..05     garden mulch and leaf litter (courtyard beds)
    home_step_gravel_01..05    loose gravel (laneway edges)

    python3 audio/tools/gen_steps.py

One step per file, mono, peak-normalised like the others.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402

import gen_home as H  # noqa: E402
from sfxlib import bp, fade, hp, lp, noise, reverb, rng, save, secs  # noqa: E402

OUT = "home"


def _grains(dur, count, seed, lo=1500, hi=9000, spread=0.6):
    """Sparse random clicks: grit, gravel stones, twigs."""
    n = secs(dur)
    g = np.zeros(n)
    r = rng(seed)
    np.add.at(g, r.integers(0, n, count), r.lognormal(0, spread, count) * r.choice([-1, 1], count))
    return bp(g, lo, hi)


def step_tile(v):
    """Ceramic tiles on a slab: a hard, bright heel click with a short glassy
    ring, almost no low end, and a small bathroom-ish reflection."""
    r = rng(20000 + v)
    heel = H.add(bp(H.burst(0.03, 0.0015, 20010 + v), 1200, 10000) * 1.0,
                 lp(H.burst(0.04, 0.003, 20011 + v), 250) * 0.35,
                 H.modal(0.08, [(r.uniform(2400, 2900), 0.012, 0.25), (r.uniform(3800, 4500), 0.008, 0.15)], 20012 + v))
    toe = bp(H.burst(0.025, 0.0012, 20013 + v), 1500, 9000) * 0.5
    x = H.mix(0.4, [(0.01, heel, 1.0), (0.01 + r.uniform(0.07, 0.1), toe, 1.0)])
    x = reverb(x, size_s=0.5, damp_hz=7000, wet=0.16, predelay_s=0.006, seed=20014 + v).mean(axis=1)
    return fade(x, fout=0.04)


def step_concrete(v):
    """Concrete slab: a dull hard heel, dusty scuff, toe tap. Drier and
    lower than tile, grittier than brick."""
    r = rng(20100 + v)
    heel = H.add(bp(H.burst(0.04, 0.002, 20110 + v), 600, 6000) * 0.8,
                 lp(H.burst(0.06, 0.005, 20111 + v), 280) * 0.7)
    n = secs(0.14)
    scuff = (bp(noise(n, 20112 + v), 1200, 6000) * np.hanning(n) * 0.08
             + _grains(0.14, 18, 20113 + v) * np.hanning(n) * 0.12)
    toe = H.add(bp(H.burst(0.03, 0.0015, 20114 + v), 800, 6000) * 0.4, lp(H.burst(0.03, 0.003, 20115 + v), 280) * 0.2)
    x = H.mix(0.4, [(0.01, heel, 1.0), (0.025, scuff, 1.0), (0.01 + r.uniform(0.08, 0.12), toe, 1.0)])
    x = reverb(x, size_s=0.35, damp_hz=5000, wet=0.07, predelay_s=0.008, seed=20116 + v).mean(axis=1)
    return fade(x, fout=0.04)


def step_mulch(v):
    """Garden mulch and dry leaves: a soft crunch spread over the footfall,
    twig snaps, no hard transient."""
    r = rng(20200 + v)
    dur = 0.32
    n = secs(dur)
    env = np.exp(-np.linspace(0, 1, n) * 5.0) * np.minimum(1, np.linspace(0, 1, n) * 25)
    crunch = (_grains(dur, 160, 20210 + v, 800, 8000, 0.8) * 0.5 + bp(noise(n, 20211 + v), 1500, 7000) * 0.05) * env
    thud = lp(H.burst(0.1, 0.02, 20212 + v), 180) * 0.6
    parts = [(0.0, thud, 1.0), (0.005, crunch, 1.0)]
    if v in (0, 3):
        snap = hp(H.burst(0.01, 0.0008, 20213 + v), 1500) * 0.8
        parts.append((r.uniform(0.04, 0.12), snap, 1.0))
    return fade(H.mix(0.4, parts), fout=0.05)


def step_gravel(v):
    """Loose gravel: stones grinding and skittering under the sole, a long
    rough crunch, heel then toe."""
    r = rng(20300 + v)
    out = []
    for i, (at, dur, k) in enumerate(((0.0, 0.18, 120), (r.uniform(0.09, 0.13), 0.14, 80))):
        n = secs(dur)
        env = np.exp(-np.linspace(0, 1, n) * 4.0) * np.minimum(1, np.linspace(0, 1, n) * 30)
        c = (_grains(dur, k, 20310 + v * 7 + i, 600, 7000, 0.9) * 0.6
             + bp(noise(n, 20320 + v * 7 + i), 500, 4000) * 0.08) * env
        out.append((at, c + lp(H.burst(dur, 0.015, 20330 + v * 7 + i), 200) * 0.3, 1.0))
    return fade(H.mix(0.4, out), fout=0.05)


def main():
    for v in range(5):
        save(f"{OUT}/home_step_tile_{v + 1:02d}", step_tile(v))
        save(f"{OUT}/home_step_concrete_{v + 1:02d}", step_concrete(v))
        save(f"{OUT}/home_step_mulch_{v + 1:02d}", step_mulch(v))
        save(f"{OUT}/home_step_gravel_{v + 1:02d}", step_gravel(v))


if __name__ == "__main__":
    main()
