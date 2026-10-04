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


def train_alongside_loop(seconds=9.0) -> np.ndarray:
    """Racing a Transperth train: the train at ~100 km/h heard from a car
    keeping pace a few metres away. Closer and fuller than train_loop: the
    inverter's whine sweeping a little, traction-motor hum, the roll of steel
    on steel, wind buffeting off the carriage side, and the nearest car's
    four axles clacking over rail joints ("da-dum ... da-dum"), with the odd
    pantograph spark. Periodic so it loops; the game pitches it with the
    train's speed and fades it with the gap."""
    n = secs(seconds)
    t = t_axis(n)
    r = np.random.default_rng(60)

    def ftone(f):
        return round(f * seconds) / seconds

    def rms1(y):
        return y / np.sqrt(np.mean(y ** 2))

    x = 0.30 * rms1(S.circ_bp(S.pink(n, 61), 90, 2200))             # rolling roar
    x += 0.05 * rms1(S.circ_bp(noise(n, 62), 2800, 8000))           # rail hiss
    buffet = 0.6 + 0.4 * np.sin(2 * np.pi * ftone(0.9) * t) * np.sin(2 * np.pi * ftone(2.3) * t + 1.0)
    x += 0.25 * rms1(S.circ_lp(S.brown(n, 63), 120, 2)) * buffet    # wind off the carriage
    # inverter whine with a slow, small sweep, and motor hum harmonics
    sweep = np.sin(2 * np.pi * t / seconds)
    for k, (f, a) in enumerate(((1150, 0.05), (2300, 0.02), (3450, 0.01))):
        x += a * np.sin(2 * np.pi * ftone(f) * t + 12.0 * (k + 1) * sweep)
    for h, a in ((1, 0.08), (2, 0.05), (3, 0.03), (5, 0.015)):
        x += a * np.sin(2 * np.pi * ftone(165 * h) * t)
    # rail joints every 0.9 s under the nearest car's axles (bogies 17 m apart)
    clack = rms1(lp(noise(secs(0.08), 64), 3000)) * env_exp(secs(0.08), 0.008)
    thud = rms1(lp(noise(secs(0.08), 65), 250)) * env_exp(secs(0.08), 0.02)
    for start in np.arange(0.0, seconds, 0.9):
        for off, a in ((0.0, 1.0), (0.09, 0.85), (0.61, 0.7), (0.70, 0.6)):
            j = 1 + 0.15 * r.standard_normal()
            S.place(x, a * j * (1.1 * clack + 1.0 * thud), int((start + off) * SR), wrap=True)
    # the odd pantograph spark, far up on the roof
    for at in (2.37, 6.81):
        k = secs(0.04)
        sp = bp(noise(k, int(at * 100)), 3000, 9000) * env_exp(k, 0.006)
        S.place(x, 0.2 * rms1(sp) * env_exp(k, 0.006), int(at * SR), wrap=True)
    return x


def render_trains():
    S.save(f"{OUT}/traffic_train_running", train_loop(), "peak")
    S.save(f"{OUT}/traffic_train_alongside_loop", train_alongside_loop(), "peak")
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


# --------------------------------------------------------------------------
# City life: emergency sirens, cyclists, roadworks, wildlife
# --------------------------------------------------------------------------

def _periodic_phase(f: np.ndarray) -> np.ndarray:
    """Phase of a frequency curve, nudged so it wraps exactly over the loop."""
    ph = 2 * np.pi * np.cumsum(f) / SR
    cycles = round(ph[-1] / (2 * np.pi))
    return ph * (cycles * 2 * np.pi) / ph[-1]


