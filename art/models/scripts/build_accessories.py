"""Accessories that bolt onto the cars, one glb each in
art/models/cars/parts/ (origin at the car's mount empty, front toward -Z):

  roofrack_<kind>_<roof>.glb  at Mount_Roof. kind: plain (bare bars),
                         luggage (a suitcase and a tarp bundle strapped on),
                         bike (an old road bike in a wheel tray), surf (a
                         mini-mal). roof: modern (the 2007-on hatch and
                         Abarths) or classic (Nuova-style and Giardiniera);
                         the feet are set to each roof's curve. Each has a
                         Mount_Rod empty where the fishing rod lies: its butt
                         at the empty, the rod running forward along -Z.
                         Not for the 500C, the Jolly or anything without a
                         solid roof.
  roofrack_surf.glb      the modern surf rack under its old name
  spotlights_period.glb  a pair of round 1960s driving lamps on a bar,
                         at Mount_Spotlights

    python3.11 art/models/scripts/build_accessories.py [--render]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401
from mathutils import Vector  # noqa: E402

from lib import carkit as K  # noqa: E402
from lib import common as C  # noqa: E402

PARTS = "art/models/cars/parts/"


# Feet and bars for each roof, relative to Mount_Roof (roof centre): foot
# x, front and rear y, the roof's height under each foot, bar height, and
# where the rod's butt sits. Measured with raycasts on the pop and lounge
# (modern) and the nuova, 500 L and giardiniera (classic); classic feet take
# the highest of those so none sinks in (the rest sit a few mm proud).
ROOFS = {
    "modern": dict(fx=0.50, fy=(-0.42, 0.42), fz=(-0.029, -0.027), bar=0.06, bar_len=1.12, rod=(0.36, 0.75)),
    "classic": dict(fx=0.40, fy=(-0.20, 0.20), fz=(-0.019, -0.021), bar=0.05, bar_len=0.92, rod=(0.38, 0.55)),
}


def _mats():
    return {
        "chrome": C.mat("Chrome", "#d8dadc", rough=0.2, metal=0.9),
        "rubber": C.mat("RackRubber", "#1c1c1d", rough=0.9),
        "strap": C.mat("Strap", "#c4372b", rough=0.9),
    }


def _rack(roof):
    """Two chrome bars on four rubber-footed posts; returns (object, top of
    the bars)."""
    r, M = ROOFS[roof], _mats()
    bits = []
    for y, fz in zip(r["fy"], r["fz"]):
        bits.append(C.cylinder("bar", 0.014, r["bar_len"], segs=8, axis="X", loc=(0, y, r["bar"]), material=M["chrome"]))
        for sx in (-1, 1):
            x = sx * r["fx"]
            bits.append(C.box_minmax("foot", (x - 0.03, y - 0.04, fz + 0.001), (x + 0.03, y + 0.04, fz + 0.02),
                                     M["rubber"]))
            bits.append(C.cylinder("post", 0.011, r["bar"] - fz - 0.02, segs=6,
                                   loc=(x, y, (r["bar"] + fz + 0.02) / 2), material=M["chrome"]))
            bits.append(C.cylinder("cap", 0.017, 0.012, segs=8, axis="X", loc=(sx * (r["bar_len"] / 2), y, r["bar"]),
                                   material=M["rubber"]))
    return C.join(bits, "RoofRack"), r["bar"] + 0.014


def _rod_mount(roof, top, rx=None):
    """Where a fishing rod lies on the bars, along -Z (car forward)."""
    rx = ROOFS[roof]["rod"][0] if rx is None else rx
    ry = ROOFS[roof]["rod"][1]
    C.empty("Mount_Rod", (rx, ry, top + 0.012), size=0.05)


def roofrack_plain(roof):
    rack, top = _rack(roof)
    _rod_mount(roof, top)
    return [rack]


def _strap_over(y, x0, x1, z0, z1, mat):
    """A strap looped over a load from bar to bar height."""
    return [C.box_minmax("strap", (x0 - 0.006, y - 0.02, z0), (x0, y + 0.02, z1), mat),
            C.box_minmax("strap", (x1, y - 0.02, z0), (x1 + 0.006, y + 0.02, z1), mat),
            C.box_minmax("strap", (x0 - 0.006, y - 0.02, z1), (x1 + 0.006, y + 0.02, z1 + 0.006), mat)]


def roofrack_luggage(roof):
    """A brown vinyl suitcase lying flat and a rolled khaki tarp tied with
    rope, strapped across the bars."""
    rack, top = _rack(roof)
    M = _mats()
    r = ROOFS[roof]
    case = C.mat("Suitcase", "#6b4a32", rough=0.6)
    trim = C.mat("SuitcaseTrim", "#2a2420", rough=0.5)
    tarp = C.mat("Tarp", "#7d7a52", rough=1.0)
    rope = C.mat("Rope", "#d8c79a", rough=1.0)
    mod = roof == "modern"
    cw, cd, ch = (0.62, 0.46, 0.2) if mod else (0.52, 0.40, 0.18)
    cx = -0.14 if mod else -0.1
    cy = (r["fy"][0] + r["fy"][1]) / 2
    tl, tr_ = (0.5, 0.1) if mod else (0.4, 0.085)
    tx = cx + cw / 2 + 0.03 + tr_
    # three timber slats laid bar to bar carry the load (the bars are
    # further apart than the case is deep)
    wood = C.mat("Slat", "#8a6a48", rough=0.9)
    y0, y1 = r["fy"][0] - 0.05, r["fy"][1] + 0.05
    slats = []
    x_lo, x_hi = cx - cw / 2 + 0.02, tx + tr_ - 0.02
    for i in range(4):
        x = x_lo + (x_hi - x_lo) * i / 3
        slats.append(C.box_minmax("slat", (x - 0.04, y0, top), (x + 0.04, y1, top + 0.014), wood))
    base = top + 0.014
    bits = [C.box_minmax("case", (cx - cw / 2, cy - cd / 2, base), (cx + cw / 2, cy + cd / 2, base + ch), case),
            C.box_minmax("seam", (cx - cw / 2 - 0.003, cy - cd / 2 - 0.003, base + ch * 0.48),
                         (cx + cw / 2 + 0.003, cy + cd / 2 + 0.003, base + ch * 0.56), trim)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            bits.append(C.box_minmax("corner", (cx + sx * cw / 2 - (0.04 if sx > 0 else -0.004),
                                                cy + sy * cd / 2 - (0.04 if sy > 0 else -0.004), base),
                                     (cx + sx * cw / 2 + (0.004 if sx > 0 else 0.04),
                                      cy + sy * cd / 2 + (0.004 if sy > 0 else 0.04), base + ch + 0.003), trim))
    bits.append(C.box_minmax("handle", (cx - 0.07, cy - cd / 2 - 0.025, base + ch * 0.45),
                             (cx + 0.07, cy - cd / 2 - 0.003, base + ch * 0.6), trim))
    case_obj = C.join(bits + slats, "Suitcase")
    # the tarp roll lies fore and aft beside the case
    roll = [C.cylinder("tarp", tr_, tl, segs=10, axis="Y", loc=(tx, cy, base + tr_), material=tarp)]
    for dy in (-tl * 0.3, tl * 0.3):
        roll.append(C.cylinder("rope", tr_ + 0.006, 0.02, segs=10, axis="Y", loc=(tx, cy + dy, base + tr_), material=rope))
    tarp_obj = C.join(roll, "Tarp")
    # two straps run fore and aft over the case, tied off on each bar
    straps = []
    ya, yb = cy - cd / 2, cy + cd / 2
    for x in (cx - cw * 0.28, cx + cw * 0.28):
        lo, hi = top - 0.016, base + ch
        straps += [C.box_minmax("strap", (x - 0.02, ya - 0.006, base), (x + 0.02, ya, hi), M["strap"]),
                   C.box_minmax("strap", (x - 0.02, yb, base), (x + 0.02, yb + 0.006, hi), M["strap"]),
                   C.box_minmax("strap", (x - 0.02, ya - 0.006, hi), (x + 0.02, yb + 0.006, hi + 0.006), M["strap"]),
                   C.box_minmax("strap", (x - 0.02, r["fy"][0] - 0.018, base), (x + 0.02, ya, base + 0.006), M["strap"]),
                   C.box_minmax("strap", (x - 0.02, yb, base), (x + 0.02, r["fy"][1] + 0.018, base + 0.006), M["strap"])]
        for y in r["fy"]:
            straps.append(C.box_minmax("strap", (x - 0.02, y - 0.018, lo), (x + 0.02, y + 0.018, base + 0.006), M["strap"]))
    # outboard of the tarp roll, near the bar ends
    _rod_mount(roof, top, r["bar_len"] / 2 - 0.08)
    return [rack, case_obj, tarp_obj, C.join(straps, "Straps")]


def _wheel(r, x, y, z, rim_mat, tyre_mat, spokes_mat):
    bits = [C.cylinder("tyre", r, 0.025, segs=20, axis="X", loc=(x, y, z), material=tyre_mat),
            C.cylinder("rim", r - 0.02, 0.027, segs=20, axis="X", loc=(x, y, z), material=rim_mat),
            C.cylinder("web", r - 0.03, 0.006, segs=20, axis="X", loc=(x, y, z), material=spokes_mat),
            C.cylinder("hub", 0.025, 0.08, segs=8, axis="X", loc=(x, y, z), material=rim_mat)]
    return bits


def _tube(name, a, b, r, mat):
    a, b = Vector(a), Vector(b)
    d = b - a
    o = C.cylinder(name, r, d.length, segs=6, loc=(0, 0, 0), material=mat)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    o.location = (a + b) / 2
    return o


def roofrack_bike(roof):
    """An old steel road bike, upright in a wheel tray along the car, fork
    clamped at the front: red frame, drop bars, leather saddle."""
    rack, top = _rack(roof)
    chrome = _mats()["chrome"]
    frame = C.mat("BikeFrame", "#a32a24", rough=0.45)
    tyre = C.mat("BikeTyre", "#1a1a1a", rough=0.9)
    spokes = C.mat("BikeSpokes", "#b9bcbf", rough=0.4, metal=0.6, alpha=0.35)
    saddle = C.mat("Saddle", "#5a3a22", rough=0.6)
    tray_mat = C.mat("TrayBlack", "#202022", rough=0.6)
    x = -0.22 if roof == "modern" else -0.18
    R, wb = 0.34, 1.0
    yf, yr = -wb / 2, wb / 2
    tray = [C.box_minmax("tray", (x - 0.03, -0.85, top), (x + 0.03, 0.85, top + 0.03), tray_mat)]
    z = top + 0.02 + R
    bits = _wheel(R, x, yf, z, chrome, tyre, spokes) + _wheel(R, x, yr, z, chrome, tyre, spokes)
    bb = Vector((x, -0.02, z - 0.06))            # bottom bracket
    seat_top = Vector((x, 0.13, z + 0.50))
    head_top = Vector((x, -0.40, z + 0.48))
    head_bot = Vector((x, -0.36, z + 0.33))
    rear = Vector((x, yr, z))
    front = Vector((x, yf, z))
    tubes = [(bb, seat_top), (seat_top, head_top), (bb, head_bot), (head_bot, head_top),
             (bb, rear), (seat_top, rear), (head_bot, front)]
    bits += [_tube("tube", a, b, 0.014, frame) for a, b in tubes]
    bits.append(_tube("post", seat_top, seat_top + Vector((0, 0.03, 0.09)), 0.011, chrome))
    bits.append(C.box_minmax("saddle", (x - 0.035, 0.09, z + 0.6), (x + 0.035, 0.32, z + 0.63), saddle))
    stem = head_top + Vector((0, -0.08, 0.05))
    bits.append(_tube("stem", head_top, stem, 0.011, chrome))
    bits.append(C.cylinder("bars", 0.011, 0.4, segs=6, axis="X", loc=tuple(stem), material=chrome))
    for sx in (-1, 1):
        drop = stem + Vector((sx * 0.2, 0, 0))
        bits.append(_tube("drop", drop, drop + Vector((0, -0.08, -0.06)), 0.011, chrome))
        bits.append(_tube("drop", drop + Vector((0, -0.08, -0.06)), drop + Vector((0, 0.0, -0.13)), 0.011, chrome))
    # the crank and chainring
    bits.append(C.cylinder("ring", 0.1, 0.006, segs=16, axis="X", loc=(x + 0.04, bb.y, bb.z), material=chrome))
    bits.append(_tube("crank", bb + Vector((0.05, 0, 0)), bb + Vector((0.05, 0.1, -0.13)), 0.009, chrome))
    # a clamp arm from the tray up to the down tube
    bits.append(_tube("clamp", Vector((x, -0.1, top + 0.03)), bb + Vector((0, -0.08, 0.08)), 0.012, tray_mat))
    bike = C.join(bits, "Bike")
    _rod_mount(roof, top)
    return [rack, C.join(tray, "Tray"), bike]


def roofrack_surf(roof="modern"):
    """Rack feet stand on the roof either side of the mount, two chrome bars
    across, and a 7'0" board nose-forward (Blender -Y) with its fin up, held
    by two straps."""
    rack, top = _rack(roof)
    board_mat = C.mat("Surfboard", "#efe6cf", rough=0.4)
    stripe = C.mat("SurfStripe", "#2f7f8a", rough=0.4)
    strap = _mats()["strap"]
    base = top + 0.002

    # board: an elongated, slightly rockered ellipse lofted in plan
    length, width, thick = 2.13, 0.56, 0.07
    n = 16
    verts, faces = [], []
    for i in range(n + 1):
        t = i / n                                   # 0 nose .. 1 tail
        y = -length / 2 + t * length
        # widest just behind the middle, pointed nose, rounded square tail
        half = width / 2 * (math.sin(math.pi * min(1.0, t * 1.05)) ** 0.55 if t < 0.95 else 0.55)
        half = max(half, 0.02)
        rocker = 0.06 * (1 - t) ** 3 + 0.02 * t ** 4
        z0 = base + rocker
        for x, z in ((-half, z0 + thick * 0.35), (-half * 0.8, z0 + thick), (half * 0.8, z0 + thick),
                     (half, z0 + thick * 0.35), (half * 0.8, z0), (-half * 0.8, z0)):
            verts.append((x, y, z))
    ring = 6
    for i in range(n):
        for j in range(ring):
            a, b = i * ring + j, i * ring + (j + 1) % ring
            faces.append((a, b, b + ring, a + ring))
    faces.append(tuple(range(ring - 1, -1, -1)))
    faces.append(tuple(n * ring + j for j in range(ring)))
    mesh = bpy.data.meshes.new("Surfboard")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    board = bpy.data.objects.new("Surfboard", mesh)
    C.link(board)
    board.data.materials.append(board_mat)
    stripe_bar = C.box_minmax("stringer", (-0.006, -length / 2 + 0.12, base + thick + 0.001),
                              (0.006, length / 2 - 0.06, base + thick + 0.004), stripe)
    fin = C.box_minmax("fin", (-0.006, length / 2 - 0.30, base + thick), (0.006, length / 2 - 0.12, base + thick + 0.11),
                       stripe)
    # a thin band over the deck, down each rail to the bar
    straps = []
    for y in ROOFS[roof]["fy"]:
        t = (y + length / 2) / length
        half = width / 2 * math.sin(math.pi * t * 1.05) ** 0.55 + 0.004
        z_deck = base + 0.06 * (1 - t) ** 3 + 0.02 * t ** 4 + thick + 0.002
        straps += _strap_over(y, -half, half, top - 0.016, z_deck, strap)
    board = C.join([board, stripe_bar, fin] + straps, "Surfboard")
    _rod_mount(roof, top)
    return [rack, board]


def spotlights():
    """Two chrome-backed round lamps (Carello-style) on short stalks from a
    bar that clamps to the bumper; lenses face forward (Blender -Y)."""
    chrome = C.mat("Chrome", "#d8dadc", rough=0.2, metal=0.9)
    lens = C.mat("LampSpot", "#fff3d6", rough=0.1, emit="#fff1c8", emit_strength=0.4)
    dark = C.mat("SpotDark", "#202022", rough=0.6)
    bits = [C.cylinder("bar", 0.012, 0.70, segs=6, axis="X", loc=(0, 0, 0.0), material=dark)]
    for sx in (-1, 1):
        x = sx * 0.30
        bits.append(C.cylinder("stalk", 0.01, 0.07, segs=6, loc=(x, 0, 0.035), material=dark))
        bits.append(C.cylinder("rim", 0.075, 0.05, segs=14, axis="Y", loc=(x, -0.02, 0.14), material=chrome))
        bits.append(C.cylinder("bowl", 0.05, 0.05, segs=12, axis="Y", loc=(x, 0.025, 0.14), material=chrome))
        bits.append(K.lamp_disc("lens", 0.068, 0.012, (x, -0.046, 0.14), (0, -1, 0), lens, segs=14))
        bits.append(C.box_minmax("grille_bar", (x - 0.068, -0.054, 0.137), (x + 0.068, -0.05, 0.143), chrome))
    return [C.join(bits, "Spotlights")]


# Engine-lid rack (classic saloons and the Jolly), origin at Mount_RearRack on
# the lid centre. The lid bulges about 3 cm off the chord between the feet,
# so the frame stands on legs, parallel to that chord.
LID_FOOT_LO = Vector((0, 0.138, -0.14))    # lid surface near the bottom edge
LID_FOOT_HI = Vector((0, -0.232, 0.14))    # and below the rear window
LID_STANDOFF = 0.07


def _lid_frame():
    d = (LID_FOOT_HI - LID_FOOT_LO).normalized()          # up the lid
    n = Vector((0, d.z, -d.y))                             # out of the lid
    if n.y < 0:
        n = -n
    return d, n


def rack_rear_classic():
    """A chrome tube grid on four rubber-footed legs, a raised lip along the
    bottom so a case can't slide off the back."""
    M = _mats()
    d, n = _lid_frame()
    w = 0.28
    lo = LID_FOOT_LO - d * 0.02 + n * LID_STANDOFF
    hi = LID_FOOT_HI + d * 0.02 + n * LID_STANDOFF
    X = Vector((1, 0, 0))
    r = 0.009
    bits = [_tube("rail", lo - X * w, lo + X * w, r, M["chrome"]),
            _tube("rail", hi - X * w, hi + X * w, r, M["chrome"]),
            _tube("rail", (lo + hi) / 2 - X * w, (lo + hi) / 2 + X * w, r * 0.8, M["chrome"])]
    for x in (-w, -0.1, 0.1, w):
        bits.append(_tube("slat", lo + X * x, hi + X * x, r if abs(x) == w else r * 0.8, M["chrome"]))
    # bottom lip: up off the grid and across
    lip = lo + n * 0.06
    bits += [_tube("lip", lip - X * w, lip + X * w, r, M["chrome"]),
             _tube("lip_post", lo - X * w, lip - X * w, r, M["chrome"]),
             _tube("lip_post", lo + X * w, lip + X * w, r, M["chrome"])]
    for foot, end in ((LID_FOOT_LO, lo + d * 0.02), (LID_FOOT_HI, hi - d * 0.02)):
        for sx in (-1, 1):
            x = X * sx * (w - 0.04)
            bits.append(_tube("leg", foot + x + n * 0.012, end + x, 0.007, M["chrome"]))
            pad = C.cylinder("pad", 0.018, 0.014, segs=8, loc=(0, 0, 0), material=M["rubber"])
            pad.rotation_mode = "QUATERNION"
            pad.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(n)
            pad.location = foot + x + n * 0.006
            bits.append(pad)
    return C.join(bits, "RearRack"), d, n, lo, hi


