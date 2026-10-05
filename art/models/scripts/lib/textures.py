"""Procedural pixel textures (small, nearest filtered, PS1 style)."""
import math
import random

from . import common as C


def value_noise(seed, cells):
    """2D value noise in 0..1 over a unit square with `cells` lattice cells."""
    rnd = random.Random(seed)
    grid = [[rnd.random() for _ in range(cells + 1)] for _ in range(cells + 1)]

    def f(u, v):
        x, y = (u % 1.0) * cells, (v % 1.0) * cells
        i, j = int(x), int(y)
        fx, fy = x - i, y - j
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a = grid[j][i] * (1 - fx) + grid[j][i + 1] * fx
        b = grid[j + 1][i] * (1 - fx) + grid[j + 1][i + 1] * fx
        return a * (1 - fy) + b * fy
    return f


def fbm(seed, cells=4, octaves=3):
    layers = [value_noise(seed + o, cells * 2 ** o) for o in range(octaves)]

    def f(u, v):
        t, amp, norm = 0.0, 1.0, 0.0
        for n in layers:
            t += n(u, v) * amp
            norm += amp
            amp *= 0.5
        return t / norm
    return f


def lerp(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def mul(c, k):
    return tuple(x * k for x in c)


# ------------------------------------------------------------------ plates

FONT = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111",
    "3": "111001111001111", "4": "101101111001001", "5": "111100111001111",
    "6": "111100111101111", "7": "111001010010010", "8": "111101111101111",
    "9": "111101111001111", "A": "010101111101101", "B": "110101110101110",
    "C": "011100100100011", "D": "110101101101110", "E": "111100110100111",
    "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
    "I": "111010010010111", "J": "001001001101010", "K": "101101110101101",
    "L": "100100100100111", "M": "101111111101101", "N": "110101101101101",
    "O": "010101101101010", "P": "110101110100100", "Q": "010101101110011",
    "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
    "U": "101101101101111", "V": "101101101101010", "W": "101101111111101",
    "X": "101101010101101", "Y": "101101010010010", "Z": "111001010100111",
    "-": "000000111000000", " ": "000000000000000", "·": "000000010000000",
}


