#!/usr/bin/env python3
"""Garage, servo and car-wash sounds: room tone, tools, compressor, spray
paint, parts, fuel pump, EV charger, servo door chime, car wash, camera
shutter and photo-album page. Writes audio/garage/*.ogg.

    python3 audio/tools/gen_garage.py

Point sources are mono; the garage room tone is a stereo bed. Loops are
built periodically (whole-cycle frequencies, wrapped events, FFT filtering).
Seeds are fixed.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402

from sfxlib import (SR, bp, circ_filter, env_exp, fade, hp, lp, noise,  # noqa: E402
                    pink, place, reverb, rng, save, secs,
                    smooth_noise, softclip, t_axis)

OUT = "garage"

# --------------------------------------------------------------------------
# Helpers (same family as gen_car.py)
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


def garage(x, size=0.7, wet=0.18, damp=4500, seed=3):
    """Concrete-and-tin garage: a medium, slightly bright reflection tail."""
    return reverb(x, size_s=size, damp_hz=damp, wet=wet, predelay_s=0.008, seed=seed).mean(axis=1)


def periodic(x, fn):
    n = len(x)
    return fn(np.concatenate([x, x, x]))[n:2 * n]


def check_loop(name, x):
    """Seam test: the wrap-around jump must be no bigger than the ordinary
    sample steps (global 99.9th percentile, or the largest step near the join)."""
    m = x.mean(axis=1) if x.ndim == 2 else x
    d = np.abs(np.diff(m))
    local = np.concatenate([d[:200], d[-200:]]).max()
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


def snapf(f, L):
    T = L / SR
    return max(1, round(f * T)) / T


def steel_tick(seed, amp=1.0, f=None):
    """Small hardened-steel click (pawl, detent, latch)."""
    r = rng(seed)
    f = f or r.uniform(3500, 5000)
    return amp * add(modal(0.04, [(f, 0.006, 0.4), (f * 1.7, 0.004, 0.2)], seed), hp(burst(0.015, 0.0006, seed + 1), 2000) * 0.6)


# --------------------------------------------------------------------------
# Room and machines (loops)
# --------------------------------------------------------------------------


def room_tone():
    """Garage room tone (30 s stereo loop): fluorescent tube buzz (100 Hz
    and its harmonics from 50 Hz mains, with a gritty ballast edge), distant
    traffic rumble through the roller door, a faint tin-roof tick or two."""
    L = secs(30.0)
    t = t_axis(L)
    buzz = sum(np.sin(2 * np.pi * snapf(100 * k, L) * t + k) / k ** 0.8 for k in range(1, 12))
    buzz = softclip(buzz * 0.5, 2.0)
    traffic = np.stack([circ_filter(pink(L, 14001 + c), band(L, 30, 400)) for c in range(2)], axis=1)
    traffic *= np.clip(1 + 0.4 * smooth_noise(L, 0.06, 14003), 0.2, None)[:, None]
    air = np.stack([circ_filter(noise(L, 14004 + c), band(L, 500, 6000)) for c in range(2)], axis=1)
    ticks = np.zeros(L)
    r = rng(14006)
    for i in range(3):
        place(ticks, modal(0.2, [(r.uniform(900, 1400), 0.03, 1.0), (r.uniform(2400, 3000), 0.02, 0.5)], 14010 + i) * 0.3,
              int(r.integers(0, L)), wrap=True)
    ticks = periodic(ticks, lambda s: reverb(s, 0.8, 4000, 0.3, 0.01, 14020).mean(axis=1))
    x = (norm_rms(traffic) * 0.5 + norm_rms(air) * 0.08
         + np.stack([buzz, np.roll(buzz, 37)], axis=1) / np.std(buzz) * 0.07 + ticks[:, None] * 2)
    return check_loop("garage_room", x)


def compressor_loop():
    """Piston air compressor (6 s loop): 1450 rpm motor hum, a chugging
    thump on each piston stroke (~24/s, alternate strokes weaker), con-rod
    clatter, intake valve chatter and the hiss of air."""
    L = secs(6.0)
    t = t_axis(L)
    stroke = snapf(24.0, L)
    ph = (stroke * t) % 1.0
    odd = np.floor(stroke * t).astype(int) % 2
    chug = (np.exp(-ph / 0.12) - np.exp(-ph / 0.02)) * (1.0 - 0.35 * odd)
    chug = periodic(chug, lambda s: lp(hp(s, 25), 600))
    hum = sum(np.sin(2 * np.pi * snapf(f, L) * t) * a for f, a in [(50, 0.3), (100, 0.6), (150, 0.2), (300, 0.1)])
    valve = norm_rms(circ_filter(noise(L, 14101), band(L, 1500, 6000))) * np.exp(-((ph - 0.5) % 1.0) / 0.05)
    hiss = norm_rms(circ_filter(noise(L, 14102), band(L, 2500, 10000)))
    clatter = norm_rms(circ_filter(noise(L, 14103), band(L, 400, 3000))) * np.exp(-ph / 0.06) * (1.0 - 0.35 * odd)
    x = norm_rms(chug) * 0.5 + hum * 0.3 + valve * 0.35 + clatter * 0.45 + hiss * 0.12
    return check_loop("compressor", x)


def fuel_flow_loop():
    """Fuel flowing (8 s loop): turbulent liquid gush into the filler neck
    with a gurgle as air escapes, plus the dispenser pump motor whine."""
    L = secs(8.0)
    t = t_axis(L)
    gush = norm_rms(circ_filter(noise(L, 14201), band(L, 250, 4000))) * (1 + 0.15 * smooth_noise(L, 6, 14202))
    gurgle_env = np.clip(smooth_noise(L, 7, 14203), 0, None) ** 2
    gurgle = norm_rms(circ_filter(noise(L, 14204), np.exp(-0.5 * ((np.fft.rfftfreq(L, 1 / SR) - 450) / 120) ** 2)))
    motor = sum(np.sin(2 * np.pi * snapf(f, L) * t) * a for f, a in [(98, 0.5), (196, 0.3), (1180, 0.08)])
    x = gush * 0.5 + gurgle * gurgle_env * 0.35 + motor * 0.12
    return check_loop("fuel_flow", x)


def ev_hum_loop():
    """EV charger running (10 s loop): transformer/inductor hum (100 Hz +
    harmonics), a thin high coil whine, a small cooling fan."""
    L = secs(10.0)
    t = t_axis(L)
    hum = sum(np.sin(2 * np.pi * snapf(100 * k, L) * t + k) / k for k in (1, 2, 3, 4, 6))
    whine = np.sin(2 * np.pi * snapf(9600, L) * t) * 0.015
    fan = norm_rms(circ_filter(pink(L, 14301), band(L, 200, 3000))) * 0.15
    blade = np.sin(2 * np.pi * snapf(230, L) * t) * 0.03
    return check_loop("ev_hum", norm_rms(hum) * 0.3 + whine + fan + blade)


def wash_hose_loop():
    """Car-wash pressure hose (8 s loop): the jet's hard hiss at the nozzle
    and water drumming on the panel (low thrum + splatter), sweep moving."""
    L = secs(8.0)
    sweep = np.clip(1 + 0.3 * smooth_noise(L, 0.5, 14401), 0.3, None)
    jet = norm_rms(circ_filter(noise(L, 14402), band(L, 2000, 12000)))
    drum = norm_rms(circ_filter(pink(L, 14403), band(L, 80, 600))) * sweep
    splat = norm_rms(circ_filter(noise(L, 14404), band(L, 600, 5000))) * np.clip(1 + 0.5 * smooth_noise(L, 12, 14405), 0, None)
    return check_loop("wash_hose", jet * 0.4 + drum * 0.5 + splat * 0.35)


def wash_brushes_loop():
    """Car-wash rotating brushes (8 s loop): cloth strips slapping the car
    once per strip pass (brush turns ~2 rev/s, 12 strips), wet swish, and
    the gear motor hum."""
    L = secs(8.0)
    t = t_axis(L)
    x = np.zeros(L)
    rate = snapf(24.0, L)
    r = rng(14500)
    for i in range(int(round(rate * 8.0))):
        m = secs(0.06)
        slap = bp(noise(m, 14510 + i), 300, 4000) * np.exp(-t_axis(m) / 0.012) * r.uniform(0.5, 1.0)
        place(x, slap, int(i / rate * SR), wrap=True)
    x = periodic(x, lambda s: s)
    swish = norm_rms(circ_filter(noise(L, 14501), band(L, 800, 6000))) * (0.6 + 0.4 * np.sin(2 * np.pi * snapf(2.0, L) * t) ** 2)
    motor = sum(np.sin(2 * np.pi * snapf(f, L) * t) * a for f, a in [(100, 0.5), (300, 0.2), (720, 0.1)])
    return check_loop("wash_brushes", norm_rms(x) * 0.6 + swish * 0.3 + motor * 0.12)


# --------------------------------------------------------------------------
# One-shots
# --------------------------------------------------------------------------


def ratchet():
    """Socket ratchet: three back-swings, each a fast run of pawl clicks
    over the gear teeth (~70 per second), forward strokes silent apart from
    a slight creak."""
    parts = []
    t = 0.03
    for s in range(3):
        n_clicks = 9 + s
        for k in range(n_clicks):
            parts.append((t + k / 70.0, steel_tick(14600 + 20 * s + k, 0.8 if k else 1.0), 1.0))
        t += n_clicks / 70.0 + 0.35
    return fade(garage(mix(t + 0.3, parts), 0.6, 0.12), fout=0.05)


def impact_wrench():
    """Pneumatic impact wrench: air motor spins up (whine + exhaust hiss),
    the hammer hits ~25 times a second ('brrrap') with a ringing socket,
    then spins down."""
    dur = 1.8
    n = secs(dur)
    t = t_axis(n)
    on = np.clip(t / 0.08, 0, 1) * np.clip((1.5 - t) / 0.1, 0, 1)
    spin = 1 - np.exp(-t / 0.1)
    f = 140 * spin * np.where(t > 1.5, np.exp(-(t - 1.5) / 0.15), 1)
    ph = 2 * np.pi * np.cumsum(f) / SR
    whine = (np.sin(ph) * 0.5 + np.sin(6 * ph) * 0.3 + np.sin(12 * ph) * 0.15)
    hiss = bp(noise(n, 14701), 1500, 9000) * 0.3 * on
    hammer = np.zeros(n)
    r = rng(14702)
    k = 0
    tt = 0.25
    while tt < 1.45:
        hit = add(modal(0.04, [(r.uniform(2800, 3200), 0.008, 0.6), (r.uniform(5200, 5800), 0.005, 0.3), (900, 0.006, 0.4)], 14710 + k),
                  bp(burst(0.02, 0.001, 14800 + k), 800, 8000) * 0.6)
        place(hammer, hit * r.uniform(0.7, 1.0), secs(tt))
        tt += 1 / 25.0
        k += 1
    x = whine * 0.25 * np.clip(t / 0.05, 0, 1) * np.clip((dur - t) / 0.1, 0, 1) + hiss + hammer
    return fade(garage(x, 0.6, 0.12), fout=0.05)


def spray_paint():
    """Spray can: the mixing ball rattles as the can is shaken (5 strokes),
    then a 2 s pressurised hiss with a sputter at the start."""
    parts = []
    r = rng(14900)
    for s in range(5):
        for k in range(2):
            f = r.uniform(2300, 2800)
            clack = add(modal(0.06, [(f, 0.01, 0.5), (f * 2.3, 0.006, 0.2), (r.uniform(700, 900), 0.012, 0.3)], 14910 + 2 * s + k),
                        bp(burst(0.02, 0.001, 14950 + 2 * s + k), 1000, 8000) * 0.5)
            parts.append((0.02 + s * 0.22 + k * 0.11, clack, 1.0))
    n = secs(2.0)
    tt = t_axis(n)
    hiss = bp(noise(n, 14901), 2500, 12000) * np.minimum(1, tt / 0.03) * np.minimum(1, (2.0 - tt) / 0.05)
    sputter = (1 - 0.6 * (rng(14902).random(n) < 0.5) * (tt < 0.15))
    parts.append((1.4, hiss * sputter * 0.35, 1.0))
    return fade(garage(mix(3.6, parts), 0.6, 0.1), fout=0.05)


def part_fitted(v):
    """Part fitted: a satisfying clunk as a heavy part seats home (low metal
    thud with a short ring), then a bolt clicking tight."""
    r = rng(15000 + v)
    clunk = add(lp(burst(0.2, 0.02, 15010 + v), 300) * 1.4,
                modal(0.5, [(r.uniform(140, 180), 0.05, 0.6), (r.uniform(380, 450), 0.06, 0.4), (r.uniform(900, 1100), 0.05, 0.25),
                            (r.uniform(2100, 2500), 0.03, 0.12)], 15020 + v),
                bp(burst(0.03, 0.002, 15030 + v), 800, 7000) * 0.5)
    parts = [(0.02, clunk, 1.0)]
    for k in range(3):
        parts.append((0.3 + 0.07 * k + 0.04 * v, steel_tick(15040 + 10 * v + k, 0.4), 1.0))
    parts.append((0.55 + 0.04 * v, add(steel_tick(15060 + v, 0.6, 2800), lp(burst(0.05, 0.005, 15070 + v), 600) * 0.4), 1.0))
    return fade(garage(mix(1.1, parts), 0.6, 0.14), fout=0.05)


def nozzle_in():
    """Petrol nozzle lifted from the holster (plastic boot knock, hose
    flop), into the filler neck (metal clank), trigger latch click."""
    r = rng(15100)
    holster = add(modal(0.1, [(r.uniform(500, 700), 0.02, 0.5), (r.uniform(1300, 1500), 0.012, 0.3)], 15101),
                  bp(burst(0.04, 0.003, 15102), 400, 5000) * 0.5)
    flop = lp(burst(0.3, 0.05, 15103), 400) * 0.5
    clank = add(modal(0.3, [(r.uniform(900, 1100), 0.05, 0.6), (r.uniform(2300, 2600), 0.03, 0.4), (r.uniform(400, 480), 0.04, 0.4)], 15104),
                bp(burst(0.03, 0.002, 15105), 1000, 8000) * 0.6)
    latch = steel_tick(15106, 0.6, 3000)
    x = mix(1.6, [(0.02, holster, 1.0), (0.15, flop, 1.0), (0.8, clank, 1.0), (1.2, latch, 1.0)])
    return fade(garage(x, 0.5, 0.08, 5000, 15107), fout=0.05)


def nozzle_out():
    """Pump clicks off when full (sharp latch release clack), nozzle drawn
    out with a scrape and the last drips."""
    r = rng(15200)
    off = add(steel_tick(15201, 1.0, 2600), modal(0.1, [(r.uniform(700, 800), 0.02, 0.4)], 15202), lp(burst(0.05, 0.006, 15203), 500) * 0.4)
    n = secs(0.3)
    scrape = bp(noise(n, 15204), 1500, 7000) * np.hanning(n) * 0.12
    drips = np.zeros(secs(0.6))
    for i in range(3):
        m = secs(0.04)
        tm = t_axis(m)
        f0 = r.uniform(1200, 2200)
        place(drips, np.sin(2 * np.pi * np.cumsum(f0 * (1 + 3 * tm)) / SR) * np.exp(-tm / 0.01) * 0.2, secs(0.15 * i + r.uniform(0, 0.05)))
    x = mix(1.6, [(0.02, off, 1.0), (0.5, scrape, 1.0), (0.85, drips, 1.0)])
    return fade(garage(x, 0.5, 0.08, 5000, 15205), fout=0.05)


def ev_connect():
    """EV charger: connector pushed home (plastic clunk), locking pin
    solenoid snap, then the main contactor's heavy 'clack' as power flows."""
    r = rng(15300)
    plug = add(lp(burst(0.15, 0.012, 15301), 500) * 0.8, modal(0.12, [(r.uniform(600, 800), 0.015, 0.4), (r.uniform(1500, 1800), 0.01, 0.2)], 15302))
    lock = add(steel_tick(15303, 0.7, 3200), modal(0.06, [(1200, 0.01, 0.3)], 15304))
    contactor = add(modal(0.2, [(r.uniform(180, 220), 0.03, 0.6), (r.uniform(900, 1100), 0.02, 0.4), (r.uniform(2600, 3000), 0.01, 0.3)], 15305),
                    bp(burst(0.04, 0.002, 15306), 500, 7000) * 0.6)
    x = mix(1.8, [(0.02, plug, 1.0), (0.35, lock, 1.0), (1.2, contactor, 1.0)])
    return fade(garage(x, 0.5, 0.1, 5000, 15307), fout=0.05)


