"""Physically flavoured engine synthesiser.

The idea: an engine is a train of combustion pulses, one per cylinder per
two crank revolutions (four-stroke). Each pulse is a short pressure spike
that rings through the exhaust pipes (tube resonances) and the silencer
(a low-pass with a chamber resonance) before it reaches the listener. On top
of that sit mechanical noise (valve train ticks, block resonance), intake
roar, and per-engine extras (turbo whistle, cooling fan, tinny classic
sheet metal).

Small irregularities are what make it sound like an engine rather than a
buzzer: every cylinder has its own pulse strength and timing offset, every
firing varies a little from the last, and lifting off (overrun) makes the
firing weak and ragged.

Two renderers share the same model:
  render_loop()     constant RPM, exactly periodic, seamless at the join
  render_curve()    RPM and load following a curve (start-up, gear change)
Filters are causal IIRs; for loops the excitation is filtered twice round so
the filter state wraps across the join.
"""
from __future__ import annotations

import zlib
from dataclasses import dataclass, replace

import numpy as np
from scipy import signal

import sfxlib as S

SR = S.SR


@dataclass
class Engine:
    name: str
    cylinders: int = 4
    idle: float = 850
    redline: float = 6000
    # Exhaust
    pipe_ms: tuple = (10.5, 6.2)        # round-trip delays of the two pipe sections
    pipe_fb: tuple = (0.45, 0.35)       # feedback of each section (how "tubey")
    muffler_hz: float = 520             # silencer low-pass corner
    muffler_order: int = 2
    chamber_hz: float = 180             # silencer chamber resonance
    chamber_db: float = 5.0
    lowcut_hz: float = 22               # radiation high-pass
    pulse_ms: float = 0.55              # combustion pulse rise time
    rasp: float = 0.10                  # turbulent high-frequency exhaust noise
    rasp_band: tuple = (900, 4500)
    drive: float = 1.2                  # saturation of the exhaust note
    # Per-cylinder irregularity
    cyl_gain_spread: float = 0.08
    cyl_time_spread: float = 0.035      # fraction of the firing interval
    jitter_on: float = 0.06             # firing-to-firing amplitude variation on load
    jitter_off: float = 0.35            # ...and on overrun
    misfire_off: float = 0.06           # chance of a near-silent firing on overrun
    # Mechanical and intake
    mech: float = 0.12                  # valve ticks + block resonance
    block_modes: tuple = (1150, 2300, 3700)
    valves_per_cyl: int = 2
    intake: float = 0.08                # intake roar (on load, rising with rpm)
    intake_band: tuple = (700, 2600)
    whine: float = 0.015                # belt/alternator whine
    whine_ratio: float = 2.6            # whine freq = crank Hz * ratio * 10
    # Extras
    turbo: float = 0.0                  # turbo whistle level (on load)
    turbo_hz_at_redline: float = 7000
    fan: float = 0.0                    # air-cooled fan whirr
    fan_blades: int = 9
    tin: float = 0.0                    # tinny sheet-metal ring (classics)
    tin_modes: tuple = (620, 1340, 2150, 3050)
    overrun_pops: float = 0.0           # crackles on overrun (sport exhausts, Abarth)
    body: float = 1.0                   # rounded low pulse (fundamental)
    body_k: float = 2.2                 # body pulse corner, x firing frequency
    sharp: float = 0.6                  # sharp pulse through the pipes (harmonics)
    air_hz: float = 7000                # distance/air absorption roll-off
    level_curve: float = 0.8            # how much louder it gets with rpm
    load_db: float = 7.0                # on-load vs off-load level difference


# --------------------------------------------------------------------------
# Excitation
# --------------------------------------------------------------------------

def _pulse_kernel(e: Engine, load: float) -> np.ndarray:
    """One combustion pressure pulse: fast rise, decay, rarefaction dip."""
    tau = e.pulse_ms / 1000 * (1.15 - 0.3 * load)
    n = S.secs(tau * 14)
    t = np.arange(n) / SR
    p = (t / tau) * np.exp(1 - t / tau)
    dip = -0.42 * (t / (2.6 * tau)) * np.exp(1 - t / (2.6 * tau))
    k = p + dip
    return k - k.mean()


