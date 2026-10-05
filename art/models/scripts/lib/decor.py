"""Things for the townhouse bought with job money (the driving thread's
Decorate feature): three choices each of rug, floor lamp, plant and
armchair, and four posters, in a cozy 70s-to-now Perth share-house style.

Every builder returns (parts, sockets): parts authored facing -Y in Blender
(+Z in Godot), origin at the base centre (posters: the middle of the
poster, back on the wall), metres; sockets are named empty positions.

Pictures are tiny procedural images, all original; no real brands, bands,
films or maps.
"""
import math
import random

from mathutils import Vector

from . import cabin as CB
from . import common as C
from . import furniture as F
from . import textures as TX

# ------------------------------------------------------------------ helpers


def _m(name, color, rough=0.8, metal=0.0, alpha=None):
    if alpha is not None:
        m = C.mat("DC_" + name, color, rough=rough, metal=metal, alpha=alpha)
        m.use_backface_culling = False
        return m
    return C.mat("DC_" + name, color, rough=rough, metal=metal)


def _img_mat(name, img, rough=0.85):
    return C.mat("DC_" + name, "#ffffff", rough=rough, image=img)


def _glow(name, color, strength=1.5):
    # shades keep the Lampshade_Glow naming the house lamps use, so the
    # game can dim them all the same way
    return C.mat(name, color, rough=0.9, emit=color, emit_strength=strength)


