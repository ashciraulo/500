#!/usr/bin/env python3
"""Bird-watching and fishing: WA bird calls, a few calls that are subtly
wrong, the binoculars / camera / journal foley, and fishing foley.

    python3 audio/tools/gen_field.py            # everything
    python3 audio/tools/gen_field.py birds      # one group: birds, ui, fish, mystery

Everything goes to audio/field/, named as the bird-watching code asks for it
(see audio/docs/field.md): field/bird_<species>_NN (mono, 3D-ready),
field/wrong_*, field/<ui sound> and field/<fishing sound>. The magpie,
kookaburra and raven already live in audio/amb/amb_bird_* and are reached
through Audio aliases (field/bird_australian_magpie and so on), not copied.

Carnaby's black cockatoo, rainbow lorikeet, southern boobook and the willie
wagtail's chatter are cut from CC0 recordings (run fetch_sources.py first).
Every other species is synthesised (here and in field_birds.py): no CC0
recordings of those were reachable. Seeds are fixed, so the output is
identical on every run.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402

import gen_amb as A  # noqa: E402
import field_birds as FB  # noqa: E402
import gen_car as C  # noqa: E402
import sfxlib as S  # noqa: E402
from sfxlib import SR, bp, hp, lp, noise, secs, t_axis  # noqa: E402

# Lean encodes: calls stop around 8 kHz (32 kHz keeps up to 16 kHz).
BIRD_ENC = dict(quality=3, rate=32000)
FX_ENC = dict(quality=4)


def save_bird(name, y, hp_hz=150):
    """Calls are matched for loudness (-20 LUFS, never over -1 dBTP), so a
    synthesised whistle is no louder than a recorded cockatoo."""
    y = S.fade(S.hp(y, hp_hz, 2), 0.01, 0.08)
    S.save(f"field/{name}", y, norm="lufs:-20", **BIRD_ENC)


def glide(f, n):
    """Phase of a pitch curve f (Hz per sample, array of length n)."""
    return 2 * np.pi * np.cumsum(np.broadcast_to(f, (n,))) / SR


def soft_env(n, attack, release):
    t = t_axis(n)
    L = n / SR
    return np.clip(t / attack, 0, 1) ** 2 * np.clip((L - t) / release, 0, 1) ** 1.5


# --------------------------------------------------------------------------
# Synthesised species
# --------------------------------------------------------------------------


def pelican(seed):
    """Australian pelican: adults are nearly silent. A low hoarse grunt (or two)
    and the hollow wooden clap of the great bill snapping shut."""
    r = np.random.default_rng(seed)
    parts = []
    t0 = 0.05
    for _ in range(int(r.integers(1, 3))):
        L = r.uniform(0.25, 0.45)
        n = secs(L)
        t = t_axis(n)
        f0 = r.uniform(95, 130) * (1 - 0.2 * t / L)
        pulse = (np.sin(glide(f0, n)) > 0.8) * 1.0 + 0.5 * r.standard_normal(n)
        y = S.resonator(pulse, 420, 2.5) + 0.6 * S.resonator(pulse, 900, 3.0) + 0.2 * S.resonator(pulse, 1900, 4.0)
        y *= soft_env(n, 0.03, L * 0.5)
        parts.append((t0, y, 0.6))
        t0 += L + r.uniform(0.15, 0.35)
    for k in range(int(r.integers(1, 4))):  # bill clap: a dry hollow wooden knock
        clap = C.add(C.modal(0.15, [(r.uniform(520, 640), 0.025, 0.8), (r.uniform(1300, 1500), 0.012, 0.4),
                                    (r.uniform(2600, 2900), 0.006, 0.2)], seed + 10 + k),
                     bp(C.burst(0.02, 0.0012, seed + 20 + k), 900, 6000) * 0.5)
        parts.append((t0, clap, 0.9))
        t0 += r.uniform(0.09, 0.16)
    return C.room(C.mix(t0 + 0.4, parts), 0.4, 0.15, 3500, seed)


def black_swan(seed):
    """Black swan: a soft, musical, slightly reedy bugle ('whistling trumpet')
    rising into each note, in a short conversational series."""
    r = np.random.default_rng(seed)
    parts = []
    t0 = 0.05
    for i in range(int(r.integers(2, 4))):
        L = r.uniform(0.35, 0.7)
        n = secs(L)
        t = t_axis(n)
        base = r.uniform(620, 820) * (1.0 if i % 2 == 0 else r.uniform(0.85, 0.95))
        f = base * (0.82 + 0.18 * (1 - np.exp(-t / 0.05))) * (1 - 0.06 * t / L) \
            * (1 + 0.006 * np.sin(2 * np.pi * 5.5 * t))
        ph = glide(f, n)
        reed = sum((0.9 if h % 2 else 0.45) / h ** 1.1 * np.sin(h * ph) for h in range(1, 9))
        y = S.resonator(reed, 1600, 2.5) * 0.5 + reed * 0.5 + 0.08 * bp(r.standard_normal(n), 1000, 4000, 1)
        y *= soft_env(n, 0.04, L * 0.4)
        parts.append((t0, y, r.uniform(0.7, 1.0)))
        t0 += L + r.uniform(0.25, 0.7)
    return C.room(C.mix(t0 + 0.6, parts), 0.6, 0.2, 4000, seed)


def frogmouth(seed, count=None, f0=None):
    """Tawny frogmouth at night: a deep, soft, pulsing 'oom-oom-oom-oom',
    about four a second, carrying a long way through the dark."""
    r = np.random.default_rng(seed)
    count = count or int(r.integers(8, 15))
    f0 = f0 or r.uniform(260, 310)
    rate = r.uniform(3.4, 4.2)
    out = np.zeros(secs(count / rate + 1.0))
    for k in range(count):
        L = 0.13
        n = secs(L)
        t = t_axis(n)
        f = f0 * (1 + 0.04 * np.sin(np.pi * t / L)) * (1 - 0.002 * k)
        ph = glide(f, n)
        y = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.05 * bp(r.standard_normal(n), 200, 900, 1)
        y *= np.sin(np.pi * np.clip(t / L, 0, 1)) ** 1.6
        S.place(out, y * (0.7 + 0.3 * np.sin(np.pi * k / count)), secs(k / rate))
    return out


def silver_gull(seed):
    return A.silver_gull(seed)


# --------------------------------------------------------------------------
# Recorded species: the clearest calls cut from CC0 recordings
# --------------------------------------------------------------------------

def recorded():
    ck = A.src("cockatoo_perth")
    for i, (a, b) in enumerate([(44.0, 47.6), (12.1, 15.0), (19.9, 23.2)]):
        save_bird(f"bird_carnabys_black_cockatoo_{i + 1:02d}", A.cut(ck, secs(a), secs(b), 0.03, 0.3), 400)
    lk = A.src("lorikeets")
    for i, (a, b) in enumerate([(31.35, 32.95), (10.6, 11.55), (20.1, 21.9)]):
        save_bird(f"bird_rainbow_lorikeet_{i + 1:02d}", A.cut(lk, secs(a), secs(b), 0.02, 0.15), 1200)
    bb = A.src("boobook1")
    for i, (a, b) in enumerate([(34.7, 41.6), (44.7, 49.0)]):
        save_bird(f"bird_southern_boobook_{i + 1:02d}", A.cut(bb, secs(a), secs(b), 0.05, 0.4), 200)
    # willie wagtail: the same two chatter phrases as amb_bird_wagtail
    wg = A.src("wagtail1")
    ev = A.find_events(wg, 2000, 8000, thresh_db=14, min_len=0.8, max_len=3.0, gap=0.35)
    for i, (a, b, _) in enumerate(sorted(sorted(ev, key=lambda e: -e[2])[:2])):
        save_bird(f"bird_willie_wagtail_{i + 1:02d}", A.cut(wg, a, b), 1500)


# --------------------------------------------------------------------------
# Wrong calls: quiet, at night, never jumpy. Each is a real call made subtly
# impossible.
# --------------------------------------------------------------------------

def whistle_note(f, L, seed, slide=0.06):
    """A clean bird whistle with a little upward slur into the note."""
    n = secs(L)
    t = t_axis(n)
    r = np.random.default_rng(seed)
    fc = f * (1 - slide * np.exp(-t / 0.03)) * (1 + 0.004 * np.sin(2 * np.pi * r.uniform(5, 7) * t))
    ph = glide(fc, n)
    y = np.sin(ph) + 0.06 * np.sin(2 * ph)
    return y * soft_env(n, 0.02, L * 0.35)


def mono_amb(name):
    x = S.load(S.AUDIO_ROOT / f"amb/{name}.ogg")
    return x.mean(axis=1) if x.ndim == 2 else x


def wrong_calls():
    """field/wrong_magpie_song and field/wrong_frogmouth are the two the
    journal uses; the rest are spares for later clues."""
    # A magpie's carol that drifts, mid-phrase, into the midnight station's
    # falling interval (E D C G), sung in the magpie's own warbling voice and
    # a little flat, as if it learned it off a car radio.
    mag = mono_amb("amb_bird_magpie_01")
    carol = S.fade(mag[:secs(1.6)], 0.0, 0.25)
    tune = np.zeros(secs(3.4))
    for i, (at, f) in enumerate(A.INTERVAL_NOTES):
        L = 0.42 if i < 3 else 1.0
        note = FB.whistle(f * 2 * 2 ** (-30 / 1200), L, 7710 + i, slur=0.08, vib=(0.012, 9.0), harm=0.25,
                          breath=0.04)
        S.place(tune, note, secs(at * 1.1))
    y = C.mix(5.4, [(0.0, carol, 1.0), (1.35, tune, 0.8)])
    y = A.distant(A.tape_warble(y, 7715), 0.45, 0, 1, room=2.0).mean(axis=1)
    save_bird("wrong_magpie_song", y, 300)
    # A frogmouth's oom-oom-oom, but metronome-regular: every note the same
    # pitch, the same length, exactly 0.5 s apart, for far too long.
    note = frogmouth(7720, count=1, f0=280)
    note = note[:secs(0.32)]
    y = np.zeros(secs(9.0))
    for k in range(16):
        S.place(y, note, secs(0.2 + 0.5 * k))
    y = A.distant(S.fade(y, 0.1, 0.05), 0.5, 0, 2, room=2.2).mean(axis=1)
    save_bird("wrong_frogmouth", y, 150)

    bb = A.src("boobook1")
    pair = A.cut(bb, secs(37.75), secs(38.75), 0.04, 0.1)
    # boo-book-book: the pair, then one note more, a semitone too high
    third = A.rate(A.cut(bb, secs(38.25), secs(38.75), 0.02, 0.1), 2 ** (1 / 12))
    y = C.mix(3.0, [(0.0, pair, 1.0), (1.0, third, 0.9)])
    save_bird("wrong_boobook", A.distant(y, 0.5, 0, 1, room=2.2).mean(axis=1), 200)
    # a magpie carol, backwards and slowed, very soft, on worn tape
    y = A.tape_warble(A.rate(mag[::-1], 0.88), 7702)
    save_bird("wrong_magpie_reversed", A.distant(lp(y, 4500), 0.55, 0, 2, room=2.0).mean(axis=1), 300)
    # a frogmouth answered by itself from further off, note for note, and the
    # echo comes back louder than it left
    f = frogmouth(7703, count=8, f0=285)
    y = C.mix(5.2, [(0.0, A.distant(f, 0.55, 0, 3).mean(axis=1), 0.6), (2.6, f, 0.8)])
    save_bird("wrong_frogmouth_answer", y, 150)
    # the kookaburra family laughing at half speed, trailing off early
    y = A.rate(mono_amb("amb_bird_kookaburra_01"), 0.55)[:secs(6.5)]
    save_bird("wrong_kookaburra_slow", A.distant(S.fade(y, 0.05, 2.5), 0.5, 0, 4, room=2.4).mean(axis=1), 120)


def render_birds():
    recorded()
    for i in range(2):
        save_bird(f"bird_australian_pelican_{i + 1:02d}", pelican(7100 + i), 60)
    for i in range(3):
        save_bird(f"bird_black_swan_{i + 1:02d}", black_swan(7200 + i), 200)
    for i in range(2):
        save_bird(f"bird_tawny_frogmouth_{i + 1:02d}", frogmouth(7300 + i), 120)
    for i in range(3):
        save_bird(f"bird_silver_gull_{i + 1:02d}", silver_gull(7400 + i), 400)
    save_bird("bird_willie_wagtail_03", FB.wagtail_night_song(7450), 1500)
    for k, (name, fn) in enumerate(FB.SPECIES.items()):
        for i in range(3 if k % 3 else 2):
            save_bird(f"bird_{name}_{i + 1:02d}", fn(7500 + 20 * k + i), 150)
    wrong_calls()


# --------------------------------------------------------------------------
# Camera, binoculars, journal (2D UI foley, kept small and soft)
# --------------------------------------------------------------------------

def paper(dur, seed, density=300, bright=1.0):
    """Paper moving: crackle impulses through a papery band, with a soft swish."""
    n = secs(dur)
    r = np.random.default_rng(seed)
    imp = (r.random(n) < density / SR) * r.standard_normal(n)
    y = bp(imp, 1200 * bright, 7000, 2) * 2 + bp(noise(n, seed + 1), 600, 5000, 1) * 0.25
    return y * soft_env(n, 0.02, dur * 0.4)


def camera_shutter():
    """An old film SLR: the release button, the mirror slapping up, the
    cloth shutter's two curtains, the mirror dropping back, the wind lever."""
    btn = C.plastic_click(8000, 0.5, 1600)
    mirror = C.add(C.modal(0.12, [(310, 0.02, 0.8), (720, 0.015, 0.5), (1900, 0.008, 0.3)], 8001),
                   bp(C.burst(0.03, 0.003, 8002), 900, 7000) * 0.7)
    curtain = lambda s: C.add(bp(C.burst(0.015, 0.0008, s), 2500, 12000) * 0.8,  # noqa: E731
                              C.modal(0.04, [(4200, 0.006, 0.25)], s + 1))
    n = secs(0.35)
    t = t_axis(n)
    wind = (bp(noise(n, 8005), 2000, 8000, 1) * 0.05 + 0.12 * (np.sin(2 * np.pi * 95 * t) > 0.9)) \
        * np.sin(np.pi * t / 0.35)
    for k in range(9):
        S.place(wind, C.tick(8010 + k, 3600, 1500, 0.08), secs(0.03 + k * 0.035))
    x = C.mix(1.0, [(0.0, btn, 1.0), (0.03, mirror, 1.0), (0.045, curtain(8003), 1.0),
                    (0.06, curtain(8004), 0.8), (0.085, mirror * 0.6, 1.0), (0.42, wind, 1.0)])
    return C.room(x, 0.1, 0.06, 6000, 8006)


