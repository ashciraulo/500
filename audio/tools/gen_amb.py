#!/usr/bin/env python3
"""Ambience beds, ambience one-shots and night oddities for the Perth game.

Builds audio/amb/*.ogg and audio/oddity/*.ogg from:
  * recordings fetched by fetch_sources.py into build/sources/ (CC0 only,
    see audio/CREDITS.md), cut into short events and re-scattered, and
  * numpy synthesis (wind in the gums, traffic hum, pedestrian crossings,
    sirens, trains, level crossing bells, idles, radio static...).

Beds are stereo seamless loops: every layer is either built circularly (FFT
filters, wrap-around placement) or turned into a loop by an equal-power
crossfade, and recorded events are placed with sfxlib.place(..., wrap=True),
so nothing is cut at the loop point. `check_seam()` verifies each loop.

Deterministic: every random choice uses a fixed seed. Runnable from any cwd:

    python3 audio/tools/fetch_sources.py   # once, downloads the recordings
    python3 audio/tools/gen_amb.py         # everything
    python3 audio/tools/gen_amb.py amb_kingspark_day odd_   # by name prefix
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sfxlib as S  # noqa: E402
from sfxlib import SR, secs  # noqa: E402

SRC = S.AUDIO_ROOT.parent / "build" / "sources"
CACHE = SRC / "_cache"


def db(g):
    return 10 ** (g / 20)


# --------------------------------------------------------------------------
# Source handling
# --------------------------------------------------------------------------

_mem: dict[str, np.ndarray] = {}
USED: set[str] = set()  # source keys touched by the current builder


def src(key: str, stereo=False) -> np.ndarray:
    """Decoded, rumble-filtered recording (48 kHz). Mono unless stereo=True."""
    USED.add(key)
    if key not in _mem:
        f = SRC / f"{key}.mp3"
        if not f.exists():
            sys.exit(f"missing {f}: run audio/tools/fetch_sources.py first")
        c = CACHE / f"{key}.npy"
        if c.exists() and c.stat().st_mtime >= f.stat().st_mtime:
            x = np.load(c).astype(np.float64)
        else:
            x = S.load(f)
            CACHE.mkdir(parents=True, exist_ok=True)
            np.save(c, x.astype(np.float32))
        if x.ndim == 1:
            x = np.stack([x, x], axis=1)
        _mem[key] = S.hp(x, 45, 2)
    x = _mem[key]
    return x if stereo else x.mean(axis=1)


def find_events(x, lo, hi, thresh_db=12.0, min_len=0.2, max_len=8.0,
                gap=0.3, pad=0.08, floor_pct=20):
    """Detect sound events by band energy. Returns [(a, b, score_db)] in
    samples, sorted by time."""
    m = x if x.ndim == 1 else x.mean(axis=1)
    b = S.bp(m, lo, hi, 3)
    hop = SR // 100
    nf = len(b) // hop
    e = np.sqrt(np.mean(b[: nf * hop].reshape(nf, hop) ** 2, axis=1)) + 1e-9
    edb = 20 * np.log10(np.convolve(e, np.ones(5) / 5, mode="same"))
    floor = np.percentile(edb, floor_pct)
    act = (edb > floor + thresh_db).astype(int)
    idx = np.flatnonzero(np.diff(np.concatenate([[0], act, [0]])))
    segs: list[list[int]] = []
    for s, t in zip(idx[::2], idx[1::2]):
        if segs and s - segs[-1][1] < gap * 100:
            segs[-1][1] = t
        else:
            segs.append([s, t])
    out = []
    for s, t in segs:
        if (t - s) / 100 < min_len:
            continue
        t = min(t, s + int(max_len * 100))
        a = max(0, int((s / 100 - pad) * SR))
        bb = min(len(m), int((t / 100 + pad) * SR))
        out.append((a, bb, float(edb[s:t].max() - floor)))
    return out


def cut(x, a, b, fin=0.02, fout=0.06):
    y = x[a:b].copy()
    fin = min(fin, len(y) / SR / 4)
    fout = min(fout, len(y) / SR / 4)
    return S.fade(y, fin, fout)


def snips(key, lo, hi, n=None, best=False, **kw):
    """Cut events out of a recording (mono)."""
    x = src(key)
    ev = find_events(x, lo, hi, **kw)
    if best:
        ev = sorted(ev, key=lambda e: -e[2])
    if n:
        ev = ev[:n]
    return [cut(x, a, b) for a, b, _ in ev]


def rate(x, factor):
    """Resample by factor (>1 = higher and shorter)."""
    n = int(len(x) / factor)
    return np.interp(np.arange(n) * factor, np.arange(len(x)), x)


# --------------------------------------------------------------------------
# Spatial helpers
# --------------------------------------------------------------------------

def distant(s, d, pan=0.0, seed=0, room=1.4):
    """Mono snippet -> stereo, pushed back by distance d (0 near .. 1 far):
    duller, quieter direct sound and more reverb tail."""
    fc = 16000 * (0.15 ** d)
    y = S.lp(s, fc, 2)
    y = np.concatenate([y, np.zeros(secs(room + 0.05))])
    dry = S.pan(y, pan)
    wet = S.reverb(y, size_s=room, damp_hz=max(1500, fc * 0.6), wet=1.0, seed=seed)
    w = 0.12 + 0.55 * d
    return dry * (1 - w) + wet * w * 0.7


def fold(x, n):
    """Wrap anything past the loop length back onto the start (turns a
    linear filter/reverb tail into a circular one)."""
    out = x[:n].copy()
    k = len(x) - n
    while k > 0:
        m = min(k, n)
        out[:m] += x[len(x) - k:len(x) - k + m]
        k -= m
    return out


def pan_sweep(s, p0, p1):
    p = np.linspace(p0, p1, len(s))
    a = (p + 1) * np.pi / 4
    return np.stack([s * np.cos(a), s * np.sin(a)], axis=1)


def texture(x, dur, seed, chunk=20.0, xf=1.5, avoid_peaks_db=None, region=None):
    """Seamless stereo loop of `dur` s woven from random chunks of recording x
    (equal-power crossfades, then the tail crossfaded over the head)."""
    r = np.random.default_rng(seed)
    if region is not None:
        x = x[secs(region[0]):secs(region[1])]
    if x.ndim == 1:
        x = S.stereo(x, 0.6)
    n, xfn = secs(dur) + secs(xf), secs(xf)
    L = min(secs(chunk), len(x))
    ref = None
    if avoid_peaks_db is not None:
        m = x.mean(axis=1)
        hop = SR // 10
        nf = len(m) // hop
        e = 20 * np.log10(np.sqrt(np.mean(m[: nf * hop].reshape(nf, hop) ** 2, 1)) + 1e-9)
        ref = (e, np.median(e) + avoid_peaks_db, hop)
    w = np.sin(np.linspace(0, np.pi / 2, xfn))[:, None]
    out = None
    while out is None or len(out) < n:
        for _ in range(40):
            a = int(r.integers(0, len(x) - L + 1))
            if ref is None:
                break
            e, lim, hop = ref
            if e[a // hop:(a + L) // hop].max() <= lim:
                break
        c = x[a:a + L]
        if out is None:
            out = c.copy()
        else:
            out = np.concatenate([out[:-xfn], out[-xfn:] * np.cos(np.arcsin(w)) + c[:xfn] * w, c[xfn:]])
    return S.make_loop(out[:n], xf)


class Bed:
    """A stereo loop under construction."""

    def __init__(self, dur, seed):
        self.n = secs(dur)
        self.x = np.zeros((self.n, 2))
        self.r = np.random.default_rng(seed)
        self.seed = seed

    def add(self, layer, gain_db=0.0):
        """Add a full-length layer at an RMS level of gain_db dBFS."""
        assert len(layer) == self.n, (len(layer), self.n)
        layer = layer if layer.ndim == 2 else S.stereo(layer)
        self.x += layer / (np.sqrt(np.mean(layer ** 2)) + 1e-12) * db(gain_db)

    def times(self, count, jitter=0.8):
        """`count` start times spread over the loop (jittered grid, random
        phase) so events never clump or leave long holes by accident."""
        r = self.r
        grid = (np.arange(count) + 0.5 + r.uniform(-jitter / 2, jitter / 2, count)) / count
        return ((grid + r.uniform()) % 1.0 * self.n).astype(int)

    def put(self, st, at, gain_db=0.0):
        """Place an event so that its peak sits at gain_db dBFS."""
        st = st / (np.abs(st).max() + 1e-12)
        S.place(self.x, st * db(gain_db), int(at) % self.n, wrap=True)

    def scatter(self, pool, count, gain_db=(-6, 0), dist=(0.2, 0.6), pan=(-0.8, 0.8),
                pitch=0.03, jitter=0.8, room=1.4):
        r = self.r
        for at in self.times(count, jitter):
            s = pool[int(r.integers(len(pool)))]
            if pitch:
                s = rate(s, 1 + r.uniform(-pitch, pitch))
            st = distant(s, r.uniform(*dist), r.uniform(*pan), seed=int(r.integers(1 << 30)), room=room)
            self.put(st, at, r.uniform(*gain_db))


def check_seam(x, name):
    """The jump across the loop point must look like any other sample step,
    and the level either side of it must match."""
    d = np.abs(np.diff(x, axis=0))
    jump = np.abs(x[0] - x[-1]).max()
    p999 = np.percentile(d, 99.9)
    w = secs(0.1)
    ra = 20 * np.log10(np.sqrt(np.mean(x[:w] ** 2)) + 1e-12)
    rb = 20 * np.log10(np.sqrt(np.mean(x[-w:] ** 2)) + 1e-12)
    ok = jump <= max(1.5 * p999, 1e-9) and abs(ra - rb) < 6
    print(f"    seam {name}: jump {jump / (p999 + 1e-12):.2f}x p99.9 step, "
          f"edge rms {rb:.1f}/{ra:.1f} dB -> {'OK' if ok else 'FAIL'}", file=sys.stderr)
    if not ok:
        raise SystemExit(f"loop seam check failed for {name}")


def circ_limit(x, target_lufs=-24.0, ceiling_db=-2.0, iters=3):
    """Bring a loop to target loudness, tucking the few bird-chirp/clatter
    peaks that would exceed the ceiling under it with a gain curve that is
    computed circularly (wrap-mode min filter + circular smoothing), so the
    loop seam is untouched. Returns the limited signal."""
    import pyloudnorm
    from scipy.ndimage import minimum_filter1d, uniform_filter1d
    meter = pyloudnorm.Meter(SR)
    ceil = db(ceiling_db)
    y = x
    for _ in range(iters):
        y = y * db(target_lufs - meter.integrated_loudness(y))
        pk = np.abs(y).max(axis=1) if y.ndim == 2 else np.abs(y)
        g = np.minimum(1.0, ceil / (pk + 1e-12))
        g = minimum_filter1d(g, secs(0.012), mode="wrap")
        g = uniform_filter1d(g, secs(0.006), mode="wrap")
        y = y * (g[:, None] if y.ndim == 2 else g)
    return y


def save_loop(name, x, norm="amb", **enc):
    check_seam(x, name)
    if norm == "amb" or norm.startswith("lufs:"):
        x = circ_limit(x, -24.0 if norm == "amb" else float(norm.split(":")[1]))
        check_seam(x, name + " (limited)")
    S.save(name, x, norm=norm, **enc)


# Leaner encodes for the bed variants and mystery loops (they're long and have
# little above 12-16 kHz), to keep the repository small.
LEAN_WET = dict(quality=0, rate=32000)
LEAN = dict(quality=0, rate=24000)


# --------------------------------------------------------------------------
# Synthesised layers (all circular so they loop by construction)
# --------------------------------------------------------------------------

def gum_wind(n, seed, gust_rate=0.07, level=1.0, crisp=1.0):
    """Wind through eucalyptus: a soft airy hiss, plus the dense dry
    patter of hard, leathery gum leaves knocking together (a Poisson stream
    of tiny clicks whose rate follows the gusts), and a low airy body."""
    r = np.random.default_rng(seed)
    gust = 0.62 + 0.38 * np.tanh(1.1 * S.smooth_noise(n, gust_rate, seed))
    flutter = 1 + 0.18 * S.smooth_noise(n, 0.7, seed + 1)
    chans = []
    for c in range(2):
        g = np.roll(gust, secs(0.9) * c) * flutter
        hiss = S.circ_bp(S.noise(n, seed + 10 + c), 700, 7000, 1)
        dens = 300 + 4000 * g ** 3  # clicks per second
        clicks = (r.random(n) < dens / SR) * r.standard_normal(n) * (0.4 + g)
        leaves = S.circ_filter(clicks, S.circ_response(
            n, lambda f: np.exp(-((np.log2(np.maximum(f, 1) / 4500)) / 0.9) ** 2)))
        body = S.circ_bp(S.noise(n, seed + 40 + c), 100, 600, 1)
        y = hiss * 0.35 * g ** 2 + leaves * 0.9 * crisp * g + body * 0.2 * g ** 2
        chans.append(y)
    return np.stack(chans, axis=1) * level


def city_hum(n, seed, lo=40, hi=350, level=1.0):
    """Broadband distant-traffic rumble with slow swells."""
    sw = 1 + 0.3 * S.smooth_noise(n, 0.05, seed)
    ch = [S.circ_bp(S.pink(n, seed + c), lo, hi, 2) * sw for c in range(2)]
    return np.stack(ch, axis=1) * level


def ac_unit(n, seed, fan_hz=14.0, mains=50.0, level=1.0, rattle=0.0):
    """Rooftop/wall air-con: fan blade thrum + broadband airflow + 100 Hz
    compressor hum (Australian 50 Hz mains)."""
    t = S.t_axis(n)
    # make the fan rate an exact divisor of the loop so it wraps cleanly
    k = max(1, round(fan_hz * n / SR))
    fr = k * SR / n
    air = S.circ_bp(S.noise(n, seed), 150, 3000, 1)
    thr = 1 + 0.35 * np.sin(2 * np.pi * fr * t) + 0.15 * np.sin(4 * np.pi * fr * t + 1)
    km = round(2 * mains * n / SR) * SR / n
    hum = 0.25 * np.sin(2 * np.pi * km * t) + 0.08 * np.sin(4 * np.pi * km * t) + 0.04 * np.sin(6 * np.pi * km * t)
    y = air * thr * 0.6 + hum
    if rattle:
        y += rattle * S.circ_bp(S.noise(n, seed + 1), 800, 2500, 2) * (np.sin(2 * np.pi * fr * t) > 0.92)
    return y * level


def periodic_tone(n, f):
    """Frequency rounded so that a sine of it loops exactly over n samples."""
    return max(1, round(f * n / SR)) * SR / n


def car_pass(dur, seed, speed=16.0, dist=12.0, kind="car", level=1.0):
    """One vehicle passing, mono: tyre roar + engine, distance law + doppler."""
    r = np.random.default_rng(seed)
    n = secs(dur)
    t = S.t_axis(n)
    t0 = dur / 2
    x = speed * (t - t0)
    rr = np.sqrt(dist ** 2 + x ** 2)
    # source signal, then time-warp for doppler
    tyre = S.bp(S.noise(n + secs(1), seed), 200, 3500 if kind != "truck" else 2500, 2)
    rpm_f = {"car": 38, "truck": 22, "bus": 26, "moto": 70}[kind] * r.uniform(0.85, 1.15)
    tt = S.t_axis(n + secs(1))
    eng = sum(np.sin(2 * np.pi * rpm_f * h * tt + r.uniform(0, 6)) / h for h in range(1, 9))
    eng = S.lp(eng * (1 + 0.3 * S.lp(S.noise(len(tt), seed + 1), 30)), 900, 2)
    engw = {"car": 0.35, "truck": 1.0, "bus": 0.8, "moto": 0.9}[kind]
    s = tyre * (1.0 if kind != "moto" else 0.4) + eng * engw
    delay = rr / 343.0
    y = np.interp((t - delay + 0.5) * SR, np.arange(len(s)), s)
    g = (dist / rr) ** 1.1
    y = y * g
    # air absorption: further = duller (blend of two filters)
    y = y * 0.5 + S.lp(y, 1200, 1) * 0.5 * (1 - g) + S.lp(y, 6000, 1) * 0.5 * g
    return S.fade(y, 0.2, 0.2) * level


def pass_stereo(y, flip=False):
    """Pan a pass-by from one side to the other."""
    return pan_sweep(y, 0.85, -0.85) if flip else pan_sweep(y, -0.85, 0.85)


# ---- pedestrian crossing (Australian audio-tactile push button) -----------

def ped_tock(bright=0.0, seed=0):
    """The woody 'tock' of an Australian audio-tactile push-button: a sharp
    click through the button housing (resonances ~1.1 / 2.4 / 3.9 kHz) plus
    a small low knock."""
    n = secs(0.09)
    r = np.random.default_rng(seed)
    exc = np.zeros(n)
    exc[:24] = r.standard_normal(24) * np.hanning(24)
    y = (S.resonator(exc, 1150 * (1 + 0.2 * bright), 9) * 1.0
         + S.resonator(exc, 2450 * (1 + 0.1 * bright), 12) * (0.7 + bright)
         + S.resonator(exc, 3900, 14) * (0.35 + bright * 0.5))
    knock = np.sin(2 * np.pi * 330 * S.t_axis(n)) * S.env_exp(n, 0.008)
    y = y / (np.abs(y).max() + 1e-9) + 0.35 * knock
    return y * S.env_exp(n, 0.012 if bright else 0.02)


def ped_beep():
    """Button-press acknowledgement beep."""
    n = secs(0.16)
    t = S.t_axis(n)
    y = np.tanh(2.5 * np.sin(2 * np.pi * 1320 * t))
    y = S.lp(y, 4000, 2) * S.env_adsr(n, 0.004, 0.02, 0.8, 0.03)
    return y


def ped_sequence(n, locator_period=1.0, walk_at=None, walk_len=7.0, walk_rate=14.0,
                 beep_at=None, seed=0):
    """Mono loop of one crossing: locator tocks, optional button beep, and a
    'walk' phase of rapid ticks. Times in seconds, placed circularly."""
    y = np.zeros(n)
    dur = n / SR
    tock = ped_tock(seed=seed)
    tick = ped_tock(bright=1.0, seed=seed + 1) * 0.9
    k = int(round(dur / locator_period))
    per = dur / k  # exact divisor so the loop is seamless
    walk = []
    if walk_at is not None:
        walk = [(w, w + walk_len) for w in (walk_at if isinstance(walk_at, (list, tuple)) else [walk_at])]
    for i in range(k):
        tt = i * per
        if any(a - 0.3 <= tt < b + 0.3 for a, b in walk):
            continue
        S.place(y, tock, secs(tt), wrap=True)
    for a, b in walk:
        tt = a
        while tt < b:
            S.place(y, tick, secs(tt) % n, wrap=True)
            tt += 1 / walk_rate
    for bt in (beep_at or []):
        S.place(y, ped_beep() * 0.6, secs(bt) % n, wrap=True)
    return y


# ---- sirens, trains, bells --------------------------------------------------

def siren(dur, seed, mode="wail", dist=0.8):
    """Distant Australian emergency-vehicle siren (wail / yelp), mono."""
    n = secs(dur)
    t = S.t_axis(n)
    r = np.random.default_rng(seed)
    if mode == "wail":
        per = r.uniform(3.6, 4.4)
        ph = (t / per) % 1.0
        sweep = np.where(ph < 0.55, ph / 0.55, 1 - (ph - 0.55) / 0.45)
        f = 620 + 760 * np.sin(sweep * np.pi / 2)
    else:  # yelp, switching to wail at the end
        per = 0.32
        ph = (t / per) % 1.0
        f = 650 + 800 * np.sin(np.minimum(ph / 0.8, 1.0) * np.pi / 2)
        k = (t > dur * 0.55)
        ph2 = ((t - dur * 0.55) / 4.0) % 1.0
        f = np.where(k, 650 + 760 * np.sin(np.minimum(ph2 / 0.55, 1) * np.pi / 2), f)
    f = f * (1 + 0.004 * np.sin(2 * np.pi * 0.3 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.tanh(3 * np.sin(ph)) + 0.3 * np.sin(2 * ph)
    y = S.resonator(y, 1700, 1.5) + 0.3 * S.resonator(y, 900, 2)
    # distance: approaching then receding, with gentle level wobble (wind)
    env = np.exp(-((t - dur * r.uniform(0.45, 0.6)) / (dur * 0.38)) ** 2)
    env *= 1 + 0.25 * S.smooth_noise(n, 1.5, seed, periodic=False)
    y = y * env
    y = S.lp(y, 9000 * 0.15 ** dist, 4)
    wet = S.reverb(y, size_s=2.5, damp_hz=2500, wet=1.0, seed=seed).mean(axis=1)
    y = y * (1 - 0.5 * dist) + wet * 0.8 * dist
    return S.fade(y, 0.5, 1.0)


def train_pass(dur, seed, speed=24.0, dist=25.0, cars=4, brake=False):
    """Transperth-style electric multiple unit passing: inverter/traction-motor
    whine, rolling noise, wheel clatter over a rail joint at the listener,
    pantograph hiss, doppler on the moving sources. Mono."""
    r = np.random.default_rng(seed)
    n = secs(dur)
    t = S.t_axis(n)
    car_len = 23.0
    length = cars * car_len
    t0 = dur * 0.45
    pos = speed * (t - t0)  # train centre relative to listener
    if brake:
        pos = speed * (t - t0) - 0.5 * 0.6 * np.maximum(t - t0 + 3, 0) ** 2 * 0.25
    # extended source: amplitude from nearest part of the train
    near = np.clip(np.abs(pos) - length / 2, 0, None)
    rr = np.sqrt(dist ** 2 + near ** 2)
    g = (dist / rr) ** 2.0
    # source buffer with doppler from the train centre
    m = n + secs(1)
    tt = S.t_axis(m)
    roll = S.bp(S.noise(m, seed), 150, 3000, 2) + 0.6 * S.lp(S.brown(m, seed + 1), 200)
    f0 = r.uniform(380, 460) * (1 + 0.05 * tt / dur)
    whine = sum(np.sin(2 * np.pi * np.cumsum(f0 * h) / SR) / h ** 1.5 for h in (1, 2, 3, 5))
    whine += 0.3 * np.sin(2 * np.pi * np.cumsum(f0 * 3.04) / SR)
    hum = 0.4 * np.sin(2 * np.pi * 100 * tt) + 0.2 * np.sin(2 * np.pi * 300 * tt)
    s = roll * 0.8 + whine * 0.4 + hum * 0.1
    if brake:
        sq = np.sin(2 * np.pi * np.cumsum(np.full(m, 2900) * (1 + 0.01 * S.smooth_noise(m, 3, seed + 2, periodic=False))) / SR)
        s += sq * 0.12 * np.clip((tt - t0 + 1) / 3, 0, 1)
    cdist = np.sqrt(dist ** 2 + pos ** 2)
    y = np.interp((t - cdist / 343 + 0.5) * SR, np.arange(m), s) * g
    # wheel clatter: every axle crosses a joint right beside the listener
    axles = []
    for c in range(cars):
        front = -length / 2 + c * car_len
        for b in (2.5, car_len - 2.5):
            axles += [front + b - 1.25, front + b + 1.25]
    click = S.bp(S.noise(secs(0.05), seed + 3), 300, 4000, 2) * S.env_exp(secs(0.05), 0.008)
    thud = np.sin(2 * np.pi * 70 * S.t_axis(secs(0.08))) * S.env_exp(secs(0.08), 0.02)
    clk = np.zeros(n)
    for a in axles:
        # time when this axle passes the joint (train moves +x)
        ta = t0 - a / speed
        if 0 < ta < dur:
            S.place(clk, (click + 0.6 * thud[: len(click)]) * r.uniform(0.7, 1.0), secs(ta))
            S.place(clk, (click * 0.6) * r.uniform(0.5, 0.8), secs(ta + 0.9 / speed))
    y = y + clk * g * 1.5 * (dist / 25) ** 0.5
    # air absorption / ground effect: far = dull, near = bright
    y = S.lp(y, 700, 2) * (1 - g) + S.lp(y, 9000 * (25 / dist) ** 0.5, 1) * g
    wet = S.reverb(y, size_s=1.8, damp_hz=4000, wet=1.0, seed=seed).mean(axis=1)
    return S.fade(y * 0.85 + wet * 0.2, 0.8, 1.2)


def crossing_bell_loop(dur=4.0, strikes=11, seed=0):
    """Australian railway level-crossing bell: a bright bell struck fast and
    steadily (~2.75 strikes/s). Loops exactly (wrap-around tails)."""
    n = secs(dur)
    r = np.random.default_rng(seed)
    y = np.zeros(n)
    f0 = 905.0
    partials = [(1.0, 1.0, 0.9), (2.32, 0.55, 0.5), (2.98, 0.25, 0.35), (4.18, 0.3, 0.22), (5.43, 0.12, 0.15)]
    L = secs(1.4)
    tl = S.t_axis(L)
    for i in range(strikes):
        hit = np.zeros(L)
        v = r.uniform(0.85, 1.0)
        for ratio, amp, dec in partials:
            hit += amp * np.sin(2 * np.pi * f0 * ratio * tl + r.uniform(0, 6)) * np.exp(-tl / dec)
        hit[:secs(0.002)] += r.standard_normal(secs(0.002)) * 0.5
        hit = S.fade(hit, 0.0005, 0.05)
        S.place(y, hit * v, secs(i * dur / strikes), wrap=True)
    return y


# ---- more synthesised layers -------------------------------------------------

def periodic_rate(n, f0, depth, wobble_hz, seed):
    """Instantaneous rate curve (Hz) that wanders but integrates to a whole
    number of cycles over n samples, so pulse trains built on it loop."""
    rr = f0 * (1 + depth * S.smooth_noise(n, wobble_hz, seed))
    cycles = max(1, round(rr.sum() / SR))
    return rr * cycles / (rr.sum() / SR)


def pulse_times(rr):
    ph = np.cumsum(rr) / SR
    return np.flatnonzero(np.diff(np.floor(ph)) > 0) + 1


def engine_idle(n, seed, rpm=800, cyl=4, pattern=None, rough=0.05, muffler=600, wobble=0.02, miss=0.0):
    """Looping engine idle as exhaust pulses on a circular timeline.
    pattern: per-firing amplitude pattern (cross-plane V8 burble etc)."""
    r = np.random.default_rng(seed)
    fire = rpm / 60 * cyl / 2
    rr = periodic_rate(n, fire, wobble, 0.4, seed)
    idx = pulse_times(rr)
    pk = secs(0.045)
    tk = S.t_axis(pk)
    y = np.zeros(n)
    pat = pattern or [1.0]
    for i, at in enumerate(idx):
        if miss and r.random() < miss:
            continue
        a = pat[i % len(pat)] * (1 + rough * r.standard_normal())
        pop = (np.sin(2 * np.pi * r.uniform(55, 75) * tk) * np.exp(-tk / 0.012)
               + 0.5 * r.standard_normal(pk) * np.exp(-tk / 0.004))
        S.place(y, pop * a, at, wrap=True)
    y = S.circ_lp(y, muffler, 2)
    y += 0.15 * S.circ_bp(S.noise(n, seed + 1), 800, 4000, 1) * np.abs(S.circ_lp(y, 30, 1)) * 4  # mechanical tick
    return y


def club_bass(n, bpm=124, seed=0, leak=None):
    """Club music heard through walls: four-on-the-floor kick and a bass
    line, low-passed hard; `leak` (0..1 curve) lets mids through when a door
    opens. Tempo nudged so whole bars fit the loop."""
    beats = max(4, round(n / SR * bpm / 60 / 4) * 4)
    bl = n / beats
    t = S.t_axis(n)
    y = np.zeros(n)
    kick_n = secs(0.25)
    tk = S.t_axis(kick_n)
    kick = np.sin(2 * np.pi * (45 * tk + 60 * 0.03 * (1 - np.exp(-tk / 0.03)))) * np.exp(-tk / 0.12)
    notes = [41.2, 41.2, 49.0, 36.7]  # E1 E1 G1 D1 per bar
    for b in range(beats):
        S.place(y, kick, int(b * bl), wrap=True)
    bar = np.floor(t / (bl * 4 / SR)).astype(int)
    f = np.array(notes)[bar % len(notes)]
    off = ((t / (bl / SR)) % 1.0)
    gate = ((off > 0.5) & (off < 0.95)).astype(float)
    gate = S.circ_lp(gate, 60, 1)
    bass = np.sin(2 * np.pi * np.cumsum(f) / SR) * gate
    hats = S.circ_hp(S.noise(n, seed), 6000, 2) * (np.abs(off - 0.5) < 0.05)
    mids = S.circ_bp(S.noise(n, seed + 1), 300, 2500, 1) * gate * 0.3 + hats * 0.4
    low = S.circ_lp(kick_and := y + 0.7 * bass, 160, 3)
    out = low + (S.circ_lp(kick_and + mids, 3000, 2) * leak if leak is not None else 0)
    return out


def car_stereo(n, bpm=96, seed=0):
    """Muffled hip-hop/RnB-ish beat from a parked car with its doors open."""
    beats = max(4, round(n / SR * bpm / 60 / 4) * 4)
    bl = n / beats
    y = np.zeros(n)
    kn = secs(0.4)
    tk = S.t_axis(kn)
    kick = np.sin(2 * np.pi * (50 * tk + 2.5 * (1 - np.exp(-tk / 0.04)))) * np.exp(-tk / 0.2)
    snare = S.bp(S.noise(secs(0.2), seed), 800, 5000, 1) * np.exp(-S.t_axis(secs(0.2)) / 0.05)
    for b in range(beats):
        S.place(y, kick, int(b * bl), wrap=True)
        if b % 2 == 1:
            S.place(y, snare * 0.6, int(b * bl), wrap=True)
        if b % 4 == 3:
            S.place(y, kick * 0.7, int((b + 0.5) * bl), wrap=True)
    # simple minor-chord pad so it reads as music
    t = S.t_axis(n)
    chord = sum(np.sin(2 * np.pi * periodic_tone(n, f) * t) for f in (220.0, 261.6, 329.6))
    y = y + 0.12 * chord * (1 + 0.3 * np.sin(2 * np.pi * periodic_tone(n, bpm / 60 / 4) * t))
    return S.circ_lp(y, 450, 3)


def footsteps(dur, seed, rate_hz=2.8, surface="path", jog=True):
    """A jogger running past on a path (mono, with pass-by envelope)."""
    r = np.random.default_rng(seed)
    n = secs(dur)
    y = np.zeros(n)
    tt = 0.1
    while tt < dur - 0.2:
        k = secs(0.07)
        tk = S.t_axis(k)
        step = (np.sin(2 * np.pi * r.uniform(70, 100) * tk) * np.exp(-tk / 0.015) * 0.8
                + S.bp(r.standard_normal(k), 1500, 7000, 1) * np.exp(-tk / 0.02) * (0.6 if surface == "gravel" else 0.25))
        S.place(y, step * r.uniform(0.7, 1.0), secs(tt))
        tt += 1 / rate_hz * r.uniform(0.95, 1.05)
    t = S.t_axis(n)
    env = np.exp(-((t - dur / 2) / (dur / 4)) ** 2)
    return y * env


def clinks(n, seed, count):
    """Cups and cutlery on cafe tables (circular)."""
    r = np.random.default_rng(seed)
    y = np.zeros(n)
    for _ in range(count):
        k = secs(0.3)
        tk = S.t_axis(k)
        f = r.uniform(1800, 4200)
        s = sum(np.sin(2 * np.pi * f * m * tk + r.uniform(0, 6)) * np.exp(-tk / (0.08 / m)) for m in (1, 1.58, 2.37))
        s[: secs(0.002)] += r.standard_normal(secs(0.002))
        S.place(y, s * r.uniform(0.2, 1.0), int(r.integers(n)), wrap=True)
    return y


def reverse_beeper(dur, seed):
    """Truck reversing alarm (Australian trucks: tonal ~1.1 kHz beep, ~1 Hz)."""
    n = secs(dur)
    t = S.t_axis(n)
    on = ((t % 1.0) < 0.5).astype(float)
    on = S.lp(on, 200, 1)
    y = np.tanh(2 * np.sin(2 * np.pi * 1120 * t)) * on
    idle = S.lp(S.noise(n, seed), 120, 2) * 2
    return S.fade(y * 0.6 + idle, 0.3, 0.5)


def ship_horn(dur, seed, f0=72.0):
    """Big ship's horn: low, slightly beating pair of tones."""
    n = secs(dur)
    t = S.t_axis(n)
    y = np.zeros(n)
    for f, a in ((f0, 1.0), (f0 * 1.26, 0.6)):
        ph = 2 * np.pi * f * t
        y += a * (np.tanh(2.5 * np.sin(ph)) + 0.3 * np.sin(2 * ph + 0.4))
    y = S.lp(y, 900, 2) * S.env_adsr(n, 0.25, 0.2, 0.9, 0.6)
    return y


