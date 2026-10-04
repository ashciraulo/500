"""Render a short drive the way the game plays engine loops, for listening.

This mirrors audio/scripts/engine_audio.gd: the two loops either side of the
current RPM are crossfaded (equal power) and each is pitch-shifted by
current_rpm / loop_rpm; on-load and off-load sets are crossfaded by throttle.
Use it to audition a set (including your own replacement recordings) without
opening Godot:

    python3 audio/tools/preview_drive.py fire12 build/preview/fire12_drive.ogg
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sfxlib as S  # noqa: E402

SR = S.SR
CTRL = 100  # control rate (Hz) for the little car simulation


def load_set(name: str):
    folder = S.AUDIO_ROOT / "engine" / name
    sets = {"onload": {}, "offload": {}}
    for f in sorted(folder.glob(f"eng_{name}_*load_*.ogg")):
        m = re.match(rf"eng_{name}_(onload|offload)_(\d+)$", f.stem)
        if m:
            sets[m.group(1)][int(m.group(2))] = S.load(f, mono=True)
    oneshots = {k: S.load(folder / f"eng_{name}_{k}.ogg", mono=True)
                for k in ("startup", "shutdown", "limiter") if (folder / f"eng_{name}_{k}.ogg").exists()}
    return sets, oneshots


def drive_trace(idle=850, redline=6000, seconds=26.0):
    """A small 5-speed car: pull away, run up through three gears, cruise,
    lift off, change down, coast to a stop. Returns per-control-step
    rpm, throttle, and the list of gear-change times."""
    ratios = [0, 140, 80, 55, 41, 33]  # rpm per km/h in each gear (approx.)
    n = int(seconds * CTRL)
    rpm = np.zeros(n)
    thr = np.zeros(n)
    kmh = np.zeros(n)
    speed = 0.0
    gear = 1
    shift_t = -1.0
    shifts = []
    cur = idle
    for i in range(n):
        t = i / CTRL
        if t < 2.5:
            want = 0.0  # idling after start-up
        elif t < 15:
            want = 1.0 if gear < 4 else 0.45
        elif t < 19:
            want = 0.0
        elif t < 21:
            want = 0.3
        else:
            want = 0.0
        shifting = 0 <= t - shift_t < 0.4
        throttle = 0.0 if shifting else want
        # Very rough longitudinal model.
        acc = throttle * 22 / gear - 0.8 - 0.0009 * speed ** 2
        if t >= 2.5:
            speed = max(0.0, speed + acc / CTRL)
        target = max(idle, speed * ratios[gear]) if t >= 3.0 or speed > 0 else idle
        if t < 3.0 and throttle > 0:
            target = max(target, idle + 1600 * min(1, (t - 2.5) / 0.5))  # clutch slip
        if shifting:
            target = max(idle, speed * ratios[gear])
        cur += (target - cur) * (0.25 if shifting else 0.12)
        if not shifting and throttle > 0.5 and cur > 5000 and gear < 4:
            gear += 1
            shift_t = t
            shifts.append(t)
        if t > 19 and gear > 2 and cur < 1700:
            gear -= 1
            shift_t = t
            shifts.append(t)
        if speed < 8 and gear > 1 and t > 19:
            gear = 1
        if t > 21 and speed < 12:
            target = idle
        rpm[i] = min(cur, redline)
        thr[i] = throttle
        kmh[i] = speed
    drive_trace.kmh = kmh
    return rpm, thr, shifts


def play_loops(sets, rpm_ctrl, thr_ctrl, electric=False):
    n = int(len(rpm_ctrl) * SR / CTRL)
    tc = np.arange(n) / SR * CTRL
    rpm = np.interp(tc, np.arange(len(rpm_ctrl)), rpm_ctrl)
    thr = np.interp(tc, np.arange(len(thr_ctrl)), thr_ctrl)
    # Smooth throttle the way the game does (~80 ms).
    a = np.exp(-1 / (0.08 * SR))
    from scipy import signal
    load = signal.lfilter([1 - a], [1, -a], thr)
    out = np.zeros(n)
    for kind, lw in (("onload", np.sqrt(load)), ("offload", np.sqrt(1 - load))):
        pts = sorted(sets[kind])
        for j, r in enumerate(pts):
            lo = pts[j - 1] if j > 0 else None
            hi = pts[j + 1] if j + 1 < len(pts) else None
            w = np.zeros(n)
            if lo is not None:
                m = (rpm >= lo) & (rpm < r)
                w[m] = np.sin((rpm[m] - lo) / (r - lo) * np.pi / 2)
            else:
                w[rpm < r] = 1
            if hi is not None:
                m = (rpm >= r) & (rpm < hi)
                w[m] = np.cos((rpm[m] - r) / (hi - r) * np.pi / 2)
            else:
                w[rpm >= r] = 1
            if not w.any():
                continue
            loop = sets[kind][r]
            ratio = (rpm + 15) / (r + 15) if electric else rpm / r
            pos = np.cumsum(ratio) % len(loop)
            i0 = pos.astype(int)
            fr = pos - i0
            y = loop[i0] * (1 - fr) + loop[(i0 + 1) % len(loop)] * fr
            out += y * w * lw
    return out


def render(name: str, out_path: str):
    sets, one = load_set(name)
    idle = min(sets["onload"])
    red = max(sets["onload"])
    rpm, thr, shifts = drive_trace(850, 6000) if name.startswith("electric") else drive_trace(idle, red)
    electric = name.startswith("electric")
    if electric:
        rpm, shifts = drive_trace.kmh, []
    body = play_loops(sets, rpm, thr, electric)
    start = one.get("startup")
    lead = len(start) if start is not None else 0
    total = lead + len(body) + (len(one["shutdown"]) if "shutdown" in one else 0)
    x = np.zeros(total)
    if start is not None:
        S.place(x, start, 0)
        xf = S.secs(0.3)  # crossfade start-up tail into the idle loop
        body[:xf] *= np.linspace(0, 1, xf)
        x[lead - xf:lead] *= np.linspace(1, 0, xf)
        S.place(x, body, lead - xf)
    else:
        S.place(x, body, 0)
    clunks = sorted((S.AUDIO_ROOT / "engine" / "extras").glob("eng_gear_clunk_modern_*.ogg"))
    for k, t in enumerate(shifts):
        if clunks:
            c = S.load(clunks[k % len(clunks)], mono=True) * 0.18
            S.place(x, c, lead + int(t * SR))
    if "shutdown" in one:
        end = lead + len(body) - S.secs(0.4)
        x[end:end + S.secs(0.4)] *= np.linspace(1, 0, S.secs(0.4))
        x[end + S.secs(0.4):] = 0
        S.place(x, one["shutdown"], end)
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    y = S.normalise(x, "peak")
    import soundfile as sf
    import subprocess
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        sf.write(tmp.name, y.astype(np.float32), SR)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-c:a", "libvorbis",
                        "-q:a", "6", str(out)], check=True)
    print(f"wrote {out} ({len(y) / SR:.1f}s)", file=sys.stderr)
    return y


if __name__ == "__main__":
    render(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else f"build/preview/{sys.argv[1]}_drive.ogg")
