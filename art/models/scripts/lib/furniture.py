"""Low-poly furniture, fittings and plants for interiors.

Every function builds in world space at the given position and returns a
list of objects (or one object). `rot` is a rotation about Z in degrees
applied around the item's own origin; items are authored facing -Y
(their front toward -Y) before rotation.
"""
import math
import random

from mathutils import Matrix, Vector

from . import common as C
from . import textures as TX

# ------------------------------------------------------------------ materials


def M(name):
    """Shared furniture palette (warm, lived-in)."""
    pal = {
        "wood_dark": ("#5a3a26", 0.7), "wood_mid": ("#8a5e3c", 0.7), "wood_light": ("#c09a6b", 0.7),
        "oak": ("#a77d50", 0.7), "white": ("#efece4", 0.6), "cream": ("#e7dcc4", 0.8),
        "sofa": ("#7a8a6a", 0.95), "sofa_dark": ("#5f6d52", 0.95), "rust": ("#a5532e", 0.95),
        "mustard": ("#c8952e", 0.95), "teal": ("#2f6f6c", 0.9), "terracotta": ("#b8643e", 0.85),
        "pot_white": ("#e9e4da", 0.5), "pot_dark": ("#2e2c2a", 0.6), "black": ("#141414", 0.6),
        "metal": ("#9a9a9a", 0.4), "brass": ("#b8913f", 0.35), "steel": ("#c4c6c8", 0.3),
        "linen": ("#ece6d8", 0.95), "duvet": ("#d9cdb5", 0.95), "throw": ("#8c4a3c", 0.95),
        "pillow": ("#f2eee6", 0.95), "leaf": ("#3f6b35", 0.8), "leaf_light": ("#5e8a3e", 0.8),
        "leaf_dark": ("#2c4f2a", 0.8), "soil": ("#3a2a1e", 1.0), "rug_red": ("#8e3b2e", 1.0),
        "rug_blue": ("#3c4f6e", 1.0), "rug_cream": ("#d8ccb2", 1.0), "paper": ("#f4f0e2", 0.9),
        "cork": ("#b98c5a", 1.0), "red_string": ("#c0141a", 0.8), "screen": ("#1d2a33", 0.3),
        "vinyl": ("#0d0d0d", 0.3), "porcelain": ("#f4f4f2", 0.25), "chrome": ("#d6d8da", 0.15),
        "fridge": ("#e6e6e2", 0.4), "lampshade": ("#f1dfb8", 0.9), "towel": ("#c9b79c", 1.0),
        "book1": ("#7a2f2a", 0.9), "book2": ("#2f4a6a", 0.9), "book3": ("#c9a650", 0.9),
        "book4": ("#3e5e3a", 0.9), "book5": ("#d8d0bd", 0.9), "cat_food": ("#c77d3a", 0.8),
        "box": ("#a88458", 0.95), "cloth": ("#bdb6a6", 1.0), "frame": ("#2b2622", 0.6),
        "curtain": ("#efe6d2", 1.0), "blind": ("#ecebe6", 0.8),
    }
    col, rough = pal[name]
    metal = 0.8 if name in ("metal", "brass", "steel", "chrome") else 0.0
    return C.mat("F_" + name, col, rough=rough, metal=metal)


def emissive(name, color, strength):
    return C.mat(name, color, rough=0.9, emit=color, emit_strength=strength)


# ------------------------------------------------------------------ placement

def _place(objs, pos, rot):
    m = Matrix.Translation(Vector(pos)) @ Matrix.Rotation(math.radians(rot), 4, "Z")
    for o in objs:
        o.data.transform(m @ o.matrix_basis)
        o.matrix_basis = Matrix.Identity(4)
    return objs


def bx(lo, hi, mat):
    return C.box_minmax("f", lo, hi, mat)


def cyl(r, h, loc, mat, segs=8, r_top=None, axis="Z"):
    return C.cylinder("f", r, h, segs=segs, axis=axis, loc=loc, material=mat, r_top=r_top)


def item(name, parts, pos, rot=0, parent=None):
    """Bake parts into one named object at pos/rot."""
    objs = []
    for p in parts:
        C.apply_transform(p)
        objs.append(p)
    _place(objs, pos, rot)
    o = C.join(objs, name)
    if parent is not None:
        o.parent = parent
    return o


# ------------------------------------------------------------------ living

def sofa(color="sofa", w=2.0, d=0.9):
    c = M(color)
    parts = [
        bx((-w / 2, -d / 2, 0.08), (w / 2, d / 2, 0.42), c),
        bx((-w / 2, d / 2 - 0.22, 0.42), (w / 2, d / 2, 0.85), c),
        bx((-w / 2, -d / 2, 0.42), (-w / 2 + 0.18, d / 2, 0.62), c),
        bx((w / 2 - 0.18, -d / 2, 0.42), (w / 2, d / 2, 0.62), c),
    ]
    # seat cushions and legs
    n = 3 if w > 1.6 else 2
    cw = (w - 0.36) / n
    for i in range(n):
        x0 = -w / 2 + 0.18 + i * cw
        parts.append(bx((x0 + 0.01, -d / 2 + 0.02, 0.42), (x0 + cw - 0.01, d / 2 - 0.22, 0.52), c))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(bx((sx * (w / 2 - 0.08) - 0.03, sy * (d / 2 - 0.08) - 0.03, 0),
                            (sx * (w / 2 - 0.08) + 0.03, sy * (d / 2 - 0.08) + 0.03, 0.08), M("wood_dark")))
    # cushions and a throw
    parts.append(_cushion((-w / 2 + 0.38, d / 2 - 0.3, 0.68), M("mustard")))
    parts.append(_cushion((w / 2 - 0.38, d / 2 - 0.3, 0.68), M("rust")))
    throw = bx((w / 2 - 0.55, -d / 2 - 0.01, 0.2), (w / 2 - 0.15, d / 2 - 0.2, 0.53), M("throw"))
    parts.append(throw)
    return parts


