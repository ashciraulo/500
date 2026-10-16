"""The Alfa 75's opening front doors and its cockpit.

`split_doors` cuts each front door out of the shell in lib/alfa75.py along
its shut lines, the way lib/valiant_cabin.py does the Valiant's, and takes
along whatever rides on it: the glass, the band's length on the door, the
pull handle and the mirror.

`cockpit` builds the inside as the driver sees it, after photos of
1985-88 75s: a dark grey dash with a deep rectangular hood over two big
dials (speedo to 220 km/h on the left, rev counter to 8000 on the right);
a centre stack with three small gauges, the radio and switches; a
two-spoke wheel with a wide pad (no badge); the gear lever far back on the
tunnel with the 75's hoop handbrake beside it; grey velour bucket seats
with headrests and a rear bench between the wheel tubs; grey door cards
with armrests; a pale grey headliner with the overhead switch console.

Coordinates as in lib/alfa75.py while building: front toward +Y, origin
on the ground at the footprint centre, the driver on +X (right-hand
drive), the kerb side on -X.
"""
import math

import bpy  # noqa: F401,I001  (bpy must load before bmesh)
import bmesh
from mathutils import Matrix, Vector

from . import common as C
from . import carkit as K
from . import cabin as CB
from . import textures as TX
from . import period_vehicles as PV
from . import valiant_cabin as VC
from . import alfa75 as A

_rprism, _tube, _bar, _uv, _bench = VC._rprism, VC._tube, VC._bar, VC._uv, VC._bench

# ------------------------------------------------------------------ doors

DOOR_OPEN_DEG = 65
DOOR_Y0, DOOR_Y1 = -0.19, 0.735   # rear (B pillar) and front shut lines
DOOR_Z0 = 0.35                     # bottom edge, over the sill strip
HINGE_DY = -0.02


def door_outline():
    """Side outline (y, z) of the front door: up the front shut line to the
    belt, along it to the A pillar's foot, up the pillar outside the glass
    to the roof edge, back to the B pillar and down it."""
    z_top = A.DLO_Z1 + 0.03
    zb = A.ZB(DOOR_Y1) - 0.006
    a0 = A._a_line(zb) - 0.012
    a1 = A._a_line(z_top) - 0.012
    return [(DOOR_Y0, DOOR_Z0), (DOOR_Y1, DOOR_Z0), (DOOR_Y1, zb), (a0, zb), (a1, z_top), (DOOR_Y0, z_top)]


def split_doors(parts, trims=None):
    """Cut both front doors out of the body (parts[0]) and gather what rides
    on them, plus trims[side] (the door card from `cockpit`). Returns (body
    parts, door items, empties) in lib/city_vehicles.py's form."""
    body = parts[0]
    C.apply_transform(body)
    outline = door_outline()
    bm = bmesh.new()
    bm.from_mesh(body.data)
    VC._slice(bm, outline + outline[:1], 0.5)
    bm.to_mesh(body.data)
    bm.free()
    items, empties = [], {}
    rest = list(parts[1:])
    for side, sx in (("L", -1), ("R", 1)):
        def on_door(f, sx=sx):
            c = f.calc_center_median()
            return sx * c.x > 0.5 and K.inside_poly((c.y, c.z), outline)
        door = VC._take(body, on_door, "door_" + side)
        ride, glass = [door], []
        for o in list(rest):
            if o.type != "MESH" or not len(o.data.vertices):
                continue
            C.apply_transform(o)
            vs = [v.co for v in o.data.vertices]
            cx = sum(v.x for v in vs) / len(vs)
            if sx * cx < 0.5:
                continue
            ys = [v.y for v in vs]
            c = (sum(ys) / len(ys), sum(v.z for v in vs) / len(vs))
            if min(ys) > DOOR_Y0 - 0.002 and max(ys) < DOOR_Y1 + 0.17 and K.inside_poly(c, outline):
                rest.remove(o)
                (glass if o.name.startswith("glass") else ride).append(o)
            elif min(ys) < DOOR_Y0 and max(ys) > DOOR_Y1 and min(v.z for v in vs) > DOOR_Z0:
                # a run along the car (the band): the door keeps its length
                piece = VC._take(o, lambda f: DOOR_Y0 < f.calc_center_median().y < DOOR_Y1 and
                                 f.calc_center_median().z < A.DLO_Z1, o.name + "_door")
                ride.append(piece)
        _cut_runs(ride[1:])
        ride += (trims or {}).get(side, [])
        hinge = (sx * (A.HW - 0.01), DOOR_Y1 + HINGE_DY, 0.6)
        items.append(("Door_" + side, ride, hinge, None))
        items.append(("Door_%s_Glass" % side, glass, hinge, "Door_" + side))
        sign = -1 if side == "L" else 1
        empties["DoorOpen_" + side] = (hinge, DOOR_OPEN_DEG * sign)
    return [body] + rest, items, empties