def _events(n_samples: int, rpm_curve: np.ndarray, e: Engine, load_curve: np.ndarray,
            seed: int, periodic: bool):
    """Firing times (fractional samples), cylinder index and amplitude."""
    r = np.random.default_rng(seed)
    # Crank phase in revolutions; one firing every 2/cyl revolutions.
    revs = np.cumsum(rpm_curve / 60 / SR)
    per_fire = 2 / e.cylinders
    n_fire = int(revs[-1] / per_fire)
    fire_rev = (np.arange(n_fire) + 0.5) * per_fire
    times = np.interp(fire_rev, revs, np.arange(n_samples))
    cyl = np.arange(n_fire) % e.cylinders
    cr = np.random.default_rng(zlib.crc32(e.name.encode()))
    cyl_gain = 1 + e.cyl_gain_spread * cr.uniform(-1, 1, e.cylinders)
    cyl_off = e.cyl_time_spread * cr.uniform(-1, 1, e.cylinders)
    interval = SR * 60 / np.maximum(rpm_curve, 50) * per_fire
    ti = np.clip(times.astype(int), 0, n_samples - 1)
    times = times + cyl_off[cyl] * interval[ti]
    load = load_curve[ti]
    jit = e.jitter_on * load + e.jitter_off * (1 - load)
    amp = cyl_gain[cyl] * np.clip(1 + jit * r.standard_normal(n_fire), 0.05, None)
    mis = r.random(n_fire) < e.misfire_off * (1 - load)
    amp[mis] *= 0.12
    # Overrun amplitude is weaker; load raises pressure.
    amp *= 0.35 + 0.65 * load
    if periodic:
        times = np.mod(times, n_samples)
    return times, cyl, amp, load


def _impulses(n, times, amps, periodic):
    x = np.zeros(n + 2)
    i = np.floor(times).astype(int)
    f = times - i
    np.add.at(x, i, amps * (1 - f))
    np.add.at(x, i + 1, amps * f)
    if periodic:
        x[0] += x[n]
        x[1] += x[n + 1]
    return x[:n]


def _filt(b, a, x, periodic):
    """Causal IIR; for loops, run twice round so state wraps across the join."""
    if periodic:
        y = signal.lfilter(b, a, np.concatenate([x, x, x]))
        return y[2 * len(x):]
    return signal.lfilter(b, a, x)


def _sos(sos, x, periodic):
    if periodic:
        y = signal.sosfilt(sos, np.concatenate([x, x, x]))
        return y[2 * len(x):]
    return signal.sosfilt(sos, x)


def _comb(x, delay_ms, fb, periodic, damp_hz=2500):
    """Pipe section: feedback comb with a gentle low-pass in the loop,
    approximated by a comb followed by smoothing of the feedback."""
    d = max(1, int(round(delay_ms / 1000 * SR)))
    # One-pole low-pass inside the feedback loop: H = 1 / (1 - fb * z^-d * lp(z))
    a1 = np.exp(-2 * np.pi * damp_hz / SR)
    # lp(z) = (1-a1) / (1 - a1 z^-1); combine into one rational function:
    # y(1 - a1 z^-1) - fb(1-a1) z^-d y = x(1 - a1 z^-1)
    den = np.zeros(d + 1)
    den[0] = 1
    den[1] -= a1
    den[d] -= fb * (1 - a1)
    num = np.array([1, -a1])
    return _filt(num, den, x, periodic) * (1 - fb)


def _resbank(x, freqs, q, periodic):
    out = np.zeros_like(x)
    for i, f in enumerate(freqs):
        w0 = 2 * np.pi * f / SR
        alpha = np.sin(w0) / (2 * q)
        b = [alpha, 0, -alpha]
        a = [1 + alpha, -2 * np.cos(w0), 1 - alpha]
        out += _filt(b, a, x, periodic) / (1 + 0.4 * i)
    return out


def _peq(x, f0, gain_db, q, periodic):
    A = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * A, -2 * np.cos(w0), 1 - alpha * A]
    a = [1 + alpha / A, -2 * np.cos(w0), 1 - alpha / A]
    return _filt(b, a, x, periodic)


def _noise(n, seed, periodic):
    return np.random.default_rng(seed).standard_normal(n)