def servo_chime():
    """Servo entry chime: the cheap electronic 'ding-dong' over the door
    (two soft square-ish tones, E5 then C5) through a small ceiling horn."""
    n1, n2 = secs(0.9), secs(1.4)

    def tone(f, n):
        t = t_axis(n)
        x = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * 3 * f * t) + 0.1 * np.sin(2 * np.pi * 5 * f * t)
        return x * np.exp(-t / 0.45) * np.minimum(1, t / 0.004)

    x = mix(2.0, [(0.02, tone(659.26, n1), 1.0), (0.42, tone(523.25, n2), 1.0)])
    x = hp(lp(x, 4500), 350)
    return fade(garage(x, 0.8, 0.2, 5000, 15400), fout=0.1)


def wash_drips():
    """After the car wash: water dripping off the car into puddles and
    onto the concrete (~5 s, thinning out)."""
    dur = 5.0
    n = secs(dur)
    r = rng(15500)
    x = np.zeros(n)
    for i in range(80):
        at = r.exponential(1.6)
        if at > dur - 0.1:
            continue
        m = secs(0.04)
        tm = t_axis(m)
        if r.random() < 0.5:
            f0 = r.uniform(800, 2500)
            d = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 3 * tm)) / SR) * np.exp(-tm / r.uniform(0.005, 0.015)) * 0.4
        else:
            d = bp(burst(0.04, 0.003, 15510 + i), 800, 7000)
        place(x, d * r.uniform(0.2, 1.0), secs(at))
    return fade(garage(x, 0.6, 0.12, 6000, 15501), fout=0.2)