def _cut_runs(objs):
    """Trim pieces taken off a long run so their ends sit on the shut lines."""
    for o in objs:
        if not o.name.endswith("_door"):
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        for y, keep_neg in ((DOOR_Y1, True), (DOOR_Y0, False)):
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, y, 0),
                                   plane_no=(0, 1, 0), clear_outer=keep_neg, clear_inner=not keep_neg)
        bm.to_mesh(o.data)
        bm.free()


# ------------------------------------------------------------------ cockpit

DRIVER_X = 0.36
# The front seats' profiles below are drawn SEAT_DY further back than they
# sit: the backs come up just behind the B pillar, the cushions' fronts a
# good stride short of the pedals.
SEAT_DY = 0.30
HIP = (DRIVER_X, -0.16, 0.56)       # a little over the cushion, as the game seats people
# the driver's eye: a head ahead of the seat back's face, well under the roof
EYE = Vector((DRIVER_X, -0.13, 1.15))
FACE_Y = 0.468                     # the dial panel inside the hood
DIAL_R = 0.06
DIAL_Z = 0.885
SPEEDO_X, TACH_X = 0.265, 0.465
COL_TILT = 22
HUB = Vector((DRIVER_X, 0.25, 0.87))   # high, as the 75s is: the dials show through the top of the rim
RIM_R = 0.19
SPEED_FULL, REV_FULL = 220, 8
DASH_X = 0.78
FRAMES = {}


def _cab_mats(M):
    velour = "#707276"
    return {
        "vinyl": C.mat("A75_Velour", velour, rough=0.9),
        "pleat": C.mat("A75_VelourPleat", image=VC._pleat_tex(velour), rough=0.9),
        "panel": C.mat("A75_DoorCard", "#7a7c7f", rough=0.85),
        # a mid grey dash, its modules (dials, check panel, vents, heater,
        # radio, switch pods) set into it in near black
        "dash": C.mat("A75_Dash", "#6c6d70", rough=0.75),
        "dark": C.mat("A75_DashDark", "#1d1e21", rough=0.6),
        "mid": C.mat("A75_DashMid", "#3f4144", rough=0.8),
        "hood": C.mat("A75_DashHood", "#1b1c1e", rough=0.8),
        "lcd": C.mat("A75_Lcd", "#3f6b3a", rough=0.3, emit="#7fd06a", emit_strength=0.2),
        "red": C.mat("A75_KnobRed", "#b3322b", rough=0.5),
        "blue": C.mat("A75_KnobBlue", "#2f5fb0", rough=0.5),
        "badge": C.mat("A75_WheelBadge", "#c9cbcc", rough=0.3, metal=0.7),
        "knob": C.mat("A75_Knob", "#111113", rough=0.4),
        "carpet": C.mat("A75_Carpet", image=TX.carpet("a75_carpet", "#34363a", 5, 16), rough=1.0),
        "rubber": C.mat("A75_Rubber", "#141415", rough=0.9),
        "rim": C.mat("A75_WheelRim", "#2a2b2e", rough=0.6),
        "needle": C.mat("A75_Needle", "#f07a1c", rough=0.4, emit="#ff8a2a", emit_strength=0.25),
        "speedo": C.mat("A75_Speedo", image=CB.dial_tex("a75_speedo", SPEED_FULL, 20, face=(0.03, 0.03, 0.035),
                                                         ink=(0.9, 0.9, 0.86), tick_step=10, units="KMH"),
                        rough=0.35, emit="#c8d4e0", emit_strength=0.2, emit_image=True),
        "tach": C.mat("A75_Tach", image=CB.dial_tex("a75_tach", REV_FULL, 1, face=(0.03, 0.03, 0.035),
                                                     ink=(0.9, 0.9, 0.86), tick_step=0.5, red_from=6.2,
                                                     units="RPM", odo=False),
                      rough=0.35, emit="#c8d4e0", emit_strength=0.2, emit_image=True),
        "minor": C.mat("A75_MinorGauges", image=_minor_tex(), rough=0.35, emit="#c8d4e0", emit_strength=0.15,
                       emit_image=True),
        "radio": C.mat("A75_Radio", image=_radio_tex(), rough=0.4, emit="#ffb070", emit_strength=0.1,
                       emit_image=True),
        "chrome": C.mat("A75_CabinChrome", "#b9bbbc", rough=0.35, metal=0.5),
        "liner": C.mat("A75_Headliner", "#b7b4ad", rough=0.95),
    }


