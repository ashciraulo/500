#!/usr/bin/env python3
"""Traffic and city sounds: engines for the other cars, utes, vans and
Transperth buses, their horns, the bus air brake, and the electric trains.

    python3 audio/tools/gen_traffic.py

Writes:
    audio/engine/sedan/      generic 2.0 petrol four (cars)
    audio/engine/diesel/     2.8 turbo-diesel four (utes, vans)
    audio/engine/busdiesel/  big six-cylinder diesel (buses)
    audio/traffic/*.ogg      horns (from recordings: run fetch_sources.py first),
                             air brake, train running loop and horn

The engine sets use the same layout and synthesis as gen_engines.py (stock
exhaust only), so the game drives them with the same EngineAudio node.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import engine_synth as E  # noqa: E402
import gen_car as C  # noqa: E402
import gen_engines as G  # noqa: E402
import sfxlib as S  # noqa: E402
from sfxlib import SR, bp, env_exp, fade, hp, lp, noise, secs, t_axis  # noqa: E402

OUT = "traffic"

TRAFFIC_ENGINES = {
    # Everyday Corolla/Mazda3-type petrol four: smooth, quiet, a bit of intake.
    "sedan": E.Engine("sedan", 4, 750, 6200, pipe_ms=(11.5, 6.8), pipe_fb=(0.36, 0.28),
                      muffler_hz=380, chamber_hz=150, chamber_db=2.0, pulse_ms=0.65,
                      cyl_gain_spread=0.04, cyl_time_spread=0.015, jitter_on=0.03,
                      body=2.2, sharp=0.2, rasp=0.05, mech=0.06, valves_per_cyl=4,
                      intake=0.12, intake_band=(700, 2400), whine=0.006,
                      level_curve=0.85, load_db=6),
    # Hilux/Ranger/HiAce turbo-diesel: clattery idle, low redline, turbo whoosh.
    "diesel": E.Engine("diesel", 4, 750, 4200, pipe_ms=(13.0, 7.5), pipe_fb=(0.40, 0.30),
                       muffler_hz=340, chamber_hz=120, chamber_db=3.0, pulse_ms=0.35,
                       cyl_gain_spread=0.10, cyl_time_spread=0.03, jitter_on=0.08,
                       body=2.4, sharp=0.5, rasp=0.06, mech=0.38,
                       block_modes=(900, 1900, 3100), valves_per_cyl=4, intake=0.10,
                       intake_band=(500, 1800), turbo=0.06, turbo_hz_at_redline=5200,
                       level_curve=0.7, drive=1.6, load_db=7),
    # Transperth bus: big six, deep and gruff, slow-revving.
    "busdiesel": E.Engine("busdiesel", 6, 600, 2400, pipe_ms=(18.0, 10.5), pipe_fb=(0.45, 0.32),
                          muffler_hz=260, chamber_hz=85, chamber_db=4.0, pulse_ms=0.45,
                          cyl_gain_spread=0.08, cyl_time_spread=0.025, jitter_on=0.06,
                          body=2.6, sharp=0.45, rasp=0.04, mech=0.30,
                          block_modes=(620, 1400, 2500), valves_per_cyl=4, intake=0.08,
                          intake_band=(400, 1500), turbo=0.05, turbo_hz_at_redline=4200,
                          lowcut_hz=18, level_curve=0.6, drive=1.4, load_db=6),
}


def bus_points(e: E.Engine) -> list[int]:
    return [int(e.idle), 1000, 1400, 1900, int(e.redline)]


def render_engines():
    for name, e in TRAFFIC_ENGINES.items():
        print(f"[{name}]", file=sys.stderr)
        if name == "busdiesel":
            orig = G.rpm_points
            G.rpm_points = bus_points
            items = G.render_family(name, e)
            G.rpm_points = orig
        else:
            items = G.render_family(name, e)
        G.save_set(name, items)


# --------------------------------------------------------------------------
# Horns
# --------------------------------------------------------------------------

def horn(key: str, start: float, end: float, tail=0.3, ratio=1.0) -> np.ndarray:
    """One real honk cut from a CC0 recording (gen_car.honk): own attack,
    own release, room tail faded out. ratio > 1 pitches it up."""
    return C.honk(key, start, end, tail=tail, ratio=ratio)


def render_horns():
    # Three everyday cars: an Alfa MiTo twin (~400 + 500 Hz), a Skoda Fabia's
    # single ~496 Hz horn, and a lower single horn (~355 Hz) honked twice.
    S.save(f"{OUT}/traffic_horn_car_01", horn("horn_mito", 1.156, 1.43, tail=0.45), "peak")
    S.save(f"{OUT}/traffic_horn_car_02", horn("horn_fabia", 0.328, 0.57, tail=0.35), "peak")
    a = horn("horn_devern", 1.475, 1.625, tail=0.0)
    b = horn("horn_devern", 1.747, 1.92, tail=0.3)
    two = np.concatenate([a, np.zeros(secs(1.747 - 1.625 - 0.004)), b])
    S.save(f"{OUT}/traffic_horn_car_03", C.repitch(two, 0.9), "peak")
    # Buses: a deep truck air-horn chord (~187/280/374 Hz), held a little
    # shorter than recorded and spliced onto its own let-go.
    S.save(f"{OUT}/traffic_horn_bus", C.shortened_honk("horn_truck_air", 0.07, 0.95, 1.25, 1.75, fadeout=0.25),
           "peak")


# --------------------------------------------------------------------------
# Bus air brake and doors
# --------------------------------------------------------------------------

def render_bus():
    # Air brake release: a sharp "psssh" that tails off.
    n = secs(1.4)
    x = hp(noise(n, 40), 1800) * env_exp(n, 0.35, 0.004)
    x += 0.4 * bp(noise(n, 41), 3000, 9000) * env_exp(n, 0.12, 0.002)
    S.save(f"{OUT}/traffic_bus_air_brake", fade(x, 0, 0.1), "peak")
    # Doors folding open: air, then a clunk.
    n = secs(1.6)
    x = 0.7 * bp(noise(n, 42), 1200, 6000) * env_exp(n, 0.5, 0.05)
    k = secs(0.9)
    clunk = lp(noise(secs(0.25), 43), 600) * env_exp(secs(0.25), 0.05)
    x[k:k + clunk.size] += 1.5 * clunk
    S.save(f"{OUT}/traffic_bus_doors", fade(x, 0, 0.1), "peak")


# --------------------------------------------------------------------------
# Trains (Transperth electric multiple units)
# --------------------------------------------------------------------------

def train_loop(seconds=4.0) -> np.ndarray:
    """A train running at speed, heard from beside the line: traction motor
    whine, steady wheel-on-rail roar, and the clack of wheels over rail
    joints. The whole thing is periodic so it loops; the game pitches it with
    the train's speed."""
    n = secs(seconds)
    t = t_axis(n)

    def tone(f, a):
        f = round(f * seconds) / seconds
        return a * np.sin(2 * np.pi * f * t)

    x = 0.5 * S.circ_bp(S.pink(n, 50), 150, 2500)                  # rolling roar
    x += 0.25 * S.circ_bp(noise(n, 51), 2500, 7000)                # rail hiss
    for f, a in ((440, 0.10), (880, 0.05), (1320, 0.03), (660, 0.04)):
        x += tone(f, a)                                            # motor whine
    # Rail joints: each bogie's two axles clack over a joint, cars every ~0.5 s.
    clack = lp(noise(secs(0.05), 52), 2200) * env_exp(secs(0.05), 0.008)
    for start in np.arange(0.0, seconds, 0.5):
        for off in (0.0, 0.11):
            S.place(x, 0.9 * clack, int((start + off) * SR), wrap=True)
    return x


def render_trains():
    S.save(f"{OUT}/traffic_train_running", train_loop(), "peak")
    # Train horn: the two-tone warning sounded at level crossings, high then
    # low (~372 then ~311 Hz), both from one recorded air horn with its own
    # attack and let-go.
    try:
        hi = C.shortened_honk("horn_airhorn", 0.333, 0.95, 1.62, 1.85, fadeout=0.12, ratio=1.06)
        lo = C.shortened_honk("horn_airhorn", 0.333, 1.30, 1.62, 2.35, fadeout=0.4, ratio=0.885)
    except C.MissingHornSource as e:
        print(f"skipping the train horn, keeping the committed one: {e}")
        return
    S.save(f"{OUT}/traffic_train_horn", np.concatenate([hi, np.zeros(secs(0.08)), lo]), "peak")


def main():
    try:
        render_horns()
    except C.MissingHornSource as e:
        print(f"skipping the traffic horns, keeping the committed ones: {e}")
    render_bus()
    render_trains()
    render_engines()


if __name__ == "__main__":
    main()
