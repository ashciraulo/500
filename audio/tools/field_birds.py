"""Synthesised calls for the WA birds that have no CC0 recording we can use.

Each function takes a seed and returns a mono call (48 kHz float). They are
built from a few voices that birds really use: clean whistles (syrinx tones
with slurs and vibrato), harsh screeches (noisy, fast-FM bands), rolling
trills (a tone gated 20-60 times a second), coos (low, soft, rounded), and
croaks/quacks (pulse trains through formant resonances). The descriptions
follow field-guide transcriptions of each call. Used by gen_field.py.
"""
from __future__ import annotations

import numpy as np

import sfxlib as S
from sfxlib import SR, bp, secs, t_axis


def glide(f, n):
    return 2 * np.pi * np.cumsum(np.broadcast_to(f, (n,))) / SR


def soft_env(n, attack, release):
    t = t_axis(n)
    L = n / SR
    return np.clip(t / max(attack, 1e-4), 0, 1) ** 2 * np.clip((L - t) / max(release, 1e-4), 0, 1) ** 1.5


def series(parts, tail=0.3):
    """parts = [(start_s, signal, gain)] -> one buffer."""
    end = max(a + len(s) / SR for a, s, _ in parts) + tail
    out = np.zeros(secs(end))
    for a, s, g in parts:
        S.place(out, s * g, secs(a))
    return out


# --------------------------------------------------------------------------
# Voices
# --------------------------------------------------------------------------

def whistle(f0, L, seed, f1=None, slur=0.0, vib=(0.0, 6.0), harm=0.08, breath=0.02, attack=0.015):
    """A clean whistled note gliding f0 -> f1, with a slur into it."""
    r = np.random.default_rng(seed)
    n = secs(L)
    t = t_axis(n)
    f1 = f0 if f1 is None else f1
    f = (f0 + (f1 - f0) * (t / L)) * (1 - slur * np.exp(-t / 0.025)) \
        * (1 + vib[0] * np.sin(2 * np.pi * vib[1] * t + r.uniform(0, 6)))
    ph = glide(f, n)
    y = np.sin(ph) + harm * np.sin(2 * ph) + harm * 0.4 * np.sin(3 * ph)
    y += breath * bp(r.standard_normal(n), 1500, 9000, 1)
    return y * soft_env(n, attack, L * 0.3)


def screech(fc, L, seed, bw=0.35, fm_rate=180, fm_depth=0.25, noise=0.6, rasp=60, drop=0.1, attack=0.01):
    """A harsh screech: a tone with heavy fast FM and amplitude rasp, plus a
    band of noise around it (parrots, cockatoos, gulls, owls)."""
    r = np.random.default_rng(seed)
    n = secs(L)
    t = t_axis(n)
    fm = 1 + fm_depth * np.sin(2 * np.pi * fm_rate * t + r.uniform(0, 6)) + 0.4 * fm_depth * r.standard_normal(n)
    f = fc * (1 + 0.15 * np.exp(-t / 0.04)) * (1 - drop * t / L) * np.clip(fm, 0.3, 2)
    ph = glide(f, n)
    tone = sum(np.sin(h * ph) / h for h in range(1, 6))
    am = 1 + 0.6 * np.sin(2 * np.pi * rasp * t) if rasp else 1
    nz = bp(r.standard_normal(n), fc * (1 - bw), fc * (1 + bw), 2)
    nz /= np.std(nz) + 1e-9
    y = tone * am * (1 - noise) + nz * noise * 0.8
    return y * soft_env(n, attack, L * 0.3)


def trill(f0, L, seed, rate=30, f1=None, duty=0.55, harm=0.1, attack=0.01):
    """A rolling trill: a whistled tone gated rate times a second."""
    n = secs(L)
    t = t_axis(n)
    y = whistle(f0, L, seed, f1, harm=harm, breath=0.01, attack=attack)
    gate = np.clip((np.sin(2 * np.pi * rate * t) - (1 - 2 * duty)) * 3, 0, 1)
    return y * gate