def rack_rear_spare():
    """The lid rack with a spare 12-inch wheel lying on it, held by a strap."""
    from lib import wheels as W
    rack, d, n, lo, hi = rack_rear_classic()
    mid = (lo + hi) / 2 + n * (0.009 + 0.0625)
    wheel = W.build("SpareWheel", "classic12", loc=(0, 0, 0))
    wheel.rotation_mode = "QUATERNION"
    wheel.rotation_quaternion = Vector((1, 0, 0)).rotation_difference(n)
    wheel.location = mid
    C.apply_transform(wheel)
    strap = C.mat("LeatherStrap", "#2b2018", rough=0.7)
    top = mid + n * 0.064
    # one band across the tyre, down to the side rails
    w = 0.28
    X = Vector((1, 0, 0))
    bits = [_tube("strap", top - X * 0.2, top + X * 0.2, 0.012, strap),
            _tube("strap", top - X * 0.2, (lo + hi) / 2 - X * w, 0.012, strap),
            _tube("strap", top + X * 0.2, (lo + hi) / 2 + X * w, 0.012, strap)]
    return [rack, wheel, C.join(bits, "SpareStrap")]


# ---------------------------------------------------------------- bumpers

def _overrider(x, sgn, M, rubber):
    """One upright chrome over-rider clamped to the bumper face at x; sgn -1
    stands it out to the front (-Y), +1 to the rear."""
    from lib import cabin as CB
    bits = [CB._rbox("guard", (x - 0.018, -0.02, -0.07), (x + 0.018, 0.02, 0.09), M["chrome"], 0.012),
            C.sphere("guard_top", 0.02, (x, 0, 0.09), M["chrome"], segs=8, rings=4, scale=(0.9, 1, 0.8)),
            C.box_minmax("guard_rubber", (x - 0.007, -0.0215, -0.05), (x + 0.007, 0.0215, 0.075), rubber),
            C.box_minmax("guard_clamp", (x - 0.012, -0.03, -0.012), (x + 0.012, 0.03, 0.012), M["chrome"])]
    for b in bits:
        b.location.y += sgn * 0.026
    return bits