def siren_loop(kind: str, seconds=8.0) -> np.ndarray:
    """A WA emergency vehicle's electronic siren, close up (mono, loops):
    a square-ish tone through the roof speaker's horn. police: wail then
    yelp; ambulance: a steady wail; fire: a lower, slower wail with a
    rotary growl under it."""
    n = secs(seconds)
    t = t_axis(n)
    if kind == "police":
        half = seconds / 2
        wph = (t / (half / 1)) % 1.0  # one wail in the first half
        wail = 620 + 780 * np.sin(np.pi / 2 * np.where(wph < 0.55, wph / 0.55, 1 - (wph - 0.55) / 0.45))
        yph = (t / (half / 12)) % 1.0  # twelve yelps in the second half
        yelp = 650 + 820 * np.sin(np.minimum(yph / 0.85, 1.0) * np.pi / 2)
        mix = 0.5 - 0.5 * np.cos(np.clip((t - half) / 0.08, 0, 1) * np.pi)
        mix *= 0.5 + 0.5 * np.cos(np.clip((t - seconds + 0.08) / 0.08, 0, 1) * np.pi)
        f = wail * (1 - mix) + yelp * mix
    elif kind == "ambulance":
        ph = (t / (seconds / 2)) % 1.0
        f = 600 + 800 * np.sin(np.pi / 2 * np.where(ph < 0.5, ph / 0.5, 1 - (ph - 0.5) / 0.5))
    else:  # fire
        ph = (t / seconds) % 1.0
        f = 420 + 680 * np.sin(np.pi / 2 * np.where(ph < 0.6, ph / 0.6, 1 - (ph - 0.6) / 0.4))
    ph = _periodic_phase(f)
    x = np.tanh(3.0 * np.sin(ph)) + 0.3 * np.sin(2 * ph)
    x = S.circ_bp(x, 350, 5000, 2)
    # the horn speaker's resonances
    x = S.circ_filter(x, S.circ_response(n, lambda fr: 1 + 2.5 * np.exp(-((fr - 1700) / 500) ** 2)
                                         + 1.2 * np.exp(-((fr - 950) / 300) ** 2)))
    if kind == "fire":
        k = max(1, round(36 * seconds))
        growl = np.sin(2 * np.pi * (k / seconds) * t)
        x = x * (1 + 0.25 * growl) + 0.15 * S.circ_bp(S.pink(n, 61), 60, 300)
    return x


def bike_freewheel_loop(seconds=4.0) -> np.ndarray:
    """A bike coasting past: the freewheel's pawls ticking (about 24 a
    second at 25 km/h), tyre hum on the bitumen and a little chain rattle
    (mono, loops; the game pitches it with speed)."""
    n = secs(seconds)
    r = np.random.default_rng(62)
    x = np.zeros(n)
    k = secs(0.012)
    tk = t_axis(k)
    rate = round(24 * seconds) / seconds
    for i in range(int(rate * seconds)):
        f = r.uniform(5200, 6800)
        click = np.sin(2 * np.pi * f * tk) * np.exp(-tk / 0.0015) * r.uniform(0.6, 1.0)
        S.place(x, click, int((i / rate + r.normal(0, 0.0015)) * SR) % n, wrap=True)
    hum = S.circ_bp(S.pink(n, 63), 180, 900)
    hum *= 1 + 0.15 * np.sin(2 * np.pi * round(3.2 * seconds) / seconds * t_axis(n))  # wheel turning
    rattle = S.circ_bp(noise(n, 64), 2500, 6000) * (S.smooth_noise(n, 9, 65) > 0.6)
    return x * 0.5 + hum / np.std(hum) * 0.12 + rattle / (np.std(rattle) + 1e-12) * 0.03