def camera_shutter():
    """Old film SLR: mirror slaps up (clack), the two shutter curtains run
    (two fast ticks ~16 ms apart), mirror returns, then the film-advance
    lever ratchets round (a zip of tiny clicks) and springs back."""
    r = rng(15600)
    mirror = add(modal(0.08, [(r.uniform(1100, 1300), 0.012, 0.6), (r.uniform(2600, 3000), 0.008, 0.4), (450, 0.015, 0.4)], 15601),
                 bp(burst(0.03, 0.0015, 15602), 800, 9000) * 0.7)
    curtain1 = steel_tick(15603, 0.6, 4200)
    curtain2 = steel_tick(15604, 0.5, 3900)
    ret = add(modal(0.08, [(r.uniform(1000, 1200), 0.01, 0.4), (400, 0.012, 0.3)], 15605), bp(burst(0.02, 0.001, 15606), 800, 8000) * 0.4)
    parts = [(0.02, mirror, 1.0), (0.025, curtain1, 1.0), (0.041, curtain2, 1.0), (0.07, ret, 0.8)]
    for k in range(14):
        parts.append((0.45 + k * 0.012, steel_tick(15620 + k, 0.15, r.uniform(4500, 6000)), 1.0))
    parts.append((0.66, add(steel_tick(15650, 0.4, 3000), modal(0.05, [(900, 0.01, 0.2)], 15651)), 1.0))
    x = mix(1.0, parts)
    return fade(reverb(x, 0.2, 6000, 0.08, 0.003, 15660).mean(axis=1), fout=0.05)


