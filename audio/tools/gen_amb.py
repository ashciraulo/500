#!/usr/bin/env python3
"""Ambience beds, ambience one-shots and night oddities for the Perth game.

Builds audio/amb/*.ogg and audio/oddity/*.ogg from:
  * recordings fetched by fetch_sources.py into build/sources/ (CC0 only,
    see audio/CREDITS.md), cut into short events and re-scattered, and
  * numpy synthesis (wind in the gums, traffic hum, pedestrian crossings,
    sirens, trains, level crossing bells, idles, radio static, voices...).

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


def save_loop(name, x, norm="amb"):
    check_seam(x, name)
    if norm == "amb":
        x = circ_limit(x)
        check_seam(x, name + " (limited)")
    S.save(name, x, norm=norm)


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
# No speech synthesiser is installed (no espeak/flite), so the "voices" are a
# small formant synthesiser: a glottal pulse train (or noise, for whispers)
# through three moving vowel formants, with fricative/plosive consonants and
# phrase-level pitch declination. It sounds like calm speech in an unknown
# language: rhythm and intonation of someone reading lists, but no words.

VOWELS = {  # F1, F2, F3 (Hz), adult male-ish
    "a": (730, 1090, 2440), "e": (530, 1840, 2480), "i": (270, 2290, 3010),
    "o": (570, 840, 2410), "u": (300, 870, 2240), "@": (500, 1500, 2500),
    "I": (390, 1990, 2550), "ae": (660, 1720, 2410), "O": (450, 950, 2500),
}
FRIC = {"s": (4500, 9000), "sh": (2200, 5000), "f": (1500, 7000), "h": (500, 3000)}


def formant_voice(dur, seed, f0=108.0, rate=4.2, whisper=False, phrase=(1.6, 3.2), pause=(0.5, 1.2)):
    """Unintelligible but speech-like voice, mono, `dur` seconds."""
    r = np.random.default_rng(seed)
    n = secs(dur)
    hop = 240  # 5 ms control frames
    nfr = n // hop + 1
    F = np.zeros((nfr, 3))
    amp = np.zeros(nfr)
    fric = np.zeros(nfr)
    fband = np.zeros((nfr, 2))
    pitch = np.zeros(nfr)
    vk = list(VOWELS)
    t = 0.25
    cur = np.array(VOWELS["@"], float)
    while t < dur - 0.4:
        plen = r.uniform(*phrase)
        p_end = min(dur - 0.3, t + plen)
        p0 = t
        while t < p_end:
            # optional consonant
            c = r.random()
            if c < 0.35:
                k = list(FRIC)[int(r.integers(len(FRIC)))]
                L = r.uniform(0.05, 0.1)
                a, b = int(t * SR / hop), int((t + L) * SR / hop)
                fric[a:b] = r.uniform(0.25, 0.5)
                fband[a:b] = FRIC[k]
                t += L
            elif c < 0.6:
                t += r.uniform(0.03, 0.06)  # plosive closure (silence)
                a = int(t * SR / hop)
                fric[a:a + 2] = 0.6
                fband[a:a + 2] = (1000, 5000)
            # vowel
            L = r.uniform(0.09, 0.2) * 4.2 / rate
            v = np.array(VOWELS[vk[int(r.integers(len(vk)))]], float) * r.uniform(0.95, 1.05)
            a, b = int(t * SR / hop), int((t + L) * SR / hop)
            k = max(1, b - a)
            w = np.linspace(0, 1, k)[:, None] ** 0.5
            F[a:a + k] = cur * (1 - w) + v * w
            env = np.sin(np.linspace(0, np.pi, k)) ** 0.6
            amp[a:a + k] = np.maximum(amp[a:a + k], env * r.uniform(0.7, 1.0))
            prog = (t - p0) / max(plen, 0.1)
            pitch[a:a + k] = f0 * (1.12 - 0.22 * prog) * (1 + 0.04 * r.standard_normal())
            cur = v
            t += L
        t = p_end + r.uniform(*pause)
    # hold formants/pitch through gaps
    for arr in (F, pitch):
        last = None
        for i in range(nfr):
            if (arr[i] == 0).all() if arr.ndim == 2 else arr[i] == 0:
                if last is not None:
                    arr[i] = last
            else:
                last = arr[i].copy() if arr.ndim == 2 else arr[i]
    pitch[pitch == 0] = f0
    F[(F == 0).all(axis=1)] = VOWELS["@"]
    # sample-rate controls
    xi = np.arange(n) / hop
    up = lambda c: np.interp(xi, np.arange(nfr), c)
    amp_s = S.lp(up(amp), 40, 1)
    fr_s = S.lp(up(fric), 60, 1)
    p_s = up(pitch) * (1 + 0.006 * np.sin(2 * np.pi * 5.5 * S.t_axis(n)))
    if whisper:
        srcv = S.hp(S.noise(n, seed + 1), 300, 1)
    else:
        ph = np.cumsum(p_s) / SR
        saw = 2 * (ph % 1.0) - 1
        srcv = S.lp(np.diff(np.concatenate([[0], saw])) * -1 + 0.02 * saw, 3500, 1)
        srcv = srcv / (np.std(srcv) + 1e-9) + 0.08 * S.noise(n, seed + 2)
    # time-varying formant filter, block by block with carried state
    from scipy import signal as sg
    out = np.zeros(n)
    zi = [np.zeros(2) for _ in range(3)]
    for i in range(0, n, hop):
        blk = srcv[i:i + hop]
        f = F[min(i // hop, nfr - 1)]
        acc = 0
        for j in range(3):
            bw = (60, 90, 150)[j] * (2.5 if whisper else 1)
            rr = np.exp(-np.pi * bw / SR)
            th = 2 * np.pi * f[j] / SR
            b = [1 - rr, 0, 0]
            a = [1, -2 * rr * np.cos(th), rr * rr]
            yj, zi[j] = sg.lfilter(b, a, blk, zi=zi[j])
            acc = acc + yj * (1.0, 0.7, 0.35)[j]
        out[i:i + hop] = acc
    out = out / (np.std(out) + 1e-9) * amp_s
    # fricatives
    fr_noise = np.zeros(n)
    nz = S.noise(n, seed + 3)
    for lo, hi in {tuple(v) for v in FRIC.values()} | {(1000, 5000)}:
        mask = up((fband[:, 0] == lo).astype(float))
        fr_noise += S.bp(nz, lo, hi, 2) * mask
    out = out + fr_noise / (np.std(fr_noise) + 1e-9) * fr_s * 0.35
    return out


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
    for i, (dur, seed, f0) in enumerate(((28.0, 9001, 104.0), (35.0, 9002, 112.0), (24.0, 9003, 98.0))):
        n = secs(dur)
        y = np.zeros(n)
        intro = interval_signal(seed)
        S.place(y, intro * 0.5, secs(0.8))
        # the reading: phrases like street names then digit groups
        v = formant_voice(dur - 4.0, seed, f0=f0, rate=3.6, phrase=(1.2, 2.6), pause=(0.7, 1.6))
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
        v = formant_voice(dur, seed, f0=100, rate=r.uniform(3.0, 4.5), whisper=True,
                          phrase=(0.8, 2.0), pause=(0.3, 0.9))
        v = v / (np.abs(v).max() + 1e-9)
        # sometimes two voices overlapping, slightly apart
        if i % 2 == 1:
            v2 = formant_voice(dur, seed + 50, f0=100, rate=3.8, whisper=True)
            v = v + 0.6 * np.roll(v2 / (np.abs(v2).max() + 1e-9), secs(0.7))
        sig = radio_fx(v, seed + 1, 0.7) * 0.5
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


def pan_const(x, p):
    a = (p + 1) * np.pi / 4
    return np.stack([x[:, 0] * np.cos(a) * np.sqrt(2), x[:, 1] * np.sin(a) * np.sqrt(2)], axis=1)


# --------------------------------------------------------------------------

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