def binoculars(up: bool):
    """Binoculars raised (strap and body rustle, rubber eyecups meeting the
    brow, a soft knurled-wheel turn) or lowered (rustle, a gentle bump on the
    chest)."""
    seed = 8030 if up else 8040
    n = secs(0.4)
    rustle = (bp(noise(n, seed), 400, 4000, 1) * 0.12 + paper(0.4, seed + 1, 120, 0.6) * 0.3) \
        * soft_env(n, 0.05, 0.2)
    if up:
        cups = lp(C.burst(0.08, 0.012, seed + 2), 700) * 0.9
        wheel = np.zeros(secs(0.25))
        for k in range(6):
            S.place(wheel, C.tick(seed + 10 + k, 3000, 1200, 0.07), secs(k * 0.035))
        x = C.mix(0.9, [(0.0, rustle, 1.0), (0.32, cups, 1.0), (0.5, wheel, 1.0)])
    else:
        bump = C.add(lp(C.burst(0.1, 0.02, seed + 2), 400) * 1.2,
                     C.modal(0.12, [(220, 0.03, 0.4), (540, 0.02, 0.2)], seed + 3))
        x = C.mix(0.8, [(0.0, rustle, 1.0), (0.36, bump, 1.0)])
    return C.room(x, 0.1, 0.05, 5000, seed + 5)