def sectional(long=4.0, short=2.0, d=0.92, color="sofa"):
    """L-shaped couch. The corner sits at the origin: the long run goes +Y
    with its back on the +X side, the short run goes -X with its back on the
    -Y side, so both face into the -X/+Y quarter."""
    c = M(color)
    b = 0.22
    parts = [bx((-d, 0, 0.08), (0, long, 0.42), c), bx((-short, 0, 0.08), (-d, d, 0.42), c),
             bx((-b, 0, 0.42), (0, long, 0.85), c), bx((-short, 0, 0.42), (-b, b, 0.85), c),
             bx((-d, long - 0.18, 0.42), (-b, long, 0.62), c), bx((-short, b, 0.42), (-short + 0.18, d, 0.62), c)]
    # seat cushions: the long run includes the corner seat
    run = long - 0.18 - b
    n = max(2, int(round(run / 0.8)))
    for i in range(n):
        y0 = b + i * run / n
        parts.append(bx((-d + 0.02, y0 + 0.01, 0.42), (-b - 0.01, y0 + run / n - 0.01, 0.52), c))
    run = short - 0.18 - d
    n = max(1, int(round(run / 0.8)))
    for i in range(n):
        x0 = -short + 0.18 + i * run / n
        parts.append(bx((x0 + 0.01, b + 0.01, 0.42), (x0 + run / n - 0.01, d - 0.02, 0.52), c))
    # back cushions leaning on the backs
    for y, col in ((0.75, "rust"), (long * 0.5, "mustard"), (long - 0.6, "cream")):
        parts.append(bx((-b - 0.13, y - 0.21, 0.5), (-b - 0.01, y + 0.21, 0.82), M(col)))
    parts.append(bx((-short + 0.4, b + 0.01, 0.5), (-short + 0.82, b + 0.13, 0.82), M("teal")))
    parts.append(bx((-d - 0.01, long - 0.75, 0.2), (-b - 0.05, long - 0.3, 0.53), M("throw")))
    for x, y in ((-0.08, 0.08), (-0.08, long - 0.08), (-d + 0.08, long - 0.08), (-short + 0.08, 0.08),
                 (-short + 0.08, d - 0.08), (-d + 0.08, d - 0.08)):
        parts.append(bx((x - 0.03, y - 0.03, 0), (x + 0.03, y + 0.03, 0.08), M("wood_dark")))
    return parts


def _cushion(pos, mat):
    o = bx((-0.2, -0.07, -0.18), (0.2, 0.07, 0.18), mat)
    o.rotation_euler = (math.radians(-12), 0, 0)
    o.location = pos
    return o


def armchair(color="rust"):
    c = M(color)
    parts = [
        bx((-0.42, -0.42, 0.12), (0.42, 0.42, 0.42), c),
        bx((-0.42, 0.22, 0.42), (0.42, 0.42, 0.95), c),
        bx((-0.42, -0.42, 0.42), (-0.30, 0.42, 0.65), c),
        bx((0.30, -0.42, 0.42), (0.42, 0.42, 0.65), c),
        bx((-0.29, -0.40, 0.42), (0.29, 0.21, 0.50), c),
    ]
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(cyl(0.025, 0.12, (sx * 0.34, sy * 0.34, 0.06), M("wood_mid"), 5, r_top=0.02))
    parts.append(_cushion((0, 0.12, 0.65), M("cream")))
    return parts


def coffee_table(w=1.0, d=0.55):
    parts = [bx((-w / 2, -d / 2, 0.38), (w / 2, d / 2, 0.42), M("oak")),
             bx((-w / 2 + 0.05, -d / 2 + 0.05, 0.12), (w / 2 - 0.05, d / 2 - 0.05, 0.14), M("oak"))]
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(bx((sx * (w / 2 - 0.05) - 0.025, sy * (d / 2 - 0.05) - 0.025, 0),
                            (sx * (w / 2 - 0.05) + 0.025, sy * (d / 2 - 0.05) + 0.025, 0.38), M("oak")))
    # a mug, a stack of books, a candle
    parts.append(cyl(0.04, 0.09, (0.25, -0.05, 0.465), M("terracotta"), 8))
    parts += [bx((-0.35, -0.12, 0.42), (-0.12, 0.08, 0.45), M("book2")),
              bx((-0.33, -0.10, 0.45), (-0.14, 0.06, 0.48), M("book3"))]
    parts.append(cyl(0.03, 0.08, (0.05, 0.12, 0.46), M("cream"), 6))
    return parts


def rug(w, d, color="rug_red", border="rug_cream"):
    return [bx((-w / 2, -d / 2, 0.0), (w / 2, d / 2, 0.01), M(border)),
            bx((-w / 2 + 0.12, -d / 2 + 0.12, 0.01), (w / 2 - 0.12, d / 2 - 0.12, 0.015), M(color))]