def _minor_tex():
    """Three small dials side by side for the centre stack: oil pressure,
    water temperature and fuel, white on black, needles printed on."""
    w, h = 96, 32
    face, ink, orange = (0.03, 0.03, 0.035), (0.88, 0.88, 0.84), (0.94, 0.48, 0.11)
    px = [(0.08, 0.08, 0.09)] * (w * h)
    for k, ang in enumerate((-30, 10, 40)):
        cx, cy = 16 + 32 * k, 16
        for y in range(h):
            for x in range(32 * k, 32 * k + 32):
                u, v = x + 0.5 - cx, y + 0.5 - cy
                r = math.hypot(u, v)
                a = math.degrees(math.atan2(u, v))
                if r < 14:
                    px[y * w + x] = face
                if 11 < r < 13.5 and -70 <= a <= 70 and int(a) % 20 < 4:
                    px[y * w + x] = ink
                if r < 11 and abs(a - ang) < 7 and r > 2:
                    px[y * w + x] = orange
    return CB._image("a75_minor", w, h, px)


def _radio_tex():
    """A late-80s cassette radio face: dark, an amber display, a tape slot."""
    w, h = 48, 12
    px = [(0.06, 0.06, 0.065)] * (w * h)
    for y in range(3, 7):
        for x in range(4, 20):
            px[y * w + x] = (0.85, 0.5, 0.15) if (x + y) % 3 else (0.4, 0.22, 0.08)
    for x in range(24, 44):
        px[5 * w + x] = (0.0, 0.0, 0.0)
        px[6 * w + x] = (0.0, 0.0, 0.0)
    for k in range(5):
        for y in range(8, 10):
            for x in range(4 + k * 8, 9 + k * 8):
                px[y * w + x] = (0.3, 0.3, 0.32)
    return CB._image("a75_radio", w, h, px)


def _face_frame(x, z, y=FACE_Y):
    """A frame on the dial panel: local x to the driver's right (+X), y up,
    z toward the driver (-Y)."""
    return CB._frame((x, y, z), (1, 0, 0), (0, 0, 1))


def _inset(name, x0, x1, z0, z1, mat, y=0.448, r=0.008, depth=0.006):
    """A flat module on the dash's face, standing `depth` proud of it."""
    return _rprism(name, _box(x0, x1, z0, z1), "y", y - depth, y, mat, r=r)


