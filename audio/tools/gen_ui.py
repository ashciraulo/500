#!/usr/bin/env python3
"""UI sounds: menu, job, checkpoint, countdown, stingers, rewards, map, save.
Writes audio/ui/*.ogg (stereo).

    python3 audio/tools/gen_ui.py

Style: a warm, slightly tape-worn 1970s Italian TV jingle - vibraphone, soft
FM bells, a Rhodes-like FM electric piano, round bass and felt clicks, all in
D major (D minor for 'failed') so they sit with the music. Every sound runs
through a tape stage (wow and flutter, soft saturation, rolled-off top, faint
hiss) and a small plate-like reverb. Seeds are fixed.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402

from sfxlib import (SR, bp, env_exp, fade, hp, lp, noise, place, reverb, rng,  # noqa: E402
                    save, secs, softclip, t_axis)

OUT = "ui"


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


# MIDI note numbers used below
D3, A3, D4, E4, Fs4, F4, G4, A4, Bb4, B4, Cs5, C5, D5, E5, Fs5, F5, G5, A5, B5, Cs6, D6, E6, Fs6, A6 = (
    50, 57, 62, 64, 66, 65, 67, 69, 70, 71, 73, 72, 74, 76, 78, 77, 79, 81, 83, 85, 86, 88, 90, 93)
D2, A2, G2, Bb2, F2, C3 = 38, 45, 43, 46, 41, 48

# --------------------------------------------------------------------------
# Instruments (mono). Each takes frequency, held duration and velocity.
# --------------------------------------------------------------------------


def release_env(n, held, rel=0.08):
    """1 while the note is held, then a short damper release."""
    t = t_axis(n)
    return np.where(t < held, 1.0, np.exp(-(t - held) / rel))


def vibe(f, held=1.0, vel=1.0, seed=0):
    """Vibraphone: aluminium bar - fundamental plus the tuned 4th partial and
    a faint 10th, soft yarn-mallet thump, motor tremolo ~5.5 Hz."""
    dur = held + 0.6
    n = secs(dur)
    t = t_axis(n)
    dec = 1.6 * (440 / f) ** 0.5
    x = (np.sin(2 * np.pi * f * t) * np.exp(-t / dec)
         + 0.22 * vel * np.sin(2 * np.pi * 4 * f * t) * np.exp(-t / (dec * 0.18))
         + 0.05 * vel * np.sin(2 * np.pi * 9.9 * f * t) * np.exp(-t / 0.05))
    x *= 1 - 0.22 * (0.5 + 0.5 * np.sin(2 * np.pi * 5.5 * t))
    mallet = lp(noise(n, seed + 1) * env_exp(n, 0.004), 1500) * 0.15 * vel
    x = (x + mallet) * release_env(n, held, 0.12)
    a = secs(0.002)
    x[:a] *= np.linspace(0, 1, a)
    return x * vel


def fm_bell(f, held=1.0, vel=1.0, ratio=3.5, index=2.5, decay=0.9, seed=0):
    """Soft FM bell (modulator at an inharmonic ratio, index decaying)."""
    n = secs(held + decay * 1.5)
    t = t_axis(n)
    idx = index * vel * np.exp(-t / (decay * 0.3))
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * ratio * t)) * np.exp(-t / decay)
    a = secs(0.003)
    x[:a] *= np.linspace(0, 1, a)
    return x * vel * release_env(n, held + decay, 0.2)


def epiano(f, held=0.5, vel=1.0, seed=0):
    """Rhodes-ish FM electric piano: 1:1 FM for the bark, a quick high tine
    'ping' (ratio 14), long round decay."""
    n = secs(held + 0.5)
    t = t_axis(n)
    idx = (1.2 * vel + 0.3) * np.exp(-t / 0.18) + 0.25
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t)) * np.exp(-t / 1.6)
    x += 0.12 * vel * np.sin(2 * np.pi * 14 * f * t) * np.exp(-t / 0.02)
    a = secs(0.002)
    x[:a] *= np.linspace(0, 1, a)
    return x * vel * release_env(n, held, 0.15)


def bass(f, held=0.4, vel=1.0, seed=0):
    """Round finger bass: sine + a little 2nd/3rd harmonic, pluck decay."""
    n = secs(held + 0.25)
    t = t_axis(n)
    x = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t) + 0.12 * np.sin(6 * np.pi * f * t)
    x *= np.exp(-t / 0.9)
    x = softclip(x * 0.8, 1.3)
    a = secs(0.004)
    x[:a] *= np.linspace(0, 1, a)
    return x * vel * release_env(n, held, 0.06)


def brass(f, held=0.6, vel=1.0, seed=0):
    """Soft 70s brass section pad: band-limited saw whose brightness opens
    after the attack (like a lip 'blat'), slight vibrato."""
    n = secs(held + 0.3)
    t = t_axis(n)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.3, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    bright = 2 + 6 * vel * (1 - np.exp(-t / 0.06)) * np.exp(-t / 0.8) + 2
    x = np.zeros(n)
    k = 1
    while k * f < 8000:
        x += np.sin(k * ph) / k * np.exp(-k / bright)
        k += 1
    env = np.minimum(1, t / 0.035) * release_env(n, held, 0.1)
    return x * env * vel * 0.8


def felt_click(seed=0, vel=1.0, tone=1800):
    """Felt-covered key/button: dull low-passed tick plus a soft body knock."""
    n = secs(0.06)
    t = t_axis(n)
    x = lp(noise(n, seed) * np.exp(-t / 0.002), tone, 2) * 1.2
    x += np.sin(2 * np.pi * 210 * t) * np.exp(-t / 0.012) * 0.5
    return x * vel


def woodblock(f, vel=1.0, seed=0):
    """Small woodblock / temple block: two short modes and a click."""
    n = secs(0.15)
    t = t_axis(n)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.035) + 0.4 * np.sin(2 * np.pi * f * 2.7 * t) * np.exp(-t / 0.012)
    x += lp(noise(n, seed) * np.exp(-t / 0.001), 4000) * 0.3
    return x * vel


# --------------------------------------------------------------------------
# Mixing, tape and room
# --------------------------------------------------------------------------


def render(dur, events):
    """events: (time_s, mono_signal, gain, pan -1..1) -> stereo buffer."""
    out = np.zeros((secs(dur), 2))
    for at, sig, g, p in events:
        a = (p + 1) * np.pi / 4
        place(out[:, 0], sig * g * np.cos(a), secs(at))
        place(out[:, 1], sig * g * np.sin(a), secs(at))
    return out


def tape(x, seed=0, wow=1.0, hiss=1.0):
    """Tape-worn character: wow (~0.6 Hz) and flutter (~7 Hz) as a moving
    read position, gentle saturation, top rolled off ~9 kHz, faint hiss."""
    n = len(x)
    t = t_axis(n)
    r = rng(seed)
    d = (0.00035 * wow * np.sin(2 * np.pi * 0.6 * t + r.uniform(0, 6))
         + 0.00002 * np.sin(2 * np.pi * 7.1 * t) + 0.0006 * wow) * SR
    idx = np.clip(np.arange(n) - d, 0, n - 1)
    y = np.stack([np.interp(idx, np.arange(n), x[:, c]) for c in range(2)], axis=1)
    y = softclip(y * 1.2, 1.5) / 1.2
    y = lp(y, 9000, 2)
    y = hp(y, 60, 1)
    h = np.stack([hp(noise(n, seed + 1), 2000), hp(noise(n, seed + 2), 2000)], axis=1) * 0.0018 * hiss
    return y + h * (np.abs(y).max() > 0)


def finish(x, seed=0, wet=0.18, size=1.0, wow=1.0, tail=0.15):
    """Tape stage -> small plate reverb -> gentle fade at the end."""
    x = np.concatenate([x, np.zeros((secs(size * 0.6), 2))])
    y = tape(x, seed, wow)
    y = reverb(y, size_s=size, damp_hz=6000, wet=wet, predelay_s=0.012, seed=seed + 3)
    return fade(y, 0.0, tail)


def chord(t, notes, inst, held, vel, gain, spread=0.5, strum=0.0, seed=0):
    ev = []
    for i, m in enumerate(notes):
        p = -spread + 2 * spread * i / max(1, len(notes) - 1)
        ev.append((t + i * strum, inst(hz(m), held, vel, seed=seed + i), gain, p))
    return ev


# --------------------------------------------------------------------------
# The sounds
# --------------------------------------------------------------------------


def menu_move():
    """Menu move: a felt tick with a tiny high vibe 'tip' (A5), very short."""
    ev = [(0.0, felt_click(10, 0.8, 2200), 0.6, 0.0), (0.0, vibe(hz(A5), 0.04, 0.5, 11), 0.25, 0.1)]
    return finish(render(0.3, ev), 12, wet=0.1, size=0.5, tail=0.05)


def menu_select():
    """Select: felt click, then a quick rising vibe pair D5 -> A5 doubled
    by a soft FM bell an octave up."""
    ev = [(0.0, felt_click(20, 1.0), 0.6, 0.0),
          (0.0, vibe(hz(D5), 0.08, 0.8, 21), 0.5, -0.2),
          (0.07, vibe(hz(A5), 0.2, 0.9, 22), 0.5, 0.2),
          (0.07, fm_bell(hz(A6), 0.05, 0.4, decay=0.3, seed=23), 0.12, 0.3)]
    return finish(render(0.7, ev), 24, wet=0.15, size=0.7, tail=0.1)


def menu_back():
    """Back: softer, falling A5 -> D5, felt click."""
    ev = [(0.0, felt_click(30, 0.8, 1500), 0.6, 0.0),
          (0.0, vibe(hz(A5), 0.06, 0.6, 31), 0.45, 0.2),
          (0.07, vibe(hz(D5), 0.15, 0.6, 32), 0.45, -0.2)]
    return finish(render(0.6, ev), 33, wet=0.15, size=0.7, tail=0.1)


def pager_buzz(dur, seed):
    """Phone/pager vibrating on a hard surface: an eccentric motor buzz
    (~170 Hz) whose rattle against the table adds harmonics and grit."""
    n = secs(dur)
    t = t_axis(n)
    f = 170 * (1 - 0.15 * np.exp(-t / 0.03))
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph)
    rattle = bp(noise(n, seed), 800, 5000) * (np.sin(ph) > 0.6) * 0.8
    x = softclip((x + rattle) * 1.2, 2.0)
    env = np.minimum(1, t / 0.015) * np.minimum(1, (dur - t) / 0.03)
    return lp(x, 4000) * env


def job_offered():
    """Job offered: two pager buzz pulses, then a soft two-note FM chime
    (F#5 + A5 over D)."""
    ev = [(0.0, pager_buzz(0.32, 40), 0.35, -0.1), (0.42, pager_buzz(0.32, 41), 0.35, -0.1),
          (0.9, fm_bell(hz(Fs5), 0.2, 0.7, decay=0.8, seed=42), 0.4, -0.2),
          (1.02, fm_bell(hz(A5), 0.2, 0.7, decay=0.9, seed=43), 0.4, 0.2),
          (0.9, vibe(hz(D5), 0.5, 0.6, 44), 0.3, 0.0)]
    return finish(render(2.1, ev), 45, wet=0.2, size=1.0)


def job_accepted():
    """Job accepted: warm rising arpeggio D-F#-A-D on vibes with a Rhodes
    chord and bass D underneath."""
    ev = [(0.0, felt_click(50, 0.9), 0.5, 0.0)]
    for i, m in enumerate([D5, Fs5, A5, D6]):
        ev.append((0.02 + 0.075 * i, vibe(hz(m), 0.4 if i == 3 else 0.12, 0.8, 51 + i), 0.45, -0.4 + 0.27 * i))
    ev += chord(0.02, [D4, Fs4, A4], epiano, 0.5, 0.6, 0.2, seed=60)
    ev.append((0.02, bass(hz(D3), 0.4, 0.8), 0.35, 0.0))
    return finish(render(1.3, ev), 55, wet=0.2, size=1.0)


def checkpoint():
    """Checkpoint pass: a bright, quick double bell 'ding-ding' (A5, D6)
    with a vibe shimmer."""
    ev = [(0.0, fm_bell(hz(A5), 0.05, 0.8, ratio=3.5, index=2.0, decay=0.5, seed=70), 0.45, -0.2),
          (0.06, fm_bell(hz(D6), 0.1, 0.9, ratio=3.5, index=2.0, decay=0.7, seed=71), 0.45, 0.2),
          (0.06, vibe(hz(D5), 0.3, 0.7, 72), 0.35, 0.0)]
    return finish(render(1.0, ev), 73, wet=0.18, size=0.9)


def countdown_tick(final=False):
    """Countdown tick for the last 10 s: a pitched woodblock (A5); the final
    variant is higher (D6) with a bell on top."""
    if final:
        ev = [(0.0, woodblock(hz(D6), 1.0, 80), 0.6, 0.0), (0.0, fm_bell(hz(D6), 0.05, 0.6, decay=0.4, seed=81), 0.25, 0.0)]
    else:
        ev = [(0.0, woodblock(hz(A5), 1.0, 82), 0.6, 0.0)]
    return finish(render(0.35, ev), 83, wet=0.1, size=0.5, tail=0.05)


def mission_complete():
    """Mission complete (~2.5 s, D major): a pickup on vibes (A4-B4-C#5) into
    a D6/9 chord - Rhodes, soft brass stab, bass D-A walk, bell sparkle."""
    ev = []
    for i, m in enumerate([A4, B4, Cs5]):
        ev.append((0.0 + 0.11 * i, vibe(hz(m), 0.1, 0.8, 90 + i), 0.45, -0.3 + 0.2 * i))
    t1 = 0.36
    ev.append((t1, vibe(hz(D5), 1.2, 1.0, 95), 0.5, 0.0))
    ev.append((t1 + 0.18, vibe(hz(Fs5), 0.9, 0.8, 96), 0.4, 0.3))
    ev.append((t1 + 0.36, vibe(hz(A5), 0.8, 0.8, 97), 0.4, -0.3))
    ev += chord(t1, [D4, Fs4, A4, B4, E5], epiano, 1.3, 0.7, 0.2, strum=0.01, seed=100)
    ev += chord(t1, [A3, D4, Fs4], brass, 0.35, 0.9, 0.12, seed=110)
    ev.append((t1, bass(hz(D2), 0.5, 1.0), 0.35, 0.0))
    ev.append((t1 + 0.55, bass(hz(A2), 0.3, 0.8), 0.35, 0.0))
    ev.append((t1 + 0.85, bass(hz(D3), 0.7, 0.9), 0.4, 0.0))
    ev.append((t1 + 0.36, fm_bell(hz(D6), 0.4, 0.5, decay=1.0, seed=120), 0.15, 0.5))
    return finish(render(2.6, ev), 125, wet=0.22, size=1.4)


def mission_failed():
    """Mission failed (~2.5 s, D minor): descending A4-F4-D4 on vibes over a
    sagging Rhodes Dm -> Bb/D, tape wow exaggerated, bass falls D -> Bb."""
    ev = []
    for i, m in enumerate([A4, F4, D4]):
        ev.append((0.18 * i, vibe(hz(m), 0.25 if i < 2 else 1.2, 0.8, 130 + i), 0.5, 0.25 - 0.25 * i))
    ev += chord(0.0, [D4, F4, A4], epiano, 0.5, 0.6, 0.18, seed=140)
    ev += chord(0.55, [D4, F4, Bb4], epiano, 1.2, 0.5, 0.18, strum=0.02, seed=145)
    ev.append((0.0, bass(hz(D3), 0.45, 0.9), 0.4, 0.0))
    ev.append((0.55, bass(hz(Bb2), 1.0, 0.8), 0.4, 0.0))
    return finish(render(2.6, ev), 150, wet=0.25, size=1.4, wow=3.0)


def badge_pickup():
    """Badge pickup: a sparkling upward run of FM bells D6-F#6-A6 with a
    vibe D5 underneath."""
    ev = [(0.0, vibe(hz(D5), 0.4, 0.7, 160), 0.3, 0.0)]
    for i, m in enumerate([A5, D6, Fs6, A6]):
        ev.append((0.05 * i, fm_bell(hz(m), 0.05, 0.6, ratio=3.5, index=1.6, decay=0.6, seed=161 + i), 0.3, -0.45 + 0.3 * i))
    return finish(render(1.2, ev), 165, wet=0.22, size=1.0)


def coin_jingle(seed, count=6):
    """A few coins settling: small metallic tings, quickly thinning."""
    r = rng(seed)
    out = np.zeros(secs(0.5))
    t = 0.0
    for i in range(count):
        f = r.uniform(3500, 6500)
        n = secs(0.12)
        tt = t_axis(n)
        c = (np.sin(2 * np.pi * f * tt) + 0.5 * np.sin(2 * np.pi * f * 2.76 * tt)) * np.exp(-tt / 0.03)
        place(out, c * r.uniform(0.2, 0.5) * 0.8 ** i, secs(t))
        t += r.uniform(0.02, 0.06)
    return out


def money_earned():
    """Money earned: soft cash-register feel - a felt key thunk, the drawer
    bell (FM bell F#6, ringing) and a little coin jingle."""
    drawer = lp(noise(secs(0.12), 170) * env_exp(secs(0.12), 0.02), 600) * 0.8
    ev = [(0.0, felt_click(171, 1.0, 1400), 0.5, 0.0), (0.05, drawer, 0.5, 0.0),
          (0.06, fm_bell(hz(Fs6), 0.3, 0.8, ratio=2.76, index=1.8, decay=0.8, seed=172), 0.35, 0.15),
          (0.12, coin_jingle(173), 0.4, -0.2)]
    return finish(render(1.3, ev), 174, wet=0.18, size=0.9)


def car_purchased():
    """Car purchased: register bell, then a short warm brass + vibe flourish
    resolving on D major with a bass hit (~2 s)."""
    ev = [(0.0, felt_click(180, 1.0, 1400), 0.5, 0.0),
          (0.02, fm_bell(hz(Fs6), 0.2, 0.8, ratio=2.76, index=1.8, decay=0.7, seed=181), 0.3, 0.2),
          (0.1, coin_jingle(182, 8), 0.35, -0.2)]
    t1 = 0.4
    for i, m in enumerate([D5, E5, Fs5, A5]):
        ev.append((t1 + 0.08 * i, vibe(hz(m), 0.08 if i < 3 else 1.0, 0.8, 183 + i), 0.4, -0.3 + 0.2 * i))
    ev += chord(t1 + 0.24, [D4, Fs4, A4, D5], brass, 0.7, 0.9, 0.14, seed=190)
    ev += chord(t1 + 0.24, [Fs4, A4, Cs5, E5], epiano, 1.0, 0.6, 0.15, seed=195)
    ev.append((t1 + 0.24, bass(hz(D2), 0.9, 1.0), 0.45, 0.0))
    return finish(render(2.4, ev), 199, wet=0.22, size=1.3)


def tier_unlocked():
    """Tier unlocked fanfare (~6.5 s): a little 1970s TV ident - brass
    calls D-A-D, vibe melody over Rhodes chords I-IV-V-I (D G A D), walking
    bass, light shaker, ending on a held D major 9 with bell sparkle."""
    ev = []
    beat = 0.3
    # shaker: soft hi-hat-ish noise on 8ths
    for i in range(16):
        n = secs(0.06)
        sh = hp(noise(n, 300 + i), 5000) * np.exp(-t_axis(n) / (0.015 if i % 2 else 0.03))
        ev.append((i * beat / 2, sh, 0.08 if i % 2 else 0.12, 0.3))
    # brass call
    for i, (m, d) in enumerate([(D4, 0.25), (A4, 0.25), (D5, 0.5)]):
        ev += chord(i * beat, [m, m + 7] if i == 2 else [m], brass, d, 1.0, 0.18, spread=0.2, seed=310 + 3 * i)
    # chords + bass, one bar per chord (2 beats each)
    prog = [([D4, Fs4, A4, Cs5], D2), ([D4, G4, B4, D5], G2), ([E4, A4, Cs5, E5], A2), ([D4, Fs4, A4, E5], D2)]
    for b, (ch, root) in enumerate(prog):
        t0 = 3 * beat + b * 2 * beat
        ev += chord(t0, ch, epiano, 2 * beat - 0.05, 0.6, 0.13, strum=0.008, seed=330 + 5 * b)
        ev.append((t0, bass(hz(root), beat * 0.9, 1.0), 0.3, 0.0))
        ev.append((t0 + beat, bass(hz(root + 7), beat * 0.8, 0.8), 0.35, 0.0))
    # vibe melody
    mel = [(Fs5, 0.5), (A5, 0.5), (G5, 0.5), (B5, 0.5), (A5, 0.5), (Cs6, 0.5), (D6, 1.0)]
    t = 3 * beat
    for i, (m, ln) in enumerate(mel):
        ev.append((t, vibe(hz(m), ln * beat * 2 - 0.05, 0.85, 350 + i), 0.4, -0.15))
        t += ln * beat * 2
    # final chord
    tf = 3 * beat + 8 * beat
    ev += chord(tf, [D4, Fs4, A4, Cs5, E5], epiano, 2.2, 0.8, 0.16, strum=0.012, seed=370)
    ev += chord(tf, [A3, D4, Fs4, A4], brass, 1.2, 0.9, 0.12, seed=380)
    ev.append((tf, bass(hz(D2), 2.0, 1.0), 0.33, 0.0))
    ev.append((tf, vibe(hz(D6), 2.0, 0.9, 390), 0.35, 0.2))
    for i, m in enumerate([A5, D6, Fs6, A6]):
        ev.append((tf + 0.1 + 0.07 * i, fm_bell(hz(m), 0.1, 0.5, decay=1.2, seed=391 + i), 0.12, -0.5 + 0.33 * i))
    return finish(render(tf + 3.2, ev), 399, wet=0.22, size=1.6, tail=0.8)


def new_best_time():
    """New best time: perky vibe figure D5-F#5-A5-B5-A5 then a bell on D6,
    over a Rhodes D chord - quick and cheeky (~1.4 s)."""
    ev = []
    for i, m in enumerate([D5, Fs5, A5, B5, A5]):
        ev.append((0.07 * i, vibe(hz(m), 0.06, 0.8, 400 + i), 0.42, -0.3 + 0.15 * i))
    ev.append((0.42, fm_bell(hz(D6), 0.3, 0.8, decay=0.9, seed=410), 0.35, 0.1))
    ev.append((0.42, vibe(hz(D6), 0.6, 0.9, 411), 0.4, 0.0))
    ev += chord(0.42, [D4, Fs4, A4, Cs5], epiano, 0.7, 0.6, 0.16, seed=412)
    ev.append((0.42, bass(hz(D3), 0.5, 0.9), 0.35, 0.0))
    return finish(render(1.6, ev), 419, wet=0.2, size=1.1)


def paper(dur, seed, density=400, bright=1.0):
    """Paper handling: crackles (sparse filtered clicks) over a soft rustle."""
    r = rng(seed)
    n = secs(dur)
    t = t_axis(n)
    env = np.sin(np.pi * t / dur) ** 0.8
    rustle = bp(noise(n, seed), 1200 * bright, 8000) * 0.12
    cr = np.zeros(n)
    k = int(density * dur)
    np.add.at(cr, r.integers(0, n, k), r.lognormal(0, 0.7, k) * r.choice([-1, 1], k))
    cr = bp(cr, 1500, 9000) * 0.5
    return (rustle + cr) * env


def map_open():
    """Map open: a felt click and a folded paper map opening out (crinkle
    swells, a soft flap at the end), with a low vibe note."""
    ev = [(0.0, felt_click(420, 0.8), 0.5, 0.0), (0.02, paper(0.45, 421), 0.7, -0.2),
          (0.25, paper(0.3, 422, 250, 0.7), 0.6, 0.25),
          (0.5, lp(noise(secs(0.08), 423) * env_exp(secs(0.08), 0.015), 900), 0.5, 0.0),
          (0.05, vibe(hz(A4), 0.3, 0.5, 424), 0.2, 0.0)]
    return finish(render(0.9, ev), 425, wet=0.12, size=0.6, tail=0.1)


def map_close():
    """Map close: quicker fold-up crinkle and a soft slap, felt click."""
    ev = [(0.0, paper(0.3, 430, 500), 0.7, 0.2), (0.15, paper(0.2, 431, 300, 0.8), 0.6, -0.2),
          (0.33, lp(noise(secs(0.08), 432) * env_exp(secs(0.08), 0.012), 1100), 0.6, 0.0),
          (0.36, felt_click(433, 0.7), 0.4, 0.0), (0.3, vibe(hz(D4), 0.2, 0.4, 434), 0.18, 0.0)]
    return finish(render(0.7, ev), 435, wet=0.12, size=0.6, tail=0.1)


def save_confirmed():
    """Save confirmed: a tape-deck key clunk and a gentle two-note bell
    A5 -> D6 (resolves home)."""
    ev = [(0.0, felt_click(440, 1.0, 1200), 0.6, 0.0),
          (0.08, fm_bell(hz(A5), 0.1, 0.6, decay=0.6, seed=441), 0.3, -0.15),
          (0.2, fm_bell(hz(D6), 0.2, 0.6, decay=0.9, seed=442), 0.3, 0.15),
          (0.2, vibe(hz(D5), 0.4, 0.5, 443), 0.25, 0.0)]
    return finish(render(1.2, ev), 444, wet=0.18, size=1.0)


def phone_notify():
    """Phone notification (fine notices and messages): the phone buzzes
    twice in a pocket (muffled, no table rattle) and a dry two-note FM
    ping falls A5 -> F5, a little flat in mood without being alarming."""
    ev = [(0.0, lp(pager_buzz(0.18, 470), 900), 0.35, 0.0), (0.26, lp(pager_buzz(0.18, 471), 900), 0.35, 0.0),
          (0.52, fm_bell(hz(A5), 0.08, 0.7, ratio=3.0, index=1.6, decay=0.35, seed=472), 0.4, -0.1),
          (0.66, fm_bell(hz(F5), 0.15, 0.7, ratio=3.0, index=1.6, decay=0.5, seed=473), 0.4, 0.1)]
    return finish(render(1.4, ev), 474, wet=0.1, size=0.5, tail=0.1)


def main():
    save(f"{OUT}/ui_menu_move", menu_move())
    save(f"{OUT}/ui_menu_select", menu_select())
    save(f"{OUT}/ui_menu_back", menu_back())
    save(f"{OUT}/ui_job_offered", job_offered())
    save(f"{OUT}/ui_job_accepted", job_accepted())
    save(f"{OUT}/ui_checkpoint", checkpoint())
    save(f"{OUT}/ui_countdown_tick", countdown_tick(False))
    save(f"{OUT}/ui_countdown_tick_final", countdown_tick(True))
    save(f"{OUT}/ui_mission_complete", mission_complete())
    save(f"{OUT}/ui_mission_failed", mission_failed())
    save(f"{OUT}/ui_badge_pickup", badge_pickup())
    save(f"{OUT}/ui_money_earned", money_earned())
    save(f"{OUT}/ui_car_purchased", car_purchased())
    save(f"{OUT}/ui_tier_unlocked", tier_unlocked())
    save(f"{OUT}/ui_new_best_time", new_best_time())
    save(f"{OUT}/ui_map_open", map_open())
    save(f"{OUT}/ui_map_close", map_close())
    save(f"{OUT}/ui_save_confirmed", save_confirmed())


if __name__ == "__main__":
    if "phone" in sys.argv[1:]:
        save(f"{OUT}/ui_phone_notify", phone_notify())
    else:
        main()
        save(f"{OUT}/ui_phone_notify", phone_notify())