def roadworks_loop(seconds=40.0, night=False) -> np.ndarray:
    """Roadworks, heard from the road (mono, loops). Day: a generator, a
    plate compactor thumping on and off, shovels scraping, the works ute
    reversing with its beeper. Night: the generator and the light tower."""
    n = secs(seconds)
    t = t_axis(n)
    r = np.random.default_rng(70 if not night else 71)
    k = round(50 * seconds)  # 3000 rpm generator: 50 Hz firing
    gen = sum(a * np.sin(2 * np.pi * (k * m / seconds) * t + m) for m, a in ((1, 1.0), (2, 0.6), (3, 0.3), (4, 0.15)))
    gen = gen * 0.3 + 0.2 * S.circ_bp(S.pink(n, 72), 200, 2000)
    x = gen * (0.6 if night else 0.35)
    if not night:
        # plate compactor: ~ 90 Hz thumps, runs of 6-10 s
        comp = np.zeros(n)
        for a, L in ((2.0, 8.0), (21.0, 7.0)):
            seg = t_axis(secs(L))
            hz = 11.0
            env = (np.sin(2 * np.pi * hz * seg) > 0.6) * 1.0
            body = S.lp(r.standard_normal(secs(L)), 300) * env
            engine = 0.4 * np.sin(2 * np.pi * 63 * seg) * (1 + 0.5 * np.sin(2 * np.pi * hz * seg))
            seg_x = (body / (np.std(body) + 1e-12) * 0.8 + engine) * np.minimum(1, np.minimum(seg / 0.5, (L - seg) / 0.5))
            S.place(comp, seg_x, secs(a), wrap=True)
        x += comp * 0.7
        # shovel scrapes into gravel
        for a in r.uniform(0, seconds, 7):
            L = secs(r.uniform(0.5, 0.9))
            sc = S.bp(r.standard_normal(L), 1200, 6000, 2) * np.hanning(L)
            crunch = S.bp(r.standard_normal(L), 200, 1200, 2) * (r.random(L) < 0.02) * 4
            S.place(x, (sc + crunch) * 0.5, secs(a), wrap=True)
        # reversing beeper, 1 kHz, 1 per second for 6 s
        bk = secs(0.5)
        beep = np.sin(2 * np.pi * 1030 * t_axis(bk)) * (t_axis(bk) < 0.5)
        beep = fade(beep, 0.005, 0.005)
        for i in range(6):
            S.place(x, beep * 0.35, secs(31.0 + i * 1.0), wrap=True)
    else:
        # the light tower's ballast buzz
        k2 = round(100 * seconds)
        x += 0.12 * np.tanh(3 * np.sin(2 * np.pi * (k2 / seconds) * t))
    return x


def ibis_grunt(seed: int) -> np.ndarray:
    """Australian white ibis: a short, hoarse, guttural honking grunt or two
    (mono). Synthesised: no CC0 recording of the species was found."""
    r = np.random.default_rng(seed)
    out = []
    for _ in range(int(r.integers(1, 4))):
        L = r.uniform(0.18, 0.35)
        n = secs(L)
        t = t_axis(n)
        f0 = r.uniform(150, 210) * (1 - 0.15 * t / L)
        ph = 2 * np.pi * np.cumsum(f0) / SR
        pulse = (np.sin(ph) > 0.7) * 1.0 + 0.3 * r.standard_normal(n)  # rough, pulsed
        y = S.resonator(pulse, 650, 3.0) + 0.7 * S.resonator(pulse, 1250, 4.0) + 0.3 * S.resonator(pulse, 2400, 5.0)
        y *= S.env_adsr(n, 0.015, 0.04, 0.8, L * 0.4)
        out.append(y)
        out.append(np.zeros(secs(r.uniform(0.08, 0.25))))
    return np.concatenate(out)


def wings_takeoff(seed: int, big: bool) -> np.ndarray:
    """A bird taking off: quick wingbeats slowing as it climbs (mono)."""
    r = np.random.default_rng(seed)
    dur = 1.6 if big else 1.1
    n = secs(dur)
    y = np.zeros(n)
    tt = 0.0
    rate = (5.5 if big else 8.5)
    k = 0
    while tt < dur - 0.2:
        L = secs(0.09 if big else 0.06)
        beat = S.bp(r.standard_normal(L), 250 if big else 500, 3500 if big else 6000, 2) * np.hanning(L)
        S.place(y, beat * (1.0 - 0.6 * tt / dur), secs(tt))
        k += 1
        tt += 1 / (rate * (1 - 0.35 * tt / dur)) * r.uniform(0.95, 1.05)
    return fade(y, 0.0, 0.2)


def roo_thump(seed: int) -> np.ndarray:
    """A kangaroo's hop landing on grass: a soft, heavy thud with a swish
    of grass (mono)."""
    r = np.random.default_rng(seed)
    n = secs(0.35)
    t = t_axis(n)
    thud = np.sin(2 * np.pi * r.uniform(55, 75) * t * (1 - 0.3 * t)) * np.exp(-t / 0.05)
    knock = S.lp(r.standard_normal(n), 600) * np.exp(-t / 0.015)
    grass = S.bp(r.standard_normal(n), 2000, 7000, 2) * np.exp(-t / 0.06) * 0.25
    return fade(thud + 0.6 * knock + grass, 0.001, 0.05)