def journal(kind):
    """The field journal: an old cloth-bound notebook."""
    if kind == "open":
        creak = C.modal(0.25, [(180, 0.06, 0.3), (410, 0.04, 0.2)], 8050) * 0.6
        x = C.mix(0.9, [(0.0, creak, 1.0), (0.05, paper(0.45, 8051, 260), 1.0),
                        (0.42, lp(C.burst(0.1, 0.02, 8052), 500) * 0.6, 1.0)])
    elif kind == "close":
        x = C.mix(0.6, [(0.0, paper(0.22, 8060, 200), 0.7),
                        (0.2, C.add(lp(C.burst(0.12, 0.018, 8061), 450) * 1.3,
                                    bp(C.burst(0.03, 0.004, 8062), 500, 3000) * 0.3), 1.0)])
    elif kind == "page":
        x = C.mix(0.6, [(0.0, paper(0.42, 8070, 420, 1.2), 1.0)])
    else:  # new entry: a quick pencil note, then a rubber stamp pressed down
        n = secs(0.7)
        t = t_axis(n)
        strokes = (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 6.0 * t))) * soft_env(n, 0.02, 0.1)
        pencil = bp(noise(n, 8080), 2500, 9000, 1) * strokes * 0.12 \
            + bp(noise(n, 8081), 300, 1500, 1) * strokes * 0.04
        stamp = C.add(lp(C.burst(0.15, 0.015, 8082), 600) * 1.4, C.modal(0.2, [(180, 0.03, 0.5), (430, 0.02, 0.3)], 8083),
                      bp(C.burst(0.02, 0.002, 8084), 800, 5000) * 0.3)
        x = C.mix(1.4, [(0.0, pencil, 1.0), (0.95, stamp, 1.0)])
    return C.room(x, 0.12, 0.07, 5000, 8090)


