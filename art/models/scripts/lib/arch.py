"""Architecture helpers: walls with openings, slabs, stairs, roofs, textures.

Everything is built in world coordinates (objects at the origin with
geometry baked), so box-projected UVs tile at a real-world scale and the
pieces can be joined per material at the end.
"""
import math
import random

from . import common as C
from . import textures as TX

# ------------------------------------------------------------------ registry

_BUCKETS = {}   # bucket name -> list of objects, joined at the end


def add(obj, bucket):
    _BUCKETS.setdefault(bucket, []).append(obj)
    return obj


def finish(parent=None):
    """Join every bucket into one object named after it."""
    out = {}
    for name, objs in _BUCKETS.items():
        o = C.join(objs, name)
        if parent is not None:
            o.parent = parent
        out[name] = o
    _BUCKETS.clear()
    return out


def reset():
    _BUCKETS.clear()


# ------------------------------------------------------------------ primitives

def block(lo, hi, material, bucket, uv=1.0):
    o = C.box_minmax("blk", lo, hi, material)
    C.apply_transform(o)
    if uv:
        C.box_uv(o, uv)
    return add(o, bucket)


def wall(axis, at, a0, a1, z0, z1, thick, material, bucket, openings=(), uv=1.0, side=0):
    """A straight wall. axis 'x': runs along X from a0..a1 at y=at.
    axis 'y': runs along Y at x=at. side: 0 centred on `at`, +1 grows to
    +normal, -1 to -normal. openings: (b0, b1, zbot, ztop) along the run."""
    if side == 0:
        t0, t1 = at - thick / 2, at + thick / 2
    elif side > 0:
        t0, t1 = at, at + thick
    else:
        t0, t1 = at - thick, at
    # Split the run into columns at every opening edge; each column is solid
    # except where openings cover it, so stacked openings (a door under a
    # window) never produce overlapping blocks.
    ops = [(max(b0, a0), min(b1, a1), zb, zt) for b0, b1, zb, zt in openings if b1 > a0 and b0 < a1]
    cuts = sorted({a0, a1} | {b for o in ops for b in o[:2]})
    pieces = []
    for c0, c1 in zip(cuts, cuts[1:]):
        if c1 - c0 < 1e-4:
            continue
        holes = sorted((max(zb, z0), min(zt, z1)) for b0, b1, zb, zt in ops
                       if b0 <= c0 + 1e-6 and b1 >= c1 - 1e-6 and zt > z0 and zb < z1)
        z = z0
        for hb, ht in holes:
            if hb > z + 1e-4:
                pieces.append((c0, c1, z, hb))
            z = max(z, ht)
        if z1 > z + 1e-4:
            pieces.append((c0, c1, z, z1))
    objs = []
    for p0, p1, q0, q1 in pieces:
        if axis == "x":
            lo, hi = (p0, t0, q0), (p1, t1, q1)
        else:
            lo, hi = (t0, p0, q0), (t1, p1, q1)
        objs.append(block(lo, hi, material, bucket, uv))
    return objs


def slab(x0, y0, x1, y1, z0, z1, material, bucket, holes=(), uv=1.0):
    """Horizontal slab with rectangular holes (x0, y0, x1, y1) cut by strips."""
    if not holes:
        return [block((x0, y0, z0), (x1, y1, z1), material, bucket, uv)]
    out = []
    hx0, hy0, hx1, hy1 = holes[0]
    rest = holes[1:]
    # four strips around the first hole, recursing for the rest
    for (a0, b0, a1, b1) in ((x0, y0, x1, hy0), (x0, hy1, x1, y1), (x0, hy0, hx0, hy1), (hx1, hy0, x1, hy1)):
        if a1 - a0 > 1e-4 and b1 - b0 > 1e-4:
            sub = [h for h in rest if h[0] < a1 and h[2] > a0 and h[1] < b1 and h[3] > b0]
            out += slab(a0, b0, a1, b1, z0, z1, material, bucket, sub, uv)
    return out