def coo(f0, L, seed, f1=None, breath=0.04):
    """A dove's soft, rounded coo: a low tone with its octave, a gentle
    swell and a breathy edge."""
    r = np.random.default_rng(seed)
    n = secs(L)
    t = t_axis(n)
    f1 = f0 if f1 is None else f1
    f = f0 + (f1 - f0) * np.sin(np.pi * t / L * 0.5)
    ph = glide(f, n)
    y = np.sin(ph) + 0.25 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    y = S.resonator(y, f0 * 2.2, 1.5) * 0.3 + y
    y += breath * bp(r.standard_normal(n), 300, 2000, 1)
    return y * np.sin(np.pi * np.clip(t / L, 0, 1)) ** 1.3


def croak(f0, L, seed, formants=((500, 2.5, 1.0), (1100, 3.0, 0.6), (2400, 4.0, 0.3)),
          drop=0.15, rough=0.5, attack=0.008):
    """A pulse-train croak or quack through formant resonances."""
    r = np.random.default_rng(seed)
    n = secs(L)
    t = t_axis(n)
    f = f0 * (1 + 0.1 * np.exp(-t / 0.03)) * (1 - drop * t / L) * (1 + 0.04 * r.standard_normal(n))
    ph = glide(f, n)
    pulse = (np.sin(ph) > 0.75) * 1.0 + rough * 0.4 * r.standard_normal(n)
    y = sum(a * S.resonator(pulse, fc, q) for fc, q, a in formants)
    return y * soft_env(n, attack, L * 0.35)


# --------------------------------------------------------------------------
# Species
# --------------------------------------------------------------------------

def galah(seed):
    """Galah: a high, shrill, slightly metallic 'chet' or 'chill-chill', in
    twos and threes, often with a soft screech."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(2, 5))):
        L = r.uniform(0.12, 0.22)
        parts.append((at, screech(r.uniform(2600, 3300), L, seed + k, bw=0.25, fm_rate=r.uniform(200, 300),
                                  fm_depth=0.12, noise=0.35, rasp=r.uniform(70, 110)), r.uniform(0.7, 1.0)))
        at += L + r.uniform(0.06, 0.2)
    return series(parts)


def little_corella(seed):
    """Little corella: a loud, harsh, wavering screech, longer than the
    galah's, and the 'flock' variant overlapping several birds."""
    r = np.random.default_rng(seed)
    birds = 1 if seed % 2 == 0 else 4
    parts = []
    for b in range(birds):
        at = r.uniform(0, 0.6) if b else 0.02
        for k in range(int(r.integers(1, 3))):
            L = r.uniform(0.35, 0.65)
            parts.append((at, screech(r.uniform(1900, 2700), L, seed + 10 * b + k, bw=0.45, fm_rate=r.uniform(90, 160),
                                      fm_depth=0.3, noise=0.55, rasp=r.uniform(40, 70), drop=0.2), r.uniform(0.6, 1.0)))
            at += L + r.uniform(0.1, 0.4)
    return series(parts)


def red_wattlebird(seed):
    """Red wattlebird: a harsh, guttural cough, 'chock' or 'kwok', in a
    rasping series, sometimes a throaty 'tobacco-box'."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(2, 5))):
        L = r.uniform(0.08, 0.16)
        y = croak(r.uniform(320, 450), L, seed + k, formants=((1300, 3, 1.0), (2300, 4, 0.7), (3600, 5, 0.3)),
                  drop=0.3, rough=0.9)
        parts.append((at, y, r.uniform(0.7, 1.0)))
        at += L + r.uniform(0.05, 0.18)
    return series(parts)


def new_holland_honeyeater(seed):
    """New Holland honeyeater: a sharp 'chik', then a fast run of thin,
    squeaky 'tsee' notes chattering high up."""
    r = np.random.default_rng(seed)
    parts = [(0.02, whistle(r.uniform(4200, 4800), 0.04, seed, slur=-0.2, harm=0.2), 1.0)]
    at = 0.12
    for k in range(int(r.integers(5, 10))):
        L = r.uniform(0.03, 0.07)
        f0 = r.uniform(5200, 7000)
        parts.append((at, whistle(f0, L, seed + 1 + k, f0 * r.uniform(0.85, 1.1), harm=0.05), r.uniform(0.5, 0.9)))
        at += L + r.uniform(0.02, 0.06)
    return series(parts)


def singing_honeyeater(seed):
    """Singing honeyeater: a loud, rolling, musical 'prrip-prrip', repeated."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(2, 4))):
        L = r.uniform(0.18, 0.28)
        parts.append((at, trill(r.uniform(2600, 3200), L, seed + k, rate=r.uniform(45, 60),
                                f1=r.uniform(3300, 3800)), 1.0))
        at += L + r.uniform(0.12, 0.25)
    return series(parts)