def bumper_overriders(sgn):
    """Pair of period over-riders, at Mount_BumperF (sgn -1) or Mount_BumperR
    (sgn 1), either side of the number plate."""
    M = _mats()
    rubber = C.mat("GuardRubber", "#121212", rough=0.8)
    bits = []
    for x in (-0.28, 0.28):
        bits += _overrider(x, sgn, M, rubber)
    return [C.join(bits, "Overriders")]


def bumper_nudge():
    """A low nudge bar for the modern cars, at Mount_BumperF: a polished alloy tube
    across the lower bumper with its ends swept back, two uprights clear of
    the plate with rubber caps, and stays back to the bumper."""
    black = C.mat("NudgeAlloy", "#c3c6c9", rough=0.25, metal=0.85)
    rubber = C.mat("NudgeRubber", "#0e0e0e", rough=0.9)
    r = 0.019
    yb = -0.075
    pts = [(-0.45, -0.02, 0.0), (-0.34, yb, 0.0), (0.34, yb, 0.0), (0.45, -0.02, 0.0)]
    bits = [_tube("bar", a, b, r, black) for a, b in zip(pts, pts[1:])]
    for p in pts[1:3]:
        bits.append(C.sphere("knuckle", r, p, black, segs=8, rings=4))
    for sx in (-1, 1):
        x = sx * 0.235
        bits += [_tube("upright", (x, yb, 0), (x, yb - 0.01, 0.15), r * 0.9, black),
                 _tube("upright", (x, yb - 0.01, 0.15), (x, yb + 0.02, 0.19), r * 0.9, black),
                 C.sphere("cap", r * 1.05, (x, yb + 0.02, 0.19), rubber, segs=8, rings=4),
                 _tube("stay", (x, yb, -0.01), (x, 0.03, -0.03), 0.012, black),
                 C.box_minmax("bracket", (x - 0.03, 0.02, -0.06), (x + 0.03, 0.035, 0.0), black)]
    return [C.join(bits, "NudgeBar")]