def metal_clank(seed, size=1.0):
    """Container / crane spreader clank: inharmonic low metal partials."""
    r = np.random.default_rng(seed)
    k = secs(2.2)
    tk = S.t_axis(k)
    y = np.zeros(k)
    for m in (1, 2.76, 5.4, 8.93, 13.3):
        f = r.uniform(80, 120) / size * m
        y += np.sin(2 * np.pi * f * tk + r.uniform(0, 6)) * np.exp(-tk / (0.9 / m ** 0.5)) / m ** 0.6
    y[: secs(0.01)] += r.standard_normal(secs(0.01)) * 2
    return S.lp(y, 4000, 1)


def hydraulic_whine(dur, seed):
    n = secs(dur)
    t = S.t_axis(n)
    f = 380 + 60 * np.clip(t / 2, 0, 1)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.3 + S.bp(S.noise(n, seed), 200, 1500, 1)
    return S.fade(y * S.env_adsr(n, 0.8, 0.1, 1, 1.0), 0.1, 0.3)


def bridge_hum(n, seed):
    """Lights on the bridge: 100 Hz ballast buzz with odd harmonics, slowly
    varying, plus a faint high transformer whine."""
    t = S.t_axis(n)
    f = periodic_tone(n, 100.0)
    y = sum(np.sin(2 * np.pi * f * h * t + h) / h ** 1.2 for h in (1, 2, 3, 5, 7, 9))
    y = np.tanh(1.5 * y) * (1 + 0.15 * S.smooth_noise(n, 0.1, seed))
    whine = 0.03 * np.sin(2 * np.pi * periodic_tone(n, 3150.0) * t)
    return y + whine


def env_window(n_total, start, length, fin, fout):
    """0..1 envelope for a long event placed inside a loop (circular)."""
    e = np.zeros(n_total)
    seg = S.env_adsr(secs(length), fin, 0.0, 1.0, fout)
    S.place(e, seg, secs(start) % n_total, wrap=True)
    return e


# --------------------------------------------------------------------------
# Builders
# --------------------------------------------------------------------------

BUILD: dict[str, callable] = {}


def builder(name):
    def deco(fn):
        BUILD[name] = fn
        return fn
    return deco


def bird_pools():
    # (mag_kp1 is an overlapping take of mag_kp2, so only kp2 is used)
    mag = (snips("mag_kp2", 900, 6000, thresh_db=14, min_len=0.6, max_len=7, gap=0.5)
           # Sydney suburban magpies: only the loud, close phrases
           + snips("mag_dl", 900, 6000, thresh_db=20, min_len=1.0, max_len=6, gap=0.5))
    return mag


@builder("amb_kingspark_day")
def kingspark_day():
    dur = 96
    B = Bed(dur, 101)
    n = B.n
    # WA bush underlay (Walyunga NP, just up the river), kept low
    B.add(texture(src("walyunga", True), dur, 1, chunk=24, avoid_peaks_db=8), -34)
    B.add(gum_wind(n, 11, gust_rate=0.06), -33)
    B.add(city_hum(n, 12, 30, 220), -46)  # the CBD is just below the park
    mag = bird_pools()
    B.scatter(mag, 12, gain_db=(-16, -5), dist=(0.15, 0.7))
    # kookaburras: one family laugh per loop, back in the trees
    kk = [cut(src("kook_kp"), secs(a), secs(a + L)) for a, L in ((16, 9), (22, 8), (2, 6))]
    B.put(distant(kk[0], 0.6, -0.5, 1), secs(40), -9)
    B.put(distant(kk[2], 0.8, 0.6, 2), secs(83), -15)
    # rainbow lorikeets: screeching flocks flying over (pan sweeps)
    lori = src("lorikeets")
    lev = find_events(lori, 2000, 8000, thresh_db=10, min_len=1.0, max_len=5, gap=0.4)
    lev = sorted(lev, key=lambda e: -e[2])[:4]
    for i, (a, b, _) in enumerate(lev[:3]):
        s = cut(lori, a, b, 0.3, 0.6)
        p0 = B.r.uniform(-0.9, -0.3) * (1 if i % 2 else -1)
        st = pan_sweep(S.lp(s, 9000), p0, -p0)
        B.put(st, B.r.integers(n), -10 - 3 * i)
    # Carnaby's black cockatoos wailing far off, and a raven
    ck = snips("cockatoo_perth", 500, 4000, thresh_db=14, min_len=0.6, max_len=4, best=True, n=3)
    B.put(distant(ck[0], 0.75, 0.7, 3), secs(12), -17)
    rv = snips("raven_db", 300, 3000, thresh_db=14, min_len=0.8, max_len=4, best=True, n=4)
    B.put(distant(rv[1], 0.8, -0.8, 4), secs(64), -18)
    save_loop("amb/amb_kingspark_day", B.x)


@builder("amb_kingspark_night")
def kingspark_night():
    dur = 120
    B = Bed(dur, 202)
    n = B.n
    B.add(texture(src("crickets_sub", True), dur, 2, chunk=17, region=(22.5, 82)), -32)
    B.add(gum_wind(n, 21, gust_rate=0.04, crisp=0.6), -44)
    B.add(city_hum(n, 22, 30, 200), -44)
    # banjo frogs 'bonk' from the lake edge (pobblebonk calls)
    bonk = (snips("pobble1", 250, 1200, thresh_db=12, min_len=0.05, max_len=0.6, gap=0.08)
            + snips("pobble2", 250, 1200, thresh_db=12, min_len=0.05, max_len=0.6, gap=0.08))
    bonk = [S.hp(b, 180) for b in bonk]
    # plus a few synthesised 'bonks' (western banjo frog: a short hollow
    # knock ~500 Hz with a quick downward bend) for variety
    for i in range(4):
        rr = np.random.default_rng(2200 + i)
        k = secs(0.25)
        tk = S.t_axis(k)
        f = rr.uniform(430, 560) * (1 + 0.35 * np.exp(-tk / 0.012))
        ph = 2 * np.pi * np.cumsum(f) / SR
        y = (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)) * np.exp(-tk / 0.05)
        bonk.append(S.fade(y, 0.002, 0.03))
    for k, at in enumerate(B.times(9, 0.9)):
        # little runs of 2-5 bonks from one or two frogs
        p = B.r.uniform(-0.7, 0.7)
        d = B.r.uniform(0.4, 0.75)
        g = B.r.uniform(-18, -9)
        tt = at
        for j in range(int(B.r.integers(2, 6))):
            s = bonk[int(B.r.integers(len(bonk)))]
            B.put(distant(s, d, p, k * 10 + j, room=1.0), tt, g)
            tt += secs(B.r.uniform(0.5, 1.4))
    # southern boobook 'mopoke' twice per loop, far apart, long silences
    owl = src("boobook1")
    ev = find_events(owl, 350, 1200, thresh_db=12, min_len=0.25, max_len=2.0, gap=0.25)
    calls = [S.lp(cut(owl, a, b), 1600, 3) for a, b, _ in ev]
    for at, p, d in ((secs(18), -0.6, 0.65), (secs(78), 0.5, 0.8)):
        tt = at
        for j in range(min(len(calls), 5)):
            B.put(distant(calls[(j + at) % len(calls)], d, p, j, room=2.0), tt, -13)
            tt += secs(B.r.uniform(1.6, 2.4))
    save_loop("amb/amb_kingspark_night", B.x)


@builder("amb_cbd_day")
def cbd_day():
    dur = 90
    B = Bed(dur, 303)
    n = B.n
    B.add(texture(src("traffic_peak", True), dur, 3, chunk=18, avoid_peaks_db=9), -27)
    B.add(city_hum(n, 31, 40, 400), -38)
    # people walking past: park voices / footsteps from Hyde Park, Perth
    B.add(texture(src("hydepark", True), dur, 4, chunk=20, avoid_peaks_db=8), -35)
    # buses pulling away / passing
    for k, at in enumerate(B.times(3, 0.6)):
        y = car_pass(9.0, 3000 + k, speed=9, dist=10, kind="bus")
        B.put(pass_stereo(y, k % 2 == 1), at, -9)
    for k, at in enumerate(B.times(7, 0.9)):
        y = car_pass(6.0, 3100 + k, speed=13, dist=8 + 6 * B.r.uniform(), kind="car" if k % 3 else "moto")
        B.put(pass_stereo(y, k % 2 == 0), at, -14)
    # two pedestrian crossings: near one (left) and across the road (right)
    near = ped_sequence(n, 1.0, walk_at=[20.0, 65.0], beep_at=[11.3, 58.2], seed=1)
    far = ped_sequence(n, 1.0, walk_at=[42.0, 87.0], beep_at=[33.0], seed=2)
    B.put(S.pan(near, -0.45), 0, -7)
    farst = fold(distant(far, 0.55, 0.6, 5, room=0.8), n)
    B.put(farst, 0, -15)
    # a distant siren once
    B.put(S.pan(siren(10.0, 31, "wail", 0.85), 0.3), secs(50), -24)
    save_loop("amb/amb_cbd_day", B.x)


@builder("amb_cbd_night")
def cbd_night():
    dur = 100
    B = Bed(dur, 404)
    n = B.n
    B.add(S.circ_lp(texture(src("traffic_night", True), dur, 5, chunk=20), 2500), -32)
    B.add(city_hum(n, 41, 30, 250), -37)
    B.add(np.stack([ac_unit(n, 42, 13.5, level=1.0), ac_unit(n, 43, 17.2, level=0.6, rattle=0.2)], axis=1), -41)
    B.add(np.stack([ac_unit(n, 44, 9.0, level=0.3), ac_unit(n, 45, 11.0, level=0.8)], axis=1)[:, ::-1], -45)
    # a crossing left tocking for nobody, across an empty street
    loc = ped_sequence(n, 1.0, walk_at=[61.0], seed=3)
    B.put(fold(distant(loc, 0.45, -0.3, 6, room=1.2), n), 0, -24)
    for k, at in enumerate(B.times(4, 0.8)):
        y = car_pass(8.0, 4000 + k, speed=15, dist=20 + 15 * B.r.uniform(), kind="car")
        B.put(pass_stereo(S.lp(y, 3000), k % 2 == 1), at, -19)
    B.put(S.pan(siren(11.0, 41, "yelp", 0.95), -0.5), secs(30), -27)
    save_loop("amb/amb_cbd_night", B.x)


# ---- P2 / P3 beds --------------------------------------------------------------

def silver_gull(seed):
    """Silver gull (the Perth 'seagull'): a harsh, nasal, rasping 'kwarr' or
    'kee-arr', often in short series. Synthesised: no CC0 recording of the
    Australian species was found, and European herring gulls sound wrong."""
    r = np.random.default_rng(seed)
    out = []
    for _ in range(int(r.integers(1, 4))):
        L = r.uniform(0.22, 0.45)
        n = secs(L)
        t = S.t_axis(n)
        f0 = r.uniform(950, 1250)
        f = f0 * (1 + 0.25 * np.exp(-t / 0.05)) * (1 - 0.18 * t / L)
        ph = 2 * np.pi * np.cumsum(f) / SR
        tone = sum(np.sin(h * ph) / h ** 0.7 for h in range(1, 7))
        rasp = 1 + 0.8 * np.sin(2 * np.pi * r.uniform(70, 110) * t) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 37 * t)))
        y = tone * rasp + 0.6 * S.bp(r.standard_normal(n), 1500, 4500, 1)
        y = S.resonator(y, 2600, 2.0) + 0.5 * S.resonator(y, 1400, 2.0)
        y *= S.env_adsr(n, 0.02, 0.05, 0.8, L * 0.4)
        out.append(y)
        out.append(np.zeros(secs(r.uniform(0.08, 0.3))))
    return np.concatenate(out)


def gull_pool():
    return [silver_gull(4000 + i) for i in range(10)]


def raven_pool():
    return (snips("raven_db", 250, 3000, thresh_db=15, min_len=1.0, max_len=4.5, gap=0.35)
            + snips("raven_yell", 250, 3000, thresh_db=15, min_len=1.0, max_len=4.5, gap=0.35))


def dog_pool():
    out = []
    for k in ("dogs_far", "dog_far2"):
        out += snips(k, 300, 3000, thresh_db=12, min_len=0.3, max_len=3.0, gap=0.6)
    return out


@builder("amb_northbridge_day")
def northbridge_day():
    dur = 90
    B = Bed(dur, 505)
    n = B.n
    B.add(texture(src("bar_wa", True), dur, 51, chunk=15), -31)          # cafe chatter
    B.add(S.circ_lp(texture(src("traffic_peak", True), dur, 52, chunk=18, avoid_peaks_db=9), 3000), -33)
    B.add(city_hum(n, 53, 40, 300), -40)
    B.add(np.stack([clinks(n, 54, 26), clinks(n, 55, 26)], axis=1), -42)
    # espresso machine steaming every so often
    for k, at in enumerate(B.times(3, 0.7)):
        st = S.bp(S.noise(secs(4), 560 + k), 2500, 9000, 2) * S.env_adsr(secs(4), 0.1, 0.2, 0.7, 0.6)
        B.put(distant(st, 0.35, B.r.uniform(-0.6, 0.6), k), at, -22)
    # a delivery truck backing into the lane, idling
    B.put(distant(reverse_beeper(9.0, 57), 0.55, 0.65, 7), secs(28), -17)
    for k, at in enumerate(B.times(5, 0.9)):
        y = car_pass(7.0, 5000 + k, speed=8, dist=10, kind="car" if k % 2 else "truck")
        B.put(pass_stereo(y, k % 2 == 0), at, -16)
    B.put(S.pan(siren(10.0, 58, "wail", 0.9), -0.4), secs(70), -27)
    save_loop("amb/amb_northbridge_day", B.x)


@builder("amb_northbridge_night")
def northbridge_night():
    dur = 96
    B = Bed(dur, 606)
    n = B.n
    # club doors opening now and then let the mids out
    leak = sum(env_window(n, st, L, 0.4, 0.8) for st, L in ((14, 6), (55, 9))) * 0.6
    B.add(np.stack([club_bass(n, 124, 61, leak), club_bass(n, 124, 61, leak * 0.8)], axis=1), -30)
    crowd = texture(src("bar_wa", True), dur, 62, chunk=14)
    B.add(crowd, -32)
    B.add(S.circ_lp(texture(src("pub_crowd", True), dur, 63, chunk=15), 3000), -36)
    B.add(S.circ_lp(texture(src("traffic_night", True), dur, 64, chunk=20), 2500), -37)
    B.add(city_hum(n, 65, 40, 250), -41)
    for k, at in enumerate(B.times(2, 0.5)):
        B.put(S.pan(siren(11.0, 660 + k, "yelp" if k else "wail", 0.92), B.r.uniform(-0.7, 0.7)), at, -26)
    for k, at in enumerate(B.times(4, 0.9)):
        y = car_pass(7.0, 6000 + k, speed=10, dist=9, kind="moto" if k == 2 else "car")
        B.put(pass_stereo(y, k % 2 == 0), at, -17)
    save_loop("amb/amb_northbridge_night", B.x)