def focus_tick():
    """One fine detent of the focus ring: played each time the dial's
    needle steps, so it is tiny and soft."""
    x = C.mix(0.08, [(0.0, C.tick(8024, 5400, 2400, 0.3), 1.0)])
    return C.room(x, 0.05, 0.04, 6000, 8025)


def focus_hit():
    """The needle caught in a sharp arc: the ring clicks home into a detent
    and the glass rings very faintly."""
    ring = C.modal(0.35, [(2630, 0.12, 0.25), (5270, 0.07, 0.1)], 8026) * 0.4
    x = C.mix(0.5, [(0.0, C.plastic_click(8027, 0.6, 2200), 1.0), (0.0, C.tick(8028, 4600, 2000, 0.4), 1.0),
                    (0.005, ring, 1.0)])
    return C.room(x, 0.08, 0.05, 6000, 8029)


def focus_miss():
    """A miss: the ring slips past soft and blurry, a dull rubbery drag."""
    n = secs(0.22)
    drag = lp(bp(noise(n, 8031), 300, 2500, 1), 1800) * soft_env(n, 0.03, 0.12) * 0.3
    x = C.mix(0.4, [(0.0, drag, 1.0), (0.12, lp(C.burst(0.06, 0.012, 8032), 500) * 0.5, 1.0)])
    return C.room(x, 0.08, 0.05, 4000, 8033)


def film_full():
    """End of the roll: the wind lever jams half way with a hard stop, then
    the rewind crank's dry whirr."""
    n = secs(0.2)
    t = t_axis(n)
    lever = bp(noise(n, 8041), 2000, 8000, 1) * 0.05 * np.sin(np.pi * t / 0.2)
    for k in range(4):
        S.place(lever, C.tick(8042 + k, 3600, 1500, 0.08), secs(0.02 + k * 0.035))
    stop = C.add(C.modal(0.08, [(1300, 0.012, 0.6), (3100, 0.006, 0.3)], 8046),
                 bp(C.burst(0.02, 0.002, 8047), 900, 6000) * 0.6)
    n = secs(1.1)
    t = t_axis(n)
    turns = 0.5 + 0.5 * np.sin(2 * np.pi * 3.2 * t)
    whirr = (bp(noise(n, 8048), 1500, 7000, 1) * 0.06 + 0.05 * (np.sin(2 * np.pi * 140 * t) > 0.85)) \
        * turns * soft_env(n, 0.05, 0.3)
    x = C.mix(1.8, [(0.0, lever, 1.0), (0.17, stop, 1.0), (0.55, whirr, 1.0)])
    return C.room(x, 0.1, 0.06, 6000, 8049)


UI_SOUNDS = {
    "shutter": camera_shutter, "focus_tick": focus_tick, "focus_hit": focus_hit, "focus_miss": focus_miss,
    "film_full": film_full, "binoculars_up": lambda: binoculars(True), "binoculars_down": lambda: binoculars(False),
    "journal_open": lambda: journal("open"), "journal_close": lambda: journal("close"),
    "journal_page": lambda: journal("page"), "journal_new_entry": lambda: journal("entry"),
}


def render_ui():
    for name, fn in UI_SOUNDS.items():
        S.save(f"field/{name}", S.fade(fn(), 0.0, 0.03), norm="peak", **FX_ENC)


# --------------------------------------------------------------------------
# Fishing
# --------------------------------------------------------------------------

def whoosh(dur, seed, lo=500, hi=3500, peak=0.4):
    """A rod or line swishing through the air: band noise whose centre and
    level rise and fall with the swing speed."""
    n = secs(dur)
    t = t_axis(n) / dur
    speed = np.exp(-((t - peak) / 0.18) ** 2)
    y = noise(n, seed)
    lo_y = bp(y, lo, (lo + hi) / 2, 2)
    hi_y = bp(y, (lo + hi) / 2, hi, 2)
    return (lo_y * (1 - speed) * 0.4 + hi_y * speed) * speed


def spool_zizz(dur, seed, rate0=240, rate1=60):
    """Line peeling off a spinning reel: fast ticks of the line over the spool
    lip (slowing as the cast loses speed) in a thin hiss."""
    n = secs(dur)
    t = t_axis(n)
    rate = rate0 + (rate1 - rate0) * (t / dur)
    ph = np.cumsum(rate / SR)
    ticks = np.diff(np.floor(ph), prepend=0)
    y = S.resonator(ticks, 3800, 6) + 0.5 * S.resonator(ticks, 6200, 8) + bp(noise(n, seed), 4000, 10000, 1) * 0.03
    return y * np.exp(-t / dur * 1.6) * soft_env(n, 0.005, dur * 0.3)