# ---------------------------------------------------------------- towbar, mudflaps

def towbar():
    """Ball hitch at Mount_TowBar: a short square tube back from under the
    bumper, a drop plate and a 50 mm ball."""
    black = C.mat("TowBlack", "#18181a", rough=0.5, metal=0.4)
    chrome = _mats()["chrome"]
    bits = [C.box_minmax("receiver", (-0.025, -0.22, -0.025), (0.025, 0.06, 0.025), black),
            C.box_minmax("cross", (-0.12, -0.22, -0.02), (0.12, -0.18, 0.02), black),
            C.box_minmax("tongue", (-0.03, 0.04, -0.02), (0.03, 0.115, 0.01), black),
            C.cylinder("neck", 0.012, 0.05, segs=8, loc=(0, 0.095, 0.035), material=chrome),
            C.sphere("ball", 0.025, (0, 0.095, 0.075), chrome, segs=12, rings=6),
            C.box_minmax("chain_plate", (-0.035, 0.04, -0.035), (0.035, 0.05, -0.02), black)]
    return [C.join(bits, "TowBar")]


def mudflap(height=0.24):
    """A plain black rubber flap hanging from its top bracket, origin at the
    top centre, in the XZ plane behind the tyre."""
    rubber = C.mat("FlapRubber", "#141414", rough=0.85)
    chrome = _mats()["chrome"]
    w = 0.2
    bits = [C.box_minmax("flap", (-w / 2, -0.003, -height), (w / 2, 0.003, 0), rubber),
            C.box_minmax("flap_lip", (-w / 2, -0.004, -height), (w / 2, 0.004, -height + 0.012), rubber),
            C.box_minmax("bracket", (-w / 2 + 0.01, -0.006, -0.03), (w / 2 - 0.01, 0.0, 0.0), chrome)]
    for x in (-0.06, 0.0, 0.06):
        bits.append(C.cylinder("rivet", 0.005, 0.004, segs=6, axis="Y", loc=(x, 0.002, -0.015), material=chrome))
    return [C.join(bits, "MudFlap")]