@builder("amb_river_day")
def river_day():
    dur = 100
    B = Bed(dur, 707)
    n = B.n
    B.add(texture(src("lapping", True), dur, 71, chunk=20), -28)
    B.add(gum_wind(n, 72, gust_rate=0.05, crisp=0.3), -37)
    B.add(city_hum(n, 73, 35, 250), -40)  # traffic across the water
    # a ferry crossing to South Perth: engine fades up and away
    fe = texture(src("ferry", True), dur, 74, chunk=16)
    env = env_window(n, 20, 40, 14, 18)
    B.add(S.circ_lp(fe, 1200) * env[:, None], -31)
    B.scatter(gull_pool(), 6, gain_db=(-22, -13), dist=(0.3, 0.8))
    B.scatter(bird_pools(), 4, gain_db=(-24, -16), dist=(0.5, 0.85))
    for k, at in enumerate(B.times(3, 0.7)):
        y = footsteps(8.0, 7100 + k, rate_hz=B.r.uniform(2.6, 3.0))
        B.put(pass_stereo(y, k % 2 == 1), at, -20)
    save_loop("amb/amb_river_day", B.x)


@builder("amb_river_night")
def river_night():
    dur = 110
    B = Bed(dur, 808)
    n = B.n
    B.add(texture(src("lapping", True), dur, 81, chunk=20), -30)
    hum = bridge_hum(n, 82)
    B.add(np.stack([hum, np.roll(hum, secs(0.013))], axis=1), -43)
    B.add(city_hum(n, 83, 30, 200), -39)
    B.add(texture(src("crickets_sub", True), dur, 84, chunk=17, region=(22.5, 82)), -44)
    for k, at in enumerate(B.times(3, 0.8)):
        y = car_pass(9.0, 8000 + k, speed=22, dist=60, kind="car")
        B.put(pass_stereo(S.lp(y, 2000), k % 2 == 1), at, -25)
    save_loop("amb/amb_river_night", B.x)


@builder("amb_suburbs_day")
def suburbs_day():
    dur = 110
    B = Bed(dur, 909)
    n = B.n
    # Hyde Park, Perth: kids, distant traffic, local birds
    B.add(texture(src("hydepark", True), dur, 91, chunk=22, avoid_peaks_db=10), -29)
    B.add(gum_wind(n, 92, gust_rate=0.05, crisp=0.7), -38)
    # a neighbour mowing for most of the loop, starting/stopping off-screen
    mow = texture(src("lawnmower", True), dur, 93, chunk=25, avoid_peaks_db=5)
    env = env_window(n, 10, 70, 4, 6)
    B.add(S.circ_lp(mow, 2500) * env[:, None], -33)
    # reticulation: impact sprinkler ticking a couple of yards over
    sp = texture(src("sprinkler", True), dur, 94, chunk=9.0, xf=0.3)
    env2 = env_window(n, 60, 45, 2, 2)
    B.add(S.circ_lp(sp, 4000) * env2[:, None], -43)
    B.scatter(bird_pools(), 7, gain_db=(-20, -9), dist=(0.25, 0.8))
    B.scatter(raven_pool(), 2, gain_db=(-22, -16), dist=(0.5, 0.85))
    wg = snips("wagtail1", 2000, 8000, thresh_db=14, min_len=0.6, max_len=3.0, gap=0.35)
    B.scatter(wg, 3, gain_db=(-22, -14), dist=(0.3, 0.6))
    B.scatter(dog_pool(), 3, gain_db=(-24, -16), dist=(0.6, 0.9))
    for k, at in enumerate(B.times(3, 0.8)):
        y = car_pass(7.0, 9100 + k, speed=11, dist=14, kind="car")
        B.put(pass_stereo(y, k % 2 == 1), at, -19)
    save_loop("amb/amb_suburbs_day", B.x)


@builder("amb_suburbs_night")
def suburbs_night():
    dur = 120
    B = Bed(dur, 1010)
    n = B.n
    B.add(texture(src("crickets_sub", True), dur, 101, chunk=17, region=(22.5, 82)), -31)
    B.add(S.circ_lp(texture(src("traffic_night", True), dur, 102, chunk=20), 1800), -38)
    B.add(gum_wind(n, 103, gust_rate=0.03, crisp=0.5), -45)
    sp = texture(src("sprinkler", True), dur, 104, chunk=9.0, xf=0.3)
    env = env_window(n, 30, 50, 1.5, 1.5)
    B.add(S.circ_lp(sp, 3500) * env[:, None], -40)
    B.scatter(dog_pool(), 4, gain_db=(-24, -17), dist=(0.7, 0.95), room=2.0)
    # ravens settling at dusk, far off
    B.scatter(raven_pool(), 2, gain_db=(-26, -20), dist=(0.75, 0.9), room=2.0)
    B.put(S.pan(siren(11.0, 105, "wail", 0.97), 0.6), secs(80), -30)
    save_loop("amb/amb_suburbs_night", B.x)


@builder("amb_freeway_day")
def freeway_day():
    dur = 80
    B = Bed(dur, 1111)
    n = B.n
    B.add(texture(src("freeway", True), dur, 111, chunk=16, avoid_peaks_db=8), -26)
    B.add(texture(src("traffic_peak", True), dur, 112, chunk=16, avoid_peaks_db=8), -32)
    B.add(city_hum(n, 113, 30, 500), -31)
    for k, at in enumerate(B.times(16, 0.9)):
        kind = "truck" if k % 5 == 0 else "car"
        y = car_pass(5.0, 11000 + k, speed=B.r.uniform(25, 30), dist=B.r.uniform(12, 30), kind=kind)
        B.put(pass_stereo(y, k % 2 == 0), at, -17 if kind == "car" else -14)
    save_loop("amb/amb_freeway_day", B.x)


@builder("amb_freeway_night")
def freeway_night():
    dur = 100
    B = Bed(dur, 1212)
    n = B.n
    # nearly empty WA highway (crickets in the verge)
    B.add(texture(src("highway_wa", True), dur, 121, chunk=20, avoid_peaks_db=6), -33)
    B.add(city_hum(n, 122, 30, 300), -40)
    for k, at in enumerate(B.times(6, 0.9)):
        kind = "truck" if k in (1, 4) else "car"
        y = car_pass(8.0, 12000 + k, speed=B.r.uniform(26, 30), dist=B.r.uniform(15, 35), kind=kind)
        B.put(pass_stereo(y, k % 2 == 1), at, -16 if kind == "truck" else -19)
    save_loop("amb/amb_freeway_night", B.x)


@builder("amb_beach_day")
def beach_day():
    dur = 100
    B = Bed(dur, 1313)
    n = B.n
    B.add(texture(src("beach_day", True), dur, 131, chunk=25), -25)
    B.add(gum_wind(n, 132, gust_rate=0.08, crisp=0.0), -34)  # the sea breeze
    B.scatter(gull_pool(), 8, gain_db=(-20, -10), dist=(0.2, 0.7))
    save_loop("amb/amb_beach_day", B.x)


@builder("amb_beach_night")
def beach_night():
    dur = 110
    B = Bed(dur, 1414)
    n = B.n
    B.add(texture(src("beach_night", True), dur, 141, chunk=25), -26)
    B.add(gum_wind(n, 142, gust_rate=0.04, crisp=0.0), -38)
    save_loop("amb/amb_beach_night", B.x)


@builder("amb_fremantle_day")
def fremantle_day():
    dur = 110
    B = Bed(dur, 1515)
    n = B.n
    B.add(texture(src("laps_horn", True), dur, 151, chunk=12, avoid_peaks_db=7), -30)
    B.add(city_hum(n, 152, 30, 220), -36)  # port machinery and ships' generators
    B.scatter(gull_pool(), 7, gain_db=(-22, -12), dist=(0.3, 0.8))
    B.put(distant(ship_horn(4.0, 153), 0.85, -0.6, 1, room=3.0), secs(35), -15)
    B.put(distant(ship_horn(2.5, 154, 88), 0.9, 0.7, 2, room=3.0), secs(92), -20)
    for k, at in enumerate(B.times(6, 0.9)):
        B.put(distant(metal_clank(1550 + k, B.r.uniform(0.8, 1.4)), B.r.uniform(0.6, 0.85),
                      B.r.uniform(-0.8, 0.8), k, room=2.5), at, -19)
    for k, at in enumerate(B.times(3, 0.6)):
        B.put(distant(hydraulic_whine(5.0, 1560 + k), 0.7, B.r.uniform(-0.6, 0.6), k, room=2.0), at, -26)
    # the freight train grinding out of the port with its crossing bell
    tr = src("freo_train")
    seg = cut(tr, secs(5), secs(35), 3.0, 4.0)
    B.put(distant(seg, 0.65, 0.4, 9, room=2.0), secs(50), -17)
    save_loop("amb/amb_fremantle_day", B.x)


@builder("amb_fremantle_night")
def fremantle_night():
    dur = 110
    B = Bed(dur, 1616)
    n = B.n
    B.add(texture(src("lapping", True), dur, 161, chunk=20), -31)
    B.add(city_hum(n, 162, 25, 160), -34)
    B.add(np.stack([ac_unit(n, 163, 8.0, level=1.0), ac_unit(n, 164, 6.5, level=1.0)], axis=1), -45)
    B.put(distant(ship_horn(5.0, 165, 68), 0.95, -0.4, 3, room=4.0), secs(40), -20)
    for k, at in enumerate(B.times(3, 0.9)):
        B.put(distant(metal_clank(1650 + k, 1.3), 0.9, B.r.uniform(-0.8, 0.8), k, room=3.0), at, -25)
    bell = np.tile(crossing_bell_loop(), 4)
    bell = S.fade(bell, 1.0, 2.0)
    B.put(distant(bell, 0.9, 0.7, 4, room=2.5), secs(85), -27)
    save_loop("amb/amb_fremantle_night", B.x)


@builder("amb_tunnel")
def tunnel():
    """Inside the Graham Farmer Freeway tunnel under Northbridge."""
    dur = 60
    B = Bed(dur, 1717)
    n = B.n
    B.add(np.stack([S.circ_lp(S.brown(n, 171 + c), 90, 2) for c in range(2)], axis=1), -26)
    jet = np.stack([ac_unit(n, 172, 24.0, level=1.0), ac_unit(n, 173, 21.0, level=1.0)], axis=1)
    B.add(S.circ_lp(jet, 1500), -32)
    hum = bridge_hum(n, 174)
    B.add(np.stack([hum, hum], axis=1), -46)
    B.add(city_hum(n, 175, 40, 600), -33)
    for k, at in enumerate(B.times(5, 0.9)):
        y = car_pass(6.0, 17000 + k, speed=20, dist=8, kind="car")
        y = S.reverb(y, size_s=3.0, damp_hz=2500, wet=0.6, seed=k)
        B.put(y, at, -20)
    save_loop("amb/amb_tunnel", B.x)


@builder("amb_carmeet")
def carmeet():
    """Night car meet in a car park: idling engines of all sorts, chatter,
    car stereos, the odd rev."""
    dur = 90
    B = Bed(dur, 1818)
    n = B.n
    v8 = engine_idle(n, 181, rpm=750, cyl=8, pattern=[1, .6, 1.1, .5, .9, .7, 1.2, .55], rough=0.12, muffler=350)
    four = engine_idle(n, 182, rpm=900, cyl=4, rough=0.05, muffler=900)
    rot = engine_idle(n, 183, rpm=1100, cyl=6, rough=0.2, muffler=700, wobble=0.05)
    B.add(np.stack([v8, v8 * 0.5], axis=1) + np.stack([four * 0.3, four], axis=1), -30)
    B.add(np.stack([rot * 0.6, rot * 0.4], axis=1), -38)
    B.add(S.circ_lp(texture(src("bar_wa", True), dur, 184, chunk=15), 4500), -32)
    cs = car_stereo(n, 96, 185)
    B.add(np.stack([cs * 0.4, cs], axis=1), -38)
    B.add(city_hum(n, 186, 30, 200), -42)
    for k, at in enumerate(B.times(4, 0.8)):
        L = secs(3.0)
        t = S.t_axis(L)
        rpm = 900 + 3200 * np.exp(-((t - 1.0) / 0.5) ** 2)
        rev = np.zeros(L)
        ph = np.cumsum(rpm / 60 * 2) / SR
        rev = np.sin(2 * np.pi * ph) + 0.5 * np.sin(4 * np.pi * ph) + 0.3 * S.noise(L, k)
        rev = S.lp(np.tanh(2 * rev), 1200, 2) * S.env_adsr(L, 0.05, 0.2, 0.8, 0.5)
        B.put(distant(rev, B.r.uniform(0.3, 0.7), B.r.uniform(-0.8, 0.8), k), at, -14)
    save_loop("amb/amb_carmeet", B.x)


# ---- free-roam variants: rain, late night (01-05), dawn (05-07) --------------
# Same rules as the beds above (stereo seamless loops, -24 LUFS). The rain
# beds are the zone as it sounds when it is wet, NOT the rain itself (the
# weather layers play that): tyre spray, gutters, drips, fewer birds and
# people, muffled traffic.

def wet_pass(dur, seed, speed=14.0, dist=12.0, kind="car", level=1.0):
    """A vehicle passing on a wet road, mono: the tyre spray hiss dominates
    (a broad 'shhhh' with a fizzy texture that trails behind the car), the
    engine muffled underneath it."""
    n = secs(dur)
    t = S.t_axis(n)
    x = speed * (t - dur / 2)
    # the spray hangs behind the car: receding side decays more slowly
    xe = np.where(x > 0, x * 0.6, x)
    g = (dist / np.sqrt(dist ** 2 + xe ** 2)) ** 1.2
    lo, hi = (500, 7000) if kind in ("truck", "bus") else (800, 9000)
    spray = S.bp(S.noise(n, seed), lo, hi, 2) + 0.5 * S.bp(S.noise(n, seed + 1), 2500, 6000, 2)
    spray *= 1 + 0.35 * S.smooth_noise(n, 30, seed + 2, periodic=False)
    spray /= np.sqrt(np.mean(spray ** 2)) + 1e-12
    eng = car_pass(dur, seed + 5, speed, dist, kind)
    eng = S.lp(eng, 700, 2) / (np.sqrt(np.mean(eng ** 2)) + 1e-12)
    y = spray * g * (1.5 if kind in ("truck", "bus") else 1.0) + eng * 0.35
    y = y * 0.5 + S.lp(y, 1800, 1) * 0.5 * (1 - g) + S.lp(y, 7000, 1) * 0.5 * g
    return S.fade(y, 0.3, 0.4) * level


def wet_hiss(n, seed, lo=1200, hi=7000):
    """The steady 'shhh' of a wet city: distant tyres on wet roads."""
    sw = 1 + 0.35 * S.smooth_noise(n, 0.07, seed)
    return np.stack([S.circ_bp(S.pink(n, seed + 1 + c), lo, hi, 2) * sw for c in range(2)], axis=1)


def drip_points(n, seed, points=8, rate=(0.5, 3.0), f=(1600, 4200), metal=False, skip=0.3):
    """Water dripping off eaves, awnings and leaves (circular, mono): each
    drip point drips at its own rough period with its own pitch; a drop is
    a tiny rising 'plink' (or a tinny tick on metal)."""
    r = np.random.default_rng(seed)
    y = np.zeros(n)
    k = secs(0.15)
    tk = S.t_axis(k)
    for _ in range(points):
        per = r.uniform(*rate)
        f0 = r.uniform(*f)
        amp = r.uniform(0.25, 1.0)
        tt = r.uniform(0, per)
        while tt < n / SR:
            if r.random() > skip:
                ff = f0 * r.uniform(0.95, 1.05) * (1 + 0.5 * (1 - np.exp(-tk / 0.006)))
                s = np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.exp(-tk / r.uniform(0.012, 0.03))
                if metal:
                    s = 0.5 * s + sum(a * np.sin(2 * np.pi * f0 * m * tk + m) * np.exp(-tk / d)
                                      for m, a, d in ((1.0, 0.8, 0.07), (2.71, 0.4, 0.04), (5.3, 0.2, 0.02)))
                s[: secs(0.002)] *= np.linspace(0, 1, secs(0.002))
                s += 0.2 * S.bp(r.standard_normal(k), 2000, 9000, 1) * np.exp(-tk / 0.002)
                S.place(y, s * amp * r.uniform(0.6, 1.0), int(tt * SR), wrap=True)
            tt += per * r.uniform(0.8, 1.25)
    return y


def gutter(n, seed, size=1.0):
    """A gutter or downpipe running with rainwater (circular, mono): a
    hollow trickle with bubbly gurgles, ringing a little in the pipe."""
    r = np.random.default_rng(seed)
    flow = S.circ_bp(S.noise(n, seed), 300, 3500, 2)
    flow *= 1 + 0.6 * S.smooth_noise(n, 9, seed + 1)
    bub = np.zeros(n)
    k = secs(0.05)
    tk = S.t_axis(k)
    for at in r.integers(0, n, int(28 * n / SR)):
        f0 = r.uniform(500, 1600) / size
        s = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.8 * tk / 0.05)) / SR) * np.exp(-tk / r.uniform(0.006, 0.018))
        S.place(bub, s * r.uniform(0.2, 1.0), int(at), wrap=True)
    pipe = lambda f: 0.3 + sum(np.exp(-((f - fc / size) / 60) ** 2) for fc in (330, 690, 1040))
    y = flow / (np.std(flow) + 1e-9) * 0.5 + bub / (np.std(bub) + 1e-9)
    return S.circ_filter(y, S.circ_response(n, pipe))


def fridge_hum(n, seed, level=1.0):
    """The city at 3 am as a fridge-like hum: 50 Hz mains harmonics from
    substations and plant rooms, over a very low rumble. Stereo."""
    t = S.t_axis(n)
    out = []
    for c in range(2):
        sw = 1 + 0.25 * S.smooth_noise(n, 0.05, seed + c)
        hum = sum(a * np.sin(2 * np.pi * periodic_tone(n, f * (1 + 0.001 * c)) * t + c + f / 50)
                  for f, a in ((50, 0.4), (100, 1.0), (150, 0.35), (200, 0.2), (300, 0.08)))
        rum = S.circ_bp(S.brown(n, seed + 10 + c), 25, 140, 2)
        out.append(hum / np.std(hum) * 0.4 * sw + rum / np.std(rum))
    return np.stack(out, axis=1) * level


def pool_pump(n, seed):
    """A neighbour's pool pump running behind a fence (mono, circular):
    2-pole motor hum and the whoosh of water through the filter."""
    t = S.t_axis(n)
    hum = sum(a * np.sin(2 * np.pi * periodic_tone(n, f) * t) for f, a in ((48.3, 0.5), (100, 1.0), (144.9, 0.3), (200, 0.2)))
    wh = S.circ_bp(S.noise(n, seed), 200, 900, 2)
    return S.circ_lp(hum / np.std(hum) * 0.6 + wh / np.std(wh), 700, 2)


def street_sweeper(dur, seed):
    """Council street sweeper creeping past in the small hours (mono):
    diesel idle-ish engine, whirring gutter brooms, a pass-by envelope."""
    n = secs(dur)
    t = S.t_axis(n)
    r = np.random.default_rng(seed)
    f = r.uniform(26, 30)
    eng = sum(np.sin(2 * np.pi * f * h * t + h) / h for h in range(1, 10))
    eng = S.lp(eng * (1 + 0.3 * S.lp(S.noise(n, seed), 25)), 700, 2)
    brush = S.bp(S.noise(n, seed + 1), 400, 4000, 2) * (1 + 0.5 * np.sin(2 * np.pi * 7.5 * t))
    env = np.exp(-((t - dur / 2) / (dur / 3.2)) ** 2)
    y = (eng / np.std(eng) * 0.7 + brush / np.std(brush) * 0.5) * env
    return S.fade(y, 0.5, 0.5)


def halyard_tinks(n, seed, clusters=10):
    """Halyards tapping aluminium masts in the boat harbour (circular, mono):
    little gust-driven clusters of dull metallic tinks."""
    r = np.random.default_rng(seed)
    y = np.zeros(n)
    k = secs(0.5)
    tk = S.t_axis(k)
    masts = [r.uniform(1500, 2800) for _ in range(4)]
    for _ in range(clusters):
        at = r.uniform(0, n / SR)
        f0 = masts[int(r.integers(len(masts)))]
        for j in range(int(r.integers(2, 6))):
            s = sum(a * np.sin(2 * np.pi * f0 * m * tk + m) * np.exp(-tk / d)
                    for m, a, d in ((1.0, 1.0, 0.18), (2.32, 0.4, 0.08), (4.1, 0.2, 0.04)))
            s[: secs(0.003)] *= np.linspace(0, 1, secs(0.003))
            S.place(y, s * r.uniform(0.3, 1.0) * 0.8 ** j, secs(at), wrap=True)
            at += r.uniform(0.25, 0.9)
    return y


def twitter(seed):
    """A small honeyeater/silvereye-ish twitter for the dawn chorus (mono):
    a run of quick high chirps sweeping down or up."""
    r = np.random.default_rng(seed)
    out = []
    for _ in range(int(r.integers(3, 10))):
        L = r.uniform(0.03, 0.09)
        n = secs(L)
        t = S.t_axis(n)
        f0, f1 = r.uniform(3500, 7000), r.uniform(2800, 6500)
        f = f0 + (f1 - f0) * (t / L) ** r.uniform(0.5, 2)
        f *= 1 + 0.04 * np.sin(2 * np.pi * r.uniform(60, 120) * t)
        y = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.15 * np.sin(4 * np.pi * np.cumsum(f) / SR)
        out.append(y * np.hanning(n))
        out.append(np.zeros(secs(r.uniform(0.03, 0.14))))
    return np.concatenate(out)


def rowing_pass(dur, seed, rate_spm=30):
    """A rowing eight out on the Swan at first light (mono): the catch
    splashes and the oars clunking in their gates, stroke after stroke,
    passing by across the water."""
    r = np.random.default_rng(seed)
    n = secs(dur)
    y = np.zeros(n)
    per = 60 / rate_spm
    tt = 0.3
    k = secs(0.4)
    tk = S.t_axis(k)
    while tt < dur - 0.5:
        for o in range(8):  # eight blades, not quite together
            sp = S.bp(r.standard_normal(k), 500, 4000, 2) * np.exp(-tk / 0.06)
            pl = np.sin(2 * np.pi * r.uniform(150, 220) * tk) * np.exp(-tk / 0.03)
            S.place(y, (sp + 0.6 * pl) * r.uniform(0.5, 1.0) * 0.4, secs(tt + r.normal(0, 0.02)))
        clunk = np.sin(2 * np.pi * r.uniform(500, 650) * tk) * np.exp(-tk / 0.015)
        S.place(y, clunk * 0.3, secs(tt + per * 0.45))
        wash = S.bp(r.standard_normal(secs(0.8)), 300, 2500, 2) * np.hanning(secs(0.8)) * 0.15
        S.place(y, wash, secs(tt + 0.1))
        tt += per * r.uniform(0.97, 1.03)
    t = S.t_axis(n)
    return y * np.exp(-((t - dur / 2) / (dur / 3.5)) ** 2)


def dawn_crickets(dur, seed):
    """Crickets from the night recording, thinned out (dawn: the last few)."""
    x = texture(src("crickets_sub", True), dur, seed, chunk=17, region=(22.5, 82))
    return S.circ_bp(x, 2500, 9000, 1)


# rain ------------------------------------------------------------------------