def wagtail_night_song(seed):
    """Willie wagtail's night song, 'sweet pretty creature': quick, sweet,
    clearly whistled notes, sung on moonlit nights."""
    r = np.random.default_rng(seed)
    notes = [(3600, 3900, 0.12), (4300, 4600, 0.1), (3800, 3500, 0.09), (4100, 4600, 0.11), (3300, 3000, 0.16)]
    parts, at = [], 0.02
    for k, (a, b, L) in enumerate(notes):
        parts.append((at, whistle(a * r.uniform(0.97, 1.03), L, seed + k, b, slur=0.05, harm=0.05), 1.0))
        at += L + 0.035
    return series(parts)


def australian_ringneck(seed):
    """Australian ringneck ('twenty-eight'): three ringing, metallic notes,
    'twen-ty-eight', the last longest."""
    r = np.random.default_rng(seed)
    base = r.uniform(2600, 3000)
    notes = [(base * 1.1, base * 1.25, 0.12), (base * 0.95, base * 1.0, 0.08), (base * 1.2, base * 0.9, 0.22)]
    parts, at = [], 0.02
    for k, (a, b, L) in enumerate(notes):
        y = whistle(a, L, seed + k, b, harm=0.35, vib=(0.02, 40), attack=0.006)
        parts.append((at, y, 1.0))
        at += L + 0.05
    return series(parts)


def grey_butcherbird(seed):
    """Grey butcherbird: rich, fluting, melodious piping, a short phrase of
    clear notes with jumps, among the finest songs in Perth gardens."""
    r = np.random.default_rng(seed)
    scale = [1046.5, 1174.7, 1318.5, 1568.0, 1760.0, 2093.0]
    parts, at = [], 0.02
    for k in range(int(r.integers(4, 7))):
        f = scale[int(r.integers(0, len(scale)))] * r.uniform(0.98, 1.02)
        L = r.uniform(0.12, 0.3)
        parts.append((at, whistle(f, L, seed + k, f * r.uniform(0.95, 1.08), slur=0.04, vib=(0.004, 6),
                                  harm=0.15, breath=0.01), r.uniform(0.7, 1.0)))
        at += L + r.uniform(0.03, 0.12)
    return S.reverb(series(parts), size_s=0.8, damp_hz=5000, wet=0.15, seed=seed).mean(axis=1)


def laughing_dove(seed):
    """Laughing dove: a soft, bubbling, laughing coo, five to seven notes
    rising then falling."""
    r = np.random.default_rng(seed)
    count = int(r.integers(5, 8))
    parts, at = [], 0.02
    for k in range(count):
        f = 430 + 80 * np.sin(np.pi * k / (count - 1))
        L = 0.11 if k < count - 1 else 0.2
        parts.append((at, coo(f, L, seed + k, f * 0.97), 1.0))
        at += L + 0.03
    return series(parts)


def spotted_dove(seed):
    """Spotted dove: 'coo, crrr-coo': a mellow coo, a rolled middle note,
    a falling end."""
    r = np.random.default_rng(seed)
    f = r.uniform(420, 480)
    mid = coo(f * 1.05, 0.3, seed + 1) * (0.6 + 0.4 * np.sin(2 * np.pi * 28 * t_axis(secs(0.3))))
    return series([(0.02, coo(f, 0.35, seed), 1.0), (0.5, mid, 0.9), (0.9, coo(f * 1.02, 0.45, seed + 2, f * 0.88), 1.0)])