# ---------------------------------------------------------------- cockpit

def _wheel_bits(rim_r, tube, rim_mat, spoke_mat, hub_mat, dish, slotted):
    """Rim in the XZ plane, dished toward the driver (+Y) by `dish`, three
    spokes (9, 3 and 6 o'clock) into a boss on the origin."""
    from lib import cabin as CB
    bits = [CB.torus_rim("rim", rim_r, tube, 32, rim_mat, ts=8)]
    bits[0].location.y = dish
    bits.append(C.cylinder("boss", 0.034, 0.05, segs=12, axis="Y", loc=(0, 0.005, 0), material=hub_mat))
    bits.append(C.cylinder("horn", 0.03, 0.012, segs=14, axis="Y", loc=(0, 0.034, 0), material=hub_mat))
    for a in (0.0, math.pi, -math.pi / 2):
        d = Vector((math.cos(a), 0, math.sin(a)))
        side = Vector((-d.z, 0, d.x))
        a0, a1 = d * 0.03 + Vector((0, 0.02, 0)), d * (rim_r - tube * 0.5) + Vector((0, dish, 0))
        if slotted:
            for k in (-1, 1):
                bits.append(_tube("spoke", a0 + side * k * 0.011, a1 + side * k * 0.014, 0.0045, spoke_mat))
        else:
            bits.append(_tube("spoke", a0, a1, 0.009, spoke_mat))
    return bits


