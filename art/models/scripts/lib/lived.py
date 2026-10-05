"""Small lived-in things for the townhouse: what's left on the benches, the
bedside tables and the floor, plus switches, power points and smoke alarms.

Same conventions as furniture.py: each function returns parts built about
the item's own origin (on the surface it sits on, or on the wall plane for
wall-mounted pieces), front toward -Y, for build_shenton's it() to place.
"""
import math
import random

from mathutils import Matrix, Vector

from . import common as C
from .furniture import M, bx, cyl


def _m(name, col, rough=0.7, metal=0.0):
    return C.mat("L_" + name, col, rough=rough, metal=metal)


def _turn(parts, deg, axis="Z", about=(0, 0, 0)):
    m = (Matrix.Translation(Vector(about)) @ Matrix.Rotation(math.radians(deg), 4, axis)
         @ Matrix.Translation(-Vector(about)))
    for p in parts:
        C.apply_transform(p)
        p.data.transform(m)
    return parts


# ------------------------------------------------------------------ walls

def switch_plate(gangs=1):
    """Light switch on the wall plane y=0, plate centre at the origin."""
    w = 0.075 if gangs == 1 else 0.115
    parts = [bx((-w / 2, -0.008, -0.058), (w / 2, 0.0, 0.058), M("white"))]
    for i in range(gangs):
        x = 0 if gangs == 1 else (-0.025 if i == 0 else 0.025)
        parts.append(bx((x - 0.009, -0.013, -0.016), (x + 0.009, -0.008, 0.016), _m("rocker", "#f7f5ef", 0.4)))
    return parts


def power_point():
    """Double power point (Australian, angled pins) on the wall plane y=0."""
    parts = [bx((-0.06, -0.008, -0.036), (0.06, 0.0, 0.036), M("white"))]
    slot = _m("slot", "#2a2a2a", 0.6)
    for sx in (-0.03, 0.03):
        for dx, lean in ((-0.008, 1), (0.008, -1)):
            s = bx((-0.0015, -0.0085, -0.005), (0.0015, -0.008, 0.005), slot)
            _turn([s], 30 * lean, "Y")
            s.location = (sx + dx, 0, 0.006)
            C.apply_transform(s)
            parts.append(s)
        parts.append(bx((sx - 0.0015, -0.0085, -0.014), (sx + 0.0015, -0.008, -0.006), slot))
        parts.append(bx((sx + 0.016, -0.011, -0.006), (sx + 0.024, -0.008, 0.006), _m("rocker", "#f7f5ef", 0.4)))
    return parts


def smoke_alarm():
    """Ceiling smoke alarm, origin on the ceiling (hangs down from z=0)."""
    return [cyl(0.065, 0.03, (0, 0, -0.015), M("white"), 12),
            cyl(0.04, 0.008, (0, 0, -0.034), _m("alarm_grille", "#dcdad4", 0.6), 10),
            C.sphere("led", 0.004, (0.045, 0, -0.031), C.mat("L_led_red", "#ff2a1a", emit="#ff2a1a",
                                                              emit_strength=2.0), segs=4, rings=3)]


def art_print(w, h, colors, seed=0):
    """Framed print on the wall plane y=0: thin black frame, a cream mat and
    a simple abstract of stacked bands (sea, dunes and sky, more or less)."""
    rnd = random.Random(seed)
    parts = [bx((-w / 2, -0.022, -h / 2), (w / 2, 0.0, h / 2), M("frame")),
             bx((-w / 2 + 0.025, -0.0225, -h / 2 + 0.025), (w / 2 - 0.025, -0.022, h / 2 - 0.025), M("paper"))]
    iw, ih = w / 2 - 0.07, h / 2 - 0.07
    z = -ih
    for i, col in enumerate(colors):
        band = (2 * ih) / len(colors) * (0.7 + 0.6 * rnd.random()) if i < len(colors) - 1 else ih - z
        top = min(z + band, ih)
        parts.append(bx((-iw, -0.0232, z), (iw, -0.0225, top), _m("print_%d_%d" % (seed, i), col, 0.9)))
        z = top
        if z >= ih:
            break
    # a sun or a moon, off centre
    parts.append(cyl(min(iw, ih) * 0.22, 0.001, (iw * 0.45, -0.0237, ih * 0.5), _m("print_sun_%d" % seed,
                                                                                  colors[-1] if seed % 2 else "#f2e2b0", 0.9),
                     10, axis="Y"))
    return parts