def _tv_lp2(x, fc, periodic):
    """Two cascaded one-pole low-passes whose corner follows fc (per sample).
    Turns the firing impulses into rounded pressure pulses whose width
    scales with the firing interval, as at a real tailpipe."""
    a = np.exp(-2 * np.pi * np.asarray(fc) / SR)
    if np.ndim(a) == 0:
        a = np.full(len(x), float(a))
    xs = np.concatenate([x, x, x]) if periodic else x
    aa = np.concatenate([a, a, a]) if periodic else a
    y = np.empty_like(xs)
    s1 = s2 = 0.0
    for i in range(len(xs)):
        s1 = aa[i] * s1 + (1 - aa[i]) * xs[i]
        s2 = aa[i] * s2 + (1 - aa[i]) * s1
        y[i] = s2
    return y[2 * len(x):] if periodic else y


def _env_from_impulses(imp, decay_ms, periodic):
    """Envelope that jumps at each firing and decays: drives noise layers."""
    a = np.exp(-1 / (decay_ms / 1000 * SR))
    return _filt([1 - a], [1, -a], np.abs(imp), periodic)


# --------------------------------------------------------------------------
# Full render
# --------------------------------------------------------------------------

def render(e: Engine, rpm: np.ndarray, load: np.ndarray, seed: int = 1,
           periodic: bool = False, layers: dict | None = None) -> np.ndarray:
    """Render an engine following per-sample rpm and load (0..1) curves."""
    n = len(rpm)
    times, cyl, amp, ld = _events(n, rpm, e, load, seed, periodic)
    lv = layers or {}

    # Two pulse trains (light and heavy combustion) blended by load, so the
    # pulse shape gets sharper and brighter as load increases.
    imp_on = _impulses(n, times, amp * ld, periodic)
    imp_off = _impulses(n, times, amp * (1 - ld), periodic)
    k_on, k_off = _pulse_kernel(e, 1.0), _pulse_kernel(e, 0.0)
    if periodic:
        exc = S.circ_convolve(imp_on, k_on) + S.circ_convolve(imp_off, k_off)
    else:
        exc = signal.fftconvolve(imp_on, k_on)[:n] + signal.fftconvolve(imp_off, k_off)[:n]

    # Combustion noise: broadband burst at each firing, part of the exhaust gas.
    imp_all = imp_on + imp_off
    env_fast = _env_from_impulses(imp_all, 1.8, periodic)
    burst = _noise(n, seed + 11, periodic) * env_fast
    exc = exc + 0.18 * _sos(signal.butter(2, [150, 3000], "bandpass", fs=SR, output="sos"), burst, periodic)

    # Body: rounded pulses (width ~ a fraction of the firing interval) carry
    # the fundamental "putt" that dominates a small engine heard outside.
    fire_hz = rpm / 60 * e.cylinders / 2
    body = _tv_lp2(imp_all, fire_hz * e.body_k, periodic)
    body = body - _filt([1], [1, -0.999], body, periodic) * 0.001  # DC block
    body /= np.std(body) + 1e-12

    # Exhaust: two pipe sections, silencer, chamber resonance, radiation.
    y = exc / (np.std(exc) + 1e-12) * e.sharp + body * e.body
    for d, fb in zip(e.pipe_ms, e.pipe_fb):
        y = _comb(y, d, fb, periodic)
    y = _sos(signal.butter(e.muffler_order, e.muffler_hz, "lowpass", fs=SR, output="sos"), y, periodic)
    y = _peq(y, e.chamber_hz, e.chamber_db, 1.4, periodic)
    y = _sos(signal.butter(2, e.lowcut_hz, "highpass", fs=SR, output="sos"), y, periodic)
    y = y / (np.std(y) + 1e-12)
    y = np.tanh(y * e.drive * 0.5) / 0.5

    # Rasp: turbulent gas noise through the tailpipe, gated by the pulses.
    env_rasp = _env_from_impulses(imp_all, 3.5, periodic)
    env_rasp /= np.max(env_rasp) + 1e-12
    rasp = _sos(signal.butter(2, list(e.rasp_band), "bandpass", fs=SR, output="sos"),
                _noise(n, seed + 3, periodic), periodic) * env_rasp
    rasp = rasp / (np.std(rasp) + 1e-12)

    # Mechanical: valve ticks (two clicks per valve event, every cam turn)
    # and the block ringing from each combustion.
    crank_hz = rpm / 60
    mech_imp = np.zeros(n)
    revs = np.cumsum(crank_hz / SR)
    n_valve = int(revs[-1] / 2 * e.cylinders * e.valves_per_cyl)
    if n_valve > 0:
        vr = (np.arange(n_valve) + 0.25) * 2 / (e.cylinders * e.valves_per_cyl)
        vt = np.interp(vr, revs, np.arange(n))
        va = np.random.default_rng(seed + 5).uniform(0.4, 1.0, n_valve)
        if periodic:
            vt = np.mod(vt, n)
        mech_imp = _impulses(n, vt, va, periodic)
    ticks = _sos(signal.butter(2, [2500, 9000], "bandpass", fs=SR, output="sos"),
                 _filt([1], [1, -0.6], mech_imp, periodic), periodic)
    block = _resbank(imp_all + 0.3 * mech_imp, e.block_modes, 18, periodic)
    mech = ticks / (np.std(ticks) + 1e-12) * 0.6 + block / (np.std(block) + 1e-12)

    # Intake roar: band of noise, pulsing with the firing, strongest on load.
    inh = _sos(signal.butter(2, list(e.intake_band), "bandpass", fs=SR, output="sos"),
               _noise(n, seed + 7, periodic), periodic)
    inh = inh * (0.5 + 0.5 * _env_from_impulses(imp_all, 6, periodic) / (np.max(np.abs(imp_all)) + 1e-12))
    inh /= np.std(inh) + 1e-12

    rpm_norm = np.clip((rpm - e.idle) / (e.redline - e.idle), 0, 1.2)
    out = y
    out = out + e.rasp * rasp * (0.4 + 0.6 * load) * (0.5 + rpm_norm) * 3
    out = out + e.mech * mech * (1.2 - 0.5 * load) * 1.5
    out = out + e.intake * inh * load * (0.2 + rpm_norm) * 2

    # Whine: a faint tone locked to the crank (timing belt / alternator).
    phase = 2 * np.pi * np.cumsum(crank_hz * e.whine_ratio * 10 / SR)
    if periodic:
        # Snap to a whole number of cycles over the loop for a clean join.
        cycles = round(phase[-1] / (2 * np.pi))
        phase = phase * (cycles * 2 * np.pi) / phase[-1]
    out = out + e.whine * np.sin(phase) * 3

    if e.turbo > 0:
        boost = np.clip(load * (rpm_norm * 1.4 - 0.15), 0, 1)
        if not periodic:
            boost = signal.lfilter([0.0004], [1, -0.9996], boost)  # spool lag
        f = 1500 + e.turbo_hz_at_redline * rpm_norm
        ph = 2 * np.pi * np.cumsum(f / SR)
        if periodic:
            cycles = round(ph[-1] / (2 * np.pi))
            ph = ph * (cycles * 2 * np.pi) / ph[-1]
        hiss = _sos(signal.butter(2, [2000, 9000], "bandpass", fs=SR, output="sos"),
                    _noise(n, seed + 9, periodic), periodic)
        whistle = np.sin(ph) * 0.5 + 0.25 * np.sin(2.01 * ph) + 0.6 * hiss / (np.std(hiss) + 1e-12)
        out = out + e.turbo * whistle * boost * 2.5

    if e.fan > 0:
        blade_hz = crank_hz * 1.6 * e.fan_blades
        ph = 2 * np.pi * np.cumsum(blade_hz / SR)
        if periodic:
            cycles = round(ph[-1] / (2 * np.pi))
            ph = ph * (cycles * 2 * np.pi) / ph[-1]
        air = _sos(signal.butter(2, [400, 5000], "bandpass", fs=SR, output="sos"),
                   _noise(n, seed + 13, periodic), periodic)
        air /= np.std(air) + 1e-12
        fan = air * (1 + 0.5 * np.sin(ph)) * 0.6 + 0.25 * np.sin(ph)
        out = out + e.fan * fan * (0.3 + rpm_norm)

    if e.tin > 0:
        tin = _resbank(imp_all + 0.6 * mech_imp, e.tin_modes, 30, periodic)
        out = out + e.tin * tin / (np.std(tin) + 1e-12)

    if e.overrun_pops > 0:
        out = out + _overrun_pops(n, rpm_norm, load, e, seed, periodic)

    # Level: louder with revs and with load.
    level = (0.35 + e.level_curve * rpm_norm) * 10 ** (-(1 - load) * e.load_db / 20)
    out = out * level
    out = _sos(signal.butter(1, 22, "highpass", fs=SR, output="sos"), out, periodic)
    out = _sos(signal.butter(2, e.air_hz, "lowpass", fs=SR, output="sos"), out, periodic)
    return out