def plop(seed, size=1.0):
    """Something small entering the water: the bubble's rising 'bloop' and a
    little splash."""
    r = np.random.default_rng(seed)
    n = secs(0.25)
    t = t_axis(n)
    f = r.uniform(500, 800) / size * (1 + 2.5 * t / 0.25)
    bub = np.sin(glide(f, n)) * np.exp(-t / (0.03 * size))
    spl = bp(r.standard_normal(n), 900, 6000, 2) * np.exp(-t / (0.02 * size)) * 0.5
    return S.fade(bub + spl, 0.002, 0.05)


def splash(seed, big):
    """A fish thrashing at the surface: a cluster of slaps and spray."""
    r = np.random.default_rng(seed)
    dur = 1.4 if big else 0.8
    out = np.zeros(secs(dur + 0.4))
    hits = int(r.integers(5, 9)) if big else int(r.integers(2, 5))
    for k in range(hits):
        at = (k / hits) * dur * r.uniform(0.85, 1.0)
        L = 0.18 if big else 0.12
        n = secs(L)
        tt = t_axis(n)
        slap = bp(r.standard_normal(n), 300 if big else 600, 7000, 2) * np.exp(-tt / (0.035 if big else 0.02))
        body = np.sin(2 * np.pi * r.uniform(90, 160) * tt) * np.exp(-tt / 0.04) * (0.8 if big else 0.3)
        S.place(out, (slap + body) * r.uniform(0.5, 1.0), secs(at))
        S.place(out, plop(seed + 10 + k, 1.4 if big else 1.0) * 0.4, secs(at + 0.03))
    spray = bp(noise(len(out), seed + 50), 2500, 9000, 1) * soft_env(len(out), 0.05, 0.4) * (0.06 if big else 0.03)
    return out + spray


def cast(seed):
    r = np.random.default_rng(seed)
    swing = r.uniform(0.45, 0.6)
    fly = r.uniform(0.9, 1.4)
    x = C.mix(swing + fly + 0.8, [(0.0, C.tick(seed, 2600, 900, 0.3), 1.0),       # bail flips open
                                  (0.1, whoosh(swing, seed + 1, 400, 3000, 0.65), 1.0),
                                  (0.1 + swing * 0.6, spool_zizz(fly, seed + 2), 0.8),
                                  (0.1 + swing * 0.6 + fly, plop(seed + 3, 0.8), 0.35)])
    return x


def reel_loop(seconds=2.0):
    """Winding the reel in at a steady pace: gear whine at the handle rate,
    the anti-reverse pawl ticking, the line laying onto the spool."""
    n = secs(seconds)
    t = t_axis(n)
    f_handle = round(2.5 * seconds) / seconds  # ~2.5 handle turns a second, whole cycles in the loop
    # main gear meshing with the pinion (~130 teeth per handle turn), and the
    # rotor's faint whirr
    gear = sum(a * np.sin(2 * np.pi * f_handle * m * t) for m, a in ((130, 0.12), (260, 0.06), (390, 0.03)))
    rotor = S.circ_bp(noise(n, 9011), 600, 2500, 1) * 0.08
    out = (gear + rotor) * (0.75 + 0.25 * np.sin(2 * np.pi * f_handle * t))
    ticks = int(round(f_handle * 8 * seconds))
    for k in range(ticks):
        S.place(out, C.tick(9000 + k % 7, 4200, 1800, 0.1), secs(k * seconds / ticks), wrap=True)
    line = S.circ_bp(noise(n, 9010), 2000, 7000, 1) * 0.02
    return C.check_loop("reel", out + line)


def tension_loop(seconds=4.0):
    """A fish pulling on a taut line: the line singing faintly as it saws
    through the water, the rod blank creaking, the drag clicking now and
    then. Fade it up with tension; near breaking point it frays."""
    n = secs(seconds)
    t = t_axis(n)
    wob = S.smooth_noise(n, 2.0, 9020, periodic=True)
    f = round(880 * seconds) / seconds
    sing = (np.sin(2 * np.pi * f * t + 3 * np.sin(2 * np.pi * 3 / seconds * t))) * (0.25 + 0.1 * wob)
    hiss = S.circ_bp(noise(n, 9021), 600, 3000, 2) * 0.25
    creak = np.zeros(n)
    r = np.random.default_rng(9022)
    for _ in range(5):
        at = r.uniform(0, seconds)
        m = secs(r.uniform(0.15, 0.35))
        rate = r.uniform(60, 120)
        pulses = np.diff(np.floor(np.cumsum(np.full(m, rate / SR))), prepend=0) * (0.5 + r.random(m))
        c = S.resonator(pulses, 700, 5) + 0.5 * S.resonator(pulses, 1500, 6)
        S.place(creak, c * np.sin(np.linspace(0, np.pi, m)) * 0.6, secs(at), wrap=True)
    drag = np.zeros(n)
    for k in range(int(r.integers(2, 5))):
        at = r.uniform(0, seconds)
        for j in range(int(r.integers(3, 7))):
            S.place(drag, C.tick(9030 + k * 10 + j, 3300, 1300, 0.2), secs(at + j * 0.03), wrap=True)
    return C.check_loop("tension", sing * 0.4 + hiss + creak + drag)