def render_city():
    for kind in ("police", "ambulance", "fire"):
        S.save(f"{OUT}/traffic_siren_{kind}_loop", siren_loop(kind), "peak", quality=4)
    S.save(f"{OUT}/traffic_bike_freewheel_loop", bike_freewheel_loop(), "peak", quality=4)
    S.save(f"{OUT}/traffic_roadworks_day_loop", roadworks_loop(), "lufs:-24", quality=2, rate=32000)
    S.save(f"{OUT}/traffic_roadworks_night_loop", roadworks_loop(20.0, night=True), "lufs:-30", quality=2, rate=32000)
    for i in range(3):
        S.save(f"{OUT}/traffic_ibis_grunt_0{i + 1}", ibis_grunt(80 + i), "peak", quality=4)
    for i in range(2):
        S.save(f"{OUT}/traffic_wings_takeoff_0{i + 1}", wings_takeoff(90 + i, big=i == 1), "peak", quality=4)
    for i in range(3):
        S.save(f"{OUT}/traffic_roo_thump_0{i + 1}", roo_thump(95 + i), "peak", quality=4)


# --------------------------------------------------------------------------
# People, trains at stations, Swan River ferries
# --------------------------------------------------------------------------

def _loop_mono(x: np.ndarray, xf=0.5) -> np.ndarray:
    return S.make_loop(x, xf)


def crowd_loop(kind: str, seconds: float) -> np.ndarray:
    """Wordless crowd walla from CC0 bar/pub recordings, taken outdoors
    (mono, loops): the room's reverb rolled off, a touch of street air.
    small: a few people talking as they walk or wait (from the quieter
    bar recording); busy: a Northbridge footpath on a Friday night."""
    import gen_amb as A
    if kind == "small":
        x = A.texture(A.src("bar_wa", True), seconds, 101, chunk=7, avoid_peaks_db=6).mean(axis=1)
        x = S.circ_bp(x, 220, 5000, 2)
    else:
        x = (A.texture(A.src("pub_crowd", True), seconds, 102, chunk=9).mean(axis=1)
             + 0.6 * A.texture(A.src("bar_wa", True), seconds, 103, chunk=9).mean(axis=1))
        x = S.circ_bp(x, 160, 6000, 2)
    # outdoors: tame the low-mid room build-up a little
    x = S.circ_filter(x, S.circ_response(len(x), lambda f: 1 - 0.4 * np.exp(-((f - 350) / 200) ** 2)))
    return x


def steps_loop(kind: str, seconds=4.0) -> np.ndarray:
    """One person walking along a concrete footpath at ~1.9 steps/s (mono,
    loops). shoes: rubber soles, a soft scuff-tap; heels: sharp clicks;
    thongs: the Australian summer flip-flop slap."""
    r = np.random.default_rng({"shoes": 110, "heels": 111, "thongs": 112}[kind])
    n = secs(seconds)
    y = np.zeros(n)
    rate = round(1.9 * seconds) / seconds
    for i in range(int(rate * seconds)):
        k = secs(0.18)
        tk = t_axis(k)
        g = r.uniform(0.75, 1.0) * (1.0 if i % 2 else 0.85)  # a slight limp-free L/R difference
        if kind == "shoes":
            st = (np.sin(2 * np.pi * r.uniform(90, 120) * tk) * np.exp(-tk / 0.012) * 0.6
                  + bp(noise(k, 113 + i), 900, 6000) * np.exp(-tk / 0.025) * 0.5)
            scuff = bp(noise(k, 130 + i), 2000, 8000) * np.exp(-((tk - 0.09) / 0.03) ** 2) * 0.15
            st = st + scuff
        elif kind == "heels":
            heel = np.sin(2 * np.pi * r.uniform(2400, 2900) * tk) * np.exp(-tk / 0.006)
            heel += bp(noise(k, 113 + i), 2500, 9000) * np.exp(-tk / 0.004) * 1.2
            toe = np.roll(bp(noise(k, 150 + i), 800, 5000) * np.exp(-tk / 0.01) * 0.3, secs(0.07))
            st = heel + toe
        else:
            slap = bp(noise(k, 113 + i), 600, 5000) * np.exp(-tk / 0.008)
            flap = np.roll(bp(noise(k, 170 + i), 400, 3500) * np.exp(-tk / 0.006) * 0.8, secs(r.uniform(0.09, 0.12)))
            st = slap + flap
        S.place(y, fade(st, 0.0005, 0.02) * g, secs(i / rate + r.normal(0, 0.008)) % n, wrap=True)
    return y