def bookshelf(w=0.9, h=1.9, d=0.32, seed=1):
    rnd = random.Random(seed)
    wood = M("wood_mid")
    parts = [bx((-w / 2, -d / 2, 0), (-w / 2 + 0.03, d / 2, h), wood),
             bx((w / 2 - 0.03, -d / 2, 0), (w / 2, d / 2, h), wood),
             bx((-w / 2, d / 2 - 0.02, 0), (w / 2, d / 2, h), wood)]
    shelves = 5
    for i in range(shelves + 1):
        z = i * (h - 0.03) / shelves
        parts.append(bx((-w / 2, -d / 2, z), (w / 2, d / 2, z + 0.03), wood))
        if i < shelves:
            x = -w / 2 + 0.04
            while x < w / 2 - 0.08:
                bw = rnd.uniform(0.025, 0.05)
                bh = rnd.uniform(0.18, 0.3)
                if rnd.random() < 0.12:
                    # a little plant or ornament instead of books
                    parts.append(cyl(0.04, 0.07, (x + 0.05, 0, z + 0.065), M("pot_white"), 6))
                    parts.append(C.sphere("f", 0.06, (x + 0.05, 0, z + 0.14), M("leaf"), segs=6, rings=3))
                    x += 0.12
                    continue
                parts.append(bx((x, -d / 2 + 0.04, z + 0.03), (x + bw, d / 2 - 0.04, z + 0.03 + bh),
                                M("book%d" % rnd.randint(1, 5))))
                x += bw + 0.003
    return parts


def floor_lamp():
    return [cyl(0.15, 0.03, (0, 0, 0.015), M("brass"), 10),
            cyl(0.012, 1.45, (0, 0, 0.75), M("brass"), 5),
            cyl(0.2, 0.28, (0, 0, 1.52), emissive("Lampshade_Glow", "#f6d9a0", 1.5), 10, r_top=0.13)]


def table_lamp():
    return [cyl(0.07, 0.22, (0, 0, 0.11), M("terracotta"), 8, r_top=0.05),
            cyl(0.13, 0.18, (0, 0, 0.31), emissive("Lampshade_Glow", "#f6d9a0", 1.5), 10, r_top=0.09)]


def record_player_unit():
    """Low sideboard with a turntable on top and a crate of records beside it."""
    wood = M("wood_dark")
    parts = [bx((-0.5, -0.2, 0.1), (0.5, 0.2, 0.55), wood)]
    for sx in (-1, 1):
        parts.append(bx((sx * 0.45 - 0.02, -0.15, 0), (sx * 0.45 + 0.02, 0.15, 0.1), wood))
    parts.append(bx((-0.22, -0.17, 0.55), (0.22, 0.17, 0.63), M("wood_light")))
    parts.append(cyl(0.15, 0.015, (-0.03, 0, 0.64), M("vinyl"), 14))
    parts.append(cyl(0.03, 0.02, (-0.03, 0, 0.65), M("rust"), 6))
    arm = bx((0.10, -0.01, 0.645), (0.18, 0.01, 0.66), M("steel"))
    parts.append(arm)
    # sleeves leaning in the cabinet front
    rnd = random.Random(4)
    for i in range(8):
        col = ["book1", "book2", "book3", "mustard", "teal", "rust", "cream", "book4"][i]
        parts.append(bx((-0.45 + i * 0.012, -0.18, 0.12), (-0.44 + i * 0.012, 0.13, 0.43), M(col)))
    return parts


def record_crate():
    wood = M("wood_light")
    parts = [bx((-0.18, -0.18, 0), (0.18, 0.18, 0.02), wood)]
    for a, b in (((-0.18, -0.18), (0.18, -0.16)), ((-0.18, 0.16), (0.18, 0.18)),
                 ((-0.18, -0.18), (-0.16, 0.18)), ((0.16, -0.18), (0.18, 0.18))):
        parts.append(bx((a[0], a[1], 0), (b[0], b[1], 0.3), wood))
    for i in range(14):
        col = ["book1", "book2", "book3", "mustard", "teal", "rust", "cream", "book4"][i % 8]
        parts.append(bx((-0.15, -0.15 + i * 0.022, 0.02), (0.15, -0.14 + i * 0.022, 0.33), M(col)))
    return parts


def tv_unit(w=1.2):
    parts = [bx((-w / 2, -0.2, 0.08), (w / 2, 0.2, 0.45), M("oak"))]
    for sx in (-1, 1):
        parts.append(bx((sx * (w / 2 - 0.05) - 0.02, -0.15, 0), (sx * (w / 2 - 0.05) + 0.02, 0.15, 0.08), M("wood_dark")))
    # two drawer fronts and a gap for the console
    for x0 in (-w / 2 + 0.04, w / 6):
        parts.append(bx((x0, -0.205, 0.12), (x0 + w / 3 - 0.08, -0.2, 0.41), M("wood_light")))
    return parts


def tv(diag_in=65):
    """Wall-mounted 16:9 flat screen, back on the wall, facing -Y."""
    d = diag_in * 0.0254
    w, h = d * 16 / math.hypot(16, 9), d * 9 / math.hypot(16, 9)
    return [bx((-w / 2 - 0.01, -0.045, 0), (w / 2 + 0.01, 0, h + 0.02), M("black")),
            bx((-w / 2 + 0.005, -0.05, 0.015), (w / 2 - 0.005, -0.045, h + 0.005), M("screen"))]


# ------------------------------------------------------------------ plants