def _box(x0, x1, z0, z1):
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def _dash(X):
    """After the 75's dash (ref/r10.jpg, mirrored for right-hand drive): a
    light grey moulding with its modules set into it in near black: the
    long dial panel under its hood with a pod of switches either side, the
    check panel over a cubby at the top of the centre stack, the badge strip,
    two vents side by side, the heater panel and the radio, a recessed tray
    across the passenger's side over the glovebox."""
    out = []
    # the main dash: a deep top under the windscreen's foot, a face, a
    # rounded lower edge over the knees
    prof = [(0.86, 0.872), (0.62, 0.902), (0.48, 0.905), (0.455, 0.89), (0.45, 0.80), (0.47, 0.66),
            (0.56, 0.585), (0.70, 0.57), (0.86, 0.60)]
    # under the hood the face steps back to the dial panel's foot, so the
    # dials sit whole in a binnacle with a ledge below them
    binnacle = [(0.86, 0.872), (0.62, 0.902), (0.525, 0.902), (0.525, 0.806), (0.455, 0.804), (0.45, 0.78),
                (0.47, 0.66), (0.56, 0.585), (0.70, 0.57), (0.86, 0.60)]
    for x0, x1, pr in ((-DASH_X, 0.10, prof), (0.10, 0.64, binnacle), (0.64, DASH_X, prof)):
        out.append(_rprism("dash", pr, "x", x0, x1, X["dash"], r=0.02 if pr is prof else 0.008))
    # the hood over the dials, in the dash's grey; the long panel inside it
    # near black
    hood = [(0.40, 0.985), (0.62, 0.958), (0.62, 0.90), (0.50, 0.90), (0.47, 0.96), (0.42, 0.968)]
    out.append(_rprism("dial_hood", hood, "x", 0.10, 0.64, X["dash"], r=0.012, cap=0.012))
    panel = [(0.11, 0.81), (0.63, 0.81), (0.63, 0.96), (0.11, 0.96)]
    out.append(_rprism("dial_panel", panel, "y", FACE_Y, 0.52, X["dark"], r=0.02))
    for x, mat in ((SPEEDO_X, X["speedo"]), (TACH_X, X["tach"])):
        m = _face_frame(x, DIAL_Z)
        out.append(CB._ring("dial_rim", DIAL_R - 0.001, DIAL_R + 0.005, 0.012, m, X["mid"], segs=32))
        out.append(CB._disc("dial", DIAL_R, m @ Matrix.Translation((0, 0, 0.002)), mat, segs=32))
        out.append(C.sphere("dial_cap", 0.009, tuple(m @ Vector((0, 0, 0.007))), X["knob"], segs=12, rings=4,
                            scale=(1, 0.45, 1)))
    # the small gauges (oil, water, fuel) between and outboard of the dials
    gm = _face_frame(0.365, 0.86)
    out.append(CB._quad("minor_gauges", 0.075, 0.025, gm @ Matrix.Translation((0, 0, 0.001)), X["minor"]))
    # a pod of rocker switches either side of the hood
    for x0, x1 in ((0.062, 0.10), (0.645, 0.685)):
        out.append(_inset("switch_pod", x0, x1, 0.78, 0.92, X["dark"], y=0.452, depth=0.03))
        for k in range(3):
            z = 0.80 + k * 0.04
            out.append(C.box_minmax("rocker", (x0 + 0.01, 0.418, z), (x1 - 0.01, 0.424, z + 0.025), X["mid"]))
    # the driver's knee panel: a dark cubby outboard of the column
    out.append(_inset("knee_cubby", 0.47, 0.66, 0.67, 0.73, X["dark"], y=0.462, depth=0.004))
    # vents at the dash ends, in dark surrounds
    for x in (-0.70, 0.732):
        out.append(_inset("vent_surround", x - 0.042, x + 0.042, 0.835, 0.885, X["dark"], y=0.452, depth=0.004))
        vm = _face_frame(x, 0.86, 0.446)
        for k in range(3):
            out.append(CB._place(C.box_minmax("vent_vane", (-0.034, -0.016 + k * 0.014, 0.0),
                                              (0.034, -0.012 + k * 0.014, 0.004), X["mid"]), vm))
    # across the passenger's side: a recessed tray, darker, over the
    # glovebox lid
    out.append(_inset("tray", -0.70, -0.17, 0.745, 0.815, X["mid"], y=0.452, depth=0.004))
    out.append(C.box_minmax("tray_lip", (-0.70, 0.436, 0.742), (-0.17, 0.452, 0.752), X["dash"]))
    gb = [(-0.66, 0.665), (-0.24, 0.665), (-0.24, 0.73), (-0.66, 0.73)]
    out.append(_rprism("glovebox", gb, "y", 0.452, 0.47, X["dash"], r=0.012))
    out.append(C.box_minmax("glovebox_catch", (-0.48, 0.448, 0.712), (-0.42, 0.454, 0.722), X["dark"]))
    # the centre stack, running down into the console on the tunnel
    stack = [(0.455, 0.84), (0.455, 0.56), (0.40, 0.46), (0.30, 0.43), (0.62, 0.43), (0.62, 0.84)]
    out.append(_rprism("stack", stack, "x", -0.13, 0.13, X["dash"], r=0.02, cap=0.01))
    # at its top the check panel (a green display and its warning lamps)
    # in a dark housing, a cubby under it
    out.append(_inset("check_panel", -0.12, 0.05, 0.775, 0.885, X["dark"], y=0.455, depth=0.02))
    cm = CB._frame((0.008, 0.434, 0.835), (1, 0, 0), (0, 0, 1))
    out.append(CB._quad("check_lcd", 0.05, 0.018, cm, X["lcd"]))
    for k in range(4):
        out.append(CB._quad("check_lamp", 0.012, 0.012, CB._frame((-0.099 + k * 0.022, 0.434, 0.835), (1, 0, 0),
                                                                    (0, 0, 1)), X["mid"]))
    out.append(_inset("cubby", -0.115, 0.115, 0.715, 0.76, X["hood"], y=0.457, depth=0.002))
    # the badge strip and the two vents side by side under it
    out.append(_inset("badge_strip", -0.12, 0.12, 0.665, 0.700, X["dark"], y=0.457, depth=0.006))
    out.append(C.box_minmax("strip_badge", (-0.035, 0.448, 0.677), (0.035, 0.452, 0.688), X["chrome"]))
    out.append(_inset("vents_surround", -0.12, 0.12, 0.575, 0.655, X["dark"], y=0.457, depth=0.008))
    for xc in (-0.058, 0.058):
        for k in range(5):
            z = 0.588 + k * 0.012
            out.append(C.box_minmax("vent_vane", (xc - 0.05, 0.445, z), (xc + 0.05, 0.449, z + 0.005), X["mid"]))
    # down the stack's slope: the heater panel (two dials, red and blue,
    # either side of the fan knob) over the radio
    hm = CB._frame((0.0, 0.437, 0.527), (1, 0, 0), (0, 0.48, 0.88))
    out.append(CB._place(CB._rbox("heater_panel", (-0.115, -0.04, 0.0), (0.115, 0.04, 0.012), X["dark"], 0.006),
                         hm))
    for xk, ring in ((-0.06, X["red"]), (0.0, X["mid"]), (0.06, X["blue"])):
        km = hm @ Matrix.Translation((xk, 0.0, 0.012))
        out.append(CB._ring("heater_ring", 0.018, 0.024, 0.004, km, ring, segs=20))
        out.append(CB._place(C.cylinder("heater_knob", 0.016, 0.016, segs=14, loc=(0, 0, 0.008),
                                        material=X["knob"]), km))
    rm = CB._frame((0.0, 0.415, 0.487), (1, 0, 0), (0, 0.48, 0.88))
    out.append(CB._place(CB._rbox("radio_box", (-0.10, -0.022, 0.0), (0.10, 0.022, 0.01), X["hood"], 0.004), rm))
    out.append(CB._quad("radio", 0.18, 0.04, rm @ Matrix.Translation((0, 0, 0.011)), X["radio"]))
    # needles and odometer
    sp, tc = _face_frame(SPEEDO_X, DIAL_Z), _face_frame(TACH_X, DIAL_Z)
    lift = 0.004
    speed = CB.needle("Needle_Speed_%d" % SPEED_FULL, sp, 0.008, DIAL_R * 0.92, 0.004, X["needle"], lift)
    rev = CB.needle("Needle_Rev_%d" % REV_FULL, tc, 0.008, DIAL_R * 0.92, 0.004, X["needle"], lift)
    odo = CB.odometer(sp, DIAL_R, CB.ODO_Y_DIAL, lift + 0.0005)
    return out, [(speed, sp), (rev, tc)], odo


