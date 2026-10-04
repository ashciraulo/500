"""Render every engine set: RPM loops, one-shots, exhaust variants, extras.

    python3 audio/tools/gen_engines.py               # everything
    python3 audio/tools/gen_engines.py fire12 tjet   # only these families

Output layout (audio/engine/<set>/):
    eng_<set>_onload_<rpm>.ogg    accelerating, under load (seamless loop)
    eng_<set>_offload_<rpm>.ogg   lifting off / overrun     (seamless loop)
    eng_<set>_startup.ogg / _shutdown.ogg / _limiter.ogg     one-shots
<set> is a family (fire12, fire14, twinair, tjet, classic, classicabarth,
electric, abarthe) optionally followed by an exhaust variant: fire12sport,
fire12straight, ... The game reads the RPM points straight from the file
names, so loops can be added, removed or replaced freely. For the electric
sets the number is road speed in km/h instead of RPM.

All loops in one set share a single gain, so their relative loudness (idle
vs redline, on vs off load) is preserved. Everything is mono: the game
positions the engine in 3D.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).resolve().parent))
import engine_synth as E  # noqa: E402
import sfxlib as S  # noqa: E402

SR = S.SR
PEAK = 10 ** (-1 / 20)


def rpm_points(e: E.Engine) -> list[int]:
    pts = [int(e.idle)] + list(range(1500, int(e.redline), 1000))
    if e.redline - pts[-1] < 400:
        pts[-1] = int(e.redline)
    else:
        pts.append(int(e.redline))
    return pts


def save_set(folder: str, items: dict[str, np.ndarray], gain: float | None = None):
    """Normalise a whole set with one gain (loudest item at -1 dBTP), or with
    the gain given (so exhaust variants keep their level relative to stock)."""
    if gain is None:
        gain = set_gain(items)
    for name, x in items.items():
        S.save(f"engine/{folder}/{name}", x * gain, norm="none")


def set_gain(items: dict[str, np.ndarray]) -> float:
    return PEAK / max(S.true_peak(x) for x in items.values())


# Exhaust variants are louder than stock by this much.
VARIANT_DB = {"stock": 0.0, "sport": 3.0, "straight": 6.0}


# --------------------------------------------------------------------------
# Combustion engines
# --------------------------------------------------------------------------

def starter_motor(n: int, crank_rpm: float, cyl: int, seed: int, classic=False) -> np.ndarray:
    """Starter motor whine and gear rasp, slowed by each compression stroke."""
    r = np.random.default_rng(seed)
    t = S.t_axis(n)
    comp_hz = crank_rpm / 60 * cyl / 2
    jitter = 1 + 0.04 * S.smooth_noise(n, 3, seed=seed, periodic=False)
    comp_phase = np.cumsum(comp_hz * jitter / SR)
    comp = (np.sin(2 * np.pi * comp_phase) + 1) / 2
    comp = comp ** 3  # sharp slow-downs at each compression
    speed = 1 - (0.28 if classic else 0.18) * comp
    f0 = (420 if classic else 560) * speed
    ph = 2 * np.pi * np.cumsum(f0 / SR)
    whine = sum(np.sin(k * ph) / k ** 1.2 for k in range(1, 9))
    gear = S.bp(r.standard_normal(n), 1500, 6000) * (0.6 + 0.4 * speed)
    thud = S.lp(r.standard_normal(n), 220, 2) * comp * 3
    x = whine * 0.35 + gear * 0.18 + thud * 0.5
    if classic:
        x += S.resonator(r.standard_normal(n) * comp, 900, 8) * 0.8  # tinny body
    return x


def startup(e: E.Engine, seed=11) -> np.ndarray:
    classic = e.cylinders == 2 and e.fan > 0
    crank_s = 1.4 if classic else 0.75
    catch_s = 3.6
    n_crank = S.secs(crank_s)
    crank = starter_motor(n_crank, 230 if not classic else 180, e.cylinders, seed, classic)
    crank = S.fade(crank, 0.02, 0.06)
    # Catch: a flare to ~1.6x idle, then settle to a slightly fast cold idle.
    pts = [(0, 300), (0.12, e.idle * 1.15), (0.45, e.idle * 1.65), (1.0, e.idle * 1.3),
           (2.2, e.idle * 1.08), (catch_s, e.idle)]
    rpm = E.smooth(E.curve(pts, catch_s), 6)
    load = E.smooth(E.curve([(0, 0.6), (0.35, 0.7), (0.6, 0.15), (catch_s, 0.1)], catch_s), 10)
    run = E.render(e, rpm, load, seed=seed)
    run[: S.secs(0.03)] *= np.linspace(0, 1, S.secs(0.03))
    out = np.zeros(n_crank + len(run) - S.secs(0.1))
    out = S.place(out, crank * 0.5 * np.std(run) / (np.std(crank) + 1e-12) * 1.8, 0)
    out = S.place(out, run, n_crank - S.secs(0.1))
    return out


def shutdown(e: E.Engine, seed=12) -> np.ndarray:
    dur = 1.6
    rpm = E.smooth(E.curve([(0, e.idle), (0.15, e.idle * 0.95), (0.7, e.idle * 0.35),
                            (0.85, 60), (dur, 1)], dur), 8)
    load = E.curve([(0, 0.1), (0.1, 0.0), (dur, 0.0)], dur)
    x = E.render(e, rpm, load, seed=seed)
    x *= E.curve([(0, 1), (0.6, 0.8), (0.9, 0.2), (1.2, 0)], dur)
    # Final shudder of the engine settling on its mounts.
    r = np.random.default_rng(seed)
    thud = S.lp(r.standard_normal(S.secs(0.3)), 120, 2) * S.env_exp(S.secs(0.3), 0.06)
    S.place(x, thud * np.std(x[: S.secs(0.5)]) * 2.5, S.secs(0.8))
    return S.fade(x, 0, 0.1)


def limiter(e: E.Engine, seed=13) -> np.ndarray:
    """Bouncing off the rev limiter: fuel cut drops load and revs, repeat."""
    dur = 2.0
    bounce_hz = 9 if e.cylinders == 4 else 7
    t = S.t_axis(S.secs(dur))
    saw = (t * bounce_hz) % 1
    rpm = e.redline - 180 * saw
    load = (saw > 0.35).astype(float)
    load = signal.filtfilt(*signal.butter(1, 200, fs=SR), load)
    x = E.render(e, rpm, np.clip(load, 0, 1), seed=seed)
    return S.fade(x, 0.01, 0.15)


def render_family(fam: str, e: E.Engine):
    items = {}
    for rpm in rpm_points(e):
        for kind, ld in (("onload", 1.0), ("offload", 0.0)):
            items[f"eng_{fam}_{kind}_{rpm}"] = E.render_loop(e, rpm, ld, seed=rpm + (7 if ld else 3))
    # Idle is never truly off-load or flat out: light load for both idle loops.
    idle = rpm_points(e)[0]
    items[f"eng_{fam}_onload_{idle}"] = E.render_loop(e, idle, 0.35, seed=idle + 7)
    items[f"eng_{fam}_offload_{idle}"] = E.render_loop(e, idle, 0.12, seed=idle + 3)
    items[f"eng_{fam}_startup"] = startup(e)
    items[f"eng_{fam}_shutdown"] = shutdown(e)
    items[f"eng_{fam}_limiter"] = limiter(e)
    return items


# --------------------------------------------------------------------------
# Electric (500e) and the Abarth 500e sound generator
# --------------------------------------------------------------------------

EV_SPEEDS = [0, 20, 40, 60, 80, 100, 130]


def ev_loop(kmh: float, load: float, seed: int, seconds=3.0) -> np.ndarray:
    """Permanent-magnet motor whine (rising with speed), inverter switching
    tones, gear mesh, and a faint cooling hum. All tones are snapped to whole
    cycles over the loop so it joins without a seam."""
    n = S.secs(seconds)
    t = S.t_axis(n)

    def tone(f, amp):
        f = round(f * seconds) / seconds  # whole cycles in the loop
        return amp * np.sin(2 * np.pi * f * t + 1.3 * f % 6.28)

    motor_hz = kmh * 9.6  # electrical frequency of the motor
    x = np.zeros(n)
    if kmh > 0:
        for k, a in ((1, 0.25), (2, 0.10), (6, 0.55), (12, 0.25), (18, 0.08)):
            x += tone(motor_hz * k / 4, a * (0.35 + 0.65 * load))
        # Gear mesh whine of the single reduction gear.
        x += tone(kmh * 31.0, 0.18 * (0.3 + 0.7 * load))
    # Inverter switching: carrier with sidebands at the motor frequency;
    # loudest when pulling away at low speed.
    carrier = 2600 if kmh < 30 else 5200
    low = np.clip(1 - kmh / 50, 0.15, 1) * (0.2 + 0.8 * load)
    x += tone(carrier, 0.18 * low)
    if kmh > 0:
        x += tone(carrier + motor_hz, 0.08 * low) + tone(carrier - motor_hz, 0.08 * low)
    # Cooling pump / fan hum and a little broadband air.
    x += tone(100, 0.05) + tone(200, 0.03)
    air = S.circ_bp(S.noise(n, seed), 300, 6000) * 0.02 * (0.3 + kmh / 60)
    x += air
    return x


def ev_avas(seed=31) -> np.ndarray:
    """Low-speed pedestrian warning tone (required below ~20 km/h). A soft,
    gently pulsing two-note pad; the game pitches it up with speed."""
    seconds = 4.0
    n = S.secs(seconds)
    t = S.t_axis(n)
    x = np.zeros(n)
    for f, a in ((220, 0.5), (330, 0.35), (440, 0.15), (660, 0.08), (1320, 0.05)):
        x += a * np.sin(2 * np.pi * f * t)
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 1.0 * t)  # 1 Hz, whole cycles
    x = x * trem + S.circ_bp(S.noise(n, seed), 400, 3000) * 0.05
    return x


def ev_startup(seed=32) -> np.ndarray:
    """'Ready' sound: relay clack, a rising inverter sweep and a soft chime."""
    n = S.secs(2.2)
    t = S.t_axis(n)
    r = np.random.default_rng(seed)
    clack = S.bp(r.standard_normal(S.secs(0.05)), 800, 6000) * S.env_exp(S.secs(0.05), 0.006)
    f = 300 + 2400 * np.clip(t / 1.2, 0, 1) ** 1.5
    sweep = np.sin(2 * np.pi * np.cumsum(f / SR)) * 0.12 * np.clip(1 - (t - 1.2) / 0.6, 0, 1) * np.clip(t / 0.2, 0, 1)
    chime = np.zeros(n)
    for f0, at in ((1318.5, 1.25), (1975.5, 1.45)):
        i = S.secs(at)
        m = n - i
        tt = S.t_axis(m)
        chime[i:] += 0.25 * (np.sin(2 * np.pi * f0 * tt) + 0.3 * np.sin(2 * np.pi * 2 * f0 * tt)) * np.exp(-tt / 0.35)
    x = sweep + chime
    S.place(x, clack * 0.8, 0)
    return S.fade(x, 0, 0.05)


def speaker(x: np.ndarray, periodic: bool) -> np.ndarray:
    """Play a sound through a small car speaker: band-limited, a bit
    distorted, slightly digital. Used for the Abarth 500e sound generator."""
    if periodic:
        y = S.circ_bp(x, 140, 6500, order=3)
    else:
        y = S.bp(x, 140, 6500, order=3)
    y = y / (np.max(np.abs(y)) + 1e-12)
    y = np.tanh(y * 2.5)
    y = np.round(y * 48) / 48  # gentle bit-crush
    if periodic:
        y = S.circ_lp(y, 7000)
    else:
        y = S.lp(y, 7000)
    return y


# --------------------------------------------------------------------------
# Shared extras
# --------------------------------------------------------------------------

def gear_clunk(seed: int, classic: bool) -> np.ndarray:
    """Clutch in, lever through the gate, gears engaging."""
    r = np.random.default_rng(seed)
    n = S.secs(0.45)
    x = np.zeros(n)
    # Lever leaving the gear: soft click.
    c1 = S.bp(r.standard_normal(S.secs(0.03)), 1200, 6000) * S.env_exp(S.secs(0.03), 0.004)
    # Dog engagement: metallic clunk with a low body.
    m = S.secs(0.2)
    body = S.lp(r.standard_normal(m), 260, 2) * S.env_exp(m, 0.025)
    ring = sum(S.resonator(r.standard_normal(m) * S.env_exp(m, 0.004), f, 25)
               for f in ((1650, 2900, 4300) if not classic else (950, 2100, 3400)))
    c2 = body * 1.6 + ring * (1.2 if classic else 0.6)
    S.place(x, c1 * 0.5, 0)
    S.place(x, c2, S.secs(0.12 + r.uniform(0, 0.06)))
    return x


def backfire(seed: int) -> np.ndarray:
    r = np.random.default_rng(seed)
    x = np.zeros(S.secs(0.6))
    k = r.integers(1, 4)
    at = 0
    for _ in range(k):
        S.place(x, E.pop_sample(r, size=r.uniform(0.5, 1.0)), at)
        at += S.secs(r.uniform(0.04, 0.12))
    return S.lp(x, 9000)


def turbo_spool(seed=41) -> np.ndarray:
    """Steady turbo whistle loop at mid boost; the game pitches it with boost."""
    seconds = 3.0
    n = S.secs(seconds)
    t = S.t_axis(n)
    f = round(4200 * seconds) / seconds
    wob = 1 + 0.004 * np.sin(2 * np.pi * (round(3 * seconds) / seconds) * t)
    ph = 2 * np.pi * np.cumsum(f * wob / SR)
    ph *= (round(ph[-1] / (2 * np.pi)) * 2 * np.pi) / ph[-1]
    hiss = S.circ_bp(S.noise(n, seed), 2500, 9000)
    return 0.5 * np.sin(ph) + 0.15 * np.sin(2 * ph) + 0.25 * hiss / np.std(hiss)


def turbo_flutter(seed: int) -> np.ndarray:
    """Compressor surge 'chu-chu-chu' when the throttle snaps shut."""
    r = np.random.default_rng(seed)
    n = S.secs(0.7)
    t = S.t_axis(n)
    rate = r.uniform(18, 26) * (1 - 0.4 * t / 0.7)
    flut = (np.sin(2 * np.pi * np.cumsum(rate / SR)) > 0.2).astype(float)
    flut = S.lp(flut, 150)
    air = S.bp(r.standard_normal(n), 900, 5000)
    return air * flut * np.exp(-t / 0.3)


def blowoff(seed: int) -> np.ndarray:
    """Blow-off valve 'pssh': a burst of filtered air with a falling edge."""
    r = np.random.default_rng(seed)
    n = S.secs(0.55)
    t = S.t_axis(n)
    air = r.standard_normal(n)
    sweep = np.zeros(n)
    lo = 1800 + 2500 * np.exp(-t / 0.15)
    # time-varying filter approximated by blending two bands
    a = S.bp(air, 2500, 9000)
    b = S.bp(air, 900, 3500)
    mix = np.clip((lo - 1800) / 2500, 0, 1)
    sweep = a * mix + b * (1 - mix)
    env = np.clip(t / 0.008, 0, 1) * np.exp(-t / 0.16)
    return sweep * env


def gearbox_whine(seed=43) -> np.ndarray:
    """Straight-cut gear whine loop, recorded at a nominal 60 km/h;
    the game pitches it with road speed."""
    seconds = 3.0
    n = S.secs(seconds)
    t = S.t_axis(n)
    x = np.zeros(n)
    for f, a in ((1180, 0.5), (2360, 0.2), (3540, 0.08), (590, 0.12)):
        f = round(f * seconds) / seconds
        x += a * np.sin(2 * np.pi * f * t)
    am = 1 + 0.15 * S.smooth_noise(n, 4, seed=seed)
    return x * am + S.circ_bp(S.noise(n, seed), 800, 4000) * 0.05


def intake_whoosh(seed=44) -> np.ndarray:
    """Pod-filter intake roar loop (tuning layer, faded with throttle)."""
    n = S.secs(3.0)
    x = S.circ_bp(S.pink(n, seed), 250, 3500)
    x = S.circ_filter(x, S.circ_response(n, lambda f: 1 + 2.5 * np.exp(-((f - 900) / 350) ** 2)))
    return x * (1 + 0.2 * S.smooth_noise(n, 2, seed=seed + 1))


def carb_gulp(seed: int) -> np.ndarray:
    """Twin-choke carburettor gulping air on a stab of throttle."""
    r = np.random.default_rng(seed)
    n = S.secs(0.5)
    t = S.t_axis(n)
    air = S.bp(r.standard_normal(n), 200, 2200)
    pulse = 0.6 + 0.4 * np.sin(2 * np.pi * 35 * t)
    body = S.resonator(r.standard_normal(n), 160, 4)
    env = np.clip(t / 0.03, 0, 1) * np.exp(-t / 0.18)
    return (air * pulse + body * 1.5) * env


def starter_no_catch(seed=45) -> np.ndarray:
    """A classic cranking in the rain and refusing to start (~3.5 s)."""
    n = S.secs(3.6)
    x = starter_motor(n, 165, 2, seed, classic=True)
    # Battery sagging: the cranking slows and stumbles.
    x *= E.curve([(0, 1), (2.8, 0.9), (3.4, 0.6), (3.6, 0)], 3.6)
    # One weak cough part way through, then nothing.
    r = np.random.default_rng(seed)
    S.place(x, E.pop_sample(r, 0.35) * 0.4, S.secs(1.7))
    return S.fade(x, 0.02, 0.1)


def startstop(seed=46) -> np.ndarray:
    """Hybrid stop-start restart: a short belt-starter chirp and a quick catch."""
    e = E.FAMILIES["fire12"]
    n = S.secs(0.25)
    chirp = starter_motor(n, 320, 4, seed) * 0.4
    run = startup(e, seed)[S.secs(0.6):]
    run = run[: S.secs(1.8)]
    run[: S.secs(0.02)] *= np.linspace(0, 1, S.secs(0.02))
    out = np.zeros(len(run) + n)
    S.place(out, chirp * np.std(run) / np.std(chirp), 0)
    S.place(out, run, n - S.secs(0.05))
    return S.fade(out, 0, 0.2)


def render_extras():
    items = {}
    for i in range(4):
        items[f"eng_gear_clunk_modern_0{i + 1}"] = gear_clunk(100 + i, False)
        items[f"eng_gear_clunk_classic_0{i + 1}"] = gear_clunk(200 + i, True)
    for i in range(5):
        items[f"eng_backfire_0{i + 1}"] = backfire(300 + i)
    for i in range(3):
        items[f"eng_turbo_flutter_0{i + 1}"] = turbo_flutter(400 + i)
        items[f"eng_blowoff_0{i + 1}"] = blowoff(500 + i) * 0.7
        items[f"eng_carb_gulp_0{i + 1}"] = carb_gulp(600 + i)
    for name, x in items.items():
        S.save(f"engine/extras/{name}", x, norm="peak")
    # Loops normalised a little lower so they sit under the engine.
    for name, x in {"eng_turbo_spool": turbo_spool(), "eng_gearbox_whine": gearbox_whine(),
                    "eng_intake_whoosh": intake_whoosh()}.items():
        S.save(f"engine/extras/{name}", x / S.true_peak(x) * 10 ** (-6 / 20), norm="none")
    S.save("engine/extras/eng_starter_crank_classic", starter_no_catch(), norm="peak")
    S.save("engine/fire12/eng_fire12_startstop", startstop(), norm="peak")


def render_electric():
    items = {}
    for v in EV_SPEEDS:
        items[f"eng_electric_onload_{v}"] = ev_loop(v, 1.0, seed=v + 1)
        items[f"eng_electric_offload_{v}"] = ev_loop(v, 0.15, seed=v + 2)
    items["eng_electric_startup"] = ev_startup()
    items["eng_electric_avas"] = ev_avas()
    save_set("electric", items)


def render_abarthe():
    """Abarth 500e: the T-Jet set played through an external speaker."""
    e = E.FAMILIES["tjet"]
    items = {}
    for rpm in rpm_points(e):
        for kind, ld in (("onload", 1.0), ("offload", 0.0)):
            x = E.render_loop(e, rpm, ld, seed=rpm + 17)
            items[f"eng_abarthe_{kind}_{rpm}"] = speaker(x, True) * np.std(x) / 0.3
    items["eng_abarthe_startup"] = speaker(startup(e), False) * 0.5
    items["eng_abarthe_shutdown"] = speaker(shutdown(e), False) * 0.5
    items["eng_abarthe_limiter"] = speaker(limiter(e), False) * 0.5
    save_set("abarthe", items)


def _ref(items):
    """Reference loop for matching variant levels: the mid-range on-load loop."""
    keys = sorted(k for k in items if "_onload_" in k)
    return items[keys[len(keys) // 2]]


def main(argv):
    wanted = set(argv) if argv else None
    for fam, e in E.FAMILIES.items():
        if wanted and fam not in wanted:
            continue
        sets = {}
        for var in ("stock", "sport", "straight"):
            name = fam if var == "stock" else fam + var
            print(f"[{name}]", file=sys.stderr)
            items = render_family(name, E.variant(e, var))
            g = 10 ** (VARIANT_DB[var] / 20)
            sets[name] = {k: v / (np.std(_ref(items)) + 1e-12) * g for k, v in items.items()}
        gain = min(set_gain(v) for v in sets.values())
        for name, items in sets.items():
            save_set(name, items, gain)
    if not wanted or "electric" in wanted:
        print("[electric]", file=sys.stderr)
        render_electric()
    if not wanted or "abarthe" in wanted:
        print("[abarthe]", file=sys.stderr)
        render_abarthe()
    if not wanted or "extras" in wanted:
        print("[extras]", file=sys.stderr)
        render_extras()


if __name__ == "__main__":
    main(sys.argv[1:])