@builder("amb_northbridge_rain")
def northbridge_rain():
    dur = 90
    B = Bed(dur, 2101)
    n = B.n
    leak = env_window(n, 40, 5, 0.5, 1.0) * 0.4
    B.add(np.stack([club_bass(n, 124, 21011, leak), club_bass(n, 124, 21011, leak * 0.7)], axis=1), -38)
    B.add(S.circ_lp(texture(src("bar_wa", True), dur, 21012, chunk=14), 2200), -39)  # under the awnings
    B.add(S.circ_lp(texture(src("traffic_night", True), dur, 21013, chunk=20), 1600), -37)
    B.add(wet_hiss(n, 21014), -34)
    B.add(city_hum(n, 21015, 40, 250), -42)
    g = gutter(n, 21016)
    B.add(np.stack([g, 0.35 * np.roll(g, secs(0.02))], axis=1), -38)
    B.add(np.stack([drip_points(n, 21017, 10), drip_points(n, 21018, 10)], axis=1), -39)
    for k, at in enumerate(B.times(6, 0.9)):
        y = wet_pass(8.0, 21100 + k, speed=10, dist=9, kind="truck" if k == 3 else "car")
        B.put(pass_stereo(y, k % 2 == 0), at, -15)
    B.put(S.pan(S.lp(siren(11.0, 21019, "wail", 0.95), 2500), 0.5), secs(60), -30)
    save_loop("amb/amb_northbridge_rain", B.x, **LEAN_WET)


@builder("amb_cbd_rain")
def cbd_rain():
    dur = 90
    B = Bed(dur, 2102)
    n = B.n
    B.add(S.circ_lp(texture(src("traffic_peak", True), dur, 21021, chunk=18, avoid_peaks_db=9), 2000), -31)
    B.add(wet_hiss(n, 21022), -30)
    B.add(city_hum(n, 21023, 40, 350), -38)
    g = gutter(n, 21024, 0.8)
    B.add(np.stack([0.3 * g, g], axis=1), -41)
    B.add(np.stack([drip_points(n, 21025, 7), drip_points(n, 21026, 7)], axis=1), -42)
    for k, at in enumerate(B.times(2, 0.6)):
        y = wet_pass(10.0, 21200 + k, speed=8, dist=9, kind="bus")
        B.put(pass_stereo(y, k % 2 == 1), at, -11)
    for k, at in enumerate(B.times(8, 0.9)):
        y = wet_pass(7.0, 21210 + k, speed=13, dist=8 + 6 * B.r.uniform())
        B.put(pass_stereo(y, k % 2 == 0), at, -14)
    # the crossing still tocks; one walk phase (fewer people press it)
    near = ped_sequence(n, 1.0, walk_at=[48.0], beep_at=[41.0], seed=21)
    B.put(S.pan(near, -0.45), 0, -9)
    save_loop("amb/amb_cbd_rain", B.x, **LEAN_WET)


@builder("amb_kingspark_rain")
def kingspark_rain():
    dur = 96
    B = Bed(dur, 2103)
    n = B.n
    # the gums dripping everywhere, near and far
    near = np.stack([drip_points(n, 21031, 12, (0.7, 3.5)), drip_points(n, 21032, 12, (0.7, 3.5))], axis=1)
    B.add(near, -33)
    far = np.stack([S.circ_lp(drip_points(n, 21033 + c, 30, (0.6, 2.5), (1200, 3500)), 3000) for c in range(2)], axis=1)
    B.add(far, -40)
    tr = gutter(n, 21035, 1.4)  # a trickle running off down the path
    B.add(np.stack([S.circ_lp(tr, 1800), 0.5 * S.circ_lp(np.roll(tr, secs(3)), 1800)], axis=1), -43)
    B.add(gum_wind(n, 21036, gust_rate=0.04, crisp=0.15), -43)
    B.add(wet_hiss(n, 21037, 1000, 5000), -42)  # the roads below
    B.add(city_hum(n, 21038, 30, 200), -44)
    B.scatter(bird_pools(), 2, gain_db=(-24, -20), dist=(0.6, 0.85))
    B.scatter(raven_pool(), 1, gain_db=(-24, -22), dist=(0.75, 0.9), room=2.0)
    for k, at in enumerate(B.times(2, 0.7)):
        y = wet_pass(9.0, 21300 + k, speed=12, dist=35)
        B.put(pass_stereo(S.lp(y, 4000), k % 2 == 0), at, -24)
    save_loop("amb/amb_kingspark_rain", B.x, **LEAN_WET)


@builder("amb_river_rain")
def river_rain():
    dur = 100
    B = Bed(dur, 2104)
    n = B.n
    B.add(texture(src("lapping", True), dur, 21041, chunk=20), -29)
    B.add(wet_hiss(n, 21042, 900, 5000), -34)  # wet traffic across the water
    B.add(city_hum(n, 21043, 30, 220), -40)
    B.add(np.stack([drip_points(n, 21044, 5, metal=True), drip_points(n, 21045, 5, metal=True)], axis=1), -44)
    for k, at in enumerate(B.times(4, 0.8)):
        y = wet_pass(10.0, 21400 + k, speed=22, dist=60)
        B.put(pass_stereo(S.lp(y, 2500), k % 2 == 1), at, -24)
    B.scatter(gull_pool(), 2, gain_db=(-26, -22), dist=(0.6, 0.85))
    save_loop("amb/amb_river_rain", B.x, **LEAN_WET)


@builder("amb_suburbs_rain")
def suburbs_rain():
    dur = 110
    B = Bed(dur, 2105)
    n = B.n
    g1, g2 = gutter(n, 21051), gutter(n, 21052, 1.3)
    B.add(np.stack([g1, 0.4 * g1], axis=1) + np.stack([0.25 * g2, 0.7 * g2], axis=1), -33)
    B.add(np.stack([drip_points(n, 21053, 12, (0.6, 3.5)), drip_points(n, 21054, 12, (0.6, 3.5))], axis=1), -35)
    B.add(wet_hiss(n, 21055, 900, 5000), -41)
    B.add(city_hum(n, 21056, 30, 200), -42)
    for k, at in enumerate(B.times(3, 0.8)):
        y = wet_pass(8.0, 21500 + k, speed=11, dist=12)
        B.put(pass_stereo(y, k % 2 == 1), at, -16)
    B.scatter(dog_pool(), 1, gain_db=(-26, -24), dist=(0.75, 0.9), room=2.0)
    B.scatter(raven_pool(), 1, gain_db=(-26, -24), dist=(0.75, 0.9), room=2.0)
    save_loop("amb/amb_suburbs_rain", B.x, **LEAN_WET)


@builder("amb_freeway_rain")
def freeway_rain():
    dur = 80
    B = Bed(dur, 2106)
    n = B.n
    B.add(S.circ_lp(texture(src("freeway", True), dur, 21061, chunk=16, avoid_peaks_db=8), 2200), -31)
    B.add(wet_hiss(n, 21062, 700, 8000), -27)
    B.add(city_hum(n, 21063, 30, 500), -33)
    for k, at in enumerate(B.times(16, 0.9)):
        kind = "truck" if k % 5 == 0 else "car"
        y = wet_pass(6.0 if kind == "car" else 8.0, 21600 + k, speed=B.r.uniform(24, 29),
                     dist=B.r.uniform(12, 30), kind=kind)
        B.put(pass_stereo(y, k % 2 == 0), at, -16 if kind == "car" else -12)
    save_loop("amb/amb_freeway_rain", B.x, **LEAN_WET)


@builder("amb_fremantle_rain")
def fremantle_rain():
    dur = 110
    B = Bed(dur, 2107)
    n = B.n
    B.add(texture(src("lapping", True), dur, 21071, chunk=20), -30)
    B.add(city_hum(n, 21072, 25, 160), -35)
    # drips off container and shed roofs onto steel
    B.add(np.stack([drip_points(n, 21073, 9, (0.6, 3.0), (900, 2200), metal=True),
                    drip_points(n, 21074, 9, (0.6, 3.0), (900, 2200), metal=True)], axis=1), -37)
    g = gutter(n, 21075, 0.7)
    B.add(np.stack([0.5 * g, g], axis=1), -41)
    B.add(wet_hiss(n, 21076, 900, 5000), -41)
    B.put(distant(ship_horn(4.0, 21077, 70), 0.95, -0.5, 1, room=4.0), secs(55), -22)
    for k, at in enumerate(B.times(2, 0.8)):
        B.put(distant(metal_clank(21078 + k, 1.2), 0.9, B.r.uniform(-0.8, 0.8), k, room=3.0), at, -28)
    save_loop("amb/amb_fremantle_rain", B.x, **LEAN_WET)


@builder("amb_beach_rain")
def beach_rain():
    dur = 100
    B = Bed(dur, 2108)
    n = B.n
    B.add(S.circ_lp(texture(src("beach_day", True), dur, 21081, chunk=25), 5000), -26)  # rougher grey surf
    B.add(gum_wind(n, 21082, gust_rate=0.06, crisp=0.0), -35)
    B.add(wet_hiss(n, 21083, 900, 5000), -43)
    B.add(np.stack([drip_points(n, 21084, 4), drip_points(n, 21085, 4)], axis=1), -45)
    for k, at in enumerate(B.times(2, 0.7)):
        y = wet_pass(9.0, 21800 + k, speed=17, dist=40)
        B.put(pass_stereo(S.lp(y, 3500), k % 2 == 0), at, -24)
    B.scatter(gull_pool(), 1, gain_db=(-26, -24), dist=(0.6, 0.8))
    save_loop("amb/amb_beach_rain", B.x, **LEAN_WET)


# late night (01:00-05:00) ----------------------------------------------------

@builder("amb_northbridge_late")
def northbridge_late():
    dur = 96
    B = Bed(dur, 2201)
    n = B.n
    B.add(fridge_hum(n, 22011), -34)
    B.add(np.stack([ac_unit(n, 22012, 12.5, level=1.0), ac_unit(n, 22013, 15.0, level=0.5, rattle=0.15)], axis=1), -41)
    B.add(S.circ_lp(texture(src("traffic_night", True), dur, 22014, chunk=20), 1400), -42)
    sign = bridge_hum(n, 22015)  # a neon sign left buzzing
    B.add(np.stack([0.3 * sign, sign], axis=1), -50)
    B.put(distant(street_sweeper(22.0, 22016), 0.55, -0.3, 1, room=1.6), secs(20), -18)
    B.put(distant(metal_clank(22017, 0.5), 0.75, 0.6, 2, room=1.8), secs(62), -30)  # a bin lid
    y = car_pass(7.0, 22018, speed=11, dist=12)
    B.put(pass_stereo(S.lp(y, 3000)), secs(80), -21)
    B.put(S.pan(siren(11.0, 22019, "wail", 0.98), -0.6), secs(48), -35)
    save_loop("amb/amb_northbridge_late", B.x, norm="lufs:-27", **LEAN)


@builder("amb_cbd_late")
def cbd_late():
    dur = 100
    B = Bed(dur, 2202)
    n = B.n
    B.add(fridge_hum(n, 22021), -33)
    B.add(np.stack([ac_unit(n, 22022, 13.5, level=1.0), ac_unit(n, 22023, 17.2, level=0.6)], axis=1), -41)
    B.add(np.stack([ac_unit(n, 22024, 9.0, level=0.3), ac_unit(n, 22025, 11.0, level=0.8)], axis=1)[:, ::-1], -46)
    loc = ped_sequence(n, 1.0, seed=22)
    B.put(fold(distant(loc, 0.55, 0.35, 6, room=1.4), n), 0, -27)
    B.put(distant(street_sweeper(24.0, 22026), 0.7, 0.4, 3, room=2.0), secs(55), -22)
    y = car_pass(8.0, 22027, speed=15, dist=30)
    B.put(pass_stereo(S.lp(y, 2500), True), secs(15), -23)
    B.put(distant(metal_clank(22028, 0.6), 0.85, -0.7, 4, room=2.5), secs(88), -31)
    save_loop("amb/amb_cbd_late", B.x, norm="lufs:-27", **LEAN)


@builder("amb_kingspark_late")
def kingspark_late():
    dur = 120
    B = Bed(dur, 2203)
    n = B.n
    B.add(S.circ_lp(texture(src("crickets_sub", True), dur, 22031, chunk=17, region=(22.5, 82)), 7000), -37)
    B.add(gum_wind(n, 22032, gust_rate=0.02, crisp=0.3), -50)
    B.add(fridge_hum(n, 22033), -40)
    owl = src("boobook1")
    ev = find_events(owl, 350, 1200, thresh_db=12, min_len=0.25, max_len=2.0, gap=0.25)
    calls = [S.lp(cut(owl, a, b), 1600, 3) for a, b, _ in ev]
    tt = secs(64)
    for j in range(min(len(calls), 4)):
        B.put(distant(calls[(j + 3) % len(calls)], 0.85, -0.5, j, room=2.4), tt, -16)
        tt += secs(B.r.uniform(1.8, 2.6))
    B.scatter(dog_pool(), 1, gain_db=(-29, -27), dist=(0.9, 0.95), room=2.5)
    y = car_pass(9.0, 22034, speed=13, dist=45)
    B.put(pass_stereo(S.lp(y, 1800)), secs(25), -28)
    save_loop("amb/amb_kingspark_late", B.x, norm="lufs:-27", **LEAN)


@builder("amb_river_late")
def river_late():
    dur = 110
    B = Bed(dur, 2204)
    n = B.n
    B.add(texture(src("lapping", True), dur, 22041, chunk=20), -32)
    hum = bridge_hum(n, 22042)
    B.add(np.stack([hum, np.roll(hum, secs(0.013))], axis=1), -43)
    B.add(fridge_hum(n, 22043), -40)
    B.add(S.circ_bp(texture(src("crickets_sub", True), dur, 22044, chunk=17, region=(22.5, 82)), 2500, 8000), -49)
    y = car_pass(10.0, 22045, speed=22, dist=70)
    B.put(pass_stereo(S.lp(y, 1600), True), secs(70), -27)
    B.put(distant(halyard_tinks(secs(6), 22046, 2), 0.8, 0.6, 5, room=2.0), secs(30), -30)  # a mooring
    save_loop("amb/amb_river_late", B.x, norm="lufs:-27", **LEAN)


@builder("amb_suburbs_late")
def suburbs_late():
    dur = 120
    B = Bed(dur, 2205)
    n = B.n
    B.add(S.circ_lp(texture(src("crickets_sub", True), dur, 22051, chunk=17, region=(22.5, 82)), 7000), -35)
    B.add(fridge_hum(n, 22052), -41)
    pp = pool_pump(n, 22053)
    B.add(np.stack([0.4 * pp, pp], axis=1), -45)
    B.scatter(dog_pool(), 1, gain_db=(-27, -25), dist=(0.85, 0.95), room=2.2)
    y = car_pass(8.0, 22054, speed=11, dist=20)
    B.put(pass_stereo(S.lp(y, 2200)), secs(90), -24)
    B.put(S.pan(siren(11.0, 22055, "wail", 0.99), 0.7), secs(35), -36)
    save_loop("amb/amb_suburbs_late", B.x, norm="lufs:-27", **LEAN)


@builder("amb_freeway_late")
def freeway_late():
    dur = 100
    B = Bed(dur, 2206)
    n = B.n
    B.add(texture(src("highway_wa", True), dur, 22061, chunk=20, avoid_peaks_db=6), -36)
    B.add(fridge_hum(n, 22062), -37)
    for k, at in enumerate(B.times(3, 0.8)):
        kind = "truck" if k == 1 else "car"
        y = car_pass(9.0, 22063 + k, speed=B.r.uniform(27, 30), dist=B.r.uniform(20, 35), kind=kind)
        B.put(pass_stereo(y, k % 2 == 1), at, -15 if kind == "truck" else -18)
    save_loop("amb/amb_freeway_late", B.x, norm="lufs:-27", **LEAN)


@builder("amb_fremantle_late")
def fremantle_late():
    dur = 110
    B = Bed(dur, 2207)
    n = B.n
    B.add(texture(src("lapping", True), dur, 22071, chunk=20), -31)
    B.add(city_hum(n, 22072, 25, 140), -37)
    B.add(np.stack([ac_unit(n, 22073, 8.0, level=1.0), ac_unit(n, 22074, 6.5, level=1.0)], axis=1), -45)
    ht = halyard_tinks(n, 22075, 9)
    B.add(fold(distant(ht, 0.6, 0.3, 7, room=1.8), n), -36)
    B.put(distant(metal_clank(22076, 1.4), 0.92, -0.7, 2, room=3.0), secs(75), -29)
    save_loop("amb/amb_fremantle_late", B.x, norm="lufs:-27", **LEAN)


@builder("amb_beach_late")
def beach_late():
    dur = 110
    B = Bed(dur, 2208)
    n = B.n
    B.add(texture(src("beach_night", True), dur, 22081, chunk=25), -27)
    B.add(gum_wind(n, 22082, gust_rate=0.03, crisp=0.0), -46)
    B.add(fridge_hum(n, 22083), -46)
    y = car_pass(10.0, 22084, speed=17, dist=60)
    B.put(pass_stereo(S.lp(y, 1500)), secs(40), -29)
    save_loop("amb/amb_beach_late", B.x, norm="lufs:-27", **LEAN)


# dawn (05:00-07:00): the magpies' carolling is the Perth dawn ----------------

@builder("amb_kingspark_dawn")
def kingspark_dawn():
    dur = 100
    B = Bed(dur, 2301)
    n = B.n
    B.add(texture(src("walyunga", True), dur, 23011, chunk=24, avoid_peaks_db=8), -36)
    B.add(dawn_crickets(dur, 23012), -44)
    B.add(gum_wind(n, 23013, gust_rate=0.04, crisp=0.6), -40)
    B.add(city_hum(n, 23014, 30, 200), -45)
    B.scatter(bird_pools(), 20, gain_db=(-15, -4), dist=(0.15, 0.75))  # carolling all round
    B.scatter([twitter(23100 + i) for i in range(8)], 12, gain_db=(-24, -13), dist=(0.2, 0.6))
    kk = [cut(src("kook_kp"), secs(a), secs(a + L)) for a, L in ((16, 9), (22, 8), (2, 6))]
    B.put(distant(kk[0], 0.5, 0.5, 1), secs(22), -8)  # the family greeting the sun
    B.put(distant(kk[1], 0.75, -0.6, 2), secs(70), -13)
    rv = snips("raven_db", 300, 3000, thresh_db=14, min_len=0.8, max_len=4, best=True, n=4)
    B.put(distant(rv[0], 0.8, -0.8, 4), secs(48), -18)
    save_loop("amb/amb_kingspark_dawn", B.x, **LEAN_WET)


@builder("amb_suburbs_dawn")
def suburbs_dawn():
    dur = 110
    B = Bed(dur, 2302)
    n = B.n
    B.add(dawn_crickets(dur, 23021), -43)
    B.add(S.circ_lp(texture(src("traffic_night", True), dur, 23022, chunk=20), 1600), -41)
    B.add(gum_wind(n, 23023, gust_rate=0.04, crisp=0.6), -43)
    B.add(city_hum(n, 23024, 30, 200), -44)
    # the retic comes on at dawn a couple of yards over
    sp = texture(src("sprinkler", True), dur, 23025, chunk=9.0, xf=0.3)
    B.add(S.circ_lp(sp, 4000) * env_window(n, 15, 40, 2, 2)[:, None], -42)
    B.scatter(bird_pools(), 16, gain_db=(-17, -5), dist=(0.2, 0.8))
    wg = snips("wagtail1", 2000, 8000, thresh_db=14, min_len=0.6, max_len=3.0, gap=0.35)
    B.scatter(wg, 4, gain_db=(-20, -13), dist=(0.25, 0.55))
    B.scatter([twitter(23200 + i) for i in range(8)], 8, gain_db=(-25, -15), dist=(0.25, 0.6))
    B.scatter(raven_pool(), 2, gain_db=(-22, -17), dist=(0.6, 0.85))
    B.scatter(dog_pool(), 1, gain_db=(-26, -24), dist=(0.8, 0.9), room=2.0)
    y = car_pass(7.0, 23026, speed=10, dist=14)  # someone off to an early shift
    B.put(pass_stereo(y), secs(80), -20)
    save_loop("amb/amb_suburbs_dawn", B.x, **LEAN_WET)


@builder("amb_river_dawn")
def river_dawn():
    dur = 100
    B = Bed(dur, 2303)
    n = B.n
    B.add(texture(src("lapping", True), dur, 23031, chunk=20), -30)
    B.add(gum_wind(n, 23032, gust_rate=0.04, crisp=0.2), -42)
    B.add(city_hum(n, 23033, 35, 250), -41)
    B.scatter(bird_pools(), 10, gain_db=(-19, -8), dist=(0.3, 0.8))
    B.scatter(gull_pool(), 4, gain_db=(-20, -13), dist=(0.3, 0.75))
    B.scatter([twitter(23300 + i) for i in range(6)], 4, gain_db=(-26, -18), dist=(0.4, 0.7))
    B.put(distant(rowing_pass(26.0, 23034), 0.55, 0.2, 3, room=2.0), secs(30), -17)
    save_loop("amb/amb_river_dawn", B.x, **LEAN_WET)


@builder("amb_beach_dawn")
def beach_dawn():
    dur = 100
    B = Bed(dur, 2304)
    n = B.n
    B.add(texture(src("beach_night", True), dur, 23041, chunk=25), -26)  # calm morning sea
    B.add(gum_wind(n, 23042, gust_rate=0.04, crisp=0.0), -40)
    B.scatter(gull_pool(), 5, gain_db=(-20, -11), dist=(0.2, 0.7))
    B.scatter(bird_pools(), 5, gain_db=(-24, -15), dist=(0.55, 0.85))  # in the dunes behind
    B.scatter([twitter(23400 + i) for i in range(4)], 3, gain_db=(-27, -20), dist=(0.5, 0.75))
    save_loop("amb/amb_beach_dawn", B.x, **LEAN_WET)


# ---- one-shots ---------------------------------------------------------------

def oneshot(name, y, hp_hz=120):
    y = S.hp(y, hp_hz, 2)
    y = S.fade(y, 0.01, 0.08)
    S.save(name, y, norm="peak")


@builder("amb_bird_oneshots")
def bird_oneshots():
    # Australian raven: the long falling 'aah-aah-aaaah'
    rv = (find_events(src("raven_db"), 250, 3000, thresh_db=15, min_len=1.0, max_len=4.5, gap=0.35)
          + [])
    rv = sorted(rv, key=lambda e: -e[2])
    rx = src("raven_db")
    for i, (a, b, _) in enumerate(rv[:3]):
        oneshot(f"amb/amb_bird_raven_{i + 1:02d}", cut(rx, a, b), 200)
    # magpie warbles: two carols from Kings Park, one close suburban warble
    kp = src("mag_kp2")
    oneshot("amb/amb_bird_magpie_01", cut(kp, secs(17.8), secs(21.4), 0.03, 0.25), 400)
    oneshot("amb/amb_bird_magpie_02", cut(kp, secs(36.3), secs(39.6), 0.03, 0.25), 400)
    dl = src("mag_dl")
    ev = find_events(dl, 900, 6000, thresh_db=18, min_len=1.5, max_len=5.0, gap=0.4)
    a, b, _ = max(ev, key=lambda e: e[2])
    oneshot("amb/amb_bird_magpie_03", cut(dl, a, b, 0.03, 0.2), 400)
    # kookaburra laughs: the Kings Park family, two different bursts
    kk = src("kook_kp")
    oneshot("amb/amb_bird_kookaburra_01", cut(kk, secs(17.0), secs(25.5), 0.05, 0.6), 250)
    oneshot("amb/amb_bird_kookaburra_02", cut(kk, secs(33.5), secs(41.0), 0.05, 0.6), 250)
    # willie wagtail chatter: the two clearest phrases of the cleaner take
    x = src("wagtail1")
    ev = find_events(x, 2000, 8000, thresh_db=14, min_len=0.8, max_len=3.0, gap=0.35)
    ev = sorted(ev, key=lambda e: -e[2])[:2]
    for i, (a, b, _) in enumerate(sorted(ev)):
        oneshot(f"amb/amb_bird_wagtail_{i + 1:02d}", cut(x, a, b), 1500)