def gable_roof(x0, x1, y0, y1, z_eave, pitch_deg, material, bucket, overhang=0.35, thick=0.12):
    """Ridge along X. Returns ridge height."""
    yc = (y0 + y1) / 2
    half = (y1 - y0) / 2 + overhang
    rise = half * math.tan(math.radians(pitch_deg))
    zr = z_eave + rise
    for s in (-1, 1):
        ye = yc + s * half
        v = [(x0 - 0.05, ye, z_eave), (x1 + 0.05, ye, z_eave), (x1 + 0.05, yc, zr), (x0 - 0.05, yc, zr)]
        v += [(p[0], p[1], p[2] + thick) for p in v]
        f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        o = C.mesh_obj("roof", v, f, material)
        C.box_uv(o, 1.0)
        add(o, bucket)
    return zr


def gable_end(x, y0, y1, z_eave, zr, thick, material, bucket):
    """Triangular wall closing a gable at x."""
    yc = (y0 + y1) / 2
    v = [(x - thick / 2, y0, z_eave), (x - thick / 2, y1, z_eave), (x - thick / 2, yc, zr),
         (x + thick / 2, y0, z_eave), (x + thick / 2, y1, z_eave), (x + thick / 2, yc, zr)]
    f = [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)]
    o = C.mesh_obj("gable", v, f, material)
    C.box_uv(o, 1.0)
    return add(o, bucket)


def hip_roof(x0, x1, y0, y1, z_eave, rise, material, bucket, thick=0.1):
    """Simple hipped roof (pyramid-ish with a short ridge along the long side)."""
    xc, yc = (x0 + x1) / 2, (y0 + y1) / 2
    w, d = x1 - x0, y1 - y0
    if w >= d:
        r0, r1 = (x0 + d / 2, yc), (x1 - d / 2, yc)
    else:
        r0, r1 = (xc, y0 + w / 2), (xc, y1 - w / 2)
    v = [(x0, y0, z_eave), (x1, y0, z_eave), (x1, y1, z_eave), (x0, y1, z_eave),
         (r0[0], r0[1], z_eave + rise), (r1[0], r1[1], z_eave + rise)]
    if w >= d:
        f = [(0, 1, 5, 4), (1, 2, 5), (2, 3, 4, 5), (3, 0, 4), (3, 2, 1, 0)]
    else:
        f = [(0, 1, 4), (1, 2, 5, 4), (2, 3, 5), (3, 0, 4, 5), (3, 2, 1, 0)]
    o = C.mesh_obj("hip", v, f, material)
    C.box_uv(o, 1.0)
    return add(o, bucket)


def stairs_straight(x0, x1, y_bottom, y_top, z0, z1, n_risers, material, bucket, solid_until=None,
                    thick=0.22):
    """Straight flight rising from y_bottom toward y_top (either direction).
    Steps are solid blocks to z0 except where `solid_until` says otherwise:
    a predicate(y_mid) -> bool, False gives a thin floating tread (for storage)."""
    rise = (z1 - z0) / n_risers
    n_treads = n_risers - 1
    run = (y_top - y_bottom) / n_treads
    for i in range(n_treads):
        ya, yb = y_bottom + i * run, y_bottom + (i + 1) * run
        top = z0 + (i + 1) * rise
        lo_y, hi_y = min(ya, yb), max(ya, yb)
        ym = (ya + yb) / 2
        bottom = z0 if (solid_until is None or solid_until(ym)) else top - thick
        block((x0, lo_y, bottom), (x1, hi_y, top), material, bucket, uv=0.5)
    return rise, run


# ------------------------------------------------------------------ textures

def tex_herringbone(name="herringbone", base="#9b4a36", seed=5, size=64):
    """Red clay pavers in herringbone (each paver 2x1 cells of 4 px)."""
    rnd = random.Random(seed)
    base = C._hex(base)
    tones = [TX.mul(base, 0.8 + rnd.random() * 0.35) for _ in range(64)]
    cell = 4

    def px(x, y):
        cx, cy = x // cell, y // cell
        k = (cx + cy) % 4
        # paver index: pairs of cells, alternating horizontal/vertical bands
        if k < 2:
            pid = ((cx - k) * 7 + cy * 13) % 64
            edge = (x % cell == 0 and k == 0) or (y % cell == 0)
        else:
            pid = (cx * 11 + (cy - (k - 2)) * 5) % 64
            edge = (y % cell == 0 and k == 2) or (x % cell == 0)
        if edge:
            return (0.42, 0.36, 0.30)
        return tones[pid]
    return C.make_image(name, size, size, px)


