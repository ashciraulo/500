"""Alfa 75 wheels and bolt-on parts, built like lib/valiant_parts.py.

- wheel_a75_l/_r: the 2.5 6V's stock 14-inch alloy on a 195/60 tyre: a
  white-silver dish with a ring of round holes round the centre nut, a
  cone of 24 radial slots near the rim and a polished lip.
- wheel_a75_simmons_l/_r: three-piece Simmons B45 style wheels (no
  maker's mark): five flat gunmetal spokes, a ring of rim bolts, a deep
  polished lip and a small black centre cap with a bar, on a lower tyre.

Every wheel has its origin at the hub, axle along X, the outer face toward
+X for sx = +1 (the driver's side) and -X for sx = -1.
"""

import math
import random

from mathutils import Matrix, Vector

from . import common as C
from . import carkit as K
from . import period_vehicles as PV

TYRE_R = 0.295


def _mats():
    return {
        "tyre": C.mat("A75_Tyre", "#1b1b1c", rough=0.92),
        "silver": C.mat("A75_WheelSilver", "#dfe0dd", rough=0.4, metal=0.25),
        "lip": C.mat("A75_WheelLip", "#eceeef", rough=0.12, metal=0.92),
        "hole": C.mat("A75_WheelHole", "#0d0d0e", rough=0.95),
        "barrel": C.mat("A75_WheelBarrel", "#2a2b2c", rough=0.7, metal=0.4),
        "nut": C.mat("A75_WheelNut", "#a9abac", rough=0.3, metal=0.9),
        "gunmetal": C.mat("A75_Gunmetal", "#6b6e72", rough=0.5, metal=0.6),
        "cap": C.mat("A75_CapBlack", "#151516", rough=0.5, metal=0.2),
    }


def _side(prof, sx):
    return [(r, sx * o) for r, o in (prof if sx > 0 else list(reversed(prof)))]


def _rev(name, prof, sx, segs, mat_of):
    n = len(prof) - 1
    o = K.revolve(name, _side(prof, sx), segs, mat_of if sx > 0 else (lambda i: mat_of(n - 1 - i)))
    C.apply_transform(o)
    return PV._smoothed(PV._fix_normals(o), 45)


def _tyre(sx, bead_r, half_w=0.097):
    """A plain black radial from the bead at bead_r out to TYRE_R."""
    side = TYRE_R - bead_r
    out = [(bead_r, half_w - 0.006), (bead_r + 0.35 * side, half_w), (bead_r + 0.75 * side, half_w - 0.004),
           (TYRE_R - 0.008, half_w - 0.02), (TYRE_R, half_w - 0.045)]
    inner = [(r, -o) for r, o in out]
    prof = inner + list(reversed(out))
    M = _mats()
    return _rev("tyre", prof, sx, 36, lambda i: M["tyre"])


def _flat(name, pts, x, mat, sx):
    """A flat polygon facing out (sx) at offset x, pts as (y, z)."""
    pts = list(pts) if sx > 0 else list(reversed(pts))
    return C.mesh_obj(name, [(sx * x, y, z) for y, z in pts], [tuple(range(len(pts)))], mat)


def _polar(r, a):
    return (r * math.cos(a), r * math.sin(a))


def _oval(cr, a, half_r, half_t, n=12):
    """A rounded hole centred at radius cr, angle a: half_r along the radius,
    half_t across it."""
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        u, v = cr + half_r * math.cos(t), half_t * math.sin(t)
        pts.append((u * ca - v * sa, u * sa + v * ca))
    return pts


def wheel_stock(sx):
    """The 75 2.5's stock alloy: a white-silver dish, flat in the middle with
    six round holes about the centre nut, a cone of 24 radial slots sloping
    out toward the rim and a polished lip."""
    M = _mats()
    p = [_tyre(sx, 0.186)]
    face = 0.078
    r0, r1, x0, x1 = 0.171, 0.13, 0.05, 0.073      # the slot cone: rim end, hub end

    def cone(r):
        return x0 + (x1 - x0) * (r0 - r) / (r0 - r1)
    rim = [(0.196, 0.088), (0.195, 0.093), (0.187, 0.094), (0.181, 0.087), (0.176, 0.066),
           (r0, x0), (r1, x1), (0.125, face - 0.002), (0.119, face), (0.03, face), (0.027, face - 0.004),
           (0.0, face - 0.004)]
    p.append(_rev("rim", rim, sx, 48, lambda i: M["lip"] if i < 3 else M["silver"]))
    for k in range(24):
        pts = _oval(0.1505, 2 * math.pi * (k + 0.5) / 24, 0.018, 0.0092)
        pts = pts if sx > 0 else list(reversed(pts))
        p.append(C.mesh_obj("hole", [(sx * (cone(math.hypot(y, z)) + 0.0009), y, z) for y, z in pts],
                            [tuple(range(len(pts)))], M["hole"]))
    for k in range(6):
        a = 2 * math.pi * k / 6 + math.pi / 6
        p.append(_flat("hole", _oval(0.058, a, 0.0125, 0.0125), face + 0.0008, M["hole"], sx))
    p.append(PV.cyl(0.017, 0.018, (sx * (face + 0.004), 0, 0), M["nut"], segs=6, axis="X"))
    p.append(PV.cyl(0.186, 0.12, (sx * -0.02, 0, 0), M["barrel"], segs=32, axis="X"))
    return C.join(p, "Wheel")