def _overrun_pops(n, rpm_norm, load, e: Engine, seed, periodic):
    """Unburnt fuel igniting in the hot exhaust when the throttle shuts."""
    r = np.random.default_rng(seed + 21)
    out = np.zeros(n)
    rate = e.overrun_pops * 9 * (1 - load) * (0.2 + rpm_norm)  # pops per second
    p = rate / SR
    hits = np.nonzero(r.random(n) < p)[0]
    for h in hits:
        out = S.place(out, pop_sample(r, size=r.uniform(0.3, 1.0)), int(h), wrap=periodic)
    return out


def pop_sample(r: np.random.Generator, size=1.0) -> np.ndarray:
    """One backfire pop/crackle: sharp crack plus a short boomy tail."""
    n = S.secs(0.09 + 0.12 * size)
    t = np.arange(n) / SR
    crack = r.standard_normal(n) * np.exp(-t / (0.0025 + 0.003 * size))
    crack = S.bp(crack, 400, 7000)
    boom = r.standard_normal(n) * np.exp(-t / (0.02 + 0.03 * size))
    boom = S.lp(boom, 450, 2)
    x = crack * 3 + boom * 2.5 * size
    return x / (np.max(np.abs(x)) + 1e-12) * 3.0 * size


# --------------------------------------------------------------------------
# Convenience wrappers
# --------------------------------------------------------------------------