# ------------------------------------------------------------------ kitchen

def toaster():
    body = _m("toaster", "#b8c4c2", 0.35, 0.3)
    return [bx((-0.13, -0.08, 0.0), (0.13, 0.08, 0.19), body),
            bx((-0.1, -0.035, 0.19), (0.1, -0.012, 0.192), M("black")),
            bx((-0.1, 0.012, 0.19), (0.1, 0.035, 0.192), M("black")),
            bx((0.13, -0.012, 0.07), (0.145, 0.012, 0.15), M("black")),
            bx((-0.12, -0.085, 0.0), (0.12, 0.085, 0.015), M("black"))]


def knife_block():
    wood = M("wood_mid")
    parts = [_turn([bx((-0.05, -0.07, 0), (0.05, 0.07, 0.2), wood)], -18, "X", (0, 0.07, 0))[0]]
    for i, x in enumerate((-0.028, 0.0, 0.028)):
        h = (0.05, 0.065, 0.045)[i]
        k = cyl(0.009, h, (x, -0.02, 0.2 + h / 2), M("black"), 6)
        _turn([k], -18, "X", (0, 0.07, 0))
        parts.append(k)
    return parts


def chopping_board():
    """Leaning against the splashback (y=0 is the wall), on the bench."""
    b = bx((-0.18, -0.018, 0.0), (0.18, 0.0, 0.42), M("wood_light"))
    hole = cyl(0.02, 0.0005, (0.0, -0.0185, 0.37), M("wood_dark"), 8, axis="Y")
    return _turn([b, hole], 10, "X", (0, 0, 0))


def utensil_crock():
    parts = [cyl(0.06, 0.15, (0, 0, 0.075), _m("crock", "#2f5b6e", 0.4), 10, r_top=0.055)]
    for i, (dx, dy, h) in enumerate(((-0.02, 0.0, 0.16), (0.02, 0.015, 0.14), (0.0, -0.02, 0.18))):
        u = cyl(0.007, h, (dx, dy, 0.15 + h / 2 - 0.05), M("wood_light") if i != 1 else M("black"), 5)
        _turn([u], (8, -10, 5)[i], "Y", (dx, dy, 0.1))
        parts.append(u)
    return parts


def canisters():
    glass = C.mat("L_jar_glass", "#d8e2df", rough=0.1, alpha=0.45)
    parts = []
    fills = (("#e9e1cc", 0.12), ("#6b4a2b", 0.08), ("#d9c08a", 0.1))
    for i, (col, fill) in enumerate(fills):
        x = -0.11 + i * 0.11
        h = (0.2, 0.15, 0.17)[i]
        parts.append(cyl(0.048, fill, (x, 0, fill / 2), _m("jar_fill_%d" % i, col, 0.9), 10))
        parts.append(cyl(0.05, h, (x, 0, h / 2), glass, 10))
        parts.append(cyl(0.052, 0.02, (x, 0, h + 0.01), M("wood_light"), 10))
    return parts