def train_station(kind: str) -> np.ndarray:
    """A Transperth train at a station platform (mono).
    arrive: inverter whine falling, brakes squealing at the end, a final
    clunk and the air hiss; doors: the door chime, the doors sliding
    open, a pause, the chime again and the doors closing with a thump;
    depart: the inverter whine climbing through its steps, rolling off."""
    import gen_amb as A
    r = np.random.default_rng({"arrive": 120, "doors": 121, "depart": 122}[kind])
    if kind == "doors":
        n = secs(9.0)
        y = np.zeros(n)
        def chime():
            c = np.zeros(secs(0.9))
            for j, f in enumerate((880.0, 698.5, 880.0)):
                L = secs(0.25)
                tk = t_axis(L)
                tone = (np.sin(2 * np.pi * f * tk) + 0.25 * np.sin(4 * np.pi * f * tk)) * np.exp(-tk / 0.12)
                S.place(c, fade(tone, 0.003, 0.05), secs(j * 0.28))
            return c
        def slide(L, seed):
            tk = t_axis(secs(L))
            hiss = bp(noise(len(tk), seed), 1500, 7000) * np.hanning(len(tk)) * 0.4
            rumble = bp(noise(len(tk), seed + 1), 120, 700) * np.hanning(len(tk))
            motor = np.sin(2 * np.pi * 180 * tk) * np.hanning(len(tk)) * 0.15
            return rumble + hiss + motor
        S.place(y, chime() * 0.5, 0)
        S.place(y, slide(1.4, 123), secs(0.9))
        S.place(y, chime() * 0.5, secs(5.6))
        S.place(y, slide(1.3, 125), secs(6.5))
        th = np.sin(2 * np.pi * 85 * t_axis(secs(0.2))) * env_exp(secs(0.2), 0.04)
        S.place(y, th * 1.2, secs(7.75))
        return y
    dur = 9.0
    n = secs(dur)
    t = t_axis(n)
    v = np.clip(1 - t / 7.2, 0, 1) if kind == "arrive" else np.clip(t / 8.0, 0, 1) ** 0.8
    # inverter whine: rises in steps as the drive changes mode
    f0 = 80 + 900 * v
    if kind == "depart":
        f0 = 80 + 900 * (np.floor(v * 4) / 4 * 0.6 + v * 0.4)
    whine = sum(np.sin(2 * np.pi * np.cumsum(f0 * h) / SR) / h ** 1.3 for h in (1, 2, 3))
    whine *= (0.2 + 0.8 * np.clip(v * 2, 0, 1)) * (0.6 if kind == "arrive" else 1.0)
    roll = lp(bp(noise(n, 126), 120, 1500), 1000) * v ** 1.5 * 1.4
    y = whine * 0.7 + roll
    if kind == "arrive":
        sq_env = np.clip((t - 4.0) / 1.0, 0, 1) * np.clip((7.3 - t) / 0.3, 0, 1)
        sq = np.sin(2 * np.pi * np.cumsum(np.full(n, 2950.0) * (1 + 0.012 * S.smooth_noise(n, 4, 127, periodic=False))) / SR)
        y += sq * sq_env * 0.12
        clunk = np.sin(2 * np.pi * 60 * t_axis(secs(0.3))) * env_exp(secs(0.3), 0.06)
        S.place(y, clunk * 0.8, secs(7.3))
        hiss = bp(noise(secs(1.4), 128), 1500, 8000) * env_exp(secs(1.4), 0.5) * 0.5
        S.place(y, hiss, secs(7.6))
    else:
        y = y * np.clip(1.2 - np.clip((t - 6.5) / 2.5, 0, 1), 0, 1)  # rolling away
    return fade(y, 0.3, 0.6)