def loop_length(rpm: float, cylinders: int, target_s: float = 3.0) -> tuple[int, float]:
    """Sample count holding an exact whole number of engine cycles, and the
    adjusted rpm that makes it exact."""
    cycle_s = 120 / rpm
    ncyc = max(1, round(target_s / cycle_s))
    n = int(round(ncyc * cycle_s * SR))
    exact_rpm = ncyc * 120 / (n / SR)
    return n, exact_rpm


def render_loop(e: Engine, rpm: float, load: float, seed: int = 1, seconds: float = 3.0):
    n, exact = loop_length(rpm, e.cylinders, seconds)
    return render(e, np.full(n, exact), np.full(n, float(load)), seed=seed, periodic=True)


def curve(points, n_s: float) -> np.ndarray:
    """Piecewise-linear curve from [(time_s, value), ...] at SR."""
    n = S.secs(n_s)
    ts = np.array([p[0] for p in points]) * SR
    vs = np.array([p[1] for p in points], dtype=float)
    return np.interp(np.arange(n), ts, vs)


def smooth(x, hz=8):
    return signal.filtfilt(*signal.butter(1, hz, fs=SR), x)


def variant(e: Engine, kind: str) -> Engine:
    """Exhaust upgrades: sport (freer, louder, a bit raspier) and
    straight-through (no silencer to speak of: loud, raw, crackly)."""
    if kind == "stock":
        return e
    if kind == "sport":
        return replace(e, name=e.name + "_sport", muffler_hz=e.muffler_hz * 1.7,
                       chamber_db=e.chamber_db + 2, rasp=e.rasp * 2.0, drive=e.drive * 1.5,
                       pipe_fb=tuple(min(0.7, f * 1.2) for f in e.pipe_fb),
                       overrun_pops=max(e.overrun_pops, 0.25), lowcut_hz=e.lowcut_hz * 0.85)
    if kind == "straight":
        return replace(e, name=e.name + "_straight", muffler_hz=e.muffler_hz * 3.2,
                       muffler_order=1, chamber_db=e.chamber_db - 2, rasp=e.rasp * 3.5,
                       drive=e.drive * 2.4, rasp_band=(700, 6500),
                       pipe_fb=tuple(min(0.78, f * 1.45) for f in e.pipe_fb),
                       overrun_pops=max(e.overrun_pops * 2, 0.6), lowcut_hz=e.lowcut_hz * 0.75)
    raise ValueError(kind)


# --------------------------------------------------------------------------
# Engine families (see the plan's engine table)
# --------------------------------------------------------------------------