@builder("amb_misc_oneshots")
def misc_oneshots():
    # dogs barking far off: short runs of barks
    pool = []
    for k in ("dogs_far", "dog_far2"):
        x = src(k)
        for a, b, s in find_events(x, 300, 3000, thresh_db=12, min_len=0.3, max_len=3.0, gap=0.6):
            pool.append((s, k, a, b))
    # prefer runs of several barks (longer events) that are still clear
    pool.sort(key=lambda c: -(c[0] + 8 * min((c[3] - c[2]) / SR, 2.0)))
    for i, (_, k, a, b) in enumerate(pool[:3]):
        y = cut(src(k), a, b, 0.01, 0.15)
        y = distant(y, 0.5, 0, i, room=1.6).mean(axis=1)
        oneshot(f"amb/amb_dog_bark_far_{i + 1:02d}", y, 150)
    oneshot("amb/amb_siren_distant_01", siren(11.0, 501, "wail", 0.8), 150)
    oneshot("amb/amb_siren_distant_02", siren(10.0, 502, "yelp", 0.85), 150)
    oneshot("amb/amb_train_pass_01", train_pass(13.0, 601, speed=24, dist=25, cars=4), 40)
    oneshot("amb/amb_train_pass_02", train_pass(16.0, 602, speed=15, dist=45, cars=6, brake=True), 40)
    bell = crossing_bell_loop()
    check_seam(bell[:, None].repeat(2, 1), "amb_crossing_bells_loop")
    S.save("amb/amb_crossing_bells_loop", bell, norm="peak")
    # pedestrian crossing parts, for placing on actual crossings in 3D
    n = secs(4.0)
    S.save("amb/amb_ped_locator_loop", ped_sequence(n, 1.0, seed=7), norm="peak")
    w = np.zeros(secs(2.0))
    for i in range(28):
        S.place(w, ped_tock(1.0, 8), secs(i / 14), wrap=True)
    S.save("amb/amb_ped_walk_loop", w, norm="peak")
    S.save("amb/amb_ped_beep", S.fade(np.concatenate([ped_beep(), np.zeros(secs(0.05))]), 0, 0.02), norm="peak")


# --------------------------------------------------------------------------
# Night oddities (audio/oddity/)
# --------------------------------------------------------------------------
# No speech synthesiser is installed (no espeak/flite), so the voices are real
# CC0 recordings made wordless: a man reading a story (voice_reader), cut into
# syllables that are each played backwards and re-sequenced into calm reading
# groups, and real whispering (whisper_ind, whisper_four), also reversed. The
# timbre, breath and cadence stay human; no words survive. VOWELS is still
# used by the choir drone below.

VOWELS = {  # F1, F2, F3 (Hz), adult male-ish
    "a": (730, 1090, 2440), "e": (530, 1840, 2480), "i": (270, 2290, 3010),
    "o": (570, 840, 2410), "u": (300, 870, 2240), "@": (500, 1500, 2500),
    "I": (390, 1990, 2550), "ae": (660, 1720, 2410), "O": (450, 950, 2500),
}


def level(v, ratio=0.35, ceil_pct=99.0):
    """Broadcast-style levelling: a slow compressor, then soft limiting of the
    rarest peaks, so a recorded voice sits steadily in the static."""
    v = v / (np.abs(v).max() + 1e-9)
    env = S.lp(np.abs(v), 12, 1)
    thr = np.percentile(env[env > 1e-3], 50)
    v = v * np.where(env > thr, (np.maximum(env, 1e-9) / thr) ** (ratio - 1), 1.0)
    c = np.percentile(np.abs(v[np.abs(v) > 1e-4]), ceil_pct)
    return np.tanh(v / c)


_units: dict[str, list[np.ndarray]] = {}


def reversed_syllables(key):
    """Syllable/word-sized pieces of a recorded voice, each reversed so
    nothing is intelligible."""
    if key not in _units:
        x = src(key)
        us = []
        for a, b, _ in find_events(x, 150, 5000, thresh_db=15, min_len=0.12, max_len=0.55, gap=0.04, pad=0.02):
            u = x[a:b][::-1].copy()
            us.append(S.fade(u, min(0.04, len(u) / SR / 4), min(0.06, len(u) / SR / 4)))
        _units[key] = us
    return _units[key]


def reversed_reader(dur, seed, slow=0.88, group=(3, 6), pause=(0.7, 1.6)):
    """A calm voice reading groups, built from reversed syllables of a real
    reader, slowed a little: human timbre and cadence, no words."""
    r = np.random.default_rng(seed)
    us = reversed_syllables("voice_reader")
    n = secs(dur)
    y = np.zeros(n + secs(2))
    t = 0.2
    while t < dur - 1.0:
        g = r.uniform(0.7, 1.0)
        for j in range(int(r.integers(*group))):
            u = rate(us[int(r.integers(len(us)))], slow * r.uniform(0.98, 1.02))
            u = u / (np.sqrt(np.mean(u ** 2)) + 1e-9) * g * (1 - 0.06 * j)
            if t + len(u) / SR > dur - 0.3:
                break
            S.place(y, u, secs(t))
            t += len(u) / SR + r.uniform(0.02, 0.12)
        t += r.uniform(*pause)
    y = y[:n]
    # a faint second take a hair behind and detuned: two mouths, one voice
    ghost = np.concatenate([np.zeros(secs(0.03)), rate(y, 0.995)])[:n]
    return level(y + 0.3 * ghost)


def reversed_whispers(dur, seed, key):
    """Real whispering played backwards, cut into phrases with pauses."""
    r = np.random.default_rng(seed)
    x = src(key)
    ref = np.std(x)
    n = secs(dur)
    y = np.zeros(n + secs(3))
    t = r.uniform(0.2, 0.6)
    while t < dur - 0.6:
        L = r.uniform(0.8, 2.0)
        for _ in range(20):  # skip stretches with no whispering in them
            a = int(r.integers(0, len(x) - secs(L) - 1))
            if np.std(x[a:a + secs(L)]) > 0.7 * ref:
                break
        seg = S.fade(x[a:a + secs(L)][::-1].copy(), 0.15, 0.25)
        S.place(y, seg / (np.sqrt(np.mean(seg ** 2)) + 1e-9) * r.uniform(0.6, 1.0), secs(t))
        t += L + r.uniform(0.25, 0.8)
    return level(y[:n])


def radio_static(n, seed, crackle=1.0, circular=False):
    """AM/shortwave static: band-limited hiss, crackles, a drifting
    heterodyne whistle, 50 Hz buzz."""
    r = np.random.default_rng(seed)
    t = S.t_axis(n)
    if circular:
        hiss = S.circ_bp(S.noise(n, seed), 250, 3500, 2)
    else:
        hiss = S.bp(S.noise(n, seed), 250, 3500, 2)
    imp = (r.random(n) < 25 / SR) * r.standard_normal(n) * 6
    cr = S.circ_bp(imp, 400, 4000, 1) if circular else S.bp(imp, 400, 4000, 1)
    sm = S.smooth_noise(n, 0.07, seed + 1, periodic=circular)
    if circular:
        f = periodic_tone(n, 1100)
        wh = 0.05 * np.sin(2 * np.pi * np.cumsum(f + 0 * t) / SR + 3 * np.sin(2 * np.pi * periodic_tone(n, 0.05) * t))
    else:
        wh = 0.05 * np.sin(2 * np.pi * np.cumsum(900 + 300 * sm) / SR)
    buzz = 0.04 * np.sign(np.sin(2 * np.pi * 50 * t)) if not circular else 0.0
    return hiss * 0.5 + cr * 0.6 * crackle + wh + buzz


def radio_fx(voice, seed, fade_depth=0.6):
    """Put a voice on a weak AM signal: band-limit, mild clip, selective
    fading and a slow pitch wobble."""
    n = len(voice)
    wob = 1 + 0.004 * S.smooth_noise(n, 0.4, seed, periodic=False)
    idx = np.cumsum(wob)
    idx = idx * (n - 1) / idx[-1]
    v = np.interp(idx, np.arange(n), voice)
    v = S.bp(v, 320, 2800, 2)
    v = np.tanh(1.6 * v / (np.abs(v).max() + 1e-9))
    qsb = 1 - fade_depth * (0.5 + 0.5 * np.tanh(2 * S.smooth_noise(n, 0.25, seed + 1, periodic=False)))
    return v * qsb


def interval_signal(seed):
    """Opening tones of the 'station': three soft sine-ish pips, a small
    falling tune on a music-box-like tone."""
    notes = [(0.0, 659.3), (0.45, 587.3), (0.9, 523.3), (1.6, 392.0)]
    L = secs(2.6)
    y = np.zeros(L)
    for at, f in notes:
        k = secs(0.9)
        tk = S.t_axis(k)
        s = (np.sin(2 * np.pi * f * tk) + 0.25 * np.sin(2 * np.pi * 2 * f * tk)) * np.exp(-tk / 0.35)
        S.place(y, S.fade(s, 0.004, 0.1), secs(at))
    return y


@builder("odd_midnight_station")
def midnight_station():
    for i, (dur, seed) in enumerate(((28.0, 9001), (35.0, 9002), (24.0, 9003))):
        n = secs(dur)
        y = np.zeros(n)
        intro = interval_signal(seed)
        S.place(y, intro * 0.5, secs(0.8))
        # the reading: groups of reversed syllables from a real reader
        v = reversed_reader(dur - 4.0, seed, slow=0.84 + 0.04 * i)
        S.place(y, v / (np.abs(v).max() + 1e-9), secs(3.6))
        # a pip between groups now and then
        r = np.random.default_rng(seed)
        for at in np.arange(9.0, dur - 3, r.uniform(7, 9)):
            k = secs(0.12)
            S.place(y, 0.25 * np.sin(2 * np.pi * 1000 * S.t_axis(k)) * np.hanning(k), secs(at))
        sig = radio_fx(y, seed + 10, 0.55)
        st = radio_static(n, seed + 20)
        mix = sig * 1.0 + st * 0.22
        mix = S.lp(S.fade(mix, 1.2, 2.0), 3800, 4)
        S.save(f"oddity/odd_midnight_station_{i + 1:02d}", mix, norm="lufs:-23")


@builder("odd_static_whisper")
def static_whisper():
    for i in range(5):
        seed = 9100 + i
        r = np.random.default_rng(seed)
        dur = float(r.uniform(3.5, 8.0))
        n = secs(dur)
        v = reversed_whispers(dur, seed, ("whisper_ind", "whisper_four")[i % 2 == 0])
        # sometimes two voices overlapping, slightly apart
        if i % 2 == 1:
            v = v + 0.6 * np.roll(reversed_whispers(dur, seed + 50, "whisper_four"), secs(0.7))
        sig = radio_fx(v, seed + 1, 0.7) * 0.65
        st = radio_static(n, seed + 2, crackle=0.6)
        mix = S.lp(S.fade(sig + st * 0.5, 0.6, 1.0), 3800, 4)
        S.save(f"oddity/odd_static_whisper_{i + 1:02d}", mix, norm="lufs:-28")


def choir_drone(n, seed, chord=(55.0, 82.4, 110.0, 130.8, 164.8), vowel="o"):
    """Choir-like drone: detuned sawtooth voices through vowel formants with
    slow breathing swells; every frequency is chosen to loop exactly."""
    t = S.t_axis(n)
    r = np.random.default_rng(seed)
    out = np.zeros((n, 2))
    F = VOWELS[vowel]
    for k, f in enumerate(chord):
        for c in range(2):
            for d in (-1, 1):
                ff = periodic_tone(n, f * (1 + d * 0.0025 * (1 + c)))
                ph = 2 * np.pi * ff * t + r.uniform(0, 6)
                saw = sum(np.sin(h * ph) / h for h in range(1, 14))
                swell = 0.6 + 0.4 * np.sin(2 * np.pi * periodic_tone(n, 0.03 + 0.01 * k) * t + r.uniform(0, 6))
                out[:, c] += saw * swell / len(chord)
    resp = lambda f: sum(a / (1 + ((f - fc) / (bw)) ** 2) for fc, bw, a in zip(F, (80, 120, 200), (1, 0.6, 0.3)))
    return np.stack([S.circ_filter(out[:, c], S.circ_response(n, resp)) for c in range(2)], axis=1)


@builder("odd_river_lights_loop")
def river_lights():
    dur = 60
    n = secs(dur)
    ch = choir_drone(n, 9201)
    ch = S.reverb(ch.mean(axis=1), size_s=4.0, damp_hz=3000, wet=0.6, circular=True, seed=9)
    hum = bridge_hum(n, 9202)
    low = np.stack([S.circ_lp(S.brown(n, 9203 + c), 80, 2) for c in range(2)], axis=1)
    x = ch / np.sqrt(np.mean(ch ** 2)) * db(-24) + S.stereo(hum) / np.sqrt(np.mean(hum ** 2)) * db(-36) \
        + low / np.sqrt(np.mean(low ** 2)) * db(-34)
    x += radio_static(n, 9204, crackle=0.2, circular=True)[:, None] * db(-48)
    save_loop("oddity/odd_river_lights_loop", x, norm="amb")


@builder("odd_discovery_sting")
def discovery_sting():
    dur = 4.5
    n = secs(dur)
    t = S.t_axis(n)
    # soft swell of a choir cluster, a glassy bell on top, fading into static
    ch = choir_drone(n, 9301, chord=(146.8, 155.6, 220.0, 293.7), vowel="u").mean(axis=1)
    sw = np.clip(t / 2.2, 0, 1) ** 2 * np.exp(-np.maximum(t - 2.4, 0) / 0.8)
    bell = np.zeros(n)
    for m, a in ((1, 1), (2.76, 0.4), (5.4, 0.2)):
        bell += (a * np.sin(2 * np.pi * 880 * m * t) * np.exp(-np.maximum(t - 2.2, 0) / (1.2 / m))
                 * np.clip((t - 2.2) / 0.03, 0, 1))
    st = S.bp(S.noise(n, 9302), 400, 3000, 2) * np.clip((t - 2.6) / 1.5, 0, 1) * np.exp(-np.maximum(t - 3.8, 0) / 0.3)
    y = ch / (np.abs(ch).max() + 1e-9) * sw + 0.25 * bell + 0.1 * st
    y = S.reverb(y, size_s=3.0, damp_hz=4000, wet=0.35, seed=9303)
    y = S.fade(y, 0.05, 0.6)
    S.save("oddity/odd_discovery_sting", y, norm="lufs:-20")


@builder("odd_lane_idle_loop")
def lane_idle():
    """A classic 500 (499 cc parallel twin) idling at the end of the lane:
    lumpy ~15 Hz firing, a slightly lazy, detuned idle, heard from afar."""
    dur = 40
    n = secs(dur)
    eng = engine_idle(n, 9401, rpm=880, cyl=2, rough=0.18, muffler=420, wobble=0.035, miss=0.015)
    eng2 = engine_idle(n, 9402, rpm=880 * 1.012, cyl=2, rough=0.1, muffler=300, wobble=0.03)  # slight detune
    y = eng + 0.4 * eng2
    y = S.circ_lp(y, 900, 2)
    st = S.reverb(y, size_s=1.6, damp_hz=1800, wet=0.45, circular=True, seed=9403)
    night = np.stack([S.circ_bp(S.noise(n, 9404 + c), 1500, 6000, 1) for c in range(2)], axis=1)
    x = st / np.sqrt(np.mean(st ** 2)) * db(-26) + night * db(-52)
    x = pan_const(x, 0.15)
    save_loop("oddity/odd_lane_idle_loop", x, norm="amb")


@builder("odd_lane_idle_cutout")
def lane_idle_cutout():
    """The lane 500 cutting out just before you reach it: the same lumpy idle
    as odd_lane_idle_loop (crossfade into this), sagging, missing, one last
    cough, then the hot exhaust ticking as it cools in the quiet."""
    dur = 9.0
    n = secs(dur)
    r = np.random.default_rng(9451)
    t = S.t_axis(n)
    # firing rate: steady idle, then the revs sag away over ~2 s from 1.4 s
    rpm = np.where(t < 1.4, 880.0, 880.0 * np.exp(-(t - 1.4) / 0.9))
    rpm *= 1 + 0.03 * S.smooth_noise(n, 0.5, 9452, periodic=False)
    ph = np.cumsum(rpm / 60) / SR
    idx = np.flatnonzero(np.diff(np.floor(ph)) > 0) + 1
    pk = secs(0.06)
    tk = S.t_axis(pk)
    eng = np.zeros(n)
    for at in idx:
        tt = at / SR
        if rpm[at] < 260:
            break
        if tt > 1.6 and r.random() < 0.25:
            continue  # missing as it dies
        a = (1 + 0.18 * r.standard_normal()) * min(1.0, rpm[at] / 700)
        pop = (np.sin(2 * np.pi * r.uniform(55, 75) * tk) * np.exp(-tk / 0.014)
               + 0.5 * r.standard_normal(pk) * np.exp(-tk / 0.004))
        S.place(eng, pop * a, at)
    last = idx[idx < n][-1] / SR if len(idx) else 3.0
    # one last cough after the stop, then a shudder of the engine on its mounts
    cough = S.lp(S.noise(secs(0.18), 9453), 500, 2) * np.exp(-S.t_axis(secs(0.18)) / 0.05)
    S.place(eng, 1.3 * cough, secs(last + 0.35))
    shud = np.sin(2 * np.pi * 9 * S.t_axis(secs(0.6))) * np.exp(-S.t_axis(secs(0.6)) / 0.15)
    S.place(eng, 0.6 * S.lp(shud * S.noise(secs(0.6), 9454), 200, 2), secs(last + 0.45))
    eng = S.lp(eng, 420, 2)
    eng += 0.15 * S.bp(S.noise(n, 9455), 800, 4000, 1) * np.abs(S.lp(eng, 30, 1)) * 4
    eng = S.lp(eng, 900, 2)
    # cooling exhaust ticks, sparse and slowing
    ticks = np.zeros(n)
    at = last + 1.3
    gap = 0.35
    while at < dur - 0.4:
        k = secs(0.02)
        tick = S.bp(S.noise(k, int(at * 1000)), 2500, 6000, 1) * np.exp(-S.t_axis(k) / 0.003)
        S.place(ticks, tick * r.uniform(0.5, 1.0), secs(at))
        gap *= r.uniform(1.1, 1.45)
        at += gap + r.uniform(0, 0.2)
    y = eng / np.sqrt(np.mean(eng[: secs(1.4)] ** 2)) * db(-26) + ticks * db(-30)
    st = S.reverb(y, size_s=1.6, damp_hz=1800, wet=0.45, seed=9403)
    night = np.stack([S.bp(S.noise(n, 9404 + c), 1500, 6000, 1) for c in range(2)], axis=1)
    x = pan_const(st + night * db(-47), 0.15)
    # match the idle loop's level (-24 LUFS) over the steady first 1.4 s
    import pyloudnorm
    head = np.concatenate([x[: secs(1.4)]] * 2)
    x *= db(-24 - pyloudnorm.Meter(SR).integrated_loudness(head))
    S.save("oddity/odd_lane_idle_cutout", S.fade(x, 0.02, 0.8), norm="none")


@builder("odd_follower_engine_loop")
def follower_engine():
    """A car keeping its distance behind you in Kings Park at night: a small
    four-cylinder at a steady ~2200 rpm, throttle easing on and off as it
    matches your speed, tyres on the road, all far off through the trees.
    Mono, for a positional player kept 60-120 m behind the car."""
    dur = 40
    n = secs(dur)
    t = S.t_axis(n)
    eng = engine_idle(n, 9501, rpm=2200, cyl=4, rough=0.08, muffler=380, wobble=0.06)
    eng = eng / np.sqrt(np.mean(eng ** 2))
    # throttle: slow swells that loop (periods divide the loop length)
    thr = 0.6 + 0.25 * np.sin(2 * np.pi * t / 20 + 0.7) + 0.15 * np.sin(2 * np.pi * t / 8 + 2.1)
    road = S.circ_bp(S.pink(n, 9502), 90, 700, 2)
    road = road / np.sqrt(np.mean(road ** 2))
    y = eng * thr * db(-4) + road * db(-10)
    y = S.circ_lp(y, 700, 2)
    y = S.reverb(y, size_s=2.2, damp_hz=1400, wet=0.5, circular=True, seed=9503).mean(axis=1)
    save_loop("oddity/odd_follower_engine_loop", y, norm="amb")


@builder("odd_river_lights_shimmer")
def river_lights_shimmer():
    """The lights on the river appearing: a faint glassy shimmer of high,
    slowly beating partials that swells and dissolves. Play once over
    odd_river_lights_loop when they come on."""
    dur = 7.0
    n = secs(dur)
    t = S.t_axis(n)
    r = np.random.default_rng(9601)
    out = np.zeros((n, 2))
    for k, f in enumerate((1318.5, 1975.5, 2637.0, 3135.9, 3951.1)):
        for c in range(2):
            ff = f * (1 + r.uniform(-0.004, 0.004))
            am = 0.5 + 0.5 * np.sin(2 * np.pi * r.uniform(2.5, 6.0) * t + r.uniform(0, 6))
            out[:, c] += np.sin(2 * np.pi * ff * t + r.uniform(0, 6)) * am / (k + 1.5)
    env = np.clip(t / 2.5, 0, 1) ** 2 * np.exp(-np.maximum(t - 2.8, 0) / 1.3)
    air = np.stack([S.bp(S.noise(n, 9602 + c), 5000, 11000, 1) for c in range(2)], axis=1) * 0.08
    y = (out + air) * env[:, None]
    y = np.stack([S.reverb(y[:, c], size_s=3.5, damp_hz=6000, wet=0.55, seed=9603 + c).mean(axis=1)
                  for c in range(2)], axis=1)
    S.save("oddity/odd_river_lights_shimmer", S.fade(y, 0.05, 1.0), norm="lufs:-30")


@builder("odd_midnight_station_found")
def midnight_station_found():
    """Finding the midnight station: its falling music-box interval signal
    surfacing out of static, then the soft choir cluster and glassy bell of
    odd_discovery_sting closing over it. Plays once on the radio's Music bus."""
    dur = 7.0
    n = secs(dur)
    t = S.t_axis(n)
    y = np.zeros(n)
    S.place(y, interval_signal(9701) * 0.6, secs(0.6))
    sig = radio_fx(y, 9702, 0.35)
    st = radio_static(n, 9703, crackle=0.6) * 0.25
    st *= np.clip(1.2 - t / 4.0, 0.05, 1)  # the static clears as the signal locks
    radio = S.lp(sig + st, 3800, 4)
    ch = choir_drone(n, 9704, chord=(130.8, 155.6, 196.0, 261.6), vowel="u").mean(axis=1)
    sw = np.clip((t - 2.6) / 2.0, 0, 1) ** 2 * np.exp(-np.maximum(t - 5.0, 0) / 0.9)
    bell = np.zeros(n)
    for m, a in ((1, 1), (2.76, 0.4), (5.4, 0.2)):
        bell += (a * np.sin(2 * np.pi * 523.3 * m * t) * np.exp(-np.maximum(t - 4.4, 0) / (1.4 / m))
                 * np.clip((t - 4.4) / 0.03, 0, 1))
    m = radio / (np.abs(radio).max() + 1e-9) * 0.7 + ch / (np.abs(ch).max() + 1e-9) * sw * 0.8 + 0.2 * bell
    m = S.reverb(m, size_s=3.0, damp_hz=4000, wet=0.3, seed=9705)
    S.save("oddity/odd_midnight_station_found", S.fade(m, 0.05, 1.0), norm="lufs:-20")


# ---- the mystery arc: clues, the key, the shed --------------------------------
# Same rules as the oddities above: quiet, soft attacks (>= 10 ms on anything
# tonal), nothing jumpy. The midnight station's falling interval (E D C G)
# is the arc's motif and turns up in the key, the shed and nowhere else.

INTERVAL_NOTES = [(0.0, 659.3), (0.45, 587.3), (0.9, 523.3), (1.6, 392.0)]  # as interval_signal()