def ferry_engine_loop(seconds=8.0, cruise=True) -> np.ndarray:
    """A Transperth ferry (a small diesel passenger ferry) across the water
    (mono, loops): the diesel's thrum, the recorded small-ferry engine
    under it, and at cruise the hull pushing through the chop."""
    import gen_amb as A
    n = secs(seconds)
    t = t_axis(n)
    rpm = 1500 if cruise else 700
    fire = round(rpm / 60 * 3 * seconds) / seconds  # six-cylinder: 3 firings a turn
    pulses = sum(np.sin(2 * np.pi * fire * h * t + h) / h for h in (1, 2, 3, 4))
    pulses *= 1 + 0.2 * np.sin(2 * np.pi * round(rpm / 120 * seconds) / seconds * t)
    diesel = S.circ_lp(np.tanh(1.5 * pulses), 900, 2)
    rec = A.texture(A.src("ferry", True), seconds, 140, chunk=6).mean(axis=1)
    rec = S.circ_lp(rec, 1500, 2)
    y = diesel / np.std(diesel) * 0.8 + rec / np.std(rec) * 0.4
    if cruise:
        wash = S.circ_lp(S.circ_bp(S.pink(n, 141), 250, 3000), 2000) * (1 + 0.4 * S.smooth_noise(n, 0.6, 142))
        y += wash / np.std(wash) * 0.2
    return y


def ferry_horn() -> np.ndarray:
    """The ferry's horn: one short and one longer blast, a small vessel's
    higher, brassier note than a ship's."""
    import gen_amb as A
    a = A.ship_horn(0.6, 1, f0=180.0)
    b = A.ship_horn(1.6, 2, f0=180.0)
    return fade(np.concatenate([a, np.zeros(secs(0.35)), b]), 0.0, 0.2)


def ferry_wake_loop(seconds=10.0) -> np.ndarray:
    """A ferry's wake reaching the shore or the jetty (mono, loops): a
    run of small waves breaking and slapping, then settling."""
    import gen_amb as A
    n = secs(seconds)
    x = A.texture(A.src("lapping", True), seconds, 150, chunk=5).mean(axis=1)
    x = x * (1 + 0.8 * np.clip(S.smooth_noise(n, 0.5, 151), 0, None))
    sl = A.pontoon_slaps(n, 152, 14).mean(axis=1)
    return x / np.std(x) + sl / (np.std(sl) + 1e-12) * 0.5


def render_people():
    S.save(f"{OUT}/traffic_crowd_small_loop", crowd_loop("small", 20.0), "lufs:-24", quality=2, rate=32000)
    S.save(f"{OUT}/traffic_crowd_busy_loop", crowd_loop("busy", 30.0), "lufs:-22", quality=2, rate=32000)
    for kind in ("shoes", "heels", "thongs"):
        S.save(f"{OUT}/traffic_steps_{kind}_loop", steps_loop(kind), "peak", quality=3)
    for kind in ("arrive", "doors", "depart"):
        S.save(f"{OUT}/traffic_train_{kind}", train_station(kind), "peak", quality=3)
    S.save(f"{OUT}/traffic_ferry_engine_loop", ferry_engine_loop(), "peak", quality=3, rate=32000)
    S.save(f"{OUT}/traffic_ferry_idle_loop", ferry_engine_loop(6.0, cruise=False), "peak", quality=3, rate=32000)
    S.save(f"{OUT}/traffic_ferry_horn", ferry_horn(), "peak", quality=3)
    S.save(f"{OUT}/traffic_ferry_wake_loop", ferry_wake_loop(), "lufs:-26", quality=2, rate=32000)



# --------------------------------------------------------------------------
# Kerbside: couriers, taxis, hazards and the parking inspector
# --------------------------------------------------------------------------


def hazard_tick_loop() -> np.ndarray:
    """Another car's hazard lights from the footpath: the same relay as ours
    but through the closed body, so dull and quiet (the game adds distance)."""
    x = C.indicator_modern()
    return C.check_loop("hazard", C.periodic(x, lambda y: lp(y, 2500, 2)) * 0.6)