def crested_tern(seed):
    """Crested tern: a harsh, grating 'kirrick' or 'kree-kree' over the water."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(1, 4))):
        L = r.uniform(0.25, 0.4)
        parts.append((at, screech(r.uniform(2300, 2800), L, seed + k, bw=0.3, fm_rate=r.uniform(120, 200),
                                  fm_depth=0.15, noise=0.4, rasp=r.uniform(90, 140), drop=0.25), 1.0))
        at += L + r.uniform(0.15, 0.4)
    return series(parts)


def pied_oystercatcher(seed):
    """Pied oystercatcher: loud, clear, piping 'peep-peep' or 'kleep',
    quick and urgent along the shore."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(3, 7))):
        L = r.uniform(0.09, 0.14)
        f = r.uniform(2900, 3300)
        parts.append((at, whistle(f, L, seed + k, f * 0.82, slur=0.12, harm=0.25, attack=0.005), 1.0))
        at += L + r.uniform(0.06, 0.12)
    return series(parts)


def pacific_black_duck(seed):
    """Pacific black duck: the female's loud quacks, descending, nasal."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(3, 6))):
        L = r.uniform(0.16, 0.24)
        f0 = 520 * (1 - 0.06 * k) * r.uniform(0.95, 1.05)
        parts.append((at, croak(f0, L, seed + k, formants=((900, 3, 1.0), (1500, 4, 0.7), (2700, 5, 0.4)),
                                drop=0.2, rough=0.3), 1.0 - 0.12 * k))
        at += L + r.uniform(0.07, 0.14)
    return series(parts)


def purple_swamphen(seed):
    """Purple swamphen: a loud, harsh, nasal screeching 'kee-ow' in the reeds."""
    r = np.random.default_rng(seed)
    L = r.uniform(0.5, 0.75)
    n = secs(L)
    t = t_axis(n)
    fc = r.uniform(1300, 1600) * (1 + 0.35 * np.sin(np.pi * t / L))
    ph = glide(fc, n)
    tone = sum(np.sin(h * ph) / h ** 0.8 for h in range(1, 8))
    y = S.resonator(tone, 2200, 2.5) + 0.5 * tone + 0.3 * bp(r.standard_normal(n), 1000, 4000, 1)
    y *= (1 + 0.4 * np.sin(2 * np.pi * 55 * t)) * soft_env(n, 0.02, L * 0.4)
    if seed % 2:
        return series([(0.02, y, 1.0), (L + 0.25, y[::1] * 0.8, 1.0)])
    return series([(0.02, y, 1.0)])


def eurasian_coot(seed):
    """Eurasian coot: a short, sharp, nasal 'kowk' or 'pitt'."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(1, 4))):
        L = r.uniform(0.07, 0.12)
        parts.append((at, croak(r.uniform(700, 900), L, seed + k, formants=((1100, 4, 1.0), (2200, 5, 0.6)),
                                drop=0.1, rough=0.2, attack=0.004), 1.0))
        at += L + r.uniform(0.3, 0.7)
    return series(parts)


def osprey(seed):
    """Eastern osprey: a run of high, plaintive whistled 'cheep-cheep-cheep',
    falling slightly."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    count = int(r.integers(4, 8))
    for k in range(count):
        L = r.uniform(0.12, 0.17)
        f = r.uniform(2700, 3000) * (1 - 0.03 * k)
        parts.append((at, whistle(f, L, seed + k, f * 1.08, slur=0.1, harm=0.2), 1.0))
        at += L + r.uniform(0.07, 0.12)
    return S.reverb(series(parts), size_s=1.2, damp_hz=4500, wet=0.2, seed=seed).mean(axis=1)


def nankeen_kestrel(seed):
    """Nankeen kestrel: a shrill, rapid 'kee-kee-kee-kee'."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(5, 10))):
        L = 0.07
        f = r.uniform(3400, 3800)
        parts.append((at, screech(f, L, seed + k, bw=0.15, fm_rate=300, fm_depth=0.05, noise=0.2, rasp=0,
                                  drop=0.1, attack=0.004), 1.0))
        at += L + 0.045
    return series(parts)


def eastern_barn_owl(seed):
    """Eastern barn owl: a long, hissing, rasping screech in the dark."""
    r = np.random.default_rng(seed)
    L = r.uniform(0.9, 1.4)
    y = screech(r.uniform(3000, 3800), L, seed, bw=0.6, fm_rate=r.uniform(30, 50), fm_depth=0.08,
                noise=0.85, rasp=r.uniform(25, 40), drop=0.15, attack=0.05)
    return S.reverb(series([(0.02, y, 1.0)]), size_s=1.5, damp_hz=4000, wet=0.25, seed=seed).mean(axis=1)