SIMMONS_BOLTS = 24


def _window(a, r0, r1, half_deg):
    """One gap between two spokes: a rounded wedge from r0 out to r1,
    half_deg wide either side of a at r1, drawing to a point near r0."""
    h = math.radians(half_deg)
    pts = [_polar(r0, a)]
    for k in range(7):
        pts.append(_polar(r1, a - h + 2 * h * k / 6))
    return PV._round_poly(pts, 0.012, 3)


def wheel_simmons(sx):
    """Three-piece Simmons B45 style wheel: five flat gunmetal spokes with
    wedge-shaped gaps, a gunmetal outer ring with 24 bright rim bolts, a
    deep polished outer lip and barrel, four nuts and a small black
    centre cap with a bright bar across it. Lower tyre on a 15-inch rim."""
    M = _mats()
    p = [_tyre(sx, 0.196, half_w=0.1)]
    face = 0.045
    # the outer piece: a wide flat polished lip facing out, stepping down
    # at its inner edge to the spokes' ring
    lip = [(0.203, 0.088), (0.203, 0.095), (0.198, 0.098), (0.164, 0.093), (0.158, 0.088), (0.156, face + 0.01),
           (0.152, face)]
    p.append(_rev("lip", lip, sx, 40, lambda i: M["lip"]))
    centre = [(0.152, face), (0.06, face), (0.055, face + 0.006), (0.034, face + 0.008), (0.0, face + 0.008)]
    p.append(_rev("centre", centre, sx, 40, lambda i: M["gunmetal"]))
    for k in range(5):
        a = 2 * math.pi * (k + 0.5) / 5 + math.pi / 2
        p.append(_flat("window", _window(a, 0.06, 0.136, 27), face + 0.0008, M["hole"], sx))
    for k in range(SIMMONS_BOLTS):
        y, z = _polar(0.145, 2 * math.pi * k / SIMMONS_BOLTS)
        p.append(PV.cyl(0.0042, 0.006, (sx * (face + 0.003), y, z), M["nut"], segs=6, axis="X"))
    for k in range(4):
        y, z = _polar(0.045, 2 * math.pi * k / 4 + math.pi / 4)
        p.append(PV.cyl(0.0075, 0.012, (sx * (face + 0.012), y, z), M["nut"], segs=6, axis="X"))
    p.append(PV.cyl(0.024, 0.01, (sx * (face + 0.013), 0, 0), M["cap"], segs=16, axis="X"))
    p.append(PV._prism("bar", [(-0.019, -0.0035), (0.019, -0.0035), (0.019, 0.0035), (-0.019, 0.0035)],
                       "x", sx * (face + 0.017), sx * (face + 0.0195), M["lip"]))
    p.append(PV.cyl(0.192, 0.1, (sx * -0.02, 0, 0), M["barrel"], segs=32, axis="X"))
    return C.join(p, "Wheel")


def wheel_teledial(sx):
    """The later 75's "telephone dial" alloy: a flat silver face with five
    big round holes round a small centre cap, a narrow polished lip."""
    M = _mats()
    p = [_tyre(sx, 0.186)]
    face = 0.07
    rim = [(0.196, 0.088), (0.195, 0.093), (0.188, 0.093), (0.183, 0.086), (0.17, face + 0.004),
           (0.165, face), (0.034, face), (0.03, face + 0.006), (0.0, face + 0.008)]
    p.append(_rev("rim", rim, sx, 40, lambda i: M["lip"] if i < 3 else M["silver"]))
    for k in range(5):
        p.append(_flat("hole", _oval(0.112, 2 * math.pi * k / 5 + math.pi / 2, 0.036, 0.036, n=16),
                       face + 0.0008, M["hole"], sx))
    for k in range(4):
        y, z = _polar(0.05, 2 * math.pi * k / 4 + math.pi / 4)
        p.append(PV.cyl(0.0075, 0.012, (sx * (face + 0.006), y, z), M["nut"], segs=6, axis="X"))
    p.append(PV.cyl(0.186, 0.13, (sx * -0.01, 0, 0), M["barrel"], segs=32, axis="X"))
    return C.join(p, "Wheel")


WHEELS = {"a75": wheel_stock, "a75_simmons": wheel_simmons, "a75_teledial": wheel_teledial}


# ------------------------------------------------------------ bolt-ons

# The mounts as lib/alfa75.py and lib/alfa75_cabin.py place them, in the
# build's frame (front +Y, the driver on +X): parts are built there and
# moved so their origin is the mount.
def _seat_l():
    from . import alfa75_cabin as CAB
    return Vector((-CAB.HIP[0], CAB.HIP[1], CAB.HIP[2]))


def _to_mount(o, at):
    C.apply_transform(o)
    o.data.transform(Matrix.Translation(-at))
    return o