def _column_frame():
    """Hub frame: local Y down the column toward the dash, Z to twelve."""
    return Matrix.Translation(HUB) @ Matrix.Rotation(math.radians(-COL_TILT), 4, "X")


def _wheel_pad(X):
    """The 75's wheel inside its rim, in the hub frame, facing the driver
    (-Y): one broad flat spoke straight across from rim to rim a little
    over the middle, a third tapering down from it to six o'clock, a
    padded boss where they meet and a plain round badge (made up, no
    marque) on it."""
    r = RIM_R - 0.004
    spokes = PV._round_poly([(-r, 0.038), (r, 0.038), (r, -0.032), (0.12, -0.042), (0.07, -0.08), (0.042, -r),
                             (-0.042, -r), (-0.07, -0.08), (-0.12, -0.042), (-r, -0.032)], 0.016, 3)
    out = [PV._smoothed(PV._prism("spokes", spokes, "y", 0.004, 0.026, X["rim"]), 40)]
    boss = PV._round_poly([(-0.095, -0.055), (0.095, -0.055), (0.1, 0.034), (-0.1, 0.034)], 0.03, 4)
    out.append(PV._smoothed(PV._prism("boss", boss, "y", -0.014, 0.01, X["rim"]), 40))
    bm = CB._frame((0.0, -0.0145, -0.008), (1, 0, 0), (0, 0, 1))
    out.append(CB._disc("badge", 0.021, bm, X["badge"], segs=20))
    out.append(CB._disc("badge_in", 0.015, bm @ Matrix.Translation((0, 0, 0.0008)), X["knob"], segs=20))
    return out


def _column(X):
    m = _column_frame()
    d = (m.to_3x3() @ Vector((0, 1, 0))).normalized()
    out = [_tube("column", [HUB + d * 0.06, HUB + d * 0.30], 0.025, X["knob"], segs=12)]
    shroud = CB._rbox("column_shroud", (-0.055, 0.06, -0.06), (0.055, 0.24, 0.03), X["dash"], 0.02)
    out.append(CB._place(shroud, m))
    for sx in (-1, 1):
        s0 = HUB + d * 0.09 + Vector((sx * 0.05, 0, 0.0))
        s1 = s0 + Vector((sx * 0.11, -0.02, 0.0))
        out.append(_tube("stalk", [s0, s1], 0.005, X["knob"], segs=6))
    return out