def tine(f, dur, seed, kind="musicbox", attack=0.012):
    """One soft struck-metal note, mono. musicbox: comb tine (bright, short
    upper partials); celesta: hammered steel bar over a resonator (rounder,
    longer). The attack is softened so nothing clicks."""
    n = secs(dur)
    t = S.t_axis(n)
    r = np.random.default_rng(seed)
    parts = {"musicbox": ((1, 1.0, 1.1), (2.0, 0.3, 0.5), (5.4, 0.12, 0.12), (8.9, 0.05, 0.06)),
             "celesta": ((1, 1.0, 1.4), (2.0, 0.22, 0.6), (3.98, 0.12, 0.25), (6.1, 0.04, 0.1))}[kind]
    y = sum(a * np.sin(2 * np.pi * f * m * t + r.uniform(0, 6)) * np.exp(-t / d) for m, a, d in parts)
    y *= np.clip(t / attack, 0, 1) ** 2
    return S.fade(y, 0, min(0.2, dur / 4))


def tape_warble(x, seed, wow=0.004, flutter=0.0012):
    """Old cassette playback: slow wow and fast flutter as a time-warp."""
    n = len(x)
    t = S.t_axis(n)
    r = np.random.default_rng(seed)
    sp = 1 + wow * np.sin(2 * np.pi * 0.7 * t + r.uniform(0, 6)) + flutter * np.sin(2 * np.pi * 6.3 * t) \
        + 0.5 * wow * S.smooth_noise(n, 1.5, seed, periodic=False)
    idx = np.clip(np.cumsum(sp) - sp[0], 0, n - 1)
    if x.ndim == 2:
        return np.stack([np.interp(idx, np.arange(n), x[:, c]) for c in range(2)], axis=1)
    return np.interp(idx, np.arange(n), x)


def tape_hiss(n, seed, circular=False):
    f = S.circ_bp if circular else S.bp
    return np.stack([f(S.noise(n, seed + c), 1800, 11000, 1) for c in range(2)], axis=1)


def motif(kind, seed, transpose=1.0, gap=1.0):
    """The station's falling interval on a tine instrument (mono)."""
    y = np.zeros(secs(INTERVAL_NOTES[-1][0] * gap + 2.0))
    for i, (at, f) in enumerate(INTERVAL_NOTES):
        S.place(y, tine(f * transpose, 1.8, seed + i, kind) * (0.85 if i < 3 else 1.0), secs(at * gap))
    return y


def soft_swell(n, rise, fall_at, fall):
    t = S.t_axis(n)
    return np.clip(t / rise, 0, 1) ** 2 * np.exp(-np.maximum(t - fall_at, 0) / fall)


@builder("odd_clue")
def clues():
    # 01: a detuned music-box note under tape warble
    n = secs(2.6)
    a = tine(659.3, 2.6, 9801, attack=0.015)
    b = tine(659.3 * 2 ** (-18 / 1200), 2.6, 9802, attack=0.02)  # a second tine 18 cents flat
    y = np.stack([a + 0.6 * b, 0.6 * a + b], axis=1)
    y = tape_warble(y, 9803) + tape_hiss(n, 9804) * 0.012
    y = S.reverb(y.mean(axis=1), size_s=1.8, damp_hz=4000, wet=0.3, seed=9805) * 0.5 + y * 0.5
    S.save("oddity/odd_clue_01", S.fade(S.lp(y, 7000), 0.01, 0.5), norm="lufs:-26", quality=3)
    # 02: a breath of static with a far chime inside it
    n = secs(2.4)
    t = S.t_axis(n)
    st = S.lp(radio_static(n, 9811, crackle=0.25), 3400, 3) * np.sin(np.pi * np.clip(t / 2.3, 0, 1)) ** 2
    chime = np.zeros(n)
    S.place(chime, tine(1318.5, 1.6, 9812, "celesta", attack=0.02), secs(0.75))
    y = S.stereo(st, 0.7) * 0.5 + distant(chime, 0.8, 0.35, 9813, room=2.0)[:n] * 0.9
    S.save("oddity/odd_clue_02", S.fade(y, 0.02, 0.3), norm="lufs:-26", quality=3)
    # 03: a low glassy swell (glass-harmonica-ish, slowly beating)
    n = secs(2.8)
    t = S.t_axis(n)
    env = np.sin(np.pi * np.clip(t / 2.7, 0, 1)) ** 2
    out = np.zeros((n, 2))
    for c in range(2):
        for m, a in ((1, 1.0), (2, 0.3), (3, 0.12), (4.02, 0.05)):
            f = 233.1 * m * (1 + (0.0035 if c else -0.0035))
            out[:, c] += a * np.sin(2 * np.pi * f * t + m + c)
    y = out * env[:, None]
    y = np.stack([S.reverb(y[:, c], size_s=2.5, damp_hz=5000, wet=0.4, seed=9821 + c).mean(axis=1) for c in range(2)], axis=1)
    S.save("oddity/odd_clue_03", S.fade(y, 0.02, 0.3), norm="lufs:-26", quality=3)
    # 04: a reversed piano note, blooming back out of its own reverb
    n = secs(2.0)
    t = S.t_axis(n)
    f0 = 293.7
    pno = sum(np.sin(2 * np.pi * f0 * h * np.sqrt(1 + 0.0004 * h * h) * t + h) / h ** 1.2 * np.exp(-t / (2.2 / h ** 0.7))
              for h in range(1, 11))
    pno[: secs(0.004)] *= np.linspace(0, 1, secs(0.004))
    pno = S.reverb(pno, size_s=2.2, damp_hz=4500, wet=0.45, seed=9831)
    rev = S.fade(pno[::-1].copy(), 0.0, 0.07)
    rev = np.concatenate([rev, np.zeros((secs(0.8), 2))])
    y = S.reverb(rev.mean(axis=1), size_s=1.6, damp_hz=4000, wet=0.3, seed=9832) * 0.6 + rev * 0.4
    S.save("oddity/odd_clue_04", S.fade(S.lp(y, 6000), 0.05, 0.4), norm="lufs:-26", quality=3)