def fruit_bowl(seed=4):
    rnd = random.Random(seed)
    parts = [cyl(0.09, 0.07, (0, 0, 0.035), _m("bowl", "#e6d8b8", 0.5), 12, r_top=0.15)]
    fruit = (("#d9822b", 0.04), ("#c6302a", 0.038), ("#e8c840", 0.035), ("#d9822b", 0.04), ("#7aa83a", 0.037))
    for i, (col, r) in enumerate(fruit):
        a = i / len(fruit) * math.tau + rnd.random() * 0.3
        d = 0.06 if i < 4 else 0.0
        z = 0.075 if i < 4 else 0.12
        parts.append(C.sphere("fruit", r, (math.cos(a) * d, math.sin(a) * d, z), _m("fruit_%d" % i, col, 0.5),
                              segs=8, rings=5))
    # a banana bunch across the top
    for k in range(3):
        b = cyl(0.016, 0.17, (0, 0, 0), _m("banana", "#e7c84a", 0.6), 6, axis="X")
        _turn([b], 25 * (k - 1), "Z")
        b.location = (0.0, -0.02 + k * 0.02, 0.15)
        C.apply_transform(b)
        parts.append(b)
    return parts


def dish_soap():
    return [cyl(0.03, 0.17, (0, 0, 0.085), _m("soap_green", "#5fae6a", 0.2), 8),
            cyl(0.012, 0.03, (0, 0, 0.185), M("white"), 6),
            bx((0.05, -0.035, 0), (0.13, 0.035, 0.035), _m("sponge", "#e8d24a", 1.0)),
            bx((0.05, -0.035, 0.035), (0.13, 0.035, 0.045), _m("scourer", "#3a7a3a", 1.0))]


def tea_towel():
    """Hung over the oven handle: origin on the handle line, front at -Y."""
    cloth = _m("tea_towel", "#e7e1d2", 1.0)
    stripe = _m("tea_towel_stripe", "#3b5b8a", 1.0)
    return [bx((-0.12, -0.012, -0.32), (0.12, -0.004, 0.0), cloth),
            bx((-0.12, 0.004, -0.12), (0.12, 0.012, 0.0), cloth),
            bx((-0.12, -0.0126, -0.29), (0.12, -0.012, -0.27), stripe),
            bx((-0.12, -0.0126, -0.25), (0.12, -0.012, -0.24), stripe)]


# ------------------------------------------------------------------ lounge

def tv_remote():
    return [bx((-0.022, -0.085, 0), (0.022, 0.085, 0.016), M("black")),
            bx((-0.01, -0.07, 0.016), (0.01, -0.055, 0.018), _m("btn_red", "#b02020", 0.5))]


def mug(color="#2f6f6c"):
    return [cyl(0.042, 0.095, (0, 0, 0.0475), _m("mug_" + color[1:], color, 0.4), 10),
            cyl(0.036, 0.004, (0, 0, 0.083), _m("tea", "#7a4a26", 0.2), 10),
            bx((0.042, -0.006, 0.02), (0.062, 0.006, 0.075), _m("mug_" + color[1:], color, 0.4))]


def folded_throw():
    return [bx((-0.32, -0.22, 0), (0.32, 0.22, 0.05), M("throw")),
            bx((-0.32, -0.22, 0.05), (0.32, -0.2, 0.06), _m("throw_fringe", "#e2d3b5", 1.0))]


# ------------------------------------------------------------------ bedroom

def alarm_clock():
    return [bx((-0.06, -0.025, 0), (0.06, 0.025, 0.07), M("black")),
            bx((-0.045, -0.0255, 0.015), (0.045, -0.025, 0.055),
               C.mat("L_clock_digits", "#ff5a2a", emit="#ff5a2a", emit_strength=1.5))]


def water_glass():
    glass = C.mat("L_glass", "#dfe9ea", rough=0.05, alpha=0.35)
    return [cyl(0.03, 0.06, (0, 0, 0.03), _m("water", "#c8dde0", 0.05), 10),
            cyl(0.032, 0.11, (0, 0, 0.055), glass, 10)]


def phone():
    return [bx((-0.036, -0.075, 0), (0.036, 0.075, 0.008), M("black")),
            bx((-0.032, -0.07, 0.008), (0.032, 0.07, 0.0085), M("screen"))]