def van_slide(open_: bool) -> np.ndarray:
    """Courier van side door. Open: handle clack, the latch lets go, rollers
    rumble back along the track and it catches on the hold-open stop.
    Close: a rolling run forward then a big hollow slam into the latches."""
    r = S.rng(600 if open_ else 610)
    seed = 600 if open_ else 610
    handle = C.add(C.modal(0.1, [(1100, 0.02, 0.5), (2400, 0.012, 0.25)], seed + 1),
                   bp(C.burst(0.03, 0.002, seed + 2), 1000, 7000) * 0.5)
    run = 0.55 if open_ else 0.45
    n = secs(run)
    t = t_axis(n)
    env = np.sin(np.linspace(0, np.pi, n)) ** 0.7
    rumble = bp(noise(n, seed + 3), 120, 1200) * env * 0.35
    # roller clicks over the track joints, speeding up then slowing
    clicks = np.zeros(n)
    k = 0.03
    while k < run - 0.03:
        S.place(clicks, C.tick(seed + 10 + int(k * 100), 2100, 700, 0.25), secs(k))
        k += r.uniform(0.05, 0.08)
    roll = rumble + clicks
    if open_:
        stop = C.add(C.modal(0.25, [(160, 0.05, 0.6), (420, 0.04, 0.35), (980, 0.02, 0.15)], seed + 4),
                     lp(C.burst(0.1, 0.01, seed + 5), 600) * 0.8)
        x = C.mix(1.3, [(0.02, handle, 1.0), (0.1, roll, 1.0), (0.1 + run, stop, 1.0)])
    else:
        slam = C.add(C.modal(0.9, [(68, 0.1, 1.0), (104, 0.07, 0.6), (190, 0.08, 0.5), (330, 0.07, 0.4),
                                   (560, 0.05, 0.25), (910, 0.03, 0.12)], seed + 6, 0.002),
                     lp(C.burst(0.3, 0.03, seed + 7), 250, 2) * 2.4,
                     bp(C.burst(0.03, 0.002, seed + 8), 1800, 9000) * 0.5)
        x = C.mix(1.6, [(0.02, handle, 1.0), (0.1, roll, 1.0), (0.1 + run, slam, 1.4)])
    return fade(C.room(x, 0.35, 0.18, 3500, seed), 0, 0.06)


def van_rear(open_: bool) -> np.ndarray:
    """Van barn doors at the back. Open: lever handle, rod latches release top
    and bottom, the two doors swing on stiff hinges. Close: one door thuds
    onto the stop, the second slams over it and the rods engage."""
    seed = 620 if open_ else 630
    lever = C.add(C.modal(0.15, [(820, 0.03, 0.5), (1900, 0.02, 0.25)], seed + 1),
                  bp(C.burst(0.04, 0.003, seed + 2), 900, 6000) * 0.5)
    if open_:
        rods = C.add(C.modal(0.2, [(1500, 0.04, 0.3), (2700, 0.03, 0.2)], seed + 3),
                     C.modal(0.2, [(1350, 0.04, 0.25)], seed + 4))
        n = secs(0.5)
        hinge = bp(noise(n, seed + 5), 400, 2500) * np.sin(np.linspace(0, np.pi, n)) ** 2 * 0.12
        x = C.mix(1.4, [(0.02, lever, 1.0), (0.08, rods, 1.0), (0.2, hinge, 1.0), (0.45, hinge * 0.8, 1.0)])
    else:
        def thud(sd, f0, g):
            return C.add(C.modal(0.8, [(f0, 0.09, 1.0), (f0 * 1.6, 0.07, 0.55), (f0 * 3.1, 0.06, 0.35),
                                       (f0 * 5.3, 0.04, 0.2)], sd, 0.002),
                         lp(C.burst(0.25, 0.03, sd + 1), 260, 2) * 2.0) * g
        latch = C.add(bp(C.burst(0.03, 0.002, seed + 9), 1800, 9000) * 0.5,
                      C.modal(0.08, [(2600, 0.01, 0.25), (3900, 0.008, 0.15)], seed + 10))
        x = C.mix(1.8, [(0.02, thud(seed + 3, 82, 0.6), 1.0), (0.62, thud(seed + 5, 74, 1.0), 1.0),
                        (0.625, latch, 1.0), (0.66, lever, 0.6)])
    return fade(C.room(x, 0.35, 0.18, 3500, seed), 0, 0.06)


