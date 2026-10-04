"""Shared helpers for the audio generators.

Every generator script in this folder builds sounds as numpy arrays and hands
them to `save()`, which normalises loudness, encodes OGG Vorbis (q6) into the
game folder, and optionally writes a 48 kHz / 24-bit WAV master.

Arrays are float64, shape (n,) for mono or (n, 2) for stereo, range -1..1.
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import pyloudnorm
import soundfile as sf
from scipy import signal

SR = 48000
AUDIO_ROOT = Path(__file__).resolve().parent.parent  # .../audio
MASTERS_ROOT = AUDIO_ROOT.parent / "build" / "audio_masters"  # gitignored
WRITE_MASTERS = os.environ.get("AUDIO_MASTERS", "0") == "1"

_rng = np.random.default_rng(500)


def rng(seed: int | None = None) -> np.random.Generator:
    """Deterministic RNG so re-running a generator gives the same files."""
    return np.random.default_rng(seed) if seed is not None else _rng


# --------------------------------------------------------------------------
# Basic building blocks
# --------------------------------------------------------------------------

def secs(n: float) -> int:
    return int(round(n * SR))


def t_axis(n: int) -> np.ndarray:
    return np.arange(n) / SR


def noise(n: int, seed: int | None = None) -> np.ndarray:
    return rng(seed).standard_normal(n)


def pink(n: int, seed: int | None = None) -> np.ndarray:
    """Pink (1/f) noise via FFT shaping. Periodic, so it loops cleanly."""
    spec = np.fft.rfft(noise(n, seed))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    spec /= np.sqrt(f)
    out = np.fft.irfft(spec, n)
    return out / (np.std(out) + 1e-12)


def brown(n: int, seed: int | None = None) -> np.ndarray:
    spec = np.fft.rfft(noise(n, seed))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    spec /= f
    out = np.fft.irfft(spec, n)
    return out / (np.std(out) + 1e-12)


def sos_filter(x: np.ndarray, kind: str, freq, order: int = 2) -> np.ndarray:
    """Butterworth filter. kind: lowpass, highpass, bandpass, bandstop."""
    sos = signal.butter(order, freq, btype=kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def lp(x, f, order=2):
    return sos_filter(x, "lowpass", min(f, SR / 2 * 0.98), order)


def hp(x, f, order=2):
    return sos_filter(x, "highpass", f, order)


def bp(x, lo, hi, order=2):
    return sos_filter(x, "bandpass", [lo, min(hi, SR / 2 * 0.98)], order)


def peak_eq(x, f0, gain_db, q=1.0):
    """RBJ peaking EQ biquad."""
    a = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * a, -2 * np.cos(w0), 1 - alpha * a]
    den = [1 + alpha / a, -2 * np.cos(w0), 1 - alpha / a]
    return signal.lfilter(b, den, x, axis=0)


def resonator(x, f0, q):
    """Two-pole resonant band-pass (constant 0 dB peak gain)."""
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2 * q)
    b = [alpha, 0, -alpha]
    den = [1 + alpha, -2 * np.cos(w0), 1 - alpha]
    return signal.lfilter(b, den, x, axis=0)


# Circular (FFT) filtering: the output wraps around, so a loop filtered this
# way has no seam at its join. Use these for anything that must loop.

def circ_response(n: int, fn) -> np.ndarray:
    """Apply a magnitude response fn(freq_array) -> gain array, circularly."""
    f = np.fft.rfftfreq(n, 1 / SR)
    return fn(f)


def circ_filter(x: np.ndarray, gain: np.ndarray) -> np.ndarray:
    if x.ndim == 2:
        return np.stack([circ_filter(x[:, c], gain) for c in range(x.shape[1])], axis=1)
    return np.fft.irfft(np.fft.rfft(x) * gain, len(x))


def circ_lp(x, fc, order=2):
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return circ_filter(x, 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def circ_hp(x, fc, order=2):
    f = np.fft.rfftfreq(len(x), 1 / SR)
    f[0] = 1e-9
    return circ_filter(x, 1 / np.sqrt(1 + (fc / f) ** (2 * order)))


def circ_bp(x, lo, hi, order=2):
    return circ_lp(circ_hp(x, lo, order), hi, order)


def circ_convolve(x: np.ndarray, kernel: np.ndarray) -> np.ndarray:
    n = len(x)
    k = np.zeros(n)
    k[: min(len(kernel), n)] = kernel[:n]
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(k), n)


def smooth_noise(n: int, rate_hz: float, seed=None, periodic=True) -> np.ndarray:
    """Slowly varying random curve (-1..1-ish) for wobble and gusts."""
    if periodic:
        x = noise(n, seed)
        return circ_lp(x, rate_hz, 2) / (np.std(circ_lp(x, rate_hz, 2)) + 1e-12)
    x = lp(noise(n, seed), rate_hz, 2)
    return x / (np.std(x) + 1e-12)


def env_adsr(n, a, d, s, r, curve=3.0):
    """Linear-time ADSR, durations in seconds, sustain level s."""
    out = np.full(n, s, dtype=float)
    ia, idd, ir = secs(a), secs(d), secs(r)
    if ia:
        out[:ia] = np.linspace(0, 1, ia)
    if idd:
        out[ia:ia + idd] = s + (1 - s) * np.exp(-curve * np.linspace(0, 1, len(out[ia:ia + idd])))
    if ir:
        out[-ir:] *= np.linspace(1, 0, ir) ** 2
    return out


def env_exp(n, decay_s, attack_s=0.001):
    t = t_axis(n)
    e = np.exp(-t / decay_s)
    ia = max(1, secs(attack_s))
    e[:ia] *= np.linspace(0, 1, ia)
    return e


def fade(x, fin=0.0, fout=0.0):
    x = x.copy()
    if fin:
        i = secs(fin)
        ramp = np.linspace(0, 1, i)
        x[:i] *= ramp if x.ndim == 1 else ramp[:, None]
    if fout:
        i = secs(fout)
        ramp = np.linspace(1, 0, i) ** 2
        x[-i:] *= ramp if x.ndim == 1 else ramp[:, None]
    return x


def make_loop(x: np.ndarray, xfade_s: float = 0.25) -> np.ndarray:
    """Turn a non-periodic render into a seamless loop by crossfading its
    tail over its head (equal-power). Output is shorter by xfade_s."""
    n = secs(xfade_s)
    head, body, tail = x[:n], x[n:-n] if n else x, x[-n:]
    w = np.sin(np.linspace(0, np.pi / 2, n))
    if x.ndim == 2:
        w = w[:, None]
    mixed = tail * np.sqrt(1 - w ** 2) + head * w
    return np.concatenate([body, mixed]) if n else x


def stereo(x: np.ndarray, width: float = 0.0, seed=None) -> np.ndarray:
    """Mono -> stereo. width>0 decorrelates the sides with a short delay."""
    if x.ndim == 2:
        return x
    if width <= 0:
        return np.stack([x, x], axis=1)
    d = secs(0.011 * width)
    r = np.roll(x, d)
    return np.stack([x, (1 - width * 0.3) * x + width * 0.3 * r], axis=1)


def pan(x: np.ndarray, p: float) -> np.ndarray:
    """Equal-power pan of mono x, p in -1..1."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