def plant(kind="monstera", seed=0, scale=1.0):
    """Potted plants, all low poly. kinds: monstera, fiddle, snake, pothos,
    fern, palm, succulent, herb."""
    rnd = random.Random(seed)
    pot_col = rnd.choice(["terracotta", "pot_white", "pot_dark", "teal"])
    parts = []
    if kind == "succulent":
        parts.append(cyl(0.06, 0.08, (0, 0, 0.04), M(pot_col), 8, r_top=0.07))
        for i in range(5):
            a = i * 2 * math.pi / 5
            leaf = C.sphere("f", 0.035, (math.cos(a) * 0.03, math.sin(a) * 0.03, 0.1), M("leaf_light"),
                            segs=5, rings=3, scale=(1, 1, 0.6))
            parts.append(leaf)
        return _scale(parts, scale)
    if kind == "herb":
        parts.append(cyl(0.09, 0.14, (0, 0, 0.07), M("terracotta"), 8, r_top=0.1))
        for i in range(6):
            parts.append(C.sphere("f", 0.05, (rnd.uniform(-0.05, 0.05), rnd.uniform(-0.05, 0.05),
                                              0.17 + rnd.uniform(0, 0.05)),
                                  M(rnd.choice(["leaf", "leaf_light"])), segs=5, rings=3))
        return _scale(parts, scale)
    pot_h, pot_r = (0.32, 0.17) if kind in ("monstera", "fiddle", "palm") else (0.2, 0.12)
    parts.append(cyl(pot_r, pot_h, (0, 0, pot_h / 2), M(pot_col), 10, r_top=pot_r * 1.12))
    parts.append(cyl(pot_r * 1.05, 0.02, (0, 0, pot_h - 0.02), M("soil"), 10))
    if kind == "monstera":
        for i in range(9):
            a = rnd.uniform(0, 2 * math.pi)
            ln = rnd.uniform(0.3, 0.6)
            h = pot_h + rnd.uniform(0.25, 0.75)
            tip = (math.cos(a) * ln, math.sin(a) * ln, h)
            parts.append(_stem((0, 0, pot_h), tip, M("leaf_dark")))
            parts.append(_leaf(tip, a, 0.22, 0.18, M(rnd.choice(["leaf", "leaf_dark"])), droop=-25))
    elif kind == "fiddle":
        parts.append(cyl(0.02, 1.0, (0, 0, pot_h + 0.5), M("wood_mid"), 5))
        for i in range(14):
            a = rnd.uniform(0, 2 * math.pi)
            h = pot_h + 0.45 + i * 0.06
            r = rnd.uniform(0.05, 0.18)
            parts.append(_leaf((math.cos(a) * r, math.sin(a) * r, h), a, 0.12, 0.1, M("leaf_dark"), droop=10))
    elif kind == "snake":
        for i in range(9):
            a = rnd.uniform(0, 2 * math.pi)
            r = rnd.uniform(0.0, 0.07)
            h = rnd.uniform(0.35, 0.6)
            blade = bx((-0.025, -0.006, 0), (0.025, 0.006, h), M(rnd.choice(["leaf", "leaf_light", "leaf_dark"])))
            blade.rotation_euler = (rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15), a)
            blade.location = (math.cos(a) * r, math.sin(a) * r, pot_h - 0.02)
            parts.append(blade)
    elif kind == "pothos":
        # trailing vine over the pot edge (good on shelves)
        for i in range(7):
            a = i * 2 * math.pi / 7 + rnd.uniform(-0.3, 0.3)
            for j in range(4):
                r = pot_r + j * 0.04
                z = pot_h - j * 0.12
                parts.append(C.sphere("f", 0.045, (math.cos(a) * r, math.sin(a) * r, z),
                                      M(rnd.choice(["leaf", "leaf_light"])), segs=5, rings=3,
                                      scale=(1, 1, 0.5)))
    elif kind == "fern":
        for i in range(12):
            a = i * 2 * math.pi / 12
            tip = (math.cos(a) * 0.35, math.sin(a) * 0.35, pot_h + rnd.uniform(0.05, 0.25))
            parts.append(_leaf(tip, a, 0.3, 0.07, M("leaf_light"), droop=-35))
    elif kind == "palm":
        parts.append(cyl(0.025, 0.9, (0, 0, pot_h + 0.45), M("wood_light"), 5))
        for i in range(8):
            a = i * 2 * math.pi / 8
            tip = (math.cos(a) * 0.3, math.sin(a) * 0.3, pot_h + 0.85)
            parts.append(_leaf(tip, a, 0.45, 0.08, M("leaf"), droop=-30))
    return _scale(parts, scale)


def _scale(parts, s):
    if s != 1.0:
        for p in parts:
            C.apply_transform(p)
            p.data.transform(Matrix.Scale(s, 4))
    return parts


def _stem(a, b, mat):
    a, b = Vector(a), Vector(b)
    d = b - a
    o = cyl(0.008, d.length, (0, 0, 0), mat, 4)
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    o.location = (a + b) / 2
    return o


def _leaf(pos, angle, length, width, mat, droop=0):
    v = [(0, 0, 0), (length * 0.5, -width / 2, 0.02), (length, 0, 0), (length * 0.5, width / 2, 0.02)]
    f = [(0, 1, 2, 3)]
    o = C.mesh_obj("leaf", v, f, mat)
    mat.use_backface_culling = False
    o.rotation_euler = (0, math.radians(-droop), angle)
    o.location = pos
    return o


def hanging_plant(drop=0.7, seed=3):
    """Macrame-hung pothos; origin at the ceiling hook."""
    parts = [cyl(0.004, drop, (0, 0, -drop / 2), M("cream"), 4)]
    p = plant("pothos", seed)
    for o in p:
        o.location.z -= drop + 0.2
    return parts + p


# ------------------------------------------------------------------ kitchen