def _quad(mat, w, h, y=0.0, x=0.0, z=0.0):
    """Picture facing -Y: (w x h) centred on (x, z), on the plane y."""
    o = C.mesh_obj("pic", [(x - w / 2, y, z - h / 2), (x + w / 2, y, z - h / 2), (x + w / 2, y, z + h / 2),
                           (x - w / 2, y, z + h / 2)], [(0, 1, 2, 3)], mat)
    uv = o.data.uv_layers.new(name="UVMap")
    for li, (u, v) in zip(o.data.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (u, v)
    return o


def _flat(mat, w, d, z):
    """Picture lying face up, centred, top of the image toward +Y."""
    o = C.mesh_obj("pic", [(-w / 2, -d / 2, z), (w / 2, -d / 2, z), (w / 2, d / 2, z), (-w / 2, d / 2, z)],
                   [(0, 1, 2, 3)], mat)
    uv = o.data.uv_layers.new(name="UVMap")
    for li, (u, v) in zip(o.data.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (u, v)
    return o


def _text_ink(lines, w, h, top=1, scale=1):
    """ink(x, y) for centred rows of the plate font."""
    cw = 4 * scale
    rows = []
    for i, line in enumerate(lines):
        x0 = (w - cw * len(line) + scale) // 2
        y0 = h - top - (i + 1) * 6 * scale
        rows.append((line, x0, y0))

    def ink(x, y):
        for line, x0, y0 in rows:
            gx, gy = x - x0, y - y0
            if 0 <= gx < cw * len(line) and 0 <= gy < 5 * scale:
                ch = line[gx // cw]
                lx, ly = (gx % cw) // scale, gy // scale
                if lx < 3 and TX.FONT.get(ch, TX.FONT[" "])[(4 - ly) * 3 + lx] == "1":
                    return True
        return False
    return ink


def _hex(c):
    return C._hex(c)


# ------------------------------------------------------------------ rugs

def _img_rug(kind):
    if kind == "jute":
        w, h = 48, 32

        def px(x, y):
            # braided bands round an oval, natural fibre
            r = math.hypot((x - 23.5) / 24, (y - 15.5) / 16)
            band = int(r * 14)
            base = (0.70, 0.57, 0.38) if band % 2 else (0.62, 0.49, 0.31)
            k = 0.92 if (x + y * 2) % 3 == 0 else 1.0
            return TX.mul(base, k)
    elif kind == "persian":
        w, h = 48, 32
        red, navy, cream, gold = _hex("#7e1f1c"), _hex("#22304e"), _hex("#e2d3b0"), _hex("#b88a3c")

        def px(x, y):
            if x < 3 or x > 44 or y < 3 or y > 28:
                return navy if (x + y) % 4 else gold
            if x < 5 or x > 42 or y < 5 or y > 26:
                return cream
            dx, dy = abs(x - 23.5) / 18, abs(y - 15.5) / 10
            if dx + dy < 0.55:
                return navy if dx + dy > 0.35 else (gold if dx + dy > 0.2 else red)
            if (x * 3 + y * 5) % 11 == 0:
                return gold
            if ((x - 8) % 9 < 2) and (y % 7 < 2):
                return navy
            return red
    else:  # retro
        w, h = 48, 32
        cols = [_hex(c) for c in ("#c8642a", "#e0a03a", "#5a3a26", "#efe0c0", "#8a3a22")]

        def px(x, y):
            # rounded-rectangle bands, 70s style
            dx, dy = max(0, abs(x - 23.5) - 10), max(0, abs(y - 15.5) - 2)
            r = math.hypot(dx, dy)
            return cols[int(r / 2.6) % len(cols)]
    return C.make_image("dc_rug_" + kind, w, h, px)


def rug(kind):
    """rug_jute (oval braided natural fibre, 2.0 x 1.4), rug_persian (2.4 x 1.6,
    red and navy with a medallion and fringes), rug_retro (2.2 x 1.5, 70s
    rounded bands). Lying flat, origin at the centre."""
    mat = _img_mat("rug_" + kind, _img_rug(kind), 1.0)
    if kind == "jute":
        w, d = 2.0, 1.4
        ring = [(w / 2 * math.cos(2 * math.pi * i / 24), d / 2 * math.sin(2 * math.pi * i / 24)) for i in range(24)]
        top = C.mesh_obj("rug", [(x, y, 0.012) for x, y in ring], [tuple(range(24))], mat)
        uv = top.data.uv_layers.new(name="UVMap")
        for li in top.data.polygons[0].loop_indices:
            x, y = ring[top.data.loops[li].vertex_index]
            uv.data[li].uv = (x / w + 0.5, y / d + 0.5)
        edge = C.mesh_obj("edge", [(x, y, z) for x, y in ring for z in (0, 0.012)],
                          [(2 * i, 2 * ((i + 1) % 24), 2 * ((i + 1) % 24) + 1, 2 * i + 1) for i in range(24)],
                          _m("Jute", "#9c7c50", 1.0))
        return [top, edge], {}
    w, d = (2.4, 1.6) if kind == "persian" else (2.2, 1.5)
    parts = [F.bx((-w / 2, -d / 2, 0), (w / 2, d / 2, 0.009), _m("RugBack", "#2a2420", 1.0)),
             _flat(mat, w, d, 0.0095)]
    if kind == "persian":
        fringe = _m("Fringe", "#e6dcc4", 1.0)
        for sx in (-1, 1):
            for i in range(16):
                y = -d / 2 + 0.05 + i * (d - 0.1) / 15
                parts.append(F.bx((sx * w / 2 - (0 if sx > 0 else 0.07), y - 0.008, 0.0),
                                  (sx * w / 2 + (0.07 if sx > 0 else 0), y + 0.008, 0.004), fringe))
    return parts, {}


# ------------------------------------------------------------------ lamps

def lamp(kind):
    """lamp_arc (marble block, steel arc, dome shade over the room),
    lamp_paper (a tall paper lantern column on a slim stand), lamp_tripod
    (timber tripod, linen drum shade). Light: the bulb."""
    steel = _m("LampSteel", "#c9cbcd", 0.25, 0.85)
    if kind == "arc":
        marble = _m("Marble", "#e9e6df", 0.3)
        parts = [CB._rbox("base", (-0.18, -0.13, 0.0), (0.18, 0.13, 0.12), marble, 0.02)]
        # the arc rises from the back of the base and falls 1.25 m forward
        pts = []
        for i in range(13):
            ph = math.pi * 0.7 * i / 12
            pts.append(Vector((0, 0.06 - 0.8 * (1 - math.cos(ph)), 0.17 + 1.85 * math.sin(ph))))
        for a, b in zip(pts, pts[1:]):
            parts.append(CB._between("arc", a, b, 0.011, steel, segs=6))
        tip = pts[-1]
        shade = C.sphere("shade", 0.2, (tip.x, tip.y, tip.z - 0.12), steel, segs=14, rings=6, scale=(1, 1, 0.75))
        # keep the dome only: drop the lower half below the rim
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(shade.data)
        cut = [v for v in bm.verts if v.co.z < -0.01]
        bmesh.ops.delete(bm, geom=cut, context="VERTS")
        bm.to_mesh(shade.data)
        bm.free()
        shade.data.materials.clear()
        shade.data.materials.append(steel)
        parts.append(shade)
        bulb = (tip.x, tip.y, tip.z - 0.15)
        parts.append(C.sphere("bulb", 0.05, bulb, _glow("Lampshade_Glow", "#f6d9a0"), segs=8, rings=4))
        return parts, {"Light": bulb}
    if kind == "paper":
        paper = _glow("Lampshade_Glow", "#f4e6c4", 1.4)
        parts = [C.cylinder("base", 0.14, 0.02, segs=12, loc=(0, 0, 0.01), material=_m("LampBlack", "#141414", 0.5)),
                 C.cylinder("pole", 0.01, 0.3, segs=6, loc=(0, 0, 0.17), material=_m("LampBlack", "#141414", 0.5))]
        # stacked lantern column with rib rings
        z = 0.32
        for i in range(4):
            r = (0.17, 0.2, 0.2, 0.17)[i]
            r2 = (0.2, 0.2, 0.17, 0.13)[i]
            parts.append(C.cylinder("paper", r, 0.3, segs=14, loc=(0, 0, z + 0.15), material=paper, r_top=r2))
            parts.append(C.cylinder("rib", r2 + 0.003, 0.006, segs=14, loc=(0, 0, z + 0.3), material=_m("Rib", "#d8c8a0")))
            z += 0.3
        return parts, {"Light": (0, 0, 0.95)}
    # tripod
    oak = _m("TripodOak", "#a77d50", 0.6)
    parts = []
    top = Vector((0, 0, 1.25))
    for k in range(3):
        a = math.radians(90 + k * 120)
        parts.append(CB._between("leg", (0.32 * math.cos(a), 0.32 * math.sin(a), 0.0), top, 0.016, oak, segs=6,
                                 r_top=0.012))
    parts.append(C.cylinder("hub", 0.03, 0.08, segs=8, loc=(0, 0, 1.24), material=steel))
    shade = _glow("Lampshade_Glow", "#efe0bc", 1.4)
    parts.append(C.cylinder("drum", 0.24, 0.3, segs=16, loc=(0, 0, 1.42), material=shade))
    parts.append(C.cylinder("drum_in", 0.235, 0.29, segs=16, loc=(0, 0, 1.42), material=shade))
    return parts, {"Light": (0, 0, 1.38)}


# ------------------------------------------------------------------ posters

PW, PH = 0.5, 0.7


def _img_poster(kind):
    w, h = 40, 56
    if kind == "band":
        # a made-up gig poster: two-colour screenprint, a howling dog moon
        bg, ink, ink2 = _hex("#efe2c4"), _hex("#2a2420"), _hex("#c8462a")
        title = _text_ink(["LOW TIDE", "CLUB"], w, h, top=3)
        foot = _text_ink(["SAT 9PM"], w, 10, top=2)

        def px(x, y):
            if title(x, y):
                return ink2
            if y < 10 and foot(x, y):
                return ink
            if (x - 20) ** 2 + (y - 26) ** 2 < 90:
                return ink2 if (x - 20) ** 2 + (y - 26) ** 2 > 60 else bg
            if 12 <= y <= 14 and 4 <= x <= 36:
                return ink
            return bg
    elif kind == "surf":
        sky1, sky2, sea, foam, sun = (_hex(c) for c in ("#f0b04a", "#d8662a", "#2f6f8a", "#e9f0ee", "#f8e3a0"))
        title = _text_ink(["SUMMER", "SWELL"], w, h, top=3)

        def px(x, y):
            if title(x, y):
                return _hex("#2a2420")
            if (x - 20) ** 2 + (y - 30) ** 2 < 49 and y > 22:
                return sun
            if y > 22:
                return sky1 if y > 32 else sky2
            # the wave curls in from the left
            crest = 22 - max(0, 14 - x) * 0.6
            if y > crest - 2 and y < 22 and x < 16:
                return foam
            return sea if (x + y) % 5 else TX.mul(sea, 0.85)
    elif kind == "map":
        # a made-up river and coast map, hand-coloured
        land, water, road, text = (_hex(c) for c in ("#e8dcb8", "#8fb8c8", "#b8462a", "#3a2a24"))
        title = _text_ink(["RIVER", "& COAST"], w, h, top=2)

        def px(x, y):
            if title(x, y):
                return text
            if y > 44:
                return land
            if x < 7 + 2 * math.sin(y * 0.35):
                return water                                     # the sea down the left
            river = 24 + 8 * math.sin(y * 0.15) - (44 - y) * 0.1
            if abs(x - river) < 2.2 + (1.5 if 18 < y < 26 else 0):
                return water
            if (x - 6) % 11 == 0 or (y - 3) % 13 == 0:
                return road
            return land if (x * 7 + y * 3) % 17 else TX.mul(land, 0.9)
    else:  # film
        bg, red, cream, dark = (_hex(c) for c in ("#141a24", "#c0141a", "#efe2c4", "#2f4a6a"))
        title = _text_ink(["NIGHT", "FERRY"], w, h, top=4)
        foot = _text_ink(["SOON"], w, 8, top=1)

        def px(x, y):
            if title(x, y):
                return cream
            if y < 8 and foot(x, y):
                return red
            # a ferry's lit windows across dark water, a moon
            if (x - 30) ** 2 + (y - 36) ** 2 < 12:
                return cream
            if 18 <= y <= 21 and 6 <= x <= 34:
                return red if y == 18 else (cream if x % 3 == 0 and y == 20 else dark)
            if y < 18 and (x + y * 3) % 9 == 0:
                return dark
            return bg
    return C.make_image("dc_poster_" + kind, w, h, px)


def poster(kind):
    """0.5 x 0.7 m poster, blu-tacked flat to the wall, back on y=0 facing
    -Y, origin at the middle. kinds: band, surf, map, film. The map comes in
    a thin timber frame."""
    mat = _img_mat("poster_" + kind, _img_poster(kind), 0.9)
    if kind == "map":
        oak = _m("FrameOak", "#a77d50", 0.6)
        parts = [F.bx((-PW / 2 - 0.025, -0.02, -PH / 2 - 0.025), (PW / 2 + 0.025, 0.0, PH / 2 + 0.025), oak),
                 _quad(mat, PW, PH, y=-0.0205),
                 _quad(_m("FrameGlass", "#dfe8ea", 0.05, 0.1, alpha=0.12), PW, PH, y=-0.022)]
        return parts, {}
    parts = [F.bx((-PW / 2, -0.002, -PH / 2), (PW / 2, 0.0, PH / 2), _m("PosterBack", "#e8e2d2", 0.9)),
             _quad(mat, PW, PH, y=-0.0022)]
    # one corner come unstuck and curling off the wall
    corner = C.mesh_obj("curl", [(PW / 2 - 0.06, -0.0024, PH / 2), (PW / 2, -0.0024, PH / 2 - 0.06),
                                 (PW / 2 - 0.02, -0.03, PH / 2 - 0.02)], [(0, 1, 2)], _m("PosterBack", "#e8e2d2", 0.9))
    parts.append(corner)
    return parts, {}


# ------------------------------------------------------------------ plants

def _leaf(base, tip, width, mat, split=False):
    """A flat leaf from base to tip, cupped slightly; optionally with the
    monstera's side splits as gaps."""
    base, tip = Vector(base), Vector(tip)
    axis = tip - base
    side = axis.cross(Vector((0, 0, 1)))
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    side.normalize()
    up = side.cross(axis).normalized()
    n = 6
    verts, faces = [], []
    for i in range(n + 1):
        t = i / n
        wdt = width * math.sin(math.pi * min(1.0, t * 1.05)) * (1.0 if t < 0.85 else (1 - t) / 0.15 * 0.9 + 0.1)
        p = base + axis * t
        cup = up * (wdt * 0.15)
        verts += [tuple(p - side * wdt + cup), tuple(p), tuple(p + side * wdt + cup)]
    for i in range(n):
        a = i * 3
        if split and i in (2, 4):
            faces.append((a + 1, a + 4, a + 5, a + 2))       # one side only: a split
            continue
        faces += [(a, a + 3, a + 4, a + 1), (a + 1, a + 4, a + 5, a + 2)]
    o = C.mesh_obj("leaf", verts, faces, mat)
    mat.use_backface_culling = False
    return o


def plant(kind):
    """plant_monstera (big split leaves on long stems, 1.1 m), plant_fiddle
    (fiddle-leaf fig, a 1.6 m stem of paddle leaves), plant_cactus (a
    columnar cactus with three arms, 1.3 m). Each in its own pot; origin
    at the pot base."""
    rnd = random.Random({"monstera": 5, "fiddle": 7, "cactus": 9}[kind])
    if kind == "cactus":
        pot = _m("PotTerracotta", "#b8643e", 0.85)
        parts = [C.cylinder("pot", 0.17, 0.28, segs=12, loc=(0, 0, 0.14), material=pot, r_top=0.2),
                 C.cylinder("rim", 0.205, 0.05, segs=12, loc=(0, 0, 0.28), material=pot),
                 C.cylinder("soil", 0.19, 0.02, segs=12, loc=(0, 0, 0.29), material=F.M("soil"))]
        green = _m("Cactus", "#4f7a45", 0.7)
        ribs = _m("CactusRib", "#3c6236", 0.7)

        def column(x, y, z0, z1, r):
            parts.append(C.cylinder("col", r, z1 - z0, segs=8, loc=(x, y, (z0 + z1) / 2), material=green))
            parts.append(C.sphere("cap", r, (x, y, z1), green, segs=8, rings=4, scale=(1, 1, 0.8)))
            for k in range(4):
                a = k * math.pi / 4
                parts.append(F.bx((x + math.cos(a) * r - 0.004, y + math.sin(a) * r - 0.004, z0 + 0.02),
                                  (x + math.cos(a) * r + 0.004, y + math.sin(a) * r + 0.004, z1 - 0.02), ribs))
        column(0, 0, 0.29, 1.25, 0.075)
        for (a, z, ln, up) in ((0.3, 0.6, 0.16, 0.32), (2.8, 0.75, 0.14, 0.28), (4.6, 0.5, 0.12, 0.22)):
            dx, dy = math.cos(a), math.sin(a)
            parts.append(CB._between("arm", (dx * 0.06, dy * 0.06, z), (dx * ln, dy * ln, z), 0.05, green, segs=8))
            column(dx * ln, dy * ln, z, z + up, 0.05)
        # a small flower on top
        parts.append(C.sphere("flower", 0.03, (0.0, 0.0, 1.3), _m("CactusFlower", "#e8608a", 0.6), segs=6, rings=3))
        return parts, {}
    pot = _m("PotCream", "#e9e4da", 0.5) if kind == "monstera" else _m("PotCharcoal", "#3a3836", 0.6)
    parts = [C.cylinder("pot", 0.19, 0.34, segs=14, loc=(0, 0, 0.17), material=pot, r_top=0.21),
             C.cylinder("soil", 0.2, 0.02, segs=14, loc=(0, 0, 0.33), material=F.M("soil"))]
    if kind == "monstera":
        stem = _m("Stem", "#5e7f3a", 0.8)
        leaf = _m("Monstera", "#2f5a2a", 0.6)
        for i in range(9):
            a = i * 2.4 + rnd.uniform(-0.2, 0.2)
            ln = rnd.uniform(0.35, 0.6)
            h = 0.34 + rnd.uniform(0.45, 0.8)
            tip = Vector((math.cos(a) * ln, math.sin(a) * ln, h))
            parts.append(CB._between("stem", (0, 0, 0.34), tip, 0.008, stem, segs=5))
            out = Vector((math.cos(a), math.sin(a), 0)) * 0.32 + Vector((0, 0, -0.12))
            parts.append(_leaf(tip, tip + out, rnd.uniform(0.13, 0.17), leaf, split=True))
        return parts, {}
    # fiddle-leaf fig
    trunk = _m("FigTrunk", "#7a6a52", 0.8)
    leaf = _m("FiddleLeaf", "#3c6a32", 0.5)
    parts.append(CB._between("trunk", (0, 0, 0.33), (0.03, 0.02, 1.55), 0.022, trunk, segs=6, r_top=0.012))
    for i in range(16):
        z = 0.75 + i * 0.055
        a = i * 2.2
        base = Vector((0.03 * (z - 0.33) / 1.22, 0.02 * (z - 0.33) / 1.22, z))
        out = Vector((math.cos(a), math.sin(a), 0.35 + rnd.uniform(-0.1, 0.25)))
        parts.append(_leaf(base, base + out.normalized() * rnd.uniform(0.24, 0.32), rnd.uniform(0.09, 0.12), leaf))
    return parts, {}


# ------------------------------------------------------------------ chairs

def _img_rattan():
    def px(x, y):
        on = ((x // 2) + (y // 2)) % 2 == 0
        k = 1.0 if on else 0.8
        if x % 2 == 0 and y % 2 == 0:
            k *= 0.88
        return TX.mul((0.78, 0.6, 0.36), k)
    return C.make_image("dc_rattan", 16, 16, px)


def chair(kind):
    """chair_rattan (a round bucket chair on a hoop base with a cushion),
    chair_velvet (a mustard velvet tub chair on short legs),
    chair_eames_style (a moulded-ply lounge chair with leather cushions on a
    swivel star base; generic, no brand). Facing -Y, origin at the floor."""
    if kind == "rattan":
        cane = _img_mat("rattan", _img_rattan(), 0.8)
        cushion = _m("RattanCushion", "#d9cdb5", 0.95)
        parts = []
        # hoop base
        for i in range(12):
            a0, a1 = 2 * math.pi * i / 12, 2 * math.pi * (i + 1) / 12
            parts.append(CB._between("hoop", (0.3 * math.cos(a0), 0.3 * math.sin(a0), 0.02),
                                     (0.3 * math.cos(a1), 0.3 * math.sin(a1), 0.02), 0.014, cane, segs=5))
        for k in range(4):
            a = k * math.pi / 2 + math.pi / 4
            parts.append(CB._between("post", (0.3 * math.cos(a), 0.3 * math.sin(a), 0.02),
                                     (0.12 * math.cos(a), 0.12 * math.sin(a), 0.36), 0.014, cane, segs=5))
        # bucket: a half bowl open to the front
        bowl = C.sphere("bowl", 0.48, (0, 0.04, 0.68), cane, segs=16, rings=8, scale=(1.0, 0.95, 0.85))
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(bowl.data)
        cut = [v for v in bm.verts if v.co.y < -0.08 and v.co.z > -0.18]
        bmesh.ops.delete(bm, geom=cut, context="VERTS")
        bm.to_mesh(bowl.data)
        bm.free()
        C.box_uv(bowl, 4.0)
        bowl.data.materials.clear()
        bowl.data.materials.append(cane)
        cane.use_backface_culling = False
        parts.append(bowl)
        parts.append(C.cylinder("seat", 0.36, 0.1, segs=14, loc=(0, 0.0, 0.44), material=cushion))
        parts.append(C.sphere("back_cushion", 0.3, (0, 0.24, 0.72), cushion, segs=12, rings=6, scale=(1.0, 0.3, 0.8)))
        return parts, {}
    if kind == "velvet":
        velvet = _m("Velvet", "#c08a2a", 0.55)
        piping = _m("VelvetPiping", "#9a6c1e", 0.6)
        brass = F.M("brass")
        parts = []
        # tub: one curved padded wall round the back, dipping to the arms
        n = 14
        verts = []
        for i in range(n + 1):
            a = math.radians(-25 + i * 230 / n)
            top = 0.8 - 0.2 * abs(math.cos(a)) ** 3
            for r in (0.38, 0.29):
                x, y = r * math.cos(a), r * 0.85 * math.sin(a) + 0.04
                verts += [(x, y, 0.36), (x, y, top)]
        faces = []
        for i in range(n):
            o0, o1 = 4 * i, 4 * (i + 1)
            faces += [(o0, o1, o1 + 1, o0 + 1),                  # outside
                      (o0 + 2, o0 + 3, o1 + 3, o1 + 2),          # inside
                      (o0 + 1, o1 + 1, o1 + 3, o0 + 3)]          # top
        faces += [(0, 1, 3, 2), (4 * n, 4 * n + 2, 4 * n + 3, 4 * n + 1)]
        tub = C.mesh_obj("tub", verts, faces, velvet)
        for p in tub.data.polygons:
            p.use_smooth = True
        parts.append(tub)
        # the piped top roll
        for i in range(n):
            a0, a1 = (math.radians(-25 + k * 230 / n) for k in (i, i + 1))
            t0, t1 = (0.8 - 0.2 * abs(math.cos(a)) ** 3 for a in (a0, a1))
            parts.append(CB._between("roll", (0.335 * math.cos(a0), 0.335 * 0.85 * math.sin(a0) + 0.04, t0),
                                     (0.335 * math.cos(a1), 0.335 * 0.85 * math.sin(a1) + 0.04, t1), 0.05, velvet,
                                     segs=8))
            parts.append(C.sphere("knuckle", 0.05, (0.335 * math.cos(a0), 0.335 * 0.85 * math.sin(a0) + 0.04, t0), velvet,
                                  segs=8, rings=4))
        parts.append(C.cylinder("base", 0.38, 0.22, segs=16, loc=(0, 0.02, 0.27), material=velvet))
        parts.append(C.cylinder("seat", 0.33, 0.1, segs=16, loc=(0, -0.02, 0.43), material=velvet))
        parts.append(C.cylinder("pipe", 0.335, 0.012, segs=16, loc=(0, -0.02, 0.48), material=piping))
        for k in range(4):
            a = math.radians(45 + k * 90)
            parts.append(CB._between("leg", (0.26 * math.cos(a), 0.26 * math.sin(a), 0.16),
                                     (0.3 * math.cos(a), 0.3 * math.sin(a), 0.0), 0.018, brass, segs=6, r_top=0.012))
        return parts, {}
    # moulded-ply lounge chair, generic
    ply = _m("Rosewood", "#4a2a1a", 0.35)
    leather = _m("Leather", "#1a1716", 0.5)
    alu = _m("StarAlu", "#2a2a2c", 0.3, 0.7)
    parts = []
    # swivel star base
    parts.append(C.cylinder("column", 0.03, 0.22, segs=8, loc=(0, 0.05, 0.13), material=alu))
    for k in range(5):
        a = math.radians(90 + k * 72)
        parts.append(CB._between("star", (0, 0.05, 0.03), (0.32 * math.cos(a), 0.05 + 0.32 * math.sin(a), 0.03), 0.02,
                                 alu, segs=6))
        parts.append(C.cylinder("glide", 0.02, 0.02, segs=6, loc=(0.32 * math.cos(a), 0.05 + 0.32 * math.sin(a), 0.01),
                                material=alu))
    # seat shell and cushion, tilted back
    tilt = math.radians(10)
    seat = [CB._rbox("seat_shell", (-0.38, -0.36, 0.0), (0.38, 0.28, 0.04), ply, 0.08),
            CB._rbox("seat_cush", (-0.34, -0.34, 0.04), (0.34, 0.26, 0.15), leather, 0.07)]
    for o in seat:
        C.apply_transform(o)            # bake the box's own centre first
        o.rotation_euler = (tilt, 0, 0)
        o.location = (0, 0.05, 0.25)
        C.apply_transform(o)
    parts += seat
    # back shell in two panels, leaning back
    lean = math.radians(-24)
    back = [CB._rbox("back_shell", (-0.38, 0.0, 0.0), (0.38, 0.04, 0.36), ply, 0.08),
            CB._rbox("back_cush", (-0.34, -0.1, 0.03), (0.34, 0.0, 0.34), leather, 0.07),
            CB._rbox("head_shell", (-0.36, 0.0, 0.38), (0.36, 0.04, 0.66), ply, 0.08),
            CB._rbox("head_cush", (-0.32, -0.1, 0.41), (0.32, 0.0, 0.64), leather, 0.07)]
    for o in back:
        C.apply_transform(o)            # bake the box's own centre first
        o.rotation_euler = (lean, 0, 0)
        o.location = (0, 0.36, 0.33)
        C.apply_transform(o)
    parts += back
    # armrests on the side of the back
    for sx in (-1, 1):
        parts.append(CB._rbox("arm", (sx * 0.4 - 0.05, -0.2, 0.5), (sx * 0.4 + 0.05, 0.32, 0.55), leather, 0.02))
        parts.append(F.bx((sx * 0.4 - 0.012, 0.25, 0.3), (sx * 0.4 + 0.012, 0.3, 0.52), alu))
    return parts, {}


RUGS = ("jute", "persian", "retro")
LAMPS = ("arc", "paper", "tripod")
POSTERS = ("band", "surf", "map", "film")
PLANTS = ("monstera", "fiddle", "cactus")
CHAIRS = ("rattan", "velvet", "eames_style")