def _gear(X):
    """The gear lever far back on the tunnel (the transaxle's linkage) in a
    rubber boot, and the 75's hoop handbrake beside it."""
    base = Vector((0.0, 0.27, 0.52))
    tip = base + Vector((0.0, -0.10, 0.17))
    out = [C.cylinder("gear_boot", 0.05, 0.05, segs=12, loc=tuple(base + Vector((0, 0, 0.02))),
                      material=X["rubber"], r_top=0.018),
           _tube("gear_lever", [base, tip], 0.007, X["chrome"], segs=8)]
    knob = C.sphere("GearKnob", 0.021, tuple(tip + Vector((0, -0.004, 0.012))), X["knob"], segs=12, rings=6,
                    scale=(1.0, 1.15, 0.9))
    # the hoop: a U of black tube lying on the console, its ends at the back
    hoop = [(0.05, -0.08, 0.535), (0.05, 0.08, 0.56), (0.07, 0.15, 0.57), (0.10, 0.15, 0.57), (0.12, 0.08, 0.56),
            (0.12, -0.08, 0.535)]
    out.append(_tube("handbrake", hoop, 0.009, X["knob"], segs=8, up=(0, 0, 1)))
    console = [(-0.12, 0.43), (0.12, 0.43), (0.11, 0.52), (-0.11, 0.52)]
    out.append(_rprism("console", console, "y", -0.30, 0.32, X["dash"], r=0.02, cap=0.01))
    return out, knob, tip


def _seats(X):
    out = []
    def fwd(prof):
        return [(y + SEAT_DY, z) for y, z in prof]
    cushion = [(-0.66, 0.40), (-0.10, 0.40), (-0.05, 0.47), (-0.06, 0.525), (-0.12, 0.54), (-0.52, 0.52),
               (-0.62, 0.50)]
    back = [(-0.57, 0.50), (-0.61, 0.62), (-0.67, 1.04), (-0.71, 1.075), (-0.77, 1.06), (-0.74, 0.62),
            (-0.69, 0.50)]
    for sx in (-1, 1):
        lo, hi = sorted((sx * 0.13, sx * 0.62))
        ins = [(lo + 0.08, hi - 0.08)]
        out.append(_bench("seat_cushion", fwd(cushion), lo, hi, ins, X, "top", r=0.03))
        out.append(_bench("seat_back", fwd(back), lo, hi, ins, X, "front", r=0.04))
        # side bolsters on the back
        for x in (lo + 0.035, hi - 0.035):
            out.append(_rprism("bolster", fwd([(-0.59, 0.56), (-0.64, 0.96), (-0.70, 0.98), (-0.69, 0.56)]), "x",
                               x - 0.035, x + 0.035, X["vinyl"], r=0.02, cap=0.012))
        hx = sx * 0.375
        out.append(PV._smoothed(CB._rbox("headrest", (hx - 0.12, -0.80 + SEAT_DY, 1.10), (hx + 0.12, -0.72 + SEAT_DY, 1.255),
                                         X["vinyl"], 0.03), 40))
        for dx in (-0.07, 0.07):
            out.append(_tube("headrest_post", [(hx + dx, -0.755 + SEAT_DY, 1.06), (hx + dx, -0.755 + SEAT_DY, 1.11)], 0.006,
                             X["chrome"], segs=6))
    # the back seat between the wheel tubs, its back up to the parcel shelf
    cushion_r = [(-1.42, 0.40), (-0.92, 0.40), (-0.88, 0.47), (-0.89, 0.53), (-0.95, 0.545), (-1.36, 0.53)]
    out.append(_bench("bench_rear", cushion_r, -0.56, 0.56, [(-0.48, -0.06), (0.06, 0.48)], X, "top", r=0.03))
    back_r = [(-1.36, 0.53), (-1.42, 0.92), (-1.47, 0.965), (-1.53, 0.955), (-1.50, 0.53)]
    out.append(_bench("bench_rear_back", back_r, -0.66, 0.66, [(-0.5, -0.06), (0.06, 0.5)], X, "front", r=0.035))
    return out