def kitchen_run(length, depth=0.6, height=0.9, top="granite", with_sink=False, with_cooktop=False,
                upper=False, oven=False):
    """A straight bench run along +X from 0..length, back against y=+depth/2... front at -Y."""
    gran = top
    parts = [bx((0, -depth / 2, 0.1), (length, depth / 2, height - 0.03), M("white")),
             bx((0.02, -depth / 2 + 0.05, 0), (length - 0.02, depth / 2, 0.1), M("black")),
             bx((0, -depth / 2 - 0.02, height - 0.03), (length, depth / 2, height + 0.01), gran)]
    n = max(1, int(length / 0.45))
    for i in range(n):
        x0 = i * length / n
        parts.append(bx((x0 + 0.01, -depth / 2 - 0.005, 0.12), (x0 + length / n - 0.01, -depth / 2, height - 0.05), M("cream")))
        parts.append(bx((x0 + length / n / 2 - 0.05, -depth / 2 - 0.02, height - 0.15),
                        (x0 + length / n / 2 + 0.05, -depth / 2 - 0.005, height - 0.13), M("steel")))
    if with_sink:
        xs = length * 0.5
        parts.append(bx((xs - 0.4, -0.2, height - 0.01), (xs + 0.4, 0.2, height + 0.012), M("steel")))
        parts.append(bx((xs - 0.35, -0.17, height - 0.005), (xs - 0.02, 0.17, height + 0.013), M("black")))
        parts.append(cyl(0.012, 0.3, (xs, 0.22, height + 0.15), M("chrome"), 5))
        spout = bx((xs - 0.01, 0.05, height + 0.28), (xs + 0.01, 0.23, height + 0.3), M("chrome"))
        parts.append(spout)
    if with_cooktop:
        xc = length * 0.5
        parts.append(bx((xc - 0.3, -0.25, height + 0.01), (xc + 0.3, 0.25, height + 0.02), M("steel")))
        for dx, dy in ((-0.15, -0.12), (0.15, -0.12), (-0.15, 0.12), (0.15, 0.12)):
            parts.append(cyl(0.06, 0.02, (xc + dx, dy, height + 0.03), M("black"), 8))
    if oven:
        xc = length * 0.5
        parts.append(bx((xc - 0.3, -depth / 2 - 0.01, 0.15), (xc + 0.3, -depth / 2, 0.8), M("white")))
        parts.append(bx((xc - 0.24, -depth / 2 - 0.015, 0.25), (xc + 0.24, -depth / 2 - 0.01, 0.6), M("black")))
    if upper:
        parts.append(bx((0, depth / 2 - 0.35, 1.5), (length, depth / 2, 2.2), M("white")))
        for i in range(n):
            x0 = i * length / n
            parts.append(bx((x0 + 0.01, depth / 2 - 0.355, 1.52), (x0 + length / n - 0.01, depth / 2 - 0.35, 2.18), M("cream")))
    return parts


def fridge():
    parts = [bx((-0.35, -0.35, 0), (0.35, 0.35, 1.8), M("fridge")),
             bx((-0.35, -0.36, 1.2), (0.35, -0.35, 1.21), M("metal")),
             bx((0.25, -0.38, 1.3), (0.28, -0.36, 1.7), M("steel")),
             bx((0.25, -0.38, 0.6), (0.28, -0.36, 1.1), M("steel"))]
    # magnets from places you've driven to; the collectible ones
    # (props/home/magnets/) go on the FRIDGE_MAGNETS spots instead once the
    # game places them
    rnd = random.Random(9)
    for i in range(9):
        x, z = rnd.uniform(-0.28, 0.2), rnd.uniform(1.25, 1.75)
        parts.append(bx((x, -0.365, z), (x + 0.06, -0.35, z + 0.05),
                        M(rnd.choice(["rust", "teal", "mustard", "book2", "cream"]))))
    return parts


# Magnet spots on the fridge's upper door, (x, z) in the fridge's frame;
# the door face is at y = -0.35.
FRIDGE_MAGNETS = [(x, z) for z in (1.68, 1.53, 1.38) for x in (-0.24, -0.12, 0.0, 0.12)]


def coffee_machine():
    return [bx((-0.12, -0.15, 0), (0.12, 0.15, 0.32), M("black")),
            bx((-0.1, -0.17, 0.05), (0.1, -0.12, 0.08), M("steel")),
            cyl(0.04, 0.08, (0, -0.1, 0.12), M("pot_white"), 8)]


def kettle():
    return [cyl(0.08, 0.2, (0, 0, 0.1), M("cream"), 8, r_top=0.06), bx((0.06, -0.01, 0.06), (0.1, 0.01, 0.17), M("black"))]


def bar_stool():
    return [cyl(0.18, 0.05, (0, 0, 0.68), M("wood_mid"), 10),
            cyl(0.02, 0.66, (0, 0, 0.33), M("black"), 5),
            cyl(0.2, 0.02, (0, 0, 0.01), M("black"), 10),
            cyl(0.14, 0.01, (0, 0, 0.3), M("black"), 8)]


def dining_table(w=1.4, d=0.8):
    parts = [bx((-w / 2, -d / 2, 0.72), (w / 2, d / 2, 0.76), M("oak"))]
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(bx((sx * (w / 2 - 0.06) - 0.03, sy * (d / 2 - 0.06) - 0.03, 0),
                            (sx * (w / 2 - 0.06) + 0.03, sy * (d / 2 - 0.06) + 0.03, 0.72), M("oak")))
    return parts