def tex_boards(name, base, w=32, h=64, board_px=4, seed=3, gap=(0.18, 0.08, 0.06), run=2, spread=0.35):
    """Timber strip flooring along V. Each board is cut into `run` lengths
    per random span; `spread` is how far the board tones vary."""
    rnd = random.Random(seed)
    base = C._hex(base)
    cols = w // board_px
    offsets = [rnd.randint(0, h) for _ in range(cols)]
    lens = [rnd.randint(h // 3, h) for _ in range(cols)]
    tones = [[TX.mul(base, 1 - spread * 0.57 + rnd.random() * spread) for _ in range(4)] for _ in range(cols)]
    grain = TX.value_noise(seed + 1, 32)

    def px(x, y):
        c = x // board_px
        if x % board_px == 0:
            return gap
        yy = (y + offsets[c]) % h
        seg = yy // max(lens[c] // run, 1)
        if yy % max(lens[c] // run, 1) == 0:
            return gap
        return TX.mul(tones[c][seg % 4], 0.92 + grain(x / w, y / h * 4) * 0.16)
    return C.make_image(name, w, h, px)


def tex_noise(name, base, amount=0.08, size=16, seed=1):
    rnd = random.Random(seed)
    base = C._hex(base)
    return C.make_image(name, size, size, lambda x, y: TX.mul(base, 1 - amount / 2 + rnd.random() * amount))


def tex_tiles(name, base, grout, tw=4, th=2, size=32, seed=1, jitter=0.06):
    rnd = random.Random(seed)
    base, grout = C._hex(base), C._hex(grout)
    tone = {}

    def px(x, y):
        row = y // th
        xo = (x + (row % 2) * (tw // 2)) if tw > th else x
        if y % th == 0 or xo % tw == 0:
            return grout
        key = (xo // tw, row)
        if key not in tone:
            tone[key] = 1 - jitter / 2 + rnd.random() * jitter
        return TX.mul(base, tone[key])
    return C.make_image(name, size, size, px)


def tex_checker_mosaic(name="mosaic", size=16):
    """Black and white octagon-and-dot floor, simplified to a dot checker."""
    def px(x, y):
        if x % 4 == 0 and y % 4 == 0:
            return (0.05, 0.05, 0.05)
        if (x % 4 in (1, 3) and y % 4 == 0) or (y % 4 in (1, 3) and x % 4 == 0):
            return (0.35, 0.35, 0.35)
        return (0.92, 0.91, 0.88)
    return C.make_image(name, size, size, px)


def tex_granite(name="granite", seed=4, size=32):
    rnd = random.Random(seed)

    def px(x, y):
        r = rnd.random()
        if r < 0.25:
            return (0.12, 0.12, 0.13)
        if r < 0.6:
            return (0.42, 0.42, 0.44)
        return (0.62, 0.61, 0.6)
    return C.make_image(name, size, size, px)


def tex_carpet(name, base, size=16, seed=2):
    return tex_noise(name, base, 0.12, size, seed)


def tex_roof_tiles(name="roof_tiles", base="#5d4a3e", size=32, seed=8):
    rnd = random.Random(seed)
    base = C._hex(base)

    def px(x, y):
        if y % 4 == 0:
            return TX.mul(base, 0.55)
        k = 0.85 + rnd.random() * 0.25
        if (x + (y // 4) * 2) % 6 == 0:
            k *= 0.7
        return TX.mul(base, k)
    return C.make_image(name, size, size, px)


def tex_corrugated(name, base, size=16):
    base = C._hex(base)
    return C.make_image(name, size, size, lambda x, y: TX.mul(base, 0.75 + 0.25 * math.sin(x * math.pi / 2) ** 2))


def tex_rollerdoor(name="rollerdoor", base="#d8cdb4", size=32):
    base = C._hex(base)

    def px(x, y):
        k = 0.8 if y % 3 == 0 else 1.0
        return TX.mul(base, k)
    return C.make_image(name, size, size, px)


def tex_pickets(name="pickets", base="#8a8f96", size=32):
    base = C._hex(base)

    def px(x, y):
        if x % 4 == 3:
            return (0.15, 0.15, 0.13)  # gap shows dark garden behind
        if y > size - 3 and x % 4 == 1:
            return (0.15, 0.15, 0.13)  # pointed tops
        return TX.mul(base, 0.95 + (x % 4) * 0.03)
    return C.make_image(name, size, size, px)