def place(dst: np.ndarray, src: np.ndarray, at: int, wrap=False):
    """Add src into dst at sample index `at` (wrapping round for loops)."""
    n = len(src)
    if wrap:
        idx = (np.arange(n) + at) % len(dst)
        np.add.at(dst, idx, src)
        return dst
    if at >= len(dst):
        return dst
    end = min(len(dst), at + n)
    dst[at:end] += src[: end - at]
    return dst


def softclip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def reverb(x: np.ndarray, size_s=1.2, damp_hz=5000, wet=0.25, predelay_s=0.01,
           seed=7, circular=False) -> np.ndarray:
    """Cheap stereo convolution reverb from an exponentially decaying noise IR."""
    n = secs(size_s)
    r = rng(seed)
    irs = []
    for c in range(2):
        ir = r.standard_normal(n) * np.exp(-6.9 * t_axis(n) / size_s)
        ir = lp(ir, damp_hz, 1)
        ir = np.concatenate([np.zeros(secs(predelay_s)), ir])
        irs.append(ir / np.sqrt(np.sum(ir ** 2)))
    xs = stereo(x)
    if circular:
        wet_sig = np.stack([circ_convolve(xs[:, c], irs[c]) for c in range(2)], axis=1)
    else:
        wet_sig = np.stack([signal.fftconvolve(xs[:, c], irs[c])[: len(xs)] for c in range(2)], axis=1)
    return xs * (1 - wet) + wet_sig * wet * 1.5


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------