def wheel_wood():
    """A dished wood-rim wheel with three slotted alloy spokes and rivets
    round the rim, origin at the hub on Mount_Wheel, column down -Y."""
    wood = C.mat("WheelWood", "#7a4522", rough=0.35)
    alloy = C.mat("SpokeAlloy", "#c4c6c8", rough=0.3, metal=0.85)
    black = C.mat("HornBlack", "#151515", rough=0.5)
    from lib import cabin as CB
    rim_r, dish = 0.18, 0.045
    bits = _wheel_bits(rim_r, 0.0125, wood, alloy, black, dish, True)
    for i in range(18):
        a = 2 * math.pi * i / 18
        bits.append(C.sphere("rivet", 0.003, (math.cos(a) * (rim_r - 0.011), dish + 0.004, math.sin(a) * (rim_r - 0.011)),
                             alloy, segs=6, rings=3))
    ring = CB.torus_rim("horn_ring", 0.029, 0.003, 16, alloy, ts=4)
    ring.location.y = 0.04
    bits.append(ring)
    return [C.join(bits, "SteeringWheel")]


def wheel_sport():
    """A smaller leather-rim sport wheel, black spokes, a red band at twelve
    o'clock."""
    leather = C.mat("SportLeather", "#141415", rough=0.75)
    satin = C.mat("SpokeSatin", "#2a2b2d", rough=0.4, metal=0.5)
    red = C.mat("RimBand", "#b31d1d", rough=0.6)
    rim_r, tube, dish = 0.165, 0.017, 0.03
    bits = _wheel_bits(rim_r, tube, leather, satin, leather, dish, False)
    bits.append(C.box_minmax("band", (-0.012, dish - tube - 0.001, rim_r - tube - 0.001),
                             (0.012, dish + tube + 0.001, rim_r + tube + 0.001), red))
    return [C.join(bits, "SteeringWheel")]