def nibble(seed):
    """A bite: two or three little twitches felt through the rod tip, and a
    dimple on the water."""
    r = np.random.default_rng(seed)
    parts = []
    t0 = 0.02
    for k in range(int(r.integers(2, 4))):
        tw = C.add(C.tick(seed + k, 2400, 800, 0.4), lp(C.burst(0.04, 0.006, seed + 10 + k), 900) * 0.4)
        parts.append((t0, tw, r.uniform(0.5, 1.0)))
        parts.append((t0 + 0.02, plop(seed + 20 + k, 0.5) * 0.15, 1.0))
        t0 += r.uniform(0.12, 0.3)
    return C.mix(t0 + 0.3, parts)


def strike():
    """Striking a bite: a fast rod sweep, the line snapping taut with a
    'thwip', and a swirl at the surface."""
    thwip = C.add(C.modal(0.2, [(1250, 0.05, 0.5), (2600, 0.03, 0.25)], 9101),
                  bp(C.burst(0.03, 0.002, 9102), 1500, 8000) * 0.5)
    return C.mix(1.0, [(0.0, whoosh(0.35, 9100, 600, 4000, 0.5), 1.0), (0.18, thwip, 1.0),
                       (0.25, splash(9103, False) * 0.5, 1.0)])


def line_snap():
    """The line parts: a sharp crack, the rod springing back through the air,
    the slack line whispering down."""
    crack = C.add(hp(C.burst(0.03, 0.001, 9200), 2000) * 1.0, C.modal(0.1, [(3100, 0.02, 0.3)], 9201))
    spring = whoosh(0.4, 9202, 300, 2500, 0.3)
    n = secs(0.8)
    slack = bp(noise(n, 9203), 3000, 9000, 1) * soft_env(n, 0.05, 0.5) * 0.06
    return C.mix(1.5, [(0.0, crack, 1.0), (0.01, spring, 0.9), (0.3, slack, 1.0)])


def landed_flop():
    """A fish landed on the jetty boards: wet slaps on timber, slowing."""
    r = np.random.default_rng(9300)
    parts = []
    t0 = 0.02
    for k in range(5):
        slap = C.add(bp(C.burst(0.08, 0.012, 9310 + k), 400, 6000) * 0.9,
                     C.modal(0.15, [(r.uniform(150, 190), 0.035, 0.7), (r.uniform(420, 480), 0.02, 0.3)], 9320 + k))
        parts.append((t0, slap, 1.0 - k * 0.15))
        t0 += 0.18 + k * 0.08
    return C.room(C.mix(t0 + 0.4, parts), 0.25, 0.1, 4000, 9330)


def bucket_drop():
    """Into the bucket: a plastic thump, water sloshing round."""
    thump = C.add(C.modal(0.3, [(140, 0.06, 0.8), (330, 0.04, 0.4), (870, 0.02, 0.2)], 9400),
                  lp(C.burst(0.1, 0.015, 9401), 500))
    n = secs(1.0)
    t = t_axis(n)
    slosh = bp(noise(n, 9402), 300, 2500, 2) * (0.5 + 0.5 * np.sin(2 * np.pi * 2.2 * t)) * np.exp(-t / 0.35) * 0.4
    return C.room(C.mix(1.3, [(0.0, thump, 1.0), (0.02, slosh, 1.0), (0.05, plop(9403, 1.2) * 0.4, 1.0)]),
                  0.2, 0.08, 4500, 9404)


def esky_lid():
    """The esky lid lifted and dropped: the hinge's plastic creak, ice
    shifting inside, then a hollow, foam-dulled thump and the latch."""
    creak = C.modal(0.2, [(620, 0.05, 0.3), (1450, 0.03, 0.15)], 9900) * 0.4
    r = np.random.default_rng(9901)
    ice = np.zeros(secs(0.5))
    for k in range(10):
        S.place(ice, C.modal(0.05, [(r.uniform(2500, 5000), 0.01, 0.3)], 9910 + k) * r.uniform(0.2, 0.5),
                secs(r.uniform(0, 0.4)))
    thump = C.add(lp(C.burst(0.12, 0.02, 9902), 350) * 1.5,
                  C.modal(0.18, [(160, 0.05, 0.6), (390, 0.03, 0.3)], 9903))
    x = C.mix(1.3, [(0.0, creak, 1.0), (0.15, ice, 1.0), (0.75, thump, 1.0),
                    (0.8, C.plastic_click(9904, 0.5, 1400), 0.6)])
    return C.room(x, 0.15, 0.08, 5000, 9905)


def drag(seed):
    """The drag giving line as a fish starts a run: the clicker ratchets up
    from a few clicks to a fast scream, holds, and slows as the run tires."""
    dur = 1.8
    n = secs(dur)
    t = t_axis(n)
    rate = 18 + 52 * np.clip(t / 0.35, 0, 1) * np.clip((dur - t) / 0.7, 0.35, 1)
    ph = np.cumsum(rate / SR)
    clicks = np.diff(np.floor(ph), prepend=0)
    r = np.random.default_rng(seed)
    clicks *= 0.7 + 0.3 * r.random(n)
    y = S.resonator(clicks, 3300, 7) + 0.6 * S.resonator(clicks, 5200, 9) + 0.3 * S.resonator(clicks, 1400, 4)
    y += bp(noise(n, seed + 1), 2000, 7000, 1) * 0.02 * np.clip(rate / 70, 0, 1)
    return C.room(y * soft_env(n, 0.01, 0.4), 0.1, 0.05, 6000, seed + 2)