def true_peak(x: np.ndarray) -> float:
    up = signal.resample_poly(x, 4, 1, axis=0)
    return float(np.max(np.abs(up)) + 1e-12)


def normalise(x: np.ndarray, mode: str) -> np.ndarray:
    """mode: 'peak' (-1 dBTP), 'amb' (-24 LUFS), 'music' (-16 LUFS),
    'lufs:<n>' (custom), or 'none'."""
    if mode == "none":
        g = 1.0
    elif mode == "peak":
        g = 10 ** (-1 / 20) / true_peak(x)
    else:
        target = {"amb": -24.0, "music": -16.0}.get(mode)
        if target is None:
            target = float(mode.split(":")[1])
        meter = pyloudnorm.Meter(SR)
        data = x if len(x) > SR // 2 else np.concatenate([x, np.zeros_like(x)[: SR]])
        loud = meter.integrated_loudness(data)
        g = 10 ** ((target - loud) / 20)
    y = x * g
    tp = true_peak(y)
    if tp > 10 ** (-1 / 20):  # never exceed -1 dBTP
        y *= 10 ** (-1 / 20) / tp
    return y


def save(rel_path: str, x: np.ndarray, norm: str = "peak", quality: int = 6) -> Path:
    """Write audio/<rel_path>.ogg (and a WAV master when AUDIO_MASTERS=1).

    rel_path is relative to audio/, without extension, e.g.
    "car/car_horn_modern_tap" -> audio/car/car_horn_modern_tap.ogg
    """
    x = np.asarray(x, dtype=np.float64)
    if not np.all(np.isfinite(x)):
        raise ValueError(f"{rel_path}: non-finite samples")
    y = normalise(x, norm)
    out = AUDIO_ROOT / f"{rel_path}.ogg"
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        sf.write(tmp.name, y.astype(np.float32), SR, subtype="FLOAT")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name,
             "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1",
             "-fflags", "+bitexact", "-flags:a", "+bitexact", str(out)],
            check=True,
        )
        os.unlink(tmp.name)
    if WRITE_MASTERS:
        m = MASTERS_ROOT / f"{rel_path}.wav"
        m.parent.mkdir(parents=True, exist_ok=True)
        sf.write(m, y, SR, subtype="PCM_24")
    ch = "stereo" if y.ndim == 2 else "mono"
    print(f"  {rel_path}.ogg  {len(y) / SR:5.2f}s {ch}", file=sys.stderr)
    return out


def load(path: str | Path, mono=False) -> np.ndarray:
    """Load any audio file (via ffmpeg) at 48 kHz float."""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(path),
                        "-ar", str(SR), "-c:a", "pcm_f32le", tmp.name], check=True)
        x, _ = sf.read(tmp.name, dtype="float64")
        os.unlink(tmp.name)
    if mono and x.ndim == 2:
        x = x.mean(axis=1)
    return x