def chair(color="wood_mid"):
    c = M(color)
    parts = [bx((-0.21, -0.21, 0.44), (0.21, 0.21, 0.48), c),
             bx((-0.21, 0.17, 0.48), (0.21, 0.21, 0.92), c)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(bx((sx * 0.18 - 0.02, sy * 0.18 - 0.02, 0), (sx * 0.18 + 0.02, sy * 0.18 + 0.02, 0.44), c))
    return parts


def laptop():
    return [bx((-0.17, -0.12, 0), (0.17, 0.12, 0.015), M("metal")),
            bx((-0.17, 0.11, 0.015), (0.17, 0.125, 0.24), M("metal")),
            bx((-0.15, 0.108, 0.03), (0.15, 0.11, 0.22), emissive("LaptopScreen", "#8fb6d6", 0.8))]


def pendant(drop=0.6, color="#f6d9a0"):
    """Origin at the ceiling."""
    return [cyl(0.004, drop, (0, 0, -drop / 2), M("black"), 4),
            cyl(0.06, 0.14, (0, 0, -drop - 0.07), emissive("Pendant_Glow", color, 1.5), 10, r_top=0.03)]


# ------------------------------------------------------------------ bedroom

def bed(w=1.53, l=2.03, color="duvet"):
    wood = M("wood_mid")
    parts = [bx((-w / 2 - 0.04, -l / 2, 0.1), (w / 2 + 0.04, l / 2, 0.3), wood),
             bx((-w / 2 - 0.04, l / 2 - 0.05, 0), (w / 2 + 0.04, l / 2 + 0.03, 1.05), wood),
             bx((-w / 2, -l / 2 + 0.02, 0.3), (w / 2, l / 2 - 0.05, 0.52), M("linen")),
             bx((-w / 2 - 0.02, -l / 2, 0.45), (w / 2 + 0.02, l / 2 - 0.55, 0.6), M(color)),
             bx((-w / 2 - 0.02, -l / 2 + 0.05, 0.6), (w / 2 + 0.02, -l / 2 + 0.6, 0.63), M("throw"))]
    for sx in (-1, 1):
        p = bx((-0.3, -0.18, 0), (0.3, 0.18, 0.14), M("pillow"))
        p.rotation_euler = (math.radians(-18), 0, 0)
        p.location = (sx * w / 4, l / 2 - 0.3, 0.55)
        parts.append(p)
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(bx((sx * w / 2 - 0.03, sy * (l / 2 - 0.05) - 0.03, 0),
                            (sx * w / 2 + 0.03, sy * (l / 2 - 0.05) + 0.03, 0.1), wood))
    return parts


def bedside_table():
    return [bx((-0.22, -0.2, 0.0), (0.22, 0.2, 0.55), M("oak")),
            bx((-0.2, -0.205, 0.33), (0.2, -0.2, 0.5), M("wood_light"))]


def robe_doors(length, height=2.3, depth=0.6):
    """Built-in robe along +X, doors facing -Y."""
    parts = [bx((0, -depth / 2, 0), (length, depth / 2, height), M("white"))]
    n = max(2, int(round(length / 0.6)))
    for i in range(n):
        x0 = i * length / n
        parts.append(bx((x0 + 0.01, -depth / 2 - 0.02, 0.02), (x0 + length / n - 0.01, -depth / 2, height - 0.02), M("white")))
        hx = x0 + (length / n - 0.08 if i % 2 == 0 else 0.08)
        parts.append(cyl(0.015, 0.02, (hx, -depth / 2 - 0.03, 1.1), M("steel"), 6, axis="Y"))
    return parts


def desk(w=1.2, d=0.6):
    parts = [bx((-w / 2, -d / 2, 0.72), (w / 2, d / 2, 0.75), M("wood_light"))]
    for sx in (-1, 1):
        parts.append(bx((sx * (w / 2 - 0.03) - 0.02, -d / 2 + 0.03, 0), (sx * (w / 2 - 0.03) + 0.02, d / 2 - 0.03, 0.72), M("black")))
    parts.append(bx((w / 2 - 0.45, -d / 2 + 0.02, 0.45), (w / 2 - 0.05, d / 2 - 0.02, 0.72), M("wood_light")))
    return parts


def corkboard(w=1.4, h=0.9):
    """Map of rumours: pinned notes and photos joined by red string. Faces -Y."""
    rnd = random.Random(14)
    parts = [bx((-w / 2, -0.02, 0), (w / 2, 0.0, h), M("frame")),
             bx((-w / 2 + 0.04, -0.03, 0.04), (w / 2 - 0.04, -0.02, h - 0.04), M("cork"))]
    pins = []
    # a rough Perth outline in pale paper, with notes around it
    parts.append(bx((-0.25, -0.035, 0.15), (0.2, -0.03, 0.75), M("paper")))
    for i in range(9):
        x, z = rnd.uniform(-w / 2 + 0.12, w / 2 - 0.12), rnd.uniform(0.12, h - 0.12)
        c = rnd.choice(["paper", "cream", "mustard", "pot_white"])
        parts.append(bx((x - 0.05, -0.04, z - 0.04), (x + 0.05, -0.034, z + 0.04), M(c)))
        parts.append(cyl(0.008, 0.012, (x, -0.045, z + 0.03), M("rust"), 5, axis="Y"))
        pins.append((x, z + 0.03))
    for a, b in zip(pins, pins[1:] + pins[:1]):
        if rnd.random() < 0.7:
            parts.append(_string(a, b))
    return parts


def _string(a, b):
    ax, az = a
    bxx, bz = b
    d = Vector((bxx - ax, 0, bz - az))
    o = bx((-d.length / 2, -0.002, -0.002), (d.length / 2, 0.002, 0.002), M("red_string"))
    o.rotation_euler = (0, -math.atan2(d.z, d.x), 0)
    o.location = ((ax + bxx) / 2, -0.05, (az + bz) / 2)
    return o


def photo_frames(n=7, seed=3, w=1.6, h=0.9):
    """A gallery wall (faces -Y), origin at its bottom centre."""
    rnd = random.Random(seed)
    parts = []
    for i in range(n):
        fw, fh = rnd.choice([(0.2, 0.25), (0.3, 0.22), (0.25, 0.3), (0.35, 0.25)])
        x = -w / 2 + (i + 0.5) * w / n + rnd.uniform(-0.05, 0.05)
        z = rnd.uniform(0.1, h - fh)
        parts.append(bx((x - fw / 2, -0.02, z), (x + fw / 2, 0, z + fh), M(rnd.choice(["frame", "wood_light", "white"]))))
        parts.append(bx((x - fw / 2 + 0.03, -0.025, z + 0.03), (x + fw / 2 - 0.03, -0.02, z + fh - 0.03),
                        M(rnd.choice(["teal", "mustard", "book2", "rust", "cream", "leaf"]))))
    return parts


def curtains(w, h, drape=0.38):
    """Two drapes pulled open either side of an opening `w` wide, hanging
    from a rod; faces -Y. Each drape covers only the wall beside the opening
    (overlapping its edge by 5 cm), so doors under it swing clear."""
    parts = [cyl(0.012, w + 2 * drape, (0, 0, h), M("brass"), 5, axis="X")]
    for sx in (-1, 1):
        inner, outer = w / 2 - 0.05, w / 2 - 0.05 + drape
        for k in range(4):
            a = inner + (outer - inner) * k / 4
            b = inner + (outer - inner) * (k + 1) / 4
            x0, x1 = (a, b) if sx > 0 else (-b, -a)
            parts.append(bx((x0, -0.03 - (k % 2) * 0.03, 0.05), (x1, 0.0 - (k % 2) * 0.03, h - 0.02), M("curtain")))
    return parts


# ------------------------------------------------------------------ bathroom & laundry

def bath(l=1.65, w=0.75):
    return [bx((-l / 2, -w / 2, 0), (l / 2, w / 2, 0.55), M("porcelain")),
            bx((-l / 2 + 0.08, -w / 2 + 0.08, 0.3), (l / 2 - 0.08, w / 2 - 0.08, 0.56), M("white")),
            cyl(0.015, 0.15, (l / 2 - 0.15, w / 2 - 0.05, 0.65), M("chrome"), 5)]


def vanity(w=0.9):
    return [bx((-w / 2, -0.25, 0), (w / 2, 0.25, 0.8), M("white")),
            bx((-w / 2 - 0.02, -0.27, 0.8), (w / 2 + 0.02, 0.25, 0.84), M("cream")),
            cyl(0.2, 0.14, (0, -0.02, 0.91), M("porcelain"), 12, r_top=0.22),
            cyl(0.012, 0.22, (0, 0.18, 0.95), M("chrome"), 5),
            bx((-w / 2 + 0.02, 0.24, 1.0), (w / 2 - 0.02, 0.25, 1.8), M("chrome"))]


def toilet():
    return [bx((-0.18, -0.05, 0), (0.18, 0.2, 0.4), M("porcelain")),
            cyl(0.19, 0.08, (0, -0.15, 0.4), M("porcelain"), 10),
            bx((-0.2, 0.12, 0.4), (0.2, 0.22, 0.8), M("porcelain"))]


def shower_screen(w=0.9, d=0.9, h=2.0):
    glass = C.mat("ShowerGlass", "#cfdde0", rough=0.05, alpha=0.3)
    glass.use_backface_culling = False
    return [bx((-w / 2, -d / 2, 0), (w / 2, -d / 2 + 0.01, h), glass),
            bx((w / 2 - 0.01, -d / 2, 0), (w / 2, d / 2, h), glass),
            bx((-w / 2, -d / 2, 0), (w / 2, d / 2, 0.05), M("porcelain")),
            cyl(0.08, 0.02, (0, d / 2 - 0.1, h - 0.1), M("chrome"), 8)]


def towel_rail():
    return [cyl(0.01, 0.6, (0, 0, 0), M("chrome"), 5, axis="X"),
            bx((-0.25, -0.03, -0.45), (0.25, 0.03, 0.0), M("towel"))]


def washing_machine():
    return [bx((-0.3, -0.3, 0), (0.3, 0.3, 0.85), M("fridge")),
            cyl(0.18, 0.03, (0, -0.31, 0.45), M("metal"), 12, axis="Y"),
            cyl(0.14, 0.035, (0, -0.32, 0.45), M("screen"), 12, axis="Y")]


def laundry_trough():
    return [bx((-0.3, -0.25, 0.0), (0.3, 0.25, 0.85), M("steel")),
            bx((-0.26, -0.21, 0.6), (0.26, 0.21, 0.86), M("metal")),
            cyl(0.012, 0.25, (0, 0.2, 1.0), M("chrome"), 5)]


# ------------------------------------------------------------------ misc

def split_ac():
    """Wall split unit; origin on the wall, faces -Y."""
    return [bx((-0.4, -0.22, -0.14), (0.4, 0.0, 0.14), M("white")),
            bx((-0.36, -0.225, -0.12), (0.36, -0.22, -0.08), M("metal"))]


def intercom():
    return [bx((-0.06, -0.04, -0.12), (0.06, 0.0, 0.12), M("pot_white")),
            bx((-0.04, -0.06, -0.02), (0.04, -0.04, 0.1), M("white"))]


def boxes(seed=2, n=4):
    rnd = random.Random(seed)
    parts = []
    z = 0.0
    for i in range(n):
        w = rnd.uniform(0.3, 0.5)
        d = rnd.uniform(0.3, 0.45)
        h = rnd.uniform(0.2, 0.35)
        dx, dy = rnd.uniform(-0.05, 0.05), rnd.uniform(-0.05, 0.05)
        parts.append(bx((dx - w / 2, dy - d / 2, z), (dx + w / 2, dy + d / 2, z + h), M("box")))
        z += h
    return parts


def vacuum():
    return [bx((-0.15, -0.2, 0), (0.15, 0.2, 0.3), M("teal")),
            cyl(0.02, 0.9, (0.0, 0.25, 0.6), M("metal"), 5)]


def sheet_covered(w=0.9, d=0.6, h=0.7):
    """Something under a dust sheet."""
    v = [(-w / 2, -d / 2, 0), (w / 2, -d / 2, 0), (w / 2, d / 2, 0), (-w / 2, d / 2, 0),
         (-w / 2 + 0.1, -d / 2 + 0.08, h * 0.8), (w / 2 - 0.05, -d / 2 + 0.1, h),
         (w / 2 - 0.12, d / 2 - 0.08, h * 0.9), (-w / 2 + 0.06, d / 2 - 0.1, h * 0.75)]
    f = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)]
    return [C.mesh_obj("sheet", v, f, M("cloth"))]