def _floor(X):
    # the floor, narrowing between the rear wheel wells
    out = [_uv(C.box_minmax("floor", (-0.78, -0.84, 0.31), (0.78, 0.76, 0.33), X["carpet"]), 0, 1, 0.12, 0.12),
           _uv(C.box_minmax("floor_rear", (-0.52, -1.55, 0.31), (0.52, -0.84, 0.33), X["carpet"]), 0, 1, 0.12, 0.12)]
    toe = [(0.72, 0.31), (0.74, 0.33), (0.94, 0.60), (0.95, 0.80), (1.0, 0.80), (1.0, 0.31)]
    out.append(_uv(_rprism("toe_board", toe, "x", -0.78, 0.78, X["carpet"], r=0.03, smooth=30), 0, 1, 0.12, 0.12))
    tunnel = [(-0.14, 0.32), (0.14, 0.32), (0.11, 0.42), (0.0, 0.44), (-0.11, 0.42)]
    out.append(_uv(_rprism("tunnel", tunnel, "y", -1.45, 0.86, X["carpet"], r=0.03, smooth=40), 0, 1, 0.12, 0.12))
    # rear wheel tubs either side of the back seat, inboard of the wells'
    # liners (lib/alfa75.py) so they don't show through the arches
    tub = [(-1.54, 0.31), (-0.87, 0.31), (-0.89, 0.55), (-0.99, 0.66), (-1.42, 0.66), (-1.52, 0.55)]
    for sx in (-1, 1):
        lo, hi = sorted((sx * 0.45, sx * 0.525))
        out.append(_uv(_rprism("wheel_tub", tub, "x", lo, hi, X["carpet"], r=0.04, cap=0.02, smooth=40), 1, 2,
                       0.12, 0.12))
    out.append(_rprism("parcel_shelf", [(-1.97, 0.955), (-1.48, 0.955), (-1.48, 0.97), (-1.97, 0.97)], "x",
                       -0.74, 0.74, X["hood"], r=0.004, smooth=30))
    thr = _rprism("throttle", [(-0.006, -0.06), (0.006, -0.06), (0.006, 0.06), (-0.006, 0.06)], "x", 0.45, 0.50,
                  X["rubber"], r=0.005, smooth=30)
    thr.data.transform(Matrix.Translation((0, 0.74, 0.42)) @ Matrix.Rotation(math.radians(-50), 4, "X"))
    out.append(thr)
    return out


def _pedal(x, w, nm, X):
    out = [_tube(nm + "_arm", [(x, 0.74, 0.62), (x, 0.70, 0.52), (x, 0.68, 0.45)], 0.007, X["knob"])]
    pad = _rprism(nm, [(-0.006, -0.026), (0.006, -0.026), (0.006, 0.026), (-0.006, 0.026)], "x",
                  x - w / 2, x + w / 2, X["rubber"], r=0.005, smooth=30)
    pad.data.transform(Matrix.Translation((0, 0.672, 0.44)) @ Matrix.Rotation(math.radians(-25), 4, "X"))
    return out + [pad]


def _gearbox_parts(X):
    """Clutch and brake (RHD, from the tunnel out: clutch, brake, then the
    throttle) for the manual; one wide brake pedal with the auto."""
    manual = _pedal(0.22, 0.06, "clutch", X) + _pedal(0.34, 0.07, "brake", X)
    auto = _pedal(0.31, 0.13, "brake_wide", X)
    return manual, auto


def _headliner(X, body):
    """A pale lining a little under the roof, followed by ray casts, the sun
    visors and the overhead switch console the 75 carries its window
    switches in."""
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.transform(body.matrix_world)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    xs = [-0.58 + 0.058 * i for i in range(21)]
    ys = [-1.04 + (0.26 + 1.04) * j / 13 for j in range(14)]
    vs, fs = [], []

    def up(x, y):
        # out at the edges a ray can slip through the side glass's opening:
        # step in until it meets the roof
        for k in (1.0, 0.94, 0.88, 0.8, 0.7):
            h = tree.ray_cast(Vector((x * k, y, 1.1)), Vector((0, 0, 1)), 1.0)[0]
            if h:
                return h.z
        return A.ZR - A.roof_drop(y)
    for y in ys:
        for x in xs:
            vs.append((x, y, up(x, y) - 0.016))
    nx = len(xs)
    for j in range(len(ys) - 1):
        for i in range(nx - 1):
            fs.append((j * nx + i, j * nx + i + 1, (j + 1) * nx + i + 1, (j + 1) * nx + i))
    o = C.mesh_obj("headliner", vs, fs, X["liner"])
    if o.data.polygons[0].normal.z > 0:
        o.data.flip_normals()
    out = [PV._smoothed(o, 40)]

    def roof(x, y):
        return up(x, y) - 0.018
    for sx in (-1, 1):
        lo, hi = sorted((sx * 0.06, sx * 0.56))
        zl = roof((lo + hi) / 2, 0.15)
        out.append(PV._smoothed(CB._rbox("sun_visor", (lo, 0.08, zl - 0.022), (hi, 0.24, zl - 0.002), X["liner"],
                                         0.025), 40))
    zc = roof(0.0, 0.05)
    out.append(PV._smoothed(CB._rbox("roof_console", (-0.09, -0.08, zc - 0.03), (0.09, 0.2, zc), X["dash"], 0.015),
                            40))
    for k in range(4):
        out.append(C.box_minmax("roof_switch", (-0.07 + k * 0.038, 0.02, zc - 0.034), (-0.05 + k * 0.038, 0.06,
                                                                                      zc - 0.029), X["knob"]))
    # the interior mirror on the console's nose
    out.append(CB._rbox("mirror", (-0.10, 0.215, zc - 0.10), (0.10, 0.232, zc - 0.05), X["knob"], 0.012))
    out.append(_tube("mirror_stem", [(0.0, 0.205, zc - 0.005), (0.0, 0.222, zc - 0.06)], 0.006, X["knob"]))
    return out