def album_page():
    """Photo album page turn: a stiff card page with a plastic sleeve lifts
    (crinkle of the film), swings over (air swish) and flops down."""
    dur = 1.0
    n = secs(dur)
    r = rng(15700)
    t = t_axis(n)
    crinkle = np.zeros(n)
    k = 120
    idx = (r.beta(2, 5, k) * 0.6 * SR).astype(int)
    np.add.at(crinkle, idx, r.lognormal(0, 0.6, k) * r.choice([-1, 1], k))
    crinkle = bp(crinkle, 2000, 10000) * 0.4
    swish = bp(noise(n, 15701), 300, 3000) * np.exp(-0.5 * ((t - 0.4) / 0.12) ** 2) * 0.08
    flop = add(lp(burst(0.12, 0.012, 15702), 600) * 0.7, bp(burst(0.04, 0.004, 15703), 600, 5000) * 0.3)
    x = mix(1.2, [(0.0, crinkle + swish, 1.0), (0.62, flop, 1.0)])
    return fade(reverb(x, 0.25, 5000, 0.08, 0.003, 15704).mean(axis=1), 0.005, 0.05)


# --------------------------------------------------------------------------


def main():
    save(f"{OUT}/garage_room_tone", room_tone(), norm="amb")
    save(f"{OUT}/garage_ratchet", ratchet())
    save(f"{OUT}/garage_impact_wrench", impact_wrench())
    save(f"{OUT}/garage_compressor", compressor_loop(), norm="lufs:-20")
    save(f"{OUT}/garage_spray_paint", spray_paint())
    for v in range(3):
        save(f"{OUT}/garage_part_fitted_{v + 1:02d}", part_fitted(v))
    save(f"{OUT}/garage_fuel_nozzle_in", nozzle_in())
    save(f"{OUT}/garage_fuel_flow", fuel_flow_loop(), norm="lufs:-20")
    save(f"{OUT}/garage_fuel_nozzle_out", nozzle_out())
    save(f"{OUT}/garage_ev_connect", ev_connect())
    save(f"{OUT}/garage_ev_hum", ev_hum_loop(), norm="amb")
    save(f"{OUT}/garage_servo_chime", servo_chime())
    save(f"{OUT}/garage_wash_hose", wash_hose_loop(), norm="lufs:-20")
    save(f"{OUT}/garage_wash_brushes", wash_brushes_loop(), norm="lufs:-20")
    save(f"{OUT}/garage_wash_drips", wash_drips())
    save(f"{OUT}/garage_camera_shutter", camera_shutter())
    save(f"{OUT}/garage_album_page", album_page())


if __name__ == "__main__":
    main()