def shoe_rack_and_coats():
    parts = [bx((-0.4, -0.15, 0), (0.4, 0.15, 0.4), M("wood_light"))]
    for i, c in enumerate(["throw", "teal", "mustard"]):
        parts.append(bx((-0.3 + i * 0.25, -0.05, 1.2), (-0.12 + i * 0.25, 0.05, 1.75), M(c)))
    parts.append(bx((-0.4, 0.05, 1.7), (0.4, 0.1, 1.76), M("wood_dark")))
    return parts


def cat_bowl():
    return [cyl(0.08, 0.04, (0, 0, 0.02), M("pot_white"), 8, r_top=0.09),
            cyl(0.07, 0.01, (0, 0, 0.04), M("cat_food"), 8)]


def hot_water_unit():
    return [bx((-0.3, -0.2, 0), (0.3, 0.2, 1.3), M("cream")), bx((-0.08, -0.205, 0.95), (0.08, -0.2, 1.05), M("rust"))]


def ac_outdoor():
    return [bx((-0.4, -0.15, 0), (0.4, 0.15, 0.55), M("pot_white")),
            cyl(0.18, 0.01, (-0.08, -0.155, 0.28), M("metal"), 10, axis="Y")]


def wall_light(glow=True):
    return [bx((-0.06, -0.06, -0.1), (0.06, 0.0, 0.1), M("black")),
            cyl(0.06, 0.16, (0, -0.1, 0.0), emissive("WallLamp_Glow", "#ffd9a0", 1.0) if glow else M("cream"), 6)]