@builder("odd_clue_more")
def clues_more():
    """Clues 05-07, so each of the seven midnight-station clues can have its
    own cue (odd_clue_0N for clue N), getting a shade closer to the station
    each time."""
    # 05: the station's first two notes on a music box, half-heard through tape
    n = secs(2.8)
    y = np.zeros(n)
    for at, (k, f) in zip((0.2, 0.75), enumerate((659.3, 587.3))):
        S.place(y, tine(f, 1.8, 9841 + k, attack=0.02), secs(at))
    y = tape_warble(np.stack([y, y], axis=1), 9843, wow=0.006) + tape_hiss(n, 9844) * 0.01
    y = S.reverb(y.mean(axis=1), size_s=2.0, damp_hz=3500, wet=0.35, seed=9845) * 0.5 + y * 0.5
    S.save("oddity/odd_clue_05", S.fade(S.lp(y, 6000), 0.02, 0.5), norm="lufs:-26", quality=3)
    # 06: a low bowed note that won't settle on its pitch, with a faint tick of a clock
    n = secs(3.0)
    t = S.t_axis(n)
    f = 110.0 * (1 + 0.006 * np.sin(2 * np.pi * 0.45 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    bow = sum(np.sin(h * ph) / h ** 1.3 for h in range(1, 9)) * (1 + 0.05 * S.smooth_noise(n, 6.0, 9851, periodic=False))
    bow = S.lp(bow, 1800, 2) * np.sin(np.pi * np.clip(t / 2.9, 0, 1)) ** 2
    ticks = np.zeros(n)
    for at in np.arange(0.4, 2.8, 0.5):
        k = secs(0.015)
        S.place(ticks, S.bp(S.noise(k, int(at * 100)), 2000, 6000, 1) * np.exp(-S.t_axis(k) / 0.003), secs(at))
    y = S.reverb(bow + 0.25 * ticks, size_s=2.2, damp_hz=4000, wet=0.35, seed=9852)
    S.save("oddity/odd_clue_06", S.fade(y, 0.05, 0.4), norm="lufs:-26", quality=3)
    # 07: the last clue before the key: the station's whole falling tune, very
    # faint, from a radio in another room, swallowed by static at the end
    m = motif("musicbox", 9861, 1.0, 0.7)
    n = len(m)
    t = S.t_axis(n)
    st = S.lp(radio_static(n, 9862, crackle=0.3), 3400, 3) * np.clip((t - 1.2) / 1.5, 0, 1) * 0.12
    sig = S.bp(m, 300, 3000, 2)
    sig *= np.clip(1.6 - t / 1.8, 0, 1)
    y = distant(sig / (np.abs(sig).max() + 1e-9) + st, 0.55, -0.2, 9863, room=1.8)
    S.save("oddity/odd_clue_07", S.fade(y, 0.02, 0.6), norm="lufs:-26", quality=3)


@builder("odd_shed_knock")
def shed_knock():
    """Knocking back from inside the locked shed, late at night: knuckles on
    corrugated iron (a dull bong with a little sheet rattle), three slow, a
    pause, two more. Heard from the courtyard, so muffled and a touch roomy.
    Mono for a positional player at the shed door."""
    r = np.random.default_rng(9701)
    n = secs(6.0)
    y = np.zeros(n)
    for at in (0.3, 1.05, 1.8, 3.9, 4.55):
        a = 1.0 + 0.15 * r.standard_normal()
        knock = _modal(1.2, [(r.uniform(85, 95), 0.25, 1.0), (r.uniform(145, 160), 0.18, 0.7),
                             (r.uniform(225, 245), 0.12, 0.5), (r.uniform(370, 400), 0.08, 0.35),
                             (r.uniform(690, 740), 0.05, 0.2), (r.uniform(1150, 1300), 0.03, 0.12)],
                       9702 + int(at * 10), attack=0.003)
        thud = S.lp(S.noise(secs(0.05), 9720 + int(at * 10)), 400, 2) * np.exp(-S.t_axis(secs(0.05)) / 0.01)
        rattle = S.bp(S.noise(secs(0.25), 9740 + int(at * 10)), 1500, 4500, 1) * np.exp(-S.t_axis(secs(0.25)) / 0.05)
        S.place(y, a * knock, secs(at))
        S.place(y, a * 0.8 * thud, secs(at))
        S.place(y, a * 0.05 * rattle, secs(at + 0.01))
    y = S.lp(y, 2500, 2)
    y = S.reverb(y, size_s=1.0, damp_hz=2500, wet=0.25, seed=9760).mean(axis=1)
    S.save("oddity/odd_shed_knock", S.fade(y, 0.0, 0.6), norm="lufs:-24", quality=3)


@builder("odd_key_found")
def key_found():
    """Finding the shed key late in the game: the midnight station's falling
    interval on a celesta, a soft choir closing over it, a small key glint."""
    dur = 6.5
    n = secs(dur)
    t = S.t_axis(n)
    cel = np.zeros(n)
    m = motif("celesta", 9901, 1.0, 1.1)
    m += 0.25 * motif("celesta", 9911, 2.0, 1.1)  # a soft octave above
    S.place(cel, m, secs(0.3))
    ch = choir_drone(n, 9902, chord=(110.0, 164.8, 220.0, 261.6), vowel="u").mean(axis=1)
    ch = ch / (np.abs(ch).max() + 1e-9) * soft_swell(n, 3.2, 4.6, 0.8)
    # the glint: a tiny bright ring as the key catches the light, twice
    gl = np.zeros(n)
    for at, a, f in ((2.7, 1.0, 5200), (2.83, 0.5, 6100)):
        k = secs(0.6)
        tk = S.t_axis(k)
        g = sum(b * np.sin(2 * np.pi * f * mm * tk) * np.exp(-tk / d) for mm, b, d in ((1, 1, 0.25), (1.52, 0.5, 0.12), (2.13, 0.3, 0.06)))
        g *= np.clip(tk / 0.008, 0, 1)
        S.place(gl, g * a, secs(at))
    y = cel / (np.abs(cel).max() + 1e-9) * 0.7 + ch * 0.55 + gl * 0.12
    st = S.reverb(y, size_s=3.0, damp_hz=4500, wet=0.35, seed=9903)
    S.save("oddity/odd_key_found", S.fade(st, 0.03, 0.9), norm="lufs:-20", quality=3)


def _modal(dur, modes, seed, attack=0.001):
    n = secs(dur)
    t = S.t_axis(n)
    r = np.random.default_rng(seed)
    y = sum(a * np.sin(2 * np.pi * f * t + r.uniform(0, 6)) * np.exp(-t / d) for f, d, a in modes)
    y[: secs(attack)] *= np.linspace(0, 1, secs(attack))
    return y


def _stick_slip(dur, rate_fn, res, seed, jitter=0.3):
    """Creaks and scrapes (as gen_home.stick_slip): one pulse per slip at
    rate_fn(t), rung through resonances [(f, q, gain)]."""
    n = secs(dur)
    t = S.t_axis(n)
    p = np.diff(np.floor(np.cumsum(rate_fn(t) / SR)), prepend=0)
    p *= 1 + jitter * np.random.default_rng(seed).standard_normal(n)
    return sum(S.resonator(p, f, q) * g for f, q, g in res)


@builder("odd_shed_unlock")
def shed_unlock():
    """The shed being unlocked: a stiff old padlock and the key grinding
    round, the shackle letting go, the hasp dropping against the tin, the
    corrugated-iron door scraping open on its dry runner, and as it opens a
    low held drone with the station's interval half-heard inside it, ending
    on still air. Foley in the same dry small-room style as home_odd_door_creak."""
    dur = 11.0
    n = secs(dur)
    t = S.t_axis(n)
    r = np.random.default_rng(9950)
    fol = np.zeros(n)
    # key in: a gritty slide over the pins, the pins ticking up
    k = secs(0.4)
    slide = S.bp(S.noise(k, 9951), 2000, 7000, 2) * np.hanning(k) * 0.12
    S.place(fol, slide, secs(0.15))
    for i in range(5):
        S.place(fol, _modal(0.04, [(r.uniform(3200, 4800), 0.005, 0.25)], 9952 + i, 0.0008), secs(0.2 + i * 0.06))
    # the stiff turn: rust grinding, catching, giving
    turn = _stick_slip(1.0, lambda x: 45 - 30 * x + 15 * np.sin(2 * np.pi * 2.3 * x),
                       [(1300, 8, 1.0), (2700, 10, 0.5), (620, 6, 0.4)], 9960, 0.5)
    turn *= np.hanning(len(turn)) ** 0.5 * 0.5
    S.place(fol, turn, secs(0.75))
    for at in (0.95, 1.35):
        S.place(fol, _modal(0.05, [(r.uniform(2200, 3000), 0.008, 0.2)], int(at * 100), 0.001), secs(at))
    # the shackle lets go
    clack = _modal(0.3, [(1850, 0.04, 0.6), (3100, 0.02, 0.35), (720, 0.06, 0.5)], 9961, 0.004)
    clack += S.bp(S.noise(secs(0.3), 9962), 1000, 6000, 1) * S.env_exp(secs(0.3), 0.004, 0.002) * 0.3
    S.place(fol, clack * 0.3, secs(1.8))
    # padlock off, hasp swings down on its pin and knocks the tin, bouncing
    sq = _stick_slip(0.35, lambda x: 120 + 200 * x, [(1700, 9, 1.0), (3400, 11, 0.4)], 9963)
    S.place(fol, sq * np.hanning(len(sq)) * 0.08, secs(2.35))
    tin = [(140, 0.35, 1.0), (233, 0.3, 0.8), (391, 0.22, 0.6), (612, 0.16, 0.45), (884, 0.12, 0.3), (1270, 0.08, 0.2)]
    for j, (at, a) in enumerate(((2.72, 1.0), (2.83, 0.45), (2.91, 0.22), (2.96, 0.1))):
        hit = _modal(0.8, [(f * r.uniform(0.98, 1.02), d, g) for f, d, g in tin], 9970 + j, 0.004)
        hit += S.bp(S.noise(secs(0.8), 9980 + j), 1500, 7000, 1) * S.env_exp(secs(0.8), 0.003, 0.002) * 0.4
        S.place(fol, hit * a * 0.18, secs(at))
    # the door: unsticks with a jerk, then scrapes along its dry runner
    dd = 3.9
    dn = secs(dd)
    tt = S.t_axis(dn)
    speed = np.clip(tt / 0.25, 0, 1) * (0.55 + 0.45 * np.clip((tt - 0.6) / 0.8, 0, 1)) * np.clip((dd - tt) / 0.6, 0, 1)
    speed *= 1 + 0.25 * S.smooth_noise(dn, 3.0, 9990, periodic=False)
    speed = np.clip(speed, 0, None)
    scr = _stick_slip(dd, lambda x: 25 + 140 * np.interp(x, tt, speed),
                      [(900, 6, 1.0), (2100, 9, 0.6), (3500, 12, 0.3), (480, 5, 0.4)], 9991, 0.4)
    scr *= np.interp(S.t_axis(len(scr)), tt, speed)
    grit = S.bp(S.noise(dn, 9992), 1500, 6000, 2) * speed * (1 + 0.5 * S.smooth_noise(dn, 12, 9993, periodic=False))
    sheet = sum(S.resonator(S.noise(dn, 9994 + i), f, 12) for i, f in enumerate((95, 160, 240)))
    sheet *= speed * (1 + 0.6 * np.sin(2 * np.pi * 4.2 * tt))  # the tin warbling as it flexes
    door = scr / (np.abs(scr).max() + 1e-9) * 0.35 + grit / (np.abs(grit).max() + 1e-9) * 0.12 \
        + S.lp(sheet, 400) / (np.abs(sheet).max() + 1e-9) * 0.22
    S.place(fol, door, secs(3.5))
    stop = S.lp(S.noise(secs(0.8), 9995), 300, 2) * S.env_exp(secs(0.8), 0.03, 0.004) * 0.6
    stop += _modal(0.8, [(f * 0.9, d, g * 0.5) for f, d, g in tin[:4]], 9996, 0.004)
    S.place(fol, stop * 0.22, secs(3.5 + dd - 0.05))
    fol = S.reverb(fol, size_s=0.6, damp_hz=4500, wet=0.25, predelay_s=0.004, seed=9997)
    fol = np.stack([fol[:, 0] * 1.0, fol[:, 1] * 0.85], axis=1)
    # the drone opening up inside, with the interval half-heard in it
    dr = choir_drone(n, 9998, chord=(49.0, 73.4, 98.0, 103.8), vowel="o")
    dr = np.stack([S.lp(dr[:, c], 900, 2) for c in range(2)], axis=1)
    sub = S.lp(S.brown(n, 9999), 70, 2)
    env = np.clip((t - 4.0) / 3.0, 0, 1) ** 2 * np.exp(-np.maximum(t - 8.6, 0) / 0.8)
    drone = (dr / (np.abs(dr).max() + 1e-9) + S.stereo(sub / (np.abs(sub).max() + 1e-9)) * 0.3) * env[:, None]
    ghost = np.zeros(n)
    S.place(ghost, rate(interval_signal(9940), 0.5), secs(5.6))  # an octave down, slow
    ghost = S.lp(radio_fx(ghost, 9941, 0.5), 1600, 2)
    ghost = S.reverb(ghost, size_s=3.5, damp_hz=1800, wet=0.7, seed=9942)
    air = np.stack([S.bp(S.noise(n, 9943 + c), 300, 3000, 1) for c in range(2)], axis=1)
    y = fol * 1.0 + drone * 0.26 + ghost / (np.abs(ghost).max() + 1e-9) * 0.07 + air * 0.004
    S.save("oddity/odd_shed_unlock", S.fade(y, 0.01, 1.2), norm="lufs:-20", quality=3)


@builder("odd_shed_interior_loop")
def shed_interior():
    """Inside the open shed: close tin-roof ticks, dust settling, a faint
    electrical hum from nowhere, and once a loop the faintest edge of the
    midnight station's static. Stereo, 40 s seamless."""
    dur = 40
    B = Bed(dur, 9960)
    n = B.n
    t = S.t_axis(n)
    room = np.stack([S.circ_lp(S.brown(n, 99601 + c), 120, 2) for c in range(2)], axis=1)
    B.add(room, -40)
    B.add(np.stack([S.circ_bp(S.noise(n, 99603 + c), 300, 4000, 1) for c in range(2)], axis=1), -52)
    # a hum from nowhere: mains harmonics, slowly wandering across the room
    hum = sum(a * np.sin(2 * np.pi * periodic_tone(n, f) * t + f) for f, a in ((50, 0.5), (100, 1.0), (150, 0.4), (250, 0.12)))
    hum *= 1 + 0.3 * S.smooth_noise(n, 0.08, 99605)
    p = 0.35 * np.sin(2 * np.pi * periodic_tone(n, 1 / 40) * t)
    B.add(np.stack([hum * np.cos((p + 1) * np.pi / 4), hum * np.sin((p + 1) * np.pi / 4)], axis=1), -42)
    # tin roof ticking as it cools/warms, close overhead, some in little runs
    for k, at in enumerate(B.times(11, 0.9)):
        tt = at
        for j in range(int(B.r.integers(1, 4))):
            f = B.r.uniform(700, 1800)
            tk = _modal(0.25, [(f, 0.03, 1.0), (f * 2.3, 0.02, 0.5), (f * 3.9, 0.01, 0.2)], 99610 + k * 5 + j, 0.0015)
            B.put(distant(tk, B.r.uniform(0.1, 0.35), B.r.uniform(-0.7, 0.7), k, room=0.6), tt, B.r.uniform(-24, -16))
            tt += secs(B.r.uniform(0.15, 0.6))
    # dust: very fine grains sifting down now and then
    dust = np.zeros((n, 2))
    dens = 4 + 10 * np.clip(S.smooth_noise(n, 0.1, 99606), 0, None)
    for c in range(2):
        g = (B.r.random(n) < dens / SR) * B.r.standard_normal(n)
        dust[:, c] = S.circ_bp(g, 3000, 12000, 1)
    B.add(dust, -50)
    # the faintest edge of the station's static, once a loop
    st = radio_static(n, 99607, crackle=0.3, circular=True)
    st = S.circ_lp(st, 3000) * env_window(n, 24, 7, 3.0, 3.0)
    B.add(S.stereo(st, 0.6), -54)
    save_loop("oddity/odd_shed_interior_loop", B.x, norm="lufs:-26", **LEAN)


@builder("odd_mystery_bed_loop")
def mystery_bed():
    """A very quiet underscore for mystery moments: two slow detuned pads
    trading places over the minute, with tape hiss and wow. No melody."""
    dur = 60
    n = secs(dur)
    t = S.t_axis(n)
    chords = ((73.4, 110.0, 174.6, 261.6), (58.3, 87.3, 146.8, 220.0))  # Dm7 / Bbmaj7, low
    envs = (0.5 + 0.5 * np.cos(2 * np.pi * periodic_tone(n, 1 / 60) * t),)
    envs = (envs[0], 1 - envs[0])
    r = np.random.default_rng(9970)
    out = np.zeros((n, 2))
    fm = periodic_tone(n, 0.45)
    for chord, env in zip(chords, envs):
        for f in chord:
            for c in range(2):
                for cents in (-9, 0, 8):
                    ff = periodic_tone(n, f * 2 ** ((cents + (3 if c else -3)) / 1200))
                    beta = 0.0025 * ff / fm  # tape wow
                    ph = 2 * np.pi * ff * t + beta * np.sin(2 * np.pi * fm * t) + r.uniform(0, 6)
                    saw = sum(np.sin(h * ph) / h for h in range(1, 9))
                    out[:, c] += saw * env
    out = np.stack([S.circ_lp(out[:, c], 700, 2) for c in range(2)], axis=1)
    out *= (1 + 0.15 * S.smooth_noise(n, 0.05, 9971))[:, None]
    pads = S.reverb(out.mean(axis=1), size_s=4.0, damp_hz=2500, wet=0.5, circular=True, seed=9972)
    pads = pads * 0.6 + out * 0.4
    hiss = tape_hiss(n, 9973, circular=True)
    x = pads / np.sqrt(np.mean(pads ** 2)) * db(-24) + hiss * db(-46) / np.sqrt(np.mean(hiss ** 2)) * 1.0
    save_loop("oddity/odd_mystery_bed_loop", x, norm="lufs:-28", **LEAN)


def pan_const(x, p):
    a = (p + 1) * np.pi / 4
    return np.stack([x[:, 0] * np.cos(a) * np.sqrt(2), x[:, 1] * np.sin(a) * np.sqrt(2)], axis=1)


# --------------------------------------------------------------------------

# ---- place ambience: layers for points of interest -----------------------
# Close-up detail for a place, played on top of the zone bed while the
# player is near it (the game fades it with distance; see audio/docs/amb.md).
# Stereo seamless loops, 45-60 s, -26 LUFS; `place_<type>_loop` by day and
# `place_<type>_night_loop` after dark.

PLACE_ENC = dict(quality=0, rate=32000)


def place_save(name, x):
    save_loop(f"amb/place/{name}", x, norm="lufs:-26", **PLACE_ENC)


def ear_wind(n, seed, gust_rate=0.09, level=1.0):
    """Wind on an exposed hilltop, as it sounds in your ears: a low, buffeting
    roar that swells with each gust, and a whistle through grass and railings."""
    gust = 0.45 + 0.55 * np.clip(0.5 + 0.6 * S.smooth_noise(n, gust_rate, seed), 0, 1.2)
    chans = []
    for c in range(2):
        g = np.roll(gust, secs(0.6) * c)
        buffet = 1 + 0.5 * S.smooth_noise(n, 6.0, seed + 5 + c)
        roar = S.circ_bp(S.brown(n, seed + 10 + c), 30, 380, 2) * buffet
        roar /= np.std(roar) + 1e-12
        air = S.circ_bp(S.noise(n, seed + 20 + c), 500, 5000, 1)
        air /= np.std(air) + 1e-12
        whistle = S.circ_bp(S.noise(n, seed + 30 + c), 1700, 2100, 4)
        whistle /= np.std(whistle) + 1e-12
        chans.append(roar * g ** 2 + air * 0.35 * g ** 2.5 + whistle * 0.12 * np.clip(g - 0.6, 0, None) * 3)
    return np.stack(chans, axis=1) * level


def pontoon_slaps(n, seed, count=40):
    """Water slapping the hollow floats of a pontoon and the quay wall
    (stereo, circular): a short wet knock with a hollow body, in little runs."""
    r = np.random.default_rng(seed)
    y = np.zeros((n, 2))
    k = secs(0.35)
    tk = S.t_axis(k)
    for _ in range(count):
        at = r.uniform(0, n / SR)
        p = r.uniform(-0.8, 0.8)
        for j in range(int(r.integers(1, 4))):
            body = np.sin(2 * np.pi * r.uniform(140, 260) * tk) * np.exp(-tk / r.uniform(0.03, 0.06))
            splash = S.bp(r.standard_normal(k), 600, 4500, 2) * np.exp(-tk / 0.04)
            gurgle = S.bp(r.standard_normal(k), 250, 900, 2) * np.exp(-tk / 0.12) * 0.4
            s = S.fade(body * 0.8 + splash * 0.5 + gurgle, 0.004, 0.05) * r.uniform(0.3, 1.0)
            S.place(y, S.pan(s, p), secs(at), wrap=True)
            at += r.uniform(0.18, 0.6)
    return y


def bell(f0, dur, seed):
    """A church bell (mono): the classic minor-third bell partials (hum,
    prime, tierce, quint, nominal...) decaying at their own rates."""
    r = np.random.default_rng(seed)
    n = secs(dur)
    t = S.t_axis(n)
    parts = ((0.5, 0.5, 3.5), (1.0, 0.8, 2.2), (1.19, 0.6, 1.6), (1.5, 0.35, 1.3),
             (2.0, 0.7, 1.2), (2.51, 0.25, 0.8), (3.0, 0.2, 0.6), (4.07, 0.12, 0.4))
    y = sum(a * np.sin(2 * np.pi * f0 * m * (1 + r.normal(0, 0.002)) * t + r.uniform(0, 6))
            * np.exp(-t / d) for m, a, d in parts)
    strike = S.bp(r.standard_normal(n), 1500, 6000, 2) * np.exp(-t / 0.01) * 0.3
    return S.fade(y + strike, 0.002, 0.3)


def swan_bells(dur, seed, rows=6):
    """The Swan Bells (the copper-and-glass bell tower by the quay) change
    ringing, heard across the water: rounds on 12 bells, then a few changes,
    each row a little uneven as real ringers are."""
    r = np.random.default_rng(seed)
    n = secs(dur)
    y = np.zeros(n)
    scale = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19][::-1]  # treble first
    tones = [bell(330 * 2 ** (s / 12) / 2, 3.0, seed + i) for i, s in enumerate(scale)]
    order = list(range(12))
    tt = 0.5
    for row in range(rows):
        for b in order:
            if tt > dur - 3.2:
                break
            S.place(y, tones[b] * r.uniform(0.6, 1.0), secs(tt + r.normal(0, 0.015)))
            tt += 0.21
        tt += 0.21  # handstroke gap
        if row >= 1:  # plain changes: swap pairs, alternating
            start = row % 2
            for i in range(start, 11, 2):
                order[i], order[i + 1] = order[i + 1], order[i]
    return y


def fluoro_buzz(n, seed, tubes=3):
    """Car park lighting at night (stereo, circular): old fluorescent tubes'
    100 Hz ballast buzz, each tube its own level and side, one of them
    flickering with little ticks."""
    r = np.random.default_rng(seed)
    t = S.t_axis(n)
    out = np.zeros((n, 2))
    for i in range(tubes):
        f = periodic_tone(n, 100 * (1 + 0.0005 * i))
        buzz = np.tanh(2.5 * np.sin(2 * np.pi * f * t + i)) + 0.3 * np.sin(4 * np.pi * f * t + 2 * i)
        buzz = S.circ_bp(buzz, 90, 1400, 2)
        y = buzz / np.std(buzz) * 0.5
        if i == 0:  # the dodgy one
            flick = np.ones(n)
            for _ in range(5):
                a = int(r.integers(n))
                L = secs(r.uniform(0.15, 0.6))
                idx = (a + np.arange(L)) % n
                flick[idx] = (r.random(L) > 0.5).astype(float) * 0.7 + 0.3
            flick = S.circ_lp(flick, 300, 1)
            y = y * flick
            for _ in range(8):
                tick = S.bp(r.standard_normal(secs(0.02)), 2000, 7000, 2) * np.exp(-S.t_axis(secs(0.02)) / 0.003)
                S.place(y, tick * 3, int(r.integers(n)), wrap=True)
        out += S.pan(y, r.uniform(-0.7, 0.7)) * r.uniform(0.5, 1.0)
    return out


def cooling_ticks(n, seed, count=25):
    """A parked car's exhaust ticking as it cools (mono, circular)."""
    r = np.random.default_rng(seed)
    y = np.zeros(n)
    k = secs(0.06)
    tk = S.t_axis(k)
    at = 0.0
    for _ in range(count):
        at += r.exponential(n / SR / count)
        f = r.uniform(2500, 5000)
        s = np.sin(2 * np.pi * f * tk) * np.exp(-tk / 0.006) + 0.3 * S.bp(r.standard_normal(k), 3000, 9000, 2) * np.exp(-tk / 0.002)
        S.place(y, s * r.uniform(0.3, 1.0), secs(at % (n / SR)), wrap=True)
    return y


def reed_rustle(n, seed):
    """Reeds and rushes at the water's edge: a dry, papery swish in gusts."""
    gust = 0.4 + 0.6 * np.clip(0.5 + 0.6 * S.smooth_noise(n, 0.12, seed), 0, 1.2)
    ch = []
    for c in range(2):
        g = np.roll(gust, secs(0.4) * c)
        x = S.circ_bp(S.noise(n, seed + 3 + c), 2500, 9000, 2)
        grain = 1 + 0.8 * S.smooth_noise(n, 25, seed + 7 + c)
        ch.append(x * g ** 2 * grain)
    return np.stack(ch, axis=1)


@builder("place_beach")
def place_beach():
    dur = 50
    B = Bed(dur, 3101)
    n = B.n
    # the shore break, close: a different stretch of the recording to the bed
    B.add(texture(src("beach_day", True), dur, 31011, chunk=18), -22)
    B.add(gum_wind(n, 31012, gust_rate=0.1, crisp=0.0), -31)
    B.add(ear_wind(n, 31013, gust_rate=0.07), -36)
    B.scatter(gull_pool(), 5, gain_db=(-18, -9), dist=(0.15, 0.5))
    place_save("place_beach_loop", B.x)


@builder("place_beach_night")
def place_beach_night():
    dur = 55
    B = Bed(dur, 3102)
    n = B.n
    B.add(texture(src("beach_night", True), dur, 31021, chunk=18), -22)
    B.add(ear_wind(n, 31022, gust_rate=0.05), -38)
    place_save("place_beach_night_loop", B.x)


@builder("place_lookout")
def place_lookout():
    """Up on a lookout (Kings Park, Reabold Hill, the coast): open wind in
    your ears, the city spread out below, birds and a plane far off."""
    dur = 50
    B = Bed(dur, 3201)
    n = B.n
    B.add(ear_wind(n, 32011, gust_rate=0.11), -24)
    B.add(gum_wind(n, 32012, gust_rate=0.09, crisp=0.6), -33)
    B.add(city_hum(n, 32013, 35, 400), -37)
    B.scatter(bird_pools(), 3, gain_db=(-26, -18), dist=(0.6, 0.9))
    # a plane coming in to Perth airport, high and far: a slow swell of jet roar
    jet = S.circ_bp(S.pink(n, 32014), 120, 2500, 2)
    B.add(np.stack([jet, np.roll(jet, secs(0.02))], axis=1) * env_window(n, 12, 26, 11, 13)[:, None], -40)
    place_save("place_lookout_loop", B.x)


@builder("place_lookout_night")
def place_lookout_night():
    dur = 55
    B = Bed(dur, 3202)
    n = B.n
    B.add(ear_wind(n, 32021, gust_rate=0.07), -27)
    B.add(city_hum(n, 32022, 30, 300), -34)
    B.add(S.circ_bp(texture(src("crickets_sub", True), dur, 32023, chunk=17, region=(22.5, 82)), 2500, 9000), -40)
    y = siren(14.0, 32024, dist=0.95)
    B.put(np.stack([y, np.roll(y, secs(0.01))], axis=1), secs(20), -30)
    place_save("place_lookout_night_loop", B.x)


@builder("place_bush")
def place_bush():
    """In among the trees (Kings Park bushland, Bold Park): birds close by,
    leaves rustling and knocking overhead. Cicadas come from the weather layer."""
    dur = 55
    B = Bed(dur, 3301)
    n = B.n
    B.add(gum_wind(n, 33011, gust_rate=0.08, crisp=1.3), -27)
    B.add(texture(src("walyunga", True), dur, 33012, chunk=20, avoid_peaks_db=8), -31)
    B.scatter(bird_pools(), 7, gain_db=(-12, -4), dist=(0.05, 0.35))
    wag = snips("wagtail1", 1500, 8000, thresh_db=12, min_len=0.4, max_len=4, best=True, n=4)
    B.scatter(wag, 3, gain_db=(-12, -6), dist=(0.05, 0.3))
    B.scatter([twitter(3310 + i) for i in range(8)], 9, gain_db=(-16, -8), dist=(0.05, 0.4), pitch=0.06)
    place_save("place_bush_loop", B.x)


@builder("place_bush_night")
def place_bush_night():
    dur = 60
    B = Bed(dur, 3302)
    n = B.n
    B.add(texture(src("crickets_sub", True), dur, 33021, chunk=17, region=(22.5, 82)), -27)
    B.add(gum_wind(n, 33022, gust_rate=0.05, crisp=0.9), -36)
    # something moving in the leaf litter (a possum, a bandicoot): a few
    # dry scuffles, close and to one side
    for k, at in enumerate(B.times(3, 0.7)):
        L = secs(B.r.uniform(0.6, 1.4))
        sc = S.bp(B.r.standard_normal(L), 1200, 7000, 2) * (S.smooth_noise(L, 18, 33023 + k, periodic=False) > 0.3)
        B.put(distant(S.fade(sc, 0.02, 0.1), 0.2, B.r.uniform(-0.8, 0.8), k), at, -16)
    owl = src("boobook1")
    ev = find_events(owl, 350, 1200, thresh_db=12, min_len=0.25, max_len=2.0, gap=0.25)
    calls = [S.lp(cut(owl, a, b), 1600, 3) for a, b, _ in ev]
    tt = secs(30)
    for j in range(min(len(calls), 4)):
        B.put(distant(calls[j % len(calls)], 0.45, 0.4, j, room=1.6), tt, -12)
        tt += secs(B.r.uniform(1.6, 2.4))
    place_save("place_bush_night_loop", B.x)


@builder("place_quay")
def place_quay():
    """Elizabeth Quay: water slapping the pontoons and the quay wall, boats'
    halyards, a ferry idling at the jetty, people strolling, and the Swan
    Bells ringing across the inlet."""
    dur = 60
    B = Bed(dur, 3401)
    n = B.n
    B.add(texture(src("lapping", True), dur, 34011, chunk=20), -27)
    B.add(pontoon_slaps(n, 34012, 34), -28)
    hal = halyard_tinks(n, 34013, clusters=8)
    B.add(np.stack([hal, np.roll(hal, secs(0.31))], axis=1), -38)
    fe = texture(src("ferry", True), dur, 34014, chunk=16)
    B.add(S.circ_lp(fe, 900) * env_window(n, 5, 30, 6, 8)[:, None], -34)
    B.add(S.circ_lp(texture(src("bar_wa", True), dur, 34015, chunk=15), 3500), -40)
    B.scatter(gull_pool(), 4, gain_db=(-18, -10), dist=(0.2, 0.6))
    for k, at in enumerate(B.times(2, 0.6)):
        y = footsteps(7.0, 34100 + k, rate_hz=B.r.uniform(2.5, 2.9))
        B.put(pass_stereo(y, k % 2 == 1), at, -22)
    bells = distant(swan_bells(22.0, 34016), 0.55, -0.4, 3, room=2.5)
    B.put(bells, secs(32), -9)
    place_save("place_quay_loop", B.x)


@builder("place_quay_night")
def place_quay_night():
    dur = 60
    B = Bed(dur, 3402)
    n = B.n
    B.add(texture(src("lapping", True), dur, 34021, chunk=20), -28)
    B.add(pontoon_slaps(n, 34022, 26), -30)
    hal = halyard_tinks(n, 34023, clusters=6)
    B.add(np.stack([hal, np.roll(hal, secs(0.27))], axis=1), -38)
    B.add(fridge_hum(n, 34024), -40)
    B.add(city_hum(n, 34025, 30, 250), -38)
    place_save("place_quay_night_loop", B.x)


def timber_creaks(n, seed, count=8):
    """Old jetty timbers taking the swell: slow stick-slip groans from the
    boards and pylons (stereo, circular)."""
    r = np.random.default_rng(seed)
    y = np.zeros((n, 2))
    for _ in range(count):
        m = secs(r.uniform(0.3, 0.9))
        rate = r.uniform(25, 60) * (1 + 0.3 * np.sin(np.linspace(0, np.pi * r.uniform(1, 3), m)))
        pulses = np.diff(np.floor(np.cumsum(rate / SR)), prepend=0) * (0.5 + r.random(m))
        c = S.resonator(pulses, r.uniform(250, 420), 4) + 0.5 * S.resonator(pulses, r.uniform(700, 1000), 5)
        c *= np.sin(np.linspace(0, np.pi, m)) ** 1.5
        S.place(y, S.pan(c, r.uniform(-0.7, 0.7)), secs(r.uniform(0, n / SR)), wrap=True)
    return y


def fish_jumps(n, seed, count=4):
    """Mullet jumping now and then: a small slap and plop out on the water."""
    r = np.random.default_rng(seed)
    y = np.zeros((n, 2))
    k = secs(0.3)
    tk = S.t_axis(k)
    for _ in range(count):
        slap = S.bp(r.standard_normal(k), 700, 6000, 2) * np.exp(-tk / 0.02)
        bloop = np.sin(2 * np.pi * np.cumsum(r.uniform(500, 800) * (1 + 2 * tk / 0.3)) / SR) * np.exp(-tk / 0.035)
        s = distant(S.fade(slap + 0.6 * bloop, 0.002, 0.05), r.uniform(0.3, 0.6), r.uniform(-0.8, 0.8), int(r.integers(9)))
        S.place(y, s, secs(r.uniform(0, n / SR)), wrap=True)
    return y


@builder("place_jetty")
def place_jetty():
    """Out on an old timber jetty (fishing spots on the river and the coast):
    water lapping round the pylons and slapping up under the boards, the
    timbers creaking, moored boats' halyards and ropes, a light sea breeze,
    gulls, now and then a fish jumping."""
    dur = 60
    B = Bed(dur, 3601)
    n = B.n
    B.add(texture(src("lapping", True), dur, 36011, chunk=20), -26)
    B.add(pontoon_slaps(n, 36012, 30), -27)
    B.add(timber_creaks(n, 36013, 7), -31)
    B.add(ear_wind(n, 36014, level=0.6), -36)
    B.add(fish_jumps(n, 36015, 3), -24)
    hal = halyard_tinks(n, 36016, clusters=7)
    B.add(np.stack([hal, np.roll(hal, secs(0.29))], axis=1), -39)
    B.add(rope_creaks(n, 36017, 6), -35)
    B.scatter(gull_pool(), 4, gain_db=(-20, -11), dist=(0.2, 0.6))
    place_save("place_jetty_loop", B.x)


@builder("place_jetty_night")
def place_jetty_night():
    """The jetty after dark: quieter water, the timbers, more fish jumping,
    the city a faint hum across the water."""
    dur = 60
    B = Bed(dur, 3602)
    n = B.n
    B.add(texture(src("lapping", True), dur, 36021, chunk=20), -28)
    B.add(pontoon_slaps(n, 36032, 20), -30)
    B.add(timber_creaks(n, 36033, 6), -31)
    B.add(fish_jumps(n, 36024, 6), -24)
    B.add(city_hum(n, 36025, 30, 250), -40)
    hal = halyard_tinks(n, 36026, clusters=5)
    B.add(np.stack([hal, np.roll(hal, secs(0.33))], axis=1), -40)
    B.add(rope_creaks(n, 36027, 5), -36)
    place_save("place_jetty_night_loop", B.x)


def rope_creaks(n, seed, count=6):
    """Mooring lines stretching on bollards and cleats as boats ride the
    swell: short, tight, squeaky stick-slip groans (stereo, circular)."""
    r = np.random.default_rng(seed)
    y = np.zeros((n, 2))
    for _ in range(count):
        m = secs(r.uniform(0.25, 0.6))
        rate = r.uniform(70, 150) * (1 + 0.4 * np.sin(np.linspace(0, np.pi, m)))
        pulses = np.diff(np.floor(np.cumsum(rate / SR)), prepend=0) * (0.6 + 0.4 * r.random(m))
        c = S.resonator(pulses, r.uniform(800, 1300), 6) + 0.6 * S.resonator(pulses, r.uniform(1800, 2600), 8)
        c *= np.sin(np.linspace(0, np.pi, m)) ** 2
        S.place(y, S.pan(c, r.uniform(-0.6, 0.6)), secs(r.uniform(0, n / SR)), wrap=True)
    return y


def rock_wash(n, seed, every=9.0):
    """Swell running up a rock groyne (stereo, circular): the dull thump of
    each wave on the boulders, its rush up between the rocks, and the long
    drain back, gurgling and trickling through the gaps."""
    r = np.random.default_rng(seed)
    y = np.zeros((n, 2))
    count = max(1, int(round(n / SR / every)))
    for k in range(count):
        at = (k + r.uniform(-0.25, 0.25)) * n / SR / count
        L = secs(6.0)
        t = S.t_axis(L)
        rise = np.clip(t / r.uniform(0.6, 1.0), 0, 1) ** 2 * np.exp(-np.clip(t - 1.0, 0, None) / 1.2)
        rush = S.bp(r.standard_normal(L), 250, 4000, 2) * rise
        thump = S.lp(r.standard_normal(L), 140, 2) * np.exp(-np.clip(t - 0.35, 0, None) / 0.12) * (t > 0.35) * 2.5
        drain = np.zeros(L)
        for _ in range(int(r.integers(40, 70))):
            b0 = r.uniform(1.4, 5.5)
            m = secs(0.03)
            tb = S.t_axis(m)
            f = r.uniform(500, 1600) * (1 + 3 * tb / 0.03)
            pop = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tb / 0.008)
            S.place(drain, pop * r.uniform(0.1, 0.5) * np.exp(-(b0 - 1.4) / 2.5), secs(b0))
        trickle = S.bp(r.standard_normal(L), 1500, 6000, 1) * np.exp(-np.clip(t - 1.5, 0, None) / 1.8) * (t > 1.2) * 0.25
        s = rush * 0.9 + thump + drain + trickle
        S.place(y, S.pan(s, r.uniform(-0.6, 0.6)), secs(at), wrap=True)
    return y


@builder("place_groyne")
def place_groyne():
    """Out on a rock groyne (Cottesloe, the Freo moles): the open shore break
    either side, swell washing up the boulders and draining back through
    the gaps, the sea breeze, gulls working the water."""
    dur = 54
    B = Bed(dur, 3701)
    n = B.n
    B.add(texture(src("beach_day", True), dur, 37011, chunk=18), -26)
    B.add(rock_wash(n, 37012, every=9.0), -24)
    B.add(ear_wind(n, 37013, gust_rate=0.08), -33)
    B.scatter(gull_pool(), 5, gain_db=(-18, -9), dist=(0.15, 0.55))
    place_save("place_groyne_loop", B.x)


@builder("place_groyne_night")
def place_groyne_night():
    dur = 54
    B = Bed(dur, 3702)
    n = B.n
    B.add(texture(src("beach_night", True), dur, 37021, chunk=18), -26)
    B.add(rock_wash(n, 37022, every=10.8), -25)
    B.add(ear_wind(n, 37023, gust_rate=0.05), -37)
    place_save("place_groyne_night_loop", B.x)


def shop_radio(n, track, start_s, seed):
    """A little radio on a shelf (mono, circular): one of the station's
    tracks through a tinny speaker, its end folded into its start."""
    x = S.load(S.AUDIO_ROOT / f"music/{track}.ogg")
    x = x.mean(axis=1) if x.ndim == 2 else x
    xf = secs(3.0)
    seg = x[secs(start_s): secs(start_s) + n + xf].copy()
    w = np.linspace(0, 1, xf)
    seg[:xf] = seg[:xf] * w + seg[n:n + xf] * (1 - w)
    seg = seg[:n]
    y = S.circ_bp(seg, 300, 3200, 2)
    return np.tanh(2.0 * y / (np.abs(y).max() + 1e-9))


def bubbler(n, seed, density=35):
    """A live-bait tank's aerator (mono, circular): the air pump's 50 Hz
    buzz and a steady stream of small bubbles breaking."""
    r = np.random.default_rng(seed)
    t = S.t_axis(n)
    f = periodic_tone(n, 50)
    pump = S.circ_bp(np.tanh(3 * np.sin(2 * np.pi * f * t)), 60, 900, 2) * 0.15
    y = np.zeros(n)
    m = secs(0.025)
    tb = S.t_axis(m)
    for _ in range(int(density * n / SR)):
        fr = r.uniform(700, 2200) * (1 + 2 * tb / 0.025)
        pop = np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-tb / 0.006)
        S.place(y, pop * r.uniform(0.2, 1.0), int(r.integers(n)), wrap=True)
    return pump + y * 0.4