PIPE_R = 0.03


def exhaust_sport():
    """A stainless sport exhaust: two big round tips side by side out under
    the back bumper on the left, the outer one over the stock pipe, a band
    and a hanger holding them. Origin at Mount_Exhaust."""
    steel = C.mat("A75_PipeSteel", "#5b5856", rough=0.5, metal=0.6)
    tip = C.mat("A75_PipeTip", "#cfd2d3", rough=0.2, metal=0.9)
    soot = C.mat("A75_PipeSoot", "#0b0b0b", rough=1.0)
    out = []
    for x in (0.0, 0.075):
        out.append(PV.cyl(PIPE_R - 0.004, 0.4, (x, 0.24, 0.0), steel, segs=12, axis="Y"))
        out.append(PV.cyl(PIPE_R + 0.004, 0.12, (x, 0.05, 0.0), tip, segs=16, axis="Y", r_top=PIPE_R + 0.006))
        out.append(PV.cyl(PIPE_R - 0.002, 0.004, (x, -0.0115, 0.0), soot, segs=12, axis="Y"))
    out.append(PV.cyl(0.006, 0.12, (0.0375, 0.2, 0.05), steel, segs=6))
    out.append(PV.cyl(0.006, 0.075, (0.0375, 0.2, 0.0), steel, segs=6, axis="X"))
    for o in out:
        PV._smoothed(o, 40)
    return out


# Over the passenger's bucket seat (lib/alfa75_cabin.py's profiles): from
# the cushion's front edge back along its top, into the crease and up the
# back's face to over its top, (y, z) just outside the velour.
BEAD_PATH = [(-0.045, 0.47), (-0.055, 0.528), (-0.12, 0.548), (-0.3, 0.542), (-0.5, 0.532), (-0.555, 0.53),
             (-0.585, 0.58), (-0.61, 0.70), (-0.64, 0.86), (-0.665, 1.0), (-0.69, 1.072), (-0.73, 1.085),
             (-0.765, 1.065)]
BEAD_HALF_W = 0.19


def _bead_image():
    """Wooden beads on cord: round brown beads, dark gaps, 32 x 32."""
    rnd = random.Random(7)
    tone = [[0.75 + 0.3 * rnd.random() for _ in range(8)] for _ in range(8)]

    def px(x, y):
        cx, cy = x % 4 - 1.5, y % 4 - 1.5
        r = math.hypot(cx, cy)
        if r > 2.0:
            return (0.06, 0.04, 0.03)
        k = tone[y // 4][x // 4] * (1.05 - 0.25 * r / 2.0)
        return (0.55 * k, 0.33 * k, 0.17 * k)
    return C.make_image("A75_Beads", 32, 32, px)


def seatcover_beads():
    """A wooden-bead cover over the passenger's bucket, front edge to over
    the top of the back, origin at Seat_L; mirror X for Seat_R."""
    seat = _seat_l()
    rows, cols = 30, 9
    pts = _resample(BEAD_PATH, rows)
    verts, faces, uvs = [], [], []
    for ri, (y, z) in enumerate(pts):
        a, b = pts[max(ri - 1, 0)], pts[min(ri + 1, rows - 1)]
        ty, tz = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(ty, tz) or 1.0
        ny, nz = tz / ln, -ty / ln
        for ci in range(cols):
            s = ci / (cols - 1) * 2 - 1
            x = seat.x + s * BEAD_HALF_W
            lift = 0.012 + 0.004 * (1 - s * s)
            verts.append((x, y + ny * lift, z + nz * lift))
            uvs.append((s * BEAD_HALF_W / 0.08, ri / (rows - 1) * 1.2 / 0.08))
    for ri in range(rows - 1):
        for ci in range(cols - 1):
            k = ri * cols + ci
            faces.append((k, k + cols, k + cols + 1, k + 1))
    o = C.mesh_obj("SeatCover", verts, faces, C.mat("A75_BeadCover", image=_bead_image(), rough=0.6))
    uvl = o.data.uv_layers.new(name="UVMap")
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            uvl.data[li].uv = uvs[o.data.loops[li].vertex_index]
    if o.data.polygons[0].normal.z < 0:
        o.data.flip_normals()
    K.solidify(o, 0.008, C.mat("A75_BeadCord", "#2a1d14", rough=0.9))
    PV._smoothed(o, 40)
    return [_to_mount(o, seat)]


def _resample(pts, n):
    d = [0.0]
    for a, b in zip(pts, pts[1:]):
        d.append(d[-1] + math.dist(a, b))
    out = []
    for i in range(n):
        t = d[-1] * i / (n - 1)
        k = min(max(j for j in range(len(d)) if d[j] <= t + 1e-9), len(pts) - 2)
        f = (t - d[k]) / max(d[k + 1] - d[k], 1e-9)
        out.append((pts[k][0] + (pts[k + 1][0] - pts[k][0]) * f, pts[k][1] + (pts[k + 1][1] - pts[k][1]) * f))
    return out


PARTS = {"exhaust_a75_sport": exhaust_sport, "seatcover_a75_beads": seatcover_beads}