FAMILIES: dict[str, Engine] = {
    # 2013 Pop: 1.2 8v Fire four. Buzzy, honest, a bit strained.
    "fire12": Engine("fire12", 4, 850, 6000, pipe_ms=(10.8, 5.9), pipe_fb=(0.42, 0.33),
                     muffler_hz=450, chamber_hz=170, chamber_db=0.5, pulse_ms=0.6,
                     body=2.0, sharp=0.3, rasp=0.08, mech=0.07, intake=0.10, intake_band=(600, 2200),
                     whine=0.004, level_curve=0.9, load_db=6),
    # 1.4 16v: smoother and revvier, slight induction rasp.
    "fire14": Engine("fire14", 4, 800, 6800, pipe_ms=(9.6, 5.1), pipe_fb=(0.38, 0.30),
                     muffler_hz=640, chamber_hz=190, chamber_db=3.5, pulse_ms=0.5,
                     cyl_gain_spread=0.05, cyl_time_spread=0.02, jitter_on=0.04,
                     rasp=0.09, mech=0.10, valves_per_cyl=4, intake=0.18,
                     intake_band=(900, 3200), whine=0.010, level_curve=1.0),
    # TwinAir 0.9: lumpy two-cylinder thrum, motorbike-like, faint turbo.
    "twinair": Engine("twinair", 2, 900, 6000, pipe_ms=(12.5, 7.4), pipe_fb=(0.50, 0.38),
                      muffler_hz=480, chamber_hz=140, chamber_db=5, pulse_ms=0.75,
                      cyl_gain_spread=0.06, cyl_time_spread=0.02, jitter_on=0.07,
                      rasp=0.10, mech=0.12, valves_per_cyl=4, intake=0.10,
                      turbo=0.05, turbo_hz_at_redline=6000, lowcut_hz=38,
                      level_curve=0.85, drive=1.5),
    # T-Jet 1.4 turbo (Abarth 500/595/695): growly, loud, spool, crackles.
    "tjet": Engine("tjet", 4, 850, 6500, pipe_ms=(9.0, 6.8), pipe_fb=(0.52, 0.40),
                   muffler_hz=820, chamber_hz=150, chamber_db=6, pulse_ms=0.5,
                   cyl_gain_spread=0.07, rasp=0.16, rasp_band=(800, 5000), mech=0.08,
                   valves_per_cyl=4, intake=0.12, turbo=0.09, turbo_hz_at_redline=8000,
                   overrun_pops=0.35, lowcut_hz=35, drive=2.2, level_curve=0.9, load_db=8),
    # Classic air-cooled twin (Nuova, D, F, L, R, Giardiniera): rattly
    # sewing-machine clatter, fan whirr, tinny exhaust, very little bass.
    "classic": Engine("classic", 2, 800, 5000, pipe_ms=(6.0, 3.4), pipe_fb=(0.40, 0.30),
                      muffler_hz=900, muffler_order=1, chamber_hz=320, chamber_db=6,
                      lowcut_hz=110, pulse_ms=0.45, cyl_gain_spread=0.14,
                      cyl_time_spread=0.05, jitter_on=0.12, jitter_off=0.45,
                      misfire_off=0.10, rasp=0.10, rasp_band=(1200, 5500), mech=0.32,
                      block_modes=(1500, 2700, 4100), intake=0.06, whine=0.0,
                      fan=0.22, fan_blades=9, tin=0.22, level_curve=0.7, drive=1.6),
    # Classic Abarth 595/695: the same clatter but rorty and angry.
    "classicabarth": Engine("classicabarth", 2, 900, 6500, pipe_ms=(7.5, 4.2),
                            pipe_fb=(0.55, 0.42), muffler_hz=1900, muffler_order=1,
                            chamber_hz=260, chamber_db=5, lowcut_hz=75, pulse_ms=0.4,
                            cyl_gain_spread=0.12, cyl_time_spread=0.04, jitter_on=0.10,
                            jitter_off=0.5, misfire_off=0.12, rasp=0.30,
                            rasp_band=(800, 6500), mech=0.24, block_modes=(1500, 2700, 4100),
                            intake=0.14, intake_band=(800, 3000), whine=0.0, fan=0.15,
                            tin=0.12, overrun_pops=0.5, level_curve=0.85, drive=2.8),
}

# Plan table names, for the docs.
FAMILY_INFO = {
    "fire12": ("Fire 1.2 8v", "500 Pop (and Hybrid)", "P1"),
    "fire14": ("1.4 16v", "Lounge, Sport", "P2"),
    "twinair": ("TwinAir 0.9", "TwinAir", "P2"),
    "tjet": ("T-Jet 1.4 turbo", "Abarth 500, 595, 695", "P2"),
    "classic": ("Classic twin, air-cooled", "Nuova, Sport, D, F, L, R, Giardiniera, Jolly", "P2"),
    "classicabarth": ("Classic Abarth", "Abarth 595 and 695 classics", "P3"),
}