def ceiling_fan(n, seed, rpm=130):
    """An old ceiling fan (mono, circular): a soft whoosh per blade pass, a
    faint motor hum, a slight tick in the bearing."""
    t = S.t_axis(n)
    fb = periodic_tone(n, rpm / 60 * 3)
    swish = S.circ_bp(S.noise(n, seed), 150, 1500, 1) * (0.6 + 0.4 * np.sin(2 * np.pi * fb * t)) ** 2
    hum = np.sin(2 * np.pi * periodic_tone(n, 100) * t) * 0.03
    tick = np.zeros(n)
    k = secs(0.01)
    s = S.bp(np.random.default_rng(seed + 1).standard_normal(k), 2000, 6000, 2) * np.exp(-S.t_axis(k) / 0.002)
    per = int(round(SR * 60 / rpm))
    for at in range(0, n, per):
        S.place(tick, s * 0.15, at, wrap=True)
    return swish * 0.5 + hum + tick


def shop_bell(seed):
    """The bell on a shop door: a small brass bell jangling on its spring."""
    r = np.random.default_rng(seed)
    y = np.zeros(secs(1.6))
    for j in range(int(r.integers(4, 7))):
        b = bell(r.uniform(1150, 1250), 1.2, seed + j)
        S.place(y, b * 0.7 ** j, secs(j * r.uniform(0.07, 0.12)))
    return y


@builder("place_tackle_shop")
def place_tackle_shop():
    """Inside the bait and tackle shop: the bait freezer and the live-bait
    tank bubbling, a ceiling fan, the radio on the shelf, rod tips knocking
    in the rack, the till, and now and then the bell on the door."""
    import gen_car as C
    dur = 48
    B = Bed(dur, 3801)
    n = B.n
    room = lambda x: S.reverb(x, size_s=0.45, damp_hz=4500, wet=0.18, seed=38019, circular=True)  # noqa: E731
    B.add(fridge_hum(n, 38011), -32)
    B.add(room(bubbler(n, 38012)), -31)
    B.add(ceiling_fan(n, 38013), -37)
    B.add(room(shop_radio(n, "mus_cinquecento_04", 40.0, 38014)), -36)
    for k, at in enumerate(B.times(3, 0.7)):
        clack = sum(C.modal(0.15, [(B.r.uniform(1100, 2400), 0.02, 0.5), (B.r.uniform(3000, 5000), 0.01, 0.2)],
                            38100 + 10 * k + j) for j in range(1))
        y = np.zeros(secs(0.8))
        for j in range(int(B.r.integers(2, 5))):
            S.place(y, clack * B.r.uniform(0.4, 1.0), secs(j * B.r.uniform(0.08, 0.2)))
        B.put(room(y), at, -24)
    till = np.zeros(secs(1.2))
    S.place(till, np.sin(2 * np.pi * 2400 * S.t_axis(secs(0.08))) * 0.4, 0)
    S.place(till, C.add(S.lp(C.burst(0.15, 0.02, 38021), 900) * 1.2, C.modal(0.3, [(900, 0.05, 0.5)], 38022)),
            secs(0.3))
    B.put(room(till), secs(14), -22)
    B.put(room(shop_bell(38023)), secs(33), -20)
    place_save("place_tackle_shop_loop", B.x)


@builder("place_photo_lab")
def place_photo_lab():
    """Inside the Lake Street photo lab: the minilab running (motor, the
    film-transport rollers ticking, the dryer fan), prints dropping into the
    tray, the chemistry pump now and then, the machine's beep, fluoros."""
    dur = 48
    B = Bed(dur, 3901)
    n = B.n
    t = S.t_axis(n)
    room = lambda x: S.reverb(x, size_s=0.5, damp_hz=5000, wet=0.15, seed=39019, circular=True)  # noqa: E731
    motor = np.tanh(2 * np.sin(2 * np.pi * periodic_tone(n, 120) * t)) * 0.4 \
        + np.sin(2 * np.pi * periodic_tone(n, 360) * t) * 0.1
    B.add(room(S.circ_bp(motor, 80, 1500, 2)), -34)
    rollers = np.zeros(n)
    k = secs(0.02)
    tk = S.t_axis(k)
    per = int(round(SR / 6.0))
    for i, at in enumerate(range(0, n, per)):
        s = np.sin(2 * np.pi * (1800 + 200 * (i % 3)) * tk) * np.exp(-tk / 0.004)
        S.place(rollers, s, at, wrap=True)
    B.add(room(rollers), -38)
    B.add(S.circ_lp(S.brown(n, 39012), 900) + S.circ_bp(S.noise(n, 39013), 400, 3000, 1) * 0.3, -33)
    B.add(fluoro_buzz(n, 39014, tubes=2), -42)
    for k, at in enumerate(B.times(6, 0.5)):
        m = secs(0.25)
        tm = S.t_axis(m)
        slap = S.bp(np.random.default_rng(39100 + k).standard_normal(m), 700, 5000, 2) * np.exp(-tm / 0.03)
        whisk = S.bp(np.random.default_rng(39200 + k).standard_normal(m), 2000, 8000, 2) * np.exp(-tm / 0.08) * 0.3
        B.put(room(slap + whisk), at, -27)
    for k, at in enumerate(B.times(2, 0.6)):
        m = secs(2.0)
        tm = S.t_axis(m)
        gur = S.bp(np.random.default_rng(39300 + k).standard_normal(m), 150, 900, 2) \
            * (0.5 + 0.5 * np.sin(2 * np.pi * 7 * tm)) * np.sin(np.pi * tm / 2.0)
        B.put(room(gur), at, -30)
    beep = np.zeros(secs(0.6))
    for j in range(2):
        S.place(beep, np.sin(2 * np.pi * 2050 * S.t_axis(secs(0.09))) * 0.5, secs(j * 0.16))
    B.put(room(beep), secs(21), -28)
    place_save("place_photo_lab_loop", B.x)


@builder("place_wrong_cockatoos_night")
def place_wrong_cockatoos_night():
    """Under the thirteen black cockatoos in Kings Park at 3 am: not one of
    them calls. Feathers resettling, a claw shifting on bark, a bill clicking
    once, branches taking their weight, and the night itself gone too quiet:
    no crickets, just the wind high up and a low hum you feel more than hear."""
    dur = 48
    B = Bed(dur, 3951)
    n = B.n
    t = S.t_axis(n)
    B.add(ear_wind(n, 39511, gust_rate=0.04, level=0.5), -40)
    f1, f2 = periodic_tone(n, 41.0), periodic_tone(n, 41.3)
    hum = np.sin(2 * np.pi * f1 * t) + np.sin(2 * np.pi * f2 * t)
    B.add(hum, -41)
    B.add(timber_creaks(n, 39512, 6), -38)
    r = B.r
    k = secs(0.4)
    tk = S.t_axis(k)
    for i, at in enumerate(B.times(18, 0.9)):
        ruffle = S.bp(r.standard_normal(k), 900, 6000, 2) * np.sin(np.pi * tk / 0.4) ** 2 \
            * (0.5 + 0.5 * np.sin(2 * np.pi * r.uniform(20, 35) * tk))
        B.put(distant(ruffle, r.uniform(0.2, 0.45), r.uniform(-0.8, 0.8), 39600 + i, room=1.6), at, r.uniform(-30, -24))
    m = secs(0.05)
    tm = S.t_axis(m)
    for i, at in enumerate(B.times(3, 0.6)):
        click = np.sin(2 * np.pi * 2600 * tm) * np.exp(-tm / 0.006) + 0.5 * S.bp(r.standard_normal(m), 1500, 6000, 2) * np.exp(-tm / 0.003)
        B.put(distant(click, 0.3, r.uniform(-0.6, 0.6), 39700 + i, room=1.6), at, -27)
    place_save("place_wrong_cockatoos_night_loop", B.x)


@builder("place_riverside")
def place_riverside():
    """On the river bank (the foreshore paths, Matilda Bay, Heirisson Island):
    small waves lapping close, reeds, birds over the water, a rowing crew."""
    dur = 55
    B = Bed(dur, 3501)
    n = B.n
    B.add(texture(src("lapping", True), dur, 35011, chunk=20), -25)
    B.add(reed_rustle(n, 35012), -36)
    B.scatter(gull_pool(), 3, gain_db=(-22, -14), dist=(0.3, 0.7))
    B.scatter(bird_pools(), 2, gain_db=(-22, -16), dist=(0.4, 0.7))
    row = rowing_pass(24.0, 35013)
    B.put(distant(row, 0.55, 0.3, 5, room=1.8), secs(18), -22)
    place_save("place_riverside_loop", B.x)


@builder("place_riverside_night")
def place_riverside_night():
    dur = 55
    B = Bed(dur, 3502)
    n = B.n
    B.add(texture(src("lapping", True), dur, 35021, chunk=20), -26)
    B.add(reed_rustle(n, 35022), -40)
    B.add(S.circ_bp(texture(src("crickets_sub", True), dur, 35023, chunk=17, region=(22.5, 82)), 2000, 9000), -36)
    bonk = (snips("pobble1", 250, 1200, thresh_db=12, min_len=0.05, max_len=0.6, gap=0.08)
            + snips("pobble2", 250, 1200, thresh_db=12, min_len=0.05, max_len=0.6, gap=0.08))
    bonk = [S.hp(b, 180) for b in bonk]
    for k, at in enumerate(B.times(5, 0.9)):
        tt = at
        for j in range(int(B.r.integers(2, 5))):
            B.put(distant(bonk[int(B.r.integers(len(bonk)))], 0.4, B.r.uniform(-0.7, 0.7), k * 10 + j, room=1.0), tt, -15)
            tt += secs(B.r.uniform(0.5, 1.3))
    place_save("place_riverside_night_loop", B.x)


@builder("place_carpark")
def place_carpark():
    """A big open car park by day (shops, the beach, the footy): distant
    traffic, doors and boots shutting, a trolley rattling past."""
    dur = 50
    B = Bed(dur, 3601)
    n = B.n
    B.add(S.circ_lp(texture(src("traffic_peak", True), dur, 36011, chunk=16), 1500), -32)
    B.add(gum_wind(n, 36012, gust_rate=0.06, crisp=0.2), -40)
    for k, at in enumerate(B.times(6, 0.8)):
        L = secs(0.5)
        tk = S.t_axis(L)
        thud = (np.sin(2 * np.pi * B.r.uniform(70, 110) * tk) * np.exp(-tk / 0.06)
                + 0.5 * S.bp(B.r.standard_normal(L), 300, 3000, 2) * np.exp(-tk / 0.02)
                + 0.25 * S.bp(B.r.standard_normal(L), 3000, 8000, 2) * np.exp(-tk / 0.008))
        B.put(distant(S.fade(thud, 0.001, 0.1), B.r.uniform(0.3, 0.75), B.r.uniform(-0.8, 0.8), k), at, -14)
    # a trolley: rattling wheels on the bitumen, passing
    L = secs(6.0)
    tk = S.t_axis(L)
    rat = S.bp(B.r.standard_normal(L), 900, 5000, 2) * (1 + 0.8 * np.sign(np.sin(2 * np.pi * 11 * tk)))
    B.put(pass_stereo(rat * np.exp(-((tk - 3) / 1.6) ** 2)), secs(22), -20)
    y = car_pass(8.0, 36013, speed=6, dist=10, kind="car")
    B.put(pass_stereo(S.lp(y, 3000)), secs(36), -18)
    place_save("place_carpark_loop", B.x)


@builder("place_carpark_night")
def place_carpark_night():
    """A quiet car park at night: buzzing fluorescent tubes (one flickering),
    a parked car ticking as it cools, the city a long way off, and nothing
    else. Nearly empty, on purpose."""
    dur = 55
    B = Bed(dur, 3602)
    n = B.n
    B.add(fluoro_buzz(n, 36021), -34)
    B.add(fridge_hum(n, 36022), -36)
    B.add(S.circ_lp(texture(src("traffic_night", True), dur, 36023, chunk=16), 900), -36)
    ct = cooling_ticks(n, 36024, count=22)
    B.add(np.stack([ct * 0.6, ct], axis=1), -36)
    y = car_pass(9.0, 36025, speed=14, dist=50, kind="car")
    B.put(pass_stereo(S.lp(y, 1500)), secs(30), -26)
    place_save("place_carpark_night_loop", B.x)


# ---- wetlands: Herdsman Lake, Lake Monger, Gwelup, Claremont, Alfred Cove ----

def reed_rustle(n, seed, gust_rate=0.07):
    """Wind through bulrushes and sedge (stereo, circular): a dry, papery
    hiss that swells with the gusts, and the stems ticking against each
    other, higher and drier than gum leaves."""
    chans = []
    for c in range(2):
        gust = 0.5 + 0.5 * np.clip(0.5 + 0.6 * S.smooth_noise(n, gust_rate, seed + c * 7), 0, 1.3)
        hiss = S.circ_bp(S.noise(n, seed + 10 + c), 1800, 9000, 1)
        hiss = hiss / (np.std(hiss) + 1e-12) * gust ** 1.5
        ticks = S.noise(n, seed + 20 + c) * (S.noise(n, seed + 30 + c) > 2.9) * gust ** 2
        ticks = S.circ_bp(ticks, 2500, 9000, 2)
        ticks = ticks / (np.std(ticks) + 1e-12)
        chans.append(hiss + 0.4 * ticks)
    return np.stack(chans, axis=1)


def reed_warbler(seed):
    """Australian reed warbler: a loud, rich, repetitive song from inside
    the reeds, 'chut-chut-chut, twee-twee, churr', phrases repeated."""
    import field_birds as F
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(3, 6))):
        kind = int(r.integers(3))
        reps = int(r.integers(2, 5))
        for j in range(reps):
            if kind == 0:
                y = F.whistle(r.uniform(2400, 3200), 0.06, seed + k * 10 + j, r.uniform(1800, 2400), harm=0.25,
                              attack=0.004)
            elif kind == 1:
                y = F.whistle(r.uniform(3200, 4200), 0.09, seed + k * 10 + j, r.uniform(3800, 4800), harm=0.12)
            else:
                y = F.trill(r.uniform(2600, 3400), 0.18, seed + k * 10 + j, rate=r.uniform(40, 55))
            parts.append((at, y, r.uniform(0.6, 1.0)))
            at += len(y) / SR + r.uniform(0.04, 0.09)
        at += r.uniform(0.15, 0.4)
    return F.series(parts)


def wetland_pools():
    import field_birds as F
    return {
        "duck": [F.pacific_black_duck(26000 + i) for i in range(4)],
        "swamphen": [F.purple_swamphen(26100 + i) for i in range(4)],
        "coot": [F.eurasian_coot(26200 + i) for i in range(6)],
        "swallow": [F.welcome_swallow(26300 + i) for i in range(3)],
        "warbler": [reed_warbler(26400 + i) for i in range(5)],
    }


def frog_bonks():
    """Western banjo frog 'bonks' from the recordings and synthesised."""
    bonk = (snips("pobble1", 250, 1200, thresh_db=12, min_len=0.05, max_len=0.6, gap=0.08)
            + snips("pobble2", 250, 1200, thresh_db=12, min_len=0.05, max_len=0.6, gap=0.08))
    bonk = [S.hp(b, 180) for b in bonk]
    for i in range(6):
        rr = np.random.default_rng(26500 + i)
        k = secs(0.25)
        tk = S.t_axis(k)
        f = rr.uniform(430, 560) * (1 + 0.35 * np.exp(-tk / 0.012))
        ph = 2 * np.pi * np.cumsum(f) / SR
        y = (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)) * np.exp(-tk / 0.05)
        bonk.append(S.fade(y, 0.002, 0.03))
    return bonk


def squelch_frog(seed):
    """Squelching froglet (Crinia insignifera), the swamp's other voice: a
    short, wet, rasping 'squelch' (mono)."""
    r = np.random.default_rng(seed)
    L = r.uniform(0.09, 0.14)
    n = secs(L)
    t = S.t_axis(n)
    pulses = (np.sin(2 * np.pi * r.uniform(90, 130) * t) > 0.3) * 1.0
    y = S.resonator(pulses + 0.3 * r.standard_normal(n), r.uniform(2400, 2900), 6.0)
    return S.fade(y * np.exp(-t / (L * 0.6)), 0.003, 0.02)


def frog_chorus(B, bonk, count, gain=(-18, -9), dist=(0.35, 0.8)):
    for k, at in enumerate(B.times(count, 0.9)):
        p = B.r.uniform(-0.8, 0.8)
        d = B.r.uniform(*dist)
        g = B.r.uniform(*gain)
        tt = at
        for j in range(int(B.r.integers(2, 6))):
            s = bonk[int(B.r.integers(len(bonk)))]
            B.put(distant(s, d, p, k * 10 + j, room=1.0), tt, g)
            tt += secs(B.r.uniform(0.5, 1.4))


@builder("amb_wetland_day")
def wetland_day():
    dur = 100
    B = Bed(dur, 2601)
    n = B.n
    B.add(S.circ_lp(texture(src("lapping", True), dur, 26011, chunk=20), 2500), -36)  # still water at the edge
    B.add(reed_rustle(n, 26012), -33)
    B.add(city_hum(n, 26013, 30, 220), -41)  # the freeway past the lake
    P = wetland_pools()
    B.scatter(P["warbler"], 7, gain_db=(-16, -8), dist=(0.15, 0.55))
    B.scatter(P["swamphen"], 4, gain_db=(-15, -8), dist=(0.25, 0.7))
    B.scatter(P["coot"], 8, gain_db=(-20, -12), dist=(0.3, 0.8))
    B.scatter(P["duck"], 3, gain_db=(-18, -11), dist=(0.4, 0.8))
    B.scatter(P["swallow"], 4, gain_db=(-24, -16), dist=(0.15, 0.5))
    B.scatter(bird_pools(), 3, gain_db=(-26, -18), dist=(0.6, 0.85))  # magpies on the far bank
    save_loop("amb/amb_wetland_day", B.x, **LEAN)


@builder("amb_wetland_dawn")
def wetland_dawn():
    dur = 100
    B = Bed(dur, 2602)
    n = B.n
    B.add(S.circ_lp(texture(src("lapping", True), dur, 26021, chunk=20), 2000), -38)
    B.add(reed_rustle(n, 26022, gust_rate=0.04), -40)
    B.add(city_hum(n, 26023, 30, 200), -44)
    P = wetland_pools()
    B.scatter(P["warbler"], 12, gain_db=(-15, -7), dist=(0.1, 0.6))
    B.scatter(P["swamphen"], 5, gain_db=(-15, -8), dist=(0.25, 0.7))
    B.scatter(P["coot"], 10, gain_db=(-19, -11), dist=(0.3, 0.8))
    B.scatter(P["duck"], 4, gain_db=(-17, -10), dist=(0.3, 0.8))
    frog_chorus(B, frog_bonks(), 4, gain=(-22, -14), dist=(0.5, 0.85))  # the last few from the night
    save_loop("amb/amb_wetland_dawn", B.x, **LEAN_WET)


@builder("amb_wetland_night")
def wetland_night():
    dur = 110
    B = Bed(dur, 2603)
    n = B.n
    B.add(texture(src("crickets_sub", True), dur, 26031, chunk=17, region=(22.5, 82)), -36)
    B.add(reed_rustle(n, 26032, gust_rate=0.035), -42)
    B.add(city_hum(n, 26033, 30, 200), -42)
    frog_chorus(B, frog_bonks(), 16, gain=(-17, -7), dist=(0.25, 0.8))
    sq = [squelch_frog(26600 + i) for i in range(8)]
    for k, at in enumerate(B.times(14, 0.9)):  # froglets in runs from the sedge
        p = B.r.uniform(-0.8, 0.8)
        tt = at
        for j in range(int(B.r.integers(3, 8))):
            B.put(distant(sq[int(B.r.integers(len(sq)))], B.r.uniform(0.3, 0.7), p, k * 20 + j, room=0.8),
                  tt, B.r.uniform(-24, -16))
            tt += secs(B.r.uniform(0.25, 0.6))
    P = wetland_pools()
    B.scatter(P["coot"], 4, gain_db=(-22, -15), dist=(0.4, 0.85))  # coots squabbling in the dark
    B.scatter(P["swamphen"], 1, gain_db=(-18, -14), dist=(0.6, 0.85))
    save_loop("amb/amb_wetland_night", B.x, **LEAN)


@builder("place_surf")
def place_surf():
    """On the sand at Trigg and Scarborough: a real swell breaking, each set
    a long roar, the whitewater fizzing up the beach and draining back."""
    dur = 54
    B = Bed(dur, 3801)
    n = B.n
    B.add(texture(src("beach_day", True), dur, 38011, chunk=18), -26)
    B.add(surf_breaks(n, 38012, every=7.5), -22)
    B.add(ear_wind(n, 38013, gust_rate=0.09), -34)
    B.scatter(gull_pool(), 4, gain_db=(-20, -11), dist=(0.2, 0.6))
    place_save("place_surf_loop", B.x)


@builder("place_surf_night")
def place_surf_night():
    dur = 54
    B = Bed(dur, 3802)
    n = B.n
    B.add(texture(src("beach_night", True), dur, 38021, chunk=18), -27)
    B.add(surf_breaks(n, 38022, every=8.5), -23)
    B.add(ear_wind(n, 38023, gust_rate=0.05), -38)
    place_save("place_surf_night_loop", B.x)


def surf_breaks(n, seed, every=7.5):
    """Breaking waves (stereo, circular): each one a low thump as the lip
    lands, a broadband roar that rolls along the beach from one side, then
    the whitewater's fizz running up the sand and hissing back."""
    r = np.random.default_rng(seed)
    y = np.zeros((n, 2))
    count = max(1, int(round(n / SR / every)))
    for k in range(count):
        at = (k + r.uniform(-0.2, 0.2)) * n / SR / count
        big = 0.7 + 0.5 * r.random()
        L = secs(7.0)
        t = S.t_axis(L)
        crash = np.clip(t / 0.25, 0, 1) * np.exp(-np.clip(t - 0.25, 0, None) / 1.4)
        roar = S.bp(r.standard_normal(L), 120, 3000, 2) * crash
        thump = S.lp(r.standard_normal(L), 120) * np.exp(-t / 0.3) * 2.5
        fizz_env = np.clip((t - 1.2) / 1.5, 0, 1) * np.exp(-np.clip(t - 2.7, 0, None) / 1.8)
        fizz = S.bp(r.standard_normal(L), 2500, 10000, 2) * fizz_env * (1 + 0.5 * (r.random(L) < 0.02))
        mono = (roar / (np.std(roar) + 1e-12) + thump / (np.std(thump) + 1e-12) * 0.6
                + fizz / (np.std(fizz) + 1e-12) * 0.5) * big
        # the break peels along the beach: sweep the pan across it
        p = (np.clip(t / 2.5, 0, 1) * 1.2 - 0.6) * (1 if k % 2 else -1)
        a = (p + 1) * np.pi / 4
        st = np.stack([mono * np.cos(a), mono * np.sin(a)], axis=1)
        idx = (np.arange(L) + int(at * SR)) % n
        np.add.at(y, idx, st)
    return y


def main(argv):
    import json
    names = list(BUILD)
    if argv:
        names = [k for k in BUILD if any(k.startswith(a) or a in k for a in argv)]
    # record which recordings ended up in which game files (for CREDITS.md)
    usage_path = SRC / "usage_amb.json"
    usage = json.loads(usage_path.read_text()) if usage_path.exists() else {}
    real_save = S.save
    for k in names:
        print(f"[{k}]", file=sys.stderr)
        USED.clear()
        outs: list[str] = []

        def save(rel, *a, **kw):
            outs.append(rel)
            return real_save(rel, *a, **kw)
        S.save = save
        try:
            BUILD[k]()
        finally:
            S.save = real_save
        usage[k] = {"sources": sorted(USED), "outputs": outs}
    usage_path.write_text(json.dumps(usage, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