def rod_out():
    """Getting the rod and tackle out: the rod bag's soft knock, lures and
    sinkers rattling in a plastic tackle box, a reel bail clicked over."""
    r = np.random.default_rng(9920)
    bag = C.add(lp(C.burst(0.12, 0.02, 9921), 400) * 0.9, C.modal(0.15, [(240, 0.03, 0.3)], 9922))
    rattle = np.zeros(secs(0.6))
    for k in range(14):
        hit = C.modal(0.04, [(r.uniform(1800, 4200), 0.008, 0.4), (r.uniform(5000, 7500), 0.004, 0.2)], 9930 + k)
        S.place(rattle, hit * r.uniform(0.2, 0.6), secs(r.uniform(0, 0.5)))
    box = C.modal(0.1, [(700, 0.02, 0.4), (1600, 0.01, 0.2)], 9923)
    x = C.mix(1.4, [(0.0, bag, 1.0), (0.2, box, 0.6), (0.22, rattle, 1.0),
                    (1.05, C.plastic_click(9924, 0.6, 1800), 0.8)])
    return C.room(x, 0.12, 0.06, 5000, 9925)


def reel_in():
    """A quick wind-in: a few fast handle turns, then the lure knocks up
    against the rod tip."""
    dur = 0.9
    n = secs(dur)
    t = t_axis(n)
    f_handle = 4.0
    gear = sum(a * np.sin(2 * np.pi * f_handle * m * t) for m, a in ((130, 0.12), (260, 0.06), (390, 0.03)))
    y = gear * (0.75 + 0.25 * np.sin(2 * np.pi * f_handle * t))
    for k in range(int(dur * f_handle * 8)):
        S.place(y, C.tick(9000 + k % 7, 4200, 1800, 0.1), secs(k / (f_handle * 8)))
    y = y * soft_env(n, 0.05, 0.12)
    knock = C.add(C.modal(0.08, [(1900, 0.012, 0.5), (4300, 0.006, 0.25)], 9941),
                  bp(C.burst(0.01, 0.001, 9942), 1500, 7000) * 0.4)
    x = C.mix(1.3, [(0.0, y, 1.0), (0.92, knock, 0.8)])
    return C.room(x, 0.1, 0.05, 6000, 9943)


def render_fish():
    enc = dict(norm="peak", **FX_ENC)
    for i in range(3):
        S.save(f"field/cast_{i + 1:02d}", cast(9500 + 10 * i), **enc)
        S.save(f"field/lure_plop_{i + 1:02d}", plop(9600 + i, [0.7, 0.9, 1.1][i]), **enc)
        S.save(f"field/bite_nibble_{i + 1:02d}", nibble(9700 + 10 * i), **enc)
    S.save("field/reel_loop", reel_loop(), **enc)
    S.save("field/line_tension_loop", tension_loop(), **enc)
    S.save("field/strike", strike(), **enc)
    S.save("field/splash_small", splash(9800, False), **enc)
    S.save("field/splash_big", splash(9810, True), **enc)
    S.save("field/line_snap", line_snap(), **enc)
    S.save("field/landed_flop", landed_flop(), **enc)
    S.save("field/bucket_drop", bucket_drop(), **enc)
    S.save("field/esky_lid", esky_lid(), **enc)
    for i in range(2):
        S.save(f"field/drag_{i + 1:02d}", drag(9950 + 10 * i), **enc)
    S.save("field/rod_out", rod_out(), **enc)
    S.save("field/reel_in", reel_in(), **enc)


# --------------------------------------------------------------------------
# The mystery: the wrong night birds' own calls, and M.'s 1979 pages. Quiet
# and plain, never a jump scare: the unease is in what is slightly off.
# --------------------------------------------------------------------------

def tape_hiss(n, seed, level=0.02):
    return bp(noise(n, seed), 2500, 12000, 1) * level + bp(noise(n, seed + 1), 200, 1500, 1) * level * 0.3


def cassette(y, seed):
    """Played back off an old cassette in a nest: band-limited, wow and
    flutter, hiss, and the play button's clunk either end."""
    y = A.tape_warble(bp(y, 250, 5000, 2), seed, wow=0.008, flutter=0.002)
    y = y + tape_hiss(len(y), seed + 1, 0.015 * np.abs(y).max())
    clunk = lambda s: C.add(C.modal(0.06, [(1400, 0.008, 0.4), (3200, 0.004, 0.2)], s),  # noqa: E731
                            lp(C.burst(0.03, 0.004, s + 1), 900) * 0.6)
    return C.mix(len(y) / SR + 1.0, [(0.0, clunk(seed + 2), 0.5), (0.25, y, 1.0), (0.3 + len(y) / SR, clunk(seed + 3), 0.6)])


def wrong_birds():
    """field/bird_wrong_<id>: what the journal's wrong birds sound like."""
    for i in range(2):
        note = frogmouth(7720 + i, count=1, f0=280)[:secs(0.32)]
        y = np.zeros(secs(9.0))
        for k in range(16):
            S.place(y, note, secs(0.2 + 0.5 * k))
        save_bird(f"bird_wrong_frogmouth_{i + 1:02d}", A.distant(S.fade(y, 0.1, 0.05), 0.5, 0, 2 + i, room=2.2).mean(axis=1), 150)
    mag = mono_amb("amb_bird_magpie_01")
    for i, cut_s in enumerate([1.6, 1.1]):
        carol = S.fade(mag[:secs(cut_s)], 0.0, 0.25)
        tune = np.zeros(secs(3.4))
        for j, (at, f) in enumerate(A.INTERVAL_NOTES):
            note = FB.whistle(f * 2 * 2 ** (-30 / 1200), 0.42 if j < 3 else 1.0, 7710 + 10 * i + j, slur=0.08,
                              vib=(0.012, 9.0), harm=0.25, breath=0.04)
            S.place(tune, note, secs(at * 1.1))
        y = C.mix(cut_s + 4.0, [(0.0, carol, 1.0), (cut_s - 0.25, tune, 0.8)])
        save_bird(f"bird_wrong_magpie_{i + 1:02d}", A.distant(A.tape_warble(y, 7715 + i), 0.45, 0, 1, room=2.0).mean(axis=1), 300)
    bb = A.src("boobook1")
    for i, (a, b) in enumerate([(34.7, 38.9), (44.7, 48.2)]):
        y = cassette(A.cut(bb, secs(a), secs(b), 0.05, 0.3), 7730 + 10 * i)
        save_bird(f"bird_wrong_boobook_{i + 1:02d}", A.distant(y, 0.35, 0, 3, room=1.6).mean(axis=1), 150)
    # the ibis grunts the crossing's walk signal: a fast run at exactly the
    # walk ticks' rate, then three at the locator's one-a-second
    for i in range(2):
        r = np.random.default_rng(7740 + i)
        y = np.zeros(secs(5.5))
        grunt = FB.croak(125, 0.06, 7741 + i, formants=((420, 2.0, 1.0), (950, 2.5, 0.6), (2100, 3.5, 0.25)),
                         drop=0.1, rough=0.6, attack=0.003)
        for k in range(int(r.integers(9, 13))):
            S.place(y, grunt, secs(0.1 + k / 7.0))
        for k in range(3):
            S.place(y, grunt * 0.8, secs(2.4 + k * 1.0))
        save_bird(f"bird_wrong_ibis_{i + 1:02d}", A.distant(y, 0.35, 0, 4, room=1.4).mean(axis=1), 120)