def _knob(name, mat, r=0.03, scale=(1, 1, 1.05)):
    return C.sphere(name, r, (0, 0, 0), mat, segs=14, rings=8, scale=scale)


def knob_wood():
    """Turned walnut ball on a short brass collar; origin on the lever top,
    +Z up the lever."""
    wood = C.mat("KnobWood", "#5e341b", rough=0.35)
    brass = C.mat("KnobBrass", "#b8913d", rough=0.3, metal=0.8)
    return [C.join([_knob("knob", wood, 0.03, (1, 1, 1.12)),
                    C.cylinder("collar", 0.012, 0.016, segs=10, loc=(0, 0, -0.03), material=brass)], "GearKnob")]


def knob_chrome():
    """A polished chrome ball with a taller collar."""
    chrome = _mats()["chrome"]
    return [C.join([_knob("knob", chrome, 0.027),
                    C.cylinder("collar", 0.013, 0.03, segs=10, loc=(0, 0, -0.033), material=chrome, r_top=0.009)],
                   "GearKnob")]


def knob_8ball():
    """A black pool ball with the white spot and its 8 on top."""
    from lib import cabin as CB
    black = C.mat("BallBlack", "#0b0b0c", rough=0.15)
    white = C.mat("BallWhite", "#eeeae0", rough=0.3)
    r = 0.03
    bits = [_knob("ball", black, r, (1, 1, 1)),
            C.cylinder("spot", 0.0125, 0.003, segs=14, loc=(0, 0, r - 0.0005), material=white)]
    for dy, rr in ((-0.0035, 0.0034), (0.0037, 0.0038)):
        ring = CB.torus_rim("eight", rr, 0.0011, 12, black, ts=4)
        ring.rotation_euler = (math.pi / 2, 0, 0)
        ring.location = (0, dy, r + 0.0012)
        bits.append(ring)
    return [C.join(bits, "GearKnob")]


# ---------------------------------------------------------------- seat covers

def _seat_profile(roof):
    """Sample the passenger seat of a Pop (modern) or Nuova (classic) relative
    to its Seat_L hip point: one polyline per column across the seat, from
    over the front edge of the cushion, back along it and up the backrest,
    each as [(x, y, z)]. The car is built only to be measured."""
    from lib import fiat500_modern as FM, fiat500_classic as FC
    import build_pop as BP
    import build_classic as BC
    C.reset()
    C.clear_material_cache()
    if roof == "modern":
        FM.build(BP.POP)
        top, half = 0.40, 0.22
    else:
        FC.build(dict(BC.CARS["nuova"], plate="1CIN-500"))
        top, half = 0.44, 0.205
    bpy.context.view_layer.update()
    hip = bpy.data.objects["Seat_L"].matrix_world.translation.copy()
    skip = tuple(o for o in bpy.data.objects if o.type == "MESH" and o.name != "Interior")

    def down(x, y):
        h = K.hit_scene(hip + Vector((x, y, 0.6)), (0, 0, -1), skip)
        return h and h[0] - hip

    def fwd(x, z):
        h = K.hit_scene(hip + Vector((x, -0.6, z)), (0, 1, 0), skip)
        return h and h[0] - hip

    cols = []
    for x in [-half + half / 8 * i for i in range(17)]:
        z0 = down(x, 0.0).z
        pts = []
        y = 0.0
        while True:                       # forward to the cushion's front edge
            p = down(x, y - 0.03)
            if p is None or p.z < z0 - 0.04 or y < -0.6:
                break
            y -= 0.03
        front = down(x, y)
        pts.append(front + Vector((0, -0.012, -0.05)))
        pts.append(front + Vector((0, -0.01, -0.012)))
        while True:                       # back along the cushion
            p = down(x, y)
            if p is None or p.z > z0 + 0.05:
                break
            pts.append(p)
            y += 0.04
        back0 = None
        z = z0 + 0.04
        while z < top:                    # up the backrest
            p = fwd(x, z)
            if p is None or (back0 is not None and abs(p.y - back0) > 0.08):
                break
            back0 = p.y
            pts.append(p)
            z += 0.04
        last = pts[-1]
        pts.append(last + Vector((0, 0.03, 0.025)))   # over the top
        pts.append(last + Vector((0, 0.07, 0.015)))
        cols.append(pts)
    # a skirt column each side, hanging over the bolsters
    cols.insert(0, [p + Vector((-0.035, 0, -0.035)) for p in cols[0]])
    cols.append([p + Vector((0.035, 0, -0.035)) for p in cols[-1]])
    C.reset()
    C.clear_material_cache()
    return cols


def _resample(pts, n):
    d = [0.0]
    for a, b in zip(pts, pts[1:]):
        d.append(d[-1] + (b - a).length)
    out = []
    for i in range(n):
        t = d[-1] * i / (n - 1)
        k = max(j for j in range(len(d)) if d[j] <= t + 1e-9)
        k = min(k, len(pts) - 2)
        f = (t - d[k]) / max(d[k + 1] - d[k], 1e-9)
        out.append(pts[k].lerp(pts[k + 1], f))
    return out