def slippers():
    felt = _m("slipper", "#8a8f99", 1.0)
    parts = []
    for sx, a in ((-0.06, 8), (0.07, -4)):
        s = [bx((-0.045, -0.13, 0), (0.045, 0.13, 0.03), felt),
             bx((-0.045, -0.13, 0.03), (0.045, -0.02, 0.06), felt)]
        _turn(s, a)
        for p in s:
            p.location.x += sx
            C.apply_transform(p)
        parts += s
    return parts


def laundry_basket():
    weave = _m("basket_weave", "#c8b48a", 1.0)
    parts = [cyl(0.2, 0.5, (0, 0, 0.25), weave, 12, r_top=0.22)]
    for z in (0.12, 0.25, 0.38):
        parts.append(cyl(0.2 + z * 0.04 + 0.003, 0.015, (0, 0, z), _m("basket_band", "#a8925f", 1.0), 12))
    # clothes heaped over the rim
    for i, (col, dx, dy) in enumerate((("#3b4d6b", -0.05, 0.02), ("#e8e4da", 0.06, -0.04), ("#8e3b2e", 0.0, 0.08))):
        parts.append(C.sphere("cloth", 0.13, (dx, dy, 0.5), _m("cloth_%d" % i, col, 1.0), segs=8, rings=4,
                              scale=(1.0, 0.8, 0.35)))
    return parts


def chair_with_clothes():
    """A bentwood chair with a jumper over the back and jeans on the seat."""
    wood = M("wood_dark")
    parts = [bx((-0.21, -0.2, 0.43), (0.21, 0.2, 0.47), wood)]
    for sx in (-0.18, 0.18):
        for sy in (-0.17, 0.17):
            parts.append(cyl(0.015, 0.43, (sx, sy, 0.215), wood, 6))
        parts.append(cyl(0.015, 0.45, (sx, 0.18, 0.69), wood, 6))
    parts.append(bx((-0.2, 0.16, 0.8), (0.2, 0.2, 0.9), wood))
    jumper = _m("jumper", "#b8862e", 1.0)
    parts.append(bx((-0.22, 0.13, 0.62), (0.22, 0.23, 0.93), jumper))
    parts.append(bx((-0.24, 0.12, 0.55), (-0.16, 0.24, 0.9), jumper))
    jeans = _m("jeans", "#3a4f74", 1.0)
    parts.append(bx((-0.17, -0.16, 0.47), (0.15, 0.1, 0.52), jeans))
    parts.append(bx((-0.17, -0.22, 0.25), (-0.05, -0.16, 0.52), jeans))
    return parts


# ------------------------------------------------------------------ bathroom

def toothbrush_cup():
    parts = [cyl(0.032, 0.1, (0, 0, 0.05), _m("cup_white", "#eceae4", 0.3), 10)]
    for i, (dx, col, lean) in enumerate(((-0.01, "#3a7ad0", 10), (0.012, "#e05a5a", -12))):
        b = cyl(0.005, 0.19, (dx, 0, 0.13), _m("brush_%d" % i, col, 0.4), 5)
        _turn([b], lean, "Y", (dx, 0, 0.05))
        parts.append(b)
    return parts


def soap_pump():
    return [cyl(0.032, 0.14, (0, 0, 0.07), _m("soap_amber", "#b8742c", 0.15), 10),
            cyl(0.008, 0.03, (0, 0, 0.155), M("white"), 6),
            bx((-0.004, -0.035, 0.165), (0.004, 0.0, 0.175), M("white"))]


def bath_mat():
    return [bx((-0.3, -0.2, 0), (0.3, 0.2, 0.012), _m("bath_mat", "#9fb7b0", 1.0))]


def bath_bottles():
    parts = []
    for i, (col, h, r) in enumerate((("#f0e8d8", 0.2, 0.03), ("#3d6e8e", 0.17, 0.028), ("#e2b6c4", 0.13, 0.025))):
        x = i * 0.065
        parts.append(cyl(r, h, (x, 0, h / 2), _m("bottle_%d" % i, col, 0.3), 8))
        parts.append(cyl(r * 0.7, 0.025, (x, 0, h + 0.0125), M("white"), 8))
    return parts