def music_box(f, L, seed):
    """One music-box tine: bright, slightly inharmonic, fast decay."""
    n = secs(L)
    t = t_axis(n)
    r = np.random.default_rng(seed)
    y = sum(a * np.sin(2 * np.pi * f * m * (1 + r.normal(0, 0.001)) * t) * np.exp(-t / d)
            for m, a, d in ((1.0, 1.0, 0.9), (2.76, 0.3, 0.25), (5.4, 0.12, 0.08)))
    return S.fade(y, 0.002, 0.1)


def m_page(found=True, yours=False):
    """A page by M.: a dry old page shifting, and the station's falling
    interval on a worn music box, slow and a little flat. Your own page
    plays it rising, the wrong way round, and stops a note short."""
    notes = A.INTERVAL_NOTES if not yours else [(at, f) for at, (_, f) in zip([0.0, 0.5, 1.0], A.INTERVAL_NOTES[::-1])]
    tune = np.zeros(secs(4.5))
    for j, (at, f) in enumerate(notes):
        S.place(tune, music_box(f * 2 * 2 ** (-35 / 1200), 1.6, 7800 + j), secs(0.3 + at * 1.35))
    tune = A.tape_warble(tune, 7810 + yours, wow=0.006, flutter=0.002)
    tune = S.reverb(tune, size_s=2.2, damp_hz=4000, wet=0.35, seed=7811).mean(axis=1)
    page = paper(0.5, 7820 + yours, 140, 0.7)
    x = C.mix(5.0, [(0.0, page, 0.5), (0.2, tune, 1.0)])
    return x + tape_hiss(len(x), 7830, 0.004)


def m_page_open():
    """One of M.'s pages opened: brittle old paper, a dry crackle, and the
    room going a little quieter round it."""
    n = secs(1.6)
    t = t_axis(n)
    crack = paper(0.8, 7840, 500, 0.8)
    swell = bp(noise(n, 7841), 60, 400, 2) * np.sin(np.pi * np.clip(t / 1.6, 0, 1)) * 0.08
    return C.mix(1.6, [(0.0, crack, 1.0), (0.0, swell, 1.0)])


def m_page_room(seconds=24.0):
    """While M.'s page is open (loop): a still room, the faint hiss of old
    tape, a low hum beating slowly against itself, and a clock somewhere
    that ticks almost, but not quite, evenly."""
    n = secs(seconds)
    t = t_axis(n)
    f1 = round(55 * seconds) / seconds
    f2 = round(55.25 * seconds) / seconds
    hum = (np.sin(2 * np.pi * f1 * t) + np.sin(2 * np.pi * f2 * t)) * 0.05
    hiss = S.circ_bp(noise(n, 7850), 2500, 10000, 1) * 0.012 + S.circ_bp(S.brown(n, 7851), 60, 600, 1) * 0.01
    clock = np.zeros(n)
    r = np.random.default_rng(7852)
    k = secs(0.04)
    tk = t_axis(k)
    tick = np.sin(2 * np.pi * 3100 * tk) * np.exp(-tk / 0.004) + 0.4 * np.sin(2 * np.pi * 1250 * tk) * np.exp(-tk / 0.01)
    ticks = int(seconds)
    for i in range(ticks):
        at = i + (0.06 if i % 7 == 3 else 0.0) + r.normal(0, 0.004)  # every seventh comes late
        S.place(clock, tick * (0.5 if i % 2 else 0.4), secs(at) % n, wrap=True)
    clock = S.circ_lp(clock, 5000) * 0.08
    return C.check_loop("m_page_room", hum + hiss + clock)


def render_mystery():
    wrong_birds()
    enc = dict(norm="lufs:-26", **FX_ENC)
    S.save("field/m_page_found", m_page(), **enc)
    S.save("field/m_page_found_yours", m_page(yours=True), **enc)
    S.save("field/m_page_open", m_page_open(), **enc)
    S.save("field/m_page_room", m_page_room(), norm="lufs:-34", **FX_ENC)


def main(argv):
    want = set(argv) or {"birds", "ui", "fish", "mystery"}
    if "birds" in want:
        render_birds()
    if "ui" in want:
        render_ui()
    if "fish" in want:
        render_fish()
    if "mystery" in want:
        render_mystery()


if __name__ == "__main__":
    main(sys.argv[1:])