def trolley_roll_loop(seconds=4.0) -> np.ndarray:
    """A courier's hand trolley rolling along the footpath: small hard wheels
    rumble on the paving, knock over the joints between slabs every half a
    metre or so, and the parcels shift on the frame."""
    n = secs(seconds)
    rumble = S.circ_bp(noise(n, 640), 90, 1500) * 0.3
    t = t_axis(n)
    rumble *= 0.8 + 0.2 * np.sin(2 * np.pi * 3.0 * t)  # wheel out of round, whole cycles
    out = rumble.copy()
    r = S.rng(641)
    for k in range(8):  # slab joints at a walking pace, ~2/s
        at = k * seconds / 8 + r.uniform(-0.02, 0.02)
        knock = C.add(C.modal(0.15, [(140, 0.03, 0.8), (380, 0.02, 0.4), (1200, 0.01, 0.2)], 650 + k),
                      lp(C.burst(0.05, 0.006, 660 + k), 900) * 0.8)
        S.place(out, knock * r.uniform(0.6, 1.0), secs(at), wrap=True)
        S.place(out, knock * 0.5, secs(at + 0.035), wrap=True)  # the second wheel
    for k in range(3):  # cardboard boxes shifting
        S.place(out, bp(C.burst(0.08, 0.015, 670 + k), 300, 2500) * 0.25, secs(r.uniform(0, seconds)), wrap=True)
    return C.check_loop("trolley", out)


def ticket_printer() -> np.ndarray:
    """Parking inspector's handheld: two key beeps, the thermal printer
    whirs the ticket out (stepper motor whine with a paper hiss), then the
    ticket is torn off against the serrated edge."""
    beep_n = secs(0.07)
    bt = t_axis(beep_n)
    beep = np.sign(np.sin(2 * np.pi * 2700 * bt)) * 0.15 * np.minimum(1, (0.07 - bt) / 0.01)
    beep = lp(beep, 6000)
    n = secs(1.6)
    t = t_axis(n)
    step = 520 * (1 + 0.02 * np.sin(2 * np.pi * 9 * t))
    ph = 2 * np.pi * np.cumsum(step) / SR
    motor = (np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.25 * np.sign(np.sin(4 * ph))) * 0.12
    paper = bp(noise(n, 680), 2000, 9000) * 0.05
    env = np.minimum(1, t / 0.03) * np.minimum(1, (1.6 - t) / 0.03)
    whir = lp(motor + paper, 7000) * env
    m = secs(0.18)
    tear = bp(noise(m, 681), 1500, 9000) * np.linspace(0.4, 1, m) * (S.rng(682).random(m) < 0.35) * 0.9
    tear = tear * np.minimum(1, (0.18 - t_axis(m)) / 0.02)
    x = C.mix(2.6, [(0.02, beep, 1.0), (0.17, beep, 1.0), (0.45, whir, 1.0), (2.2, tear, 1.0)])
    return fade(C.room(x, 0.2, 0.1, 5000, 683), 0, 0.05)


def render_kerb():
    S.save(f"{OUT}/traffic_hazard_tick_loop", hazard_tick_loop(), "peak", quality=3)
    S.save(f"{OUT}/traffic_van_slide_door_open", van_slide(True), "peak", quality=4)
    S.save(f"{OUT}/traffic_van_slide_door_close", van_slide(False), "peak", quality=4)
    S.save(f"{OUT}/traffic_van_rear_door_open", van_rear(True), "peak", quality=4)
    S.save(f"{OUT}/traffic_van_rear_door_close", van_rear(False), "peak", quality=4)
    S.save(f"{OUT}/traffic_trolley_roll_loop", trolley_roll_loop(), "peak", quality=3, rate=32000)
    # Taxis: a mid-size sedan door, a little heavier than the 500's.
    for v in range(3):
        S.save(f"{OUT}/traffic_taxi_door_close_0{v + 1}", C.door_close_modern(v, 1.15, seed=2000), "peak", quality=4)
    S.save(f"{OUT}/traffic_taxi_door_open", C.door_open_modern(0, 1.1, seed=2050), "peak", quality=4)
    S.save(f"{OUT}/traffic_ticket_printer", ticket_printer(), "peak", quality=4)


def main(argv=()):
    if "city" in argv:
        render_city()
        return
    if "people" in argv:
        render_people()
        return
    if "kerb" in argv:
        render_kerb()
        return
    try:
        render_horns()
    except C.MissingHornSource as e:
        print(f"skipping the traffic horns, keeping the committed ones: {e}")
    render_bus()
    render_trains()
    render_city()
    render_people()
    render_kerb()
    render_engines()


if __name__ == "__main__":
    main(sys.argv[1:])