def nankeen_night_heron(seed):
    """Nankeen night heron: a deep, harsh croak, 'kwok', flying over at dusk."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(1, 3))):
        L = r.uniform(0.18, 0.26)
        parts.append((at, croak(r.uniform(180, 240), L, seed + k, formants=((650, 2.5, 1.0), (1300, 3, 0.7),
                                                                           (2500, 4, 0.3)), drop=0.25, rough=0.8), 1.0))
        at += L + r.uniform(0.5, 1.0)
    return S.reverb(series(parts), size_s=1.4, damp_hz=3500, wet=0.25, seed=seed).mean(axis=1)


def rainbow_bee_eater(seed):
    """Rainbow bee-eater: a rolling, liquid 'prrp-prrp' from high in the air."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(3, 6))):
        L = r.uniform(0.1, 0.16)
        parts.append((at, trill(r.uniform(3300, 3700), L, seed + k, rate=r.uniform(55, 70),
                                f1=r.uniform(3000, 3400), duty=0.6), 1.0))
        at += L + r.uniform(0.1, 0.3)
    return series(parts)


def splendid_fairywren(seed):
    """Splendid fairy-wren: a high, fast, reeling trill that runs down the
    scale, thin and bright."""
    r = np.random.default_rng(seed)
    L = r.uniform(1.0, 1.6)
    n = secs(L)
    count = int(L * r.uniform(18, 24))
    out = np.zeros(n + secs(0.2))
    for k in range(count):
        f = 7000 - 1600 * k / count + r.uniform(-150, 150)
        S.place(out, whistle(f, 0.03, seed + k, f * 0.9, harm=0.04, attack=0.003), secs(k * L / count))
    return out * (0.6 + 0.4 * np.linspace(1, 0.5, len(out)))


def welcome_swallow(seed):
    """Welcome swallow: a quick, cheerful twitter of chirps."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(8, 15))):
        L = r.uniform(0.03, 0.08)
        f = r.uniform(3000, 6000)
        parts.append((at, whistle(f, L, seed + k, f * r.uniform(0.7, 1.3), harm=0.15, attack=0.004),
                      r.uniform(0.5, 1.0)))
        at += L + r.uniform(0.02, 0.09)
    return series(parts)


def australian_white_ibis(seed):
    """Australian white ibis: mostly quiet; a hoarse, grunting honk or two,
    low and nasal, while it probes the park lawns."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(1, 4))):
        L = r.uniform(0.2, 0.35)
        parts.append((at, croak(r.uniform(110, 150), L, seed + k, formants=((420, 2.0, 1.0), (950, 2.5, 0.6),
                                                                           (2100, 3.5, 0.25)), drop=0.2, rough=0.9), 1.0))
        at += L + r.uniform(0.25, 0.6)
    return series(parts)


def white_faced_heron(seed):
    """White-faced heron: a single gravelly, guttural 'graak' as it lifts off."""
    r = np.random.default_rng(seed)
    L = r.uniform(0.35, 0.5)
    y = croak(r.uniform(150, 190), L, seed, formants=((700, 2.5, 1.0), (1500, 3, 0.6), (2800, 4, 0.3)),
              drop=0.3, rough=1.0)
    return S.reverb(series([(0.02, y, 1.0)]), size_s=1.0, damp_hz=4000, wet=0.15, seed=seed).mean(axis=1)


def rock_dove(seed):
    """Rock dove (feral pigeon): a throaty, rolling 'oo-roo-coo', two or
    three phrases, with a burr in the middle."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(2, 4))):
        f0 = r.uniform(300, 340)
        a = coo(f0, 0.18, seed + 10 * k, f0 * 1.08)
        b = coo(f0 * 1.05, 0.35, seed + 10 * k + 1, f0 * 0.9)
        n = len(b)
        b = b * (0.6 + 0.4 * np.sin(2 * np.pi * 28 * t_axis(n)))  # the burr
        c = coo(f0 * 0.95, 0.4, seed + 10 * k + 2, f0 * 0.82)
        parts += [(at, a, 0.8), (at + 0.2, b, 1.0), (at + 0.58, c, 0.9)]
        at += 1.1 + r.uniform(0.1, 0.4)
    return series(parts)


def little_pied_cormorant(seed):
    """Little pied cormorant: near silent away from the colony; a few soft,
    low, guttural 'uk-uk' croaks."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(2, 5))):
        L = r.uniform(0.07, 0.12)
        parts.append((at, croak(r.uniform(95, 125), L, seed + k, formants=((380, 2, 1.0), (820, 2.5, 0.5),
                                                                          (1800, 3, 0.2)), drop=0.2, rough=0.7),
                      r.uniform(0.6, 0.9)))
        at += L + r.uniform(0.1, 0.25)
    return series(parts)