def plate(text, name="plate", ink=(0.09, 0.16, 0.50), w=64, h=16):
    """WA style: white plate, blue characters, thin state banner line on top."""
    text = text.upper()
    cw = 7  # 3 px glyph doubled + 1 gap
    x0 = (w - cw * len(text)) // 2 + 1

    def px(x, y):
        if x == 0 or x == w - 1 or y == 0 or y == h - 1:
            return (0.55, 0.56, 0.6)
        if y == h - 3 and 14 < x < w - 15 and x % 2 == 0:
            return ink
        gx = (x - x0)
        if 0 <= gx < cw * len(text):
            ch = text[gx // cw]
            lx = (gx % cw) // 2
            ly = (y - 2) // 2
            if lx < 3 and 0 <= ly < 5:
                bits = FONT.get(ch, FONT[" "])
                if bits[(4 - ly) * 3 + lx] == "1":
                    return ink
        return (0.95, 0.95, 0.93)
    return C.make_image(name, w, h, px)


# ------------------------------------------------------------------ paint wear

def worn_paint(name, base, zone, seed=500, w=256, h=128, fade=1.0):
    """Paint for the lofted shell UVs (u along the car, v round the profile).

    zone(u, v) -> (kind, lowness): kind is 'roof', 'bonnet', 'top' or 'side'
    and lowness (0..1) how close to the sills the point is.

    Sun-faded clear coat on the roof and bonnet (chalky blotches), a dull
    bonnet, road grime low down and a few scratches. `fade` 0 gives clean
    paint (used after a respray).
    """
    base = C._hex(base)
    chalk = lerp(base, (0.86, 0.86, 0.85), 0.55)
    dull = mul(base, 0.86)
    grime = lerp(base, (0.25, 0.22, 0.18), 0.35)
    flake = value_noise(seed, 48)
    blot = fbm(seed + 10, 5, 3)
    haze = fbm(seed + 20, 3, 2)
    rnd = random.Random(seed)
    scratches = []
    for _ in range(5):
        scratches.append((rnd.uniform(0.25, 0.85), rnd.uniform(0.25, 0.55), rnd.uniform(0.02, 0.07),
                          rnd.uniform(-0.3, 0.3)))

    def px(x, y):
        u, v = (x + 0.5) / w, (y + 0.5) / h
        kind, low = zone(u, v)
        c = mul(base, 0.97 + flake(u, v) * 0.06)
        if fade <= 0:
            return c
        if kind == "roof":
            b = blot(u * 1.6, v)
            if b > 0.52:
                c = lerp(c, chalk, min(1, (b - 0.52) * 7) * fade)
            else:
                c = lerp(c, dull, 0.3 * fade)
        elif kind == "bonnet":
            c = lerp(c, dull, 0.7 * fade)
            hz = haze(u * 2, v * 2)
            if hz > 0.55:
                c = lerp(c, chalk, min(0.6, (hz - 0.55) * 3) * fade)
        elif kind == "top":
            c = lerp(c, dull, 0.25 * fade)
        if low > 0:
            c = lerp(c, grime, low * 0.8 * fade)
        for su, sv, ln, slope in scratches:
            du = u - su
            if 0 <= du <= ln and abs((v - sv) - du * slope) < 0.002:
                c = lerp(c, (0.72, 0.72, 0.71), 0.12 * fade)
        return c
    return C.make_image(name, w, h, px)


# ------------------------------------------------------------------ fabrics

def fabric(name, color, seed=1, w=32, h=32, wear=None, tape=None, seams=True):
    """Woven seat fabric. wear: list of (u0, v0, u1, v1) scuffed rects;
    tape: list of (u0, v0, u1, v1) gaffer tape strips."""
    color = C._hex(color)
    n = value_noise(seed, 16)
    weave = random.Random(seed)
    jitter = [[weave.uniform(-0.03, 0.03) for _ in range(w)] for _ in range(h)]

    def px(x, y):
        u, v = (x + 0.5) / w, (y + 0.5) / h
        for r in tape or []:
            if r[0] <= u <= r[2] and r[1] <= v <= r[3]:
                band = int((v - r[1]) * h) % 4 == 0
                return (0.05, 0.05, 0.055) if not band else (0.12, 0.12, 0.13)
        k = 0.92 + n(u, v) * 0.1 + jitter[y][x] + (0.03 if (x + y) % 2 else 0)
        c = mul(color, k)
        if seams and (x % 16 == 0):
            c = mul(c, 0.8)
        for r in wear or []:
            if r[0] <= u <= r[2] and r[1] <= v <= r[3]:
                c = lerp(c, (0.12, 0.12, 0.13), 0.55 + 0.4 * n(u * 3, v * 3))
        return c
    return C.make_image(name, w, h, px)


def carpet(name, color="#1e1e1f", seed=3, size=16):
    color = C._hex(color)
    rnd = random.Random(seed)
    return C.make_image(name, size, size, lambda x, y: mul(color, 0.8 + rnd.random() * 0.4))


def honeycomb(name="honeycomb", size=16):
    """Black hex mesh with dark-grey webs, for grilles (tiles)."""
    def px(x, y):
        row = y // 4
        xx = (x + (2 if row % 2 else 0)) % 4
        web = y % 4 == 0 or xx == 0
        return (0.16, 0.16, 0.17) if web else (0.02, 0.02, 0.025)
    return C.make_image(name, size, size, px)


def gauges(name="gauges"):
    """Pop instrument cluster: white speedo ring with a rev ring inside."""
    s = 32

    def px(x, y):
        u, v = (x + 0.5) / s * 2 - 1, (y + 0.5) / s * 2 - 1
        r = math.hypot(u, v)
        a = math.degrees(math.atan2(v, u))
        if r > 0.94:
            return (0.6, 0.6, 0.62)
        if r > 0.70:
            tick = (a % 18) < 5 and not (-130 < a < -50)
            return (0.1, 0.1, 0.1) if tick else (0.9, 0.9, 0.88)
        if r > 0.64:
            return (0.6, 0.6, 0.62)
        if abs(v - u * 0.5) < 0.07 and r < 0.6 and u > -0.05:
            return (0.95, 0.3, 0.05)
        if r > 0.42:
            tick = (a % 30) < 6 and not (-130 < a < -50)
            return (0.9, 0.9, 0.9) if tick else (0.07, 0.07, 0.08)
        return (0.12, 0.18, 0.2)
    return C.make_image(name, s, s, px)