def bathroom_scale():
    return [bx((-0.15, -0.15, 0), (0.15, 0.15, 0.025), _m("scale", "#e8e8e6", 0.3)),
            bx((-0.04, -0.12, 0.025), (0.04, -0.09, 0.027), M("screen"))]


# ------------------------------------------------------------------ studio

def mic_stand():
    metal = M("black")
    parts = []
    for a in (0, 120, 240):
        leg = bx((0, -0.01, 0.0), (0.26, 0.01, 0.02), metal)
        _turn([leg], a)
        parts.append(leg)
    parts.append(cyl(0.012, 1.1, (0, 0, 0.55), metal, 6))
    boom = cyl(0.008, 0.6, (0, 0, 0), metal, 6, axis="Y")
    boom.location = (0, -0.2, 1.15)
    C.apply_transform(boom)
    _turn([boom], -20, "X", (0, 0, 1.1))
    parts.append(boom)
    mic = cyl(0.022, 0.16, (0, -0.48, 1.07), _m("mic_grey", "#5a5a5a", 0.35, 0.6), 8, axis="Y")
    _turn([mic], -20, "X", (0, 0, 1.1))
    parts.append(mic)
    return parts


def beanbag():
    vinyl = _m("beanbag", "#6f4a3a", 0.9)
    return [C.sphere("bag", 0.42, (0, 0, 0.26), vinyl, segs=12, rings=6, scale=(1.0, 1.0, 0.62)),
            C.sphere("dent", 0.26, (0, -0.06, 0.48), vinyl, segs=10, rings=5, scale=(1.0, 0.9, 0.35))]


def headphones():
    """Lying flat, ear cups down."""
    pad = M("black")
    parts = [cyl(0.045, 0.035, (sx, 0, 0.0175), pad, 10) for sx in (-0.085, 0.085)]
    band = []
    n = 7
    for i in range(n):
        a0, a1 = math.pi * i / n, math.pi * (i + 1) / n
        p0 = Vector((-math.cos(a0) * 0.085, math.sin(a0) * 0.09, 0.03))
        p1 = Vector((-math.cos(a1) * 0.085, math.sin(a1) * 0.09, 0.03))
        mid, d = (p0 + p1) / 2, p1 - p0
        b = bx((-d.length / 2, -0.008, -0.004), (d.length / 2, 0.008, 0.004), _m("band", "#303030", 0.6))
        b.rotation_euler = (0, 0, math.atan2(d.y, d.x))
        b.location = mid
        C.apply_transform(b)
        band.append(b)
    return parts + band


def cable(points, r=0.004):
    """A cable along floor points (x, y), lying at z=r."""
    parts = []
    for a, b in zip(points, points[1:]):
        a, b = Vector((a[0], a[1], r)), Vector((b[0], b[1], r))
        d = b - a
        c = cyl(r, d.length, (0, 0, 0), M("black"), 4, axis="X")
        c.rotation_euler = (0, 0, math.atan2(d.y, d.x))
        c.location = (a + b) / 2
        C.apply_transform(c)
        parts.append(c)
    return parts


# ------------------------------------------------------------------ the mystery

def back_door_hook():
    """Three brass coat hooks on a jarrah board (wall plane y=0). The one on
    the left is worn bright: that's where the binoculars hung."""
    parts = [bx((-0.24, -0.02, -0.05), (0.24, 0.0, 0.05), M("wood_dark"))]
    for i, x in enumerate((-0.15, 0.0, 0.15)):
        brass = M("brass") if i else _m("brass_worn", "#e2c070", 0.2, 0.9)
        parts.append(cyl(0.008, 0.06, (x, -0.05, 0.0), brass, 6, axis="Y"))
        parts.append(cyl(0.008, 0.035, (x, -0.08, 0.017), brass, 6))
        parts.append(cyl(0.016, 0.006, (x, -0.023, 0.0), brass, 8, axis="Y"))
    return parts