def australasian_darter(seed):
    """Australasian darter: mostly silent; a dry, clicking, rattling
    'kah-kah-kah' chatter, faster towards the end."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    count = int(r.integers(6, 11))
    for k in range(count):
        L = r.uniform(0.04, 0.06)
        parts.append((at, croak(r.uniform(160, 200), L, seed + k, formants=((900, 3, 1.0), (2000, 4, 0.6),
                                                                           (3500, 5, 0.3)), drop=0.1, rough=1.0,
                            attack=0.002), r.uniform(0.6, 1.0)))
        at += L + 0.12 * (1 - 0.5 * k / count) + r.uniform(0, 0.02)
    return series(parts)


def great_egret(seed):
    """Great egret: a loud, harsh, low 'kraak', the croak of a big heron
    disturbed off the shallows."""
    r = np.random.default_rng(seed)
    parts, at = [], 0.02
    for k in range(int(r.integers(1, 3))):
        L = r.uniform(0.3, 0.5)
        parts.append((at, croak(r.uniform(120, 150), L, seed + k, formants=((600, 2, 1.0), (1250, 2.5, 0.7),
                                                                           (2600, 3.5, 0.35)), drop=0.25, rough=1.2),
                      1.0))
        at += L + r.uniform(0.4, 0.8)
    return S.reverb(series(parts), size_s=1.1, damp_hz=4000, wet=0.15, seed=seed).mean(axis=1)


def musk_duck(seed):
    """Musk duck, the male's display: kicking back with both feet for a loud
    'plonk' of water, then a shrill whistle and a deep grunt."""
    r = np.random.default_rng(seed)
    n = secs(0.35)
    t = t_axis(n)
    f = 170 * np.exp(-t / 0.25) + 90
    plonk = np.sin(glide(f, n)) * np.exp(-t / 0.08)
    splash = bp(r.standard_normal(n), 800, 6000, 1) * np.exp(-t / 0.05) * 0.4
    whistle_ = whistle(r.uniform(2300, 2700), 0.3, seed + 1, r.uniform(1900, 2200), slur=0.1, harm=0.15)
    grunt = croak(r.uniform(85, 105), 0.25, seed + 2, formants=((350, 2, 1.0), (750, 2.5, 0.5), (1600, 3, 0.2)),
                  rough=0.8)
    return series([(0.02, plonk + splash, 1.0), (0.32, whistle_, 0.6), (0.7, grunt, 0.7)])


SPECIES = {
    "australian_white_ibis": australian_white_ibis, "white_faced_heron": white_faced_heron,
    "galah": galah, "little_corella": little_corella, "red_wattlebird": red_wattlebird,
    "new_holland_honeyeater": new_holland_honeyeater, "singing_honeyeater": singing_honeyeater,
    "australian_ringneck": australian_ringneck, "grey_butcherbird": grey_butcherbird,
    "laughing_dove": laughing_dove, "spotted_dove": spotted_dove, "crested_tern": crested_tern,
    "pied_oystercatcher": pied_oystercatcher, "pacific_black_duck": pacific_black_duck,
    "purple_swamphen": purple_swamphen, "eurasian_coot": eurasian_coot, "osprey": osprey,
    "nankeen_kestrel": nankeen_kestrel, "eastern_barn_owl": eastern_barn_owl,
    "nankeen_night_heron": nankeen_night_heron, "rainbow_bee_eater": rainbow_bee_eater,
    "splendid_fairywren": splendid_fairywren, "welcome_swallow": welcome_swallow,
    "rock_dove": rock_dove, "little_pied_cormorant": little_pied_cormorant,
    "australasian_darter": australasian_darter, "great_egret": great_egret, "musk_duck": musk_duck,
}