def _door_card(sx, y0, y1, X, xo=0.765):
    """A door's inside: a grey card from the sill to the belt with a top
    capping, an armrest and a pull, a pocket at the bottom."""
    out = []
    zb = A.ZB((y0 + y1) / 2)
    card = [(sx * xo, 0.36), (sx * (xo - 0.02), 0.36), (sx * (xo - 0.025), zb - 0.04), (sx * xo, zb - 0.02)]
    out.append(_rprism("door_card", card, "y", y0 + 0.01, y1 - 0.01, X["panel"], r=0.006, cap=0.006, smooth=30))
    cap = [(sx * (xo - 0.025), zb - 0.04), (sx * (xo - 0.045), zb - 0.03), (sx * (xo - 0.04), zb - 0.005),
           (sx * xo, zb)]
    out.append(_rprism("door_capping", cap, "y", y0 + 0.012, y1 - 0.012, X["dash"], r=0.008, cap=0.006))
    xi = xo - 0.025
    arm = [(sx * xi, 0.62), (sx * (xi - 0.06), 0.63), (sx * (xi - 0.065), 0.675), (sx * xi, 0.69)]
    ya = (y0 + y1) / 2
    out.append(_rprism("armrest", arm, "y", ya - 0.2, ya + 0.12, X["dash"], r=0.012, cap=0.012))
    out.append(_rprism("door_pocket", [(sx * xi, 0.40), (sx * (xi - 0.035), 0.40), (sx * (xi - 0.035), 0.50),
                                       (sx * xi, 0.50)], "y", y0 + 0.08, y1 - 0.12, X["dash"], r=0.008, cap=0.006))
    return out


def cockpit(M, body):
    """The whole inside. Returns (parts that stay with the body, items for
    the moving nodes, {"L": front door card parts, "R": ...}). Call
    `orient()` after build_city's build to give the wheel and needles their
    axes."""
    X = _cab_mats(M)
    FRAMES.clear()
    dash, needles, odo = _dash(X)
    col = _column(X)
    gear, knob, tip = _gear(X)
    parts = dash + col + gear + _seats(X) + _floor(X) + _headliner(X, body)
    # the rear doors' cards stay with the body
    parts += _door_card(-1, -1.08, -0.23, X) + _door_card(1, -1.08, -0.23, X)
    # a thick leather rim
    wheel = [CB.torus_rim("a75_rim", RIM_R, 0.017, 40, X["rim"], ts=10, squash=1.15)]
    PV._smoothed(wheel[0], 60)
    wheel += _wheel_pad(X)
    m = _column_frame()
    for o in wheel:
        C.apply_transform(o)
        o.data.transform(m)
    manual, auto = _gearbox_parts(X)
    items = [("SteeringWheel", wheel, tuple(HUB), None), ("GearKnob", [knob], None, None),
             ("Trans_Manual", manual, None, None), ("Trans_Auto", auto, None, None)]
    FRAMES["SteeringWheel"] = m
    for o, fm in needles:
        name = o.name
        C.apply_transform(o)
        items.append((name, [o], tuple(fm.translation), None))
        FRAMES[name] = fm
    odo_name = odo.name
    FRAMES[odo_name] = odo.matrix_world.copy()
    bpy.data.objects.remove(odo, do_unlink=True)
    items.append((odo_name, [], tuple(FRAMES[odo_name].translation), None))
    trims = {"L": _door_card(-1, DOOR_Y0, DOOR_Y1 - 0.03, X), "R": _door_card(1, DOOR_Y0, DOOR_Y1 - 0.03, X)}
    return parts, items, trims, tuple(tip)


def orient():
    """After build_city's build: give the steering wheel, needles and the
    odometer their own axes."""
    VC.FRAMES.clear()
    VC.FRAMES.update(FRAMES)
    VC.orient()