def padlock():
    return [bx((-0.035, -0.015, -0.05), (0.035, 0.015, 0.0), M("brass")),
            C.cylinder("shackle", 0.025, 0.012, segs=8, axis="Y", loc=(0, 0, 0.02), material=M("steel"))]


def ball_pillar(h=1.45, w=0.42):
    return [bx((-w / 2, -w / 2, 0), (w / 2, w / 2, h), M("white")),
            bx((-w / 2 - 0.03, -w / 2 - 0.03, h), (w / 2 + 0.03, w / 2 + 0.03, h + 0.06), M("white")),
            cyl(0.06, 0.06, (0, 0, h + 0.09), M("white"), 8),
            C.sphere("ball", 0.14, (0, 0, h + 0.26), M("white"), segs=10, rings=6)]


def pencil_pine(h=6.5, seed=1):
    rnd = random.Random(seed)
    parts = [cyl(0.12, 0.8, (0, 0, 0.4), M("wood_dark"), 6)]
    n = 7
    for i in range(n):
        t = i / n
        r = 0.75 * (1 - t) ** 0.6 + 0.12
        z = 0.6 + t * (h - 1.2)
        parts.append(C.sphere("f", r, (rnd.uniform(-0.05, 0.05), rnd.uniform(-0.05, 0.05), z + 0.5),
                              M(rnd.choice(["leaf_dark", "leaf"])), segs=8, rings=5, scale=(1, 1, 1.5)))
    return parts


def shrub(r=0.5, seed=1):
    rnd = random.Random(seed)
    parts = []
    for i in range(4):
        parts.append(C.sphere("f", r * rnd.uniform(0.6, 1.0),
                              (rnd.uniform(-r, r) * 0.5, rnd.uniform(-r, r) * 0.5, r * 0.6 + rnd.uniform(0, r * 0.3)),
                              M(rnd.choice(["leaf", "leaf_dark", "leaf_light"])), segs=7, rings=4))
    return parts


def street_tree(h=6.0, seed=2, bare=False):
    rnd = random.Random(seed)
    parts = [cyl(0.15, h * 0.55, (0, 0, h * 0.275), M("wood_mid"), 6, r_top=0.1)]
    if not bare:
        for i in range(5):
            parts.append(C.sphere("f", rnd.uniform(1.0, 1.6),
                                  (rnd.uniform(-1, 1), rnd.uniform(-1, 1), h * 0.6 + rnd.uniform(0, h * 0.3)),
                                  M(rnd.choice(["leaf", "leaf_light"])), segs=7, rings=4))
    return parts