def _cover(roof, name, mats, lift, shag, rows=26, uv_k=(1.0, 1.0)):
    """mats() makes (top, underside) after the measuring car is gone."""
    import random
    rnd = random.Random(5)
    cols = [_resample(c, rows) for c in _seat_profile(roof)]
    mat, under = mats()
    verts, faces, uvs = [], [], []
    nc = len(cols)
    for ci, col in enumerate(cols):
        for ri, p in enumerate(col):
            a, b = col[max(ri - 1, 0)], col[min(ri + 1, rows - 1)]
            t = (b - a).normalized()
            n = Vector((0, -t.z, t.y))
            q = p + n * (lift + (rnd.random() * shag))
            verts.append(tuple(q))
            uvs.append((ci / (nc - 1) * uv_k[0], ri / (rows - 1) * uv_k[1]))
    for ci in range(nc - 1):
        for ri in range(rows - 1):
            a = ci * rows + ri
            faces.append((a, a + rows, a + rows + 1, a + 1))
    o = C.mesh_obj(name, verts, faces, mat)
    uvl = o.data.uv_layers.new(name="UVMap")
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            uvl.data[li].uv = uvs[o.data.loops[li].vertex_index]
    K.solidify(o, 0.006, under)
    with bpy.context.temp_override(object=o, active_object=o):
        bpy.ops.object.modifier_apply(modifier="solid")
    return o


def seatcover_sheepskin(roof):
    """A shaggy cream sheepskin over the cushion and backrest, draped over
    the bolsters, origin at Seat_L (mirror for Seat_R)."""
    return [_cover(roof, "SeatCover", lambda: (C.mat("Sheepskin", "#e6dac2", rough=1.0),
                                               C.mat("SheepHide", "#b89e78", rough=0.9)), 0.022, 0.012)]


def seatcover_beaded(roof):
    """A wooden-bead seat mat (the taxi driver's favourite), origin at
    Seat_L."""
    def mats():
        return (C.mat("Beads", image=C.make_image("beads", 16, 16, px), rough=0.4),
                C.mat("BeadCord", "#2a2018", rough=0.8))

    def px(x, y):
        cx, cy = x % 4, y % 4
        if cx == 0 or cy == 0:
            return (0.08, 0.06, 0.05)
        shade = 0.85 if (cx, cy) == (1, 2) else (0.55 if (cx, cy) == (3, 1) else 0.7)
        return (0.62 * shade, 0.42 * shade, 0.24 * shade)
    return [_cover(roof, "SeatCover", mats, 0.02, 0.0, rows=26, uv_k=(7.0, 14.0))]


def export(builder, name):
    C.reset()
    C.clear_material_cache()
    objs = builder()
    print(name, "triangles:", C.tri_count(objs))
    C.turn_scene_z180()
    C.export_glb(PARTS + name)


RACKS = {"plain": roofrack_plain, "luggage": roofrack_luggage, "bike": roofrack_bike, "surf": roofrack_surf}


def main():
    for kind, fn in RACKS.items():
        for roof in ROOFS:
            export(lambda: fn(roof), "roofrack_%s_%s.glb" % (kind, roof))
    export(lambda: roofrack_surf("modern"), "roofrack_surf.glb")
    export(spotlights, "spotlights_period.glb")
    export(lambda: rack_rear_classic()[0:1], "rack_rear_classic.glb")
    export(rack_rear_spare, "rack_rear_spare.glb")
    export(lambda: bumper_overriders(-1), "bumper_overriders_f.glb")
    export(lambda: bumper_overriders(1), "bumper_overriders_r.glb")
    export(bumper_nudge, "bumper_nudge.glb")
    export(towbar, "towbar.glb")
    export(mudflap, "mudflap.glb")
    export(lambda: mudflap(0.1), "mudflap_short.glb")
    for fn in (wheel_wood, wheel_sport, knob_wood, knob_chrome, knob_8ball):
        export(fn, fn.__name__ + ".glb")
    for fn in (seatcover_sheepskin, seatcover_beaded):
        for roof in ROOFS:
            export(lambda: fn(roof), "%s_%s.glb" % (fn.__name__, roof))
    if "--render" in sys.argv:
        out = sys.argv[sys.argv.index("--render") + 1]
        for builder, name in ((lambda: roofrack_luggage("modern"), "roofrack"), (spotlights, "spotlights")):
            C.reset()
            C.clear_material_cache()
            builder()
            C.render_setup((720, 480), 16, world="#c9d6e0", strength=0.9)
            C.sun(rot=(50, 10, 150), energy=3.5)
            far = 3.2 if name == "roofrack" else 1.3
            C.camera_look((far * 0.8, -far, far * 0.6), (0, 0, 0.12), lens=40)
            C.render("%s_%s.png" % (out, name))


if __name__ == "__main__":
    main()
    C.done()
