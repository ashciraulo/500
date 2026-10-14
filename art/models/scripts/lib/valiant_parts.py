"""Bolt-on parts for the driveable VC Valiant (data/parts/*_vc_*.tres), on
the cars/ contract (art/models/README.md, "Found parts"): each glb's origin
is at its mount on the Valiant, nose +Y here (the Valiant isn't turned at
export, so that's -Z in Godot), built in the car's frame before the axle
shift and moved to the mount.

- seatcover_vc_sheepskin: a sheepskin over one half of the split bench, at
  Seat_L (the game mirrors it for Seat_R).
- exhaust_vc_twin: two pipes side by side out under the back bumper, at
  Mount_Exhaust.
- wheel_vc_whitewall_l/_r, wheel_vc_slot_l/_r: road wheels like the stock
  wheel_vc ones, origin at the hub, axle along X.
"""
import math
import random

from mathutils import Matrix, Vector

from . import common as C
from . import carkit as K
from . import period_vehicles as PV

# Seat_L, the passenger's hip on the bench (valiant_car_finish)
SEAT_L = Vector((-PV.HIP[0], PV.HIP[1], PV.HIP[2]))
MOUNT_EXHAUST = Vector((-0.45, PV.YR + 0.04, 0.3))


# ------------------------------------------------------------ sheepskin

# The bench as lib/valiant_cabin.py builds it (y forward, z up): the cushion
# runs right across the car, the back is split down the middle.
CUSHION_FRONT = 0.47
# Over the cushion's front edge, back along its top, into the crease and up
# the backrest's face, over its top: (y, z) just outside the upholstery.
SKIN_PATH = [(0.455, 0.505), (0.478, 0.545), (0.47, 0.592), (0.43, 0.618), (0.32, 0.616), (0.18, 0.611),
             (0.05, 0.604), (-0.025, 0.598), (-0.048, 0.64), (-0.058, 0.76), (-0.072, 0.88), (-0.09, 0.97),
             (-0.13, 1.055), (-0.19, 1.086), (-0.243, 1.058), (-0.262, 1.0)]
HALF_W = 0.285                # half the skin's width across the seat
ROWS = 40
COLS = 15


def _fleece_image():
    """Cream wool in tight tufts, a little uneven: 32 x 32."""
    rnd = random.Random(11)
    tuft = [[rnd.random() for _ in range(32)] for _ in range(32)]

    def px(x, y):
        # tufts are about 4 px: blend a coarse cell value with fine grain
        cx, cy = x // 4, y // 4
        cell = tuft[(cy * 7) % 32][(cx * 5) % 32]
        grain = tuft[y][x]
        k = 0.82 + 0.12 * cell + 0.08 * grain - (0.06 if (x + 2 * y) % 4 == 0 else 0.0)
        # warm enough that the sky's blue fill in the cabin leaves it cream
        return (0.97 * k, 0.72 * k, 0.40 * k)
    return C.make_image("VC_Fleece", 32, 32, px)


def _outline(t, side):
    """Half-width of the skin at t (0 front .. 1 over the top) on one side:
    a sheepskin's ragged edge, wider over the cushion, drawn in at the
    crease and the shoulders."""
    base = HALF_W
    if t < 0.08:                                  # the front flap narrows a little
        base -= 0.03 * (1 - t / 0.08)
    if 0.40 < t < 0.52:                           # tucked into the crease
        base -= 0.025 * math.sin((t - 0.40) / 0.12 * math.pi)
    if t > 0.9:                                   # rounded off over the top
        base -= 0.06 * ((t - 0.9) / 0.1) ** 2
    wave = 0.012 * math.sin(t * 23.0 + side * 1.7) + 0.006 * math.sin(t * 57.0 + side)
    return base + wave


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


def seatcover_sheepskin():
    """One sheepskin over the passenger's half of the bench (x < 0), from
    over the cushion's front edge to over the top of the backrest, origin at
    Seat_L. A bench has no bolsters, so the edges lie flat and ragged."""
    rnd = random.Random(5)
    path = _resample(SKIN_PATH, ROWS)
    verts, faces, uvs = [], [], []
    for ri, (y, z) in enumerate(path):
        a, b = path[max(ri - 1, 0)], path[min(ri + 1, ROWS - 1)]
        ty, tz = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(ty, tz) or 1.0
        ny, nz = tz / ln, -ty / ln                  # outward: the path keeps the seat on its right
        t = ri / (ROWS - 1)
        for ci in range(COLS):
            s = ci / (COLS - 1) * 2 - 1             # -1 door side .. +1 middle
            w = _outline(t, -1 if s < 0 else 1)
            x = SEAT_L.x + s * w
            # the fleece stands up most in the middle and thins at the edges
            pile = 0.008 + 0.018 * (1 - s * s) + 0.005 * rnd.random()
            verts.append((x, y + ny * pile, z + nz * pile))
            uvs.append((s * w / 0.12, t * 1.1 / 0.12))
    for ri in range(ROWS - 1):
        for ci in range(COLS - 1):
            a = ri * COLS + ci
            faces.append((a, a + COLS, a + COLS + 1, a + 1))
    wool = C.mat("VC_Sheepskin", image=_fleece_image(), rough=1.0)
    o = C.mesh_obj("SeatCover", verts, faces, wool)
    uvl = o.data.uv_layers.new(name="UVMap")
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            uvl.data[li].uv = uvs[o.data.loops[li].vertex_index]
    K.solidify(o, 0.01, C.mat("VC_SheepHide", "#b59a74", rough=0.9))
    PV._smoothed(o, 40)
    return [_to_mount(o, SEAT_L)]


def _to_mount(o, at):
    """Move a part built in the car's frame so its origin is the mount."""
    C.apply_transform(o)
    o.data.transform(Matrix.Translation(-at))
    return o


# ------------------------------------------------------------ twin pipes

PIPE_R = 0.027
PIPE_GAP = 0.07               # centre to centre


def exhaust_twin():
    """Two round pipes side by side out under the back bumper on the left,
    each with a plain chrome tip, the outer one over the stock pipe so it
    hides it, the second just inboard of it. A band clamps them together
    under the boot floor and a rod hangs them from it. Origin at
    Mount_Exhaust (the stock pipe's end)."""
    dark = C.mat("VC_PipeSteel", "#3a3633", rough=0.7, metal=0.4)
    chrome = PV._mats()["chrome"]
    soot = C.mat("VC_PipeSoot", "#0b0b0b", rough=1.0)
    out = []
    for x in (0.0, PIPE_GAP):
        out.append(PV.cyl(PIPE_R, 0.44, (x, 0.25, 0.0), dark, segs=12, axis="Y"))
        out.append(PV.cyl(PIPE_R + 0.004, 0.09, (x, 0.035, 0.0), chrome, segs=14, axis="Y"))
        # the open end: soot a hair proud of the tip's face
        out.append(PV.cyl(PIPE_R - 0.005, 0.004, (x, -0.0115, 0.0), soot, segs=12, axis="Y"))
        out.append(PV.cyl(PIPE_R + 0.007, 0.018, (x, 0.2, 0.0), dark, segs=12, axis="Y"))
    # the hanger: a rod from between the bands up to the boot floor
    out.append(PV.cyl(0.006, 0.12, (PIPE_GAP / 2, 0.2, 0.05), dark, segs=6))
    out.append(PV.cyl(0.006, PIPE_GAP, (PIPE_GAP / 2, 0.2, 0.0), dark, segs=6, axis="X"))
    for o in out:
        PV._smoothed(o, 40)
    return out


# ------------------------------------------------------------ wheels

# The tyre's outer sidewall, (radius, offset) from the tread shoulder to
# the bead, as lib/period_vehicles.py's _wheel has it.
_SIDEWALL = [(0.293, 0.074), (0.276, 0.082), (0.262, 0.087)]
_BEAD = (0.19, 0.086)


def _tyre(sx, outer, white_from=None):
    """The tyre: the stock wheel's inner sidewall and tread, then `outer`
    (radius, offset) points down the outer sidewall to the bead; the band
    starting at index white_from of `outer` is white."""
    inner = [(0.19, -0.083), (0.262, -0.087), (0.293, -0.074), (PV.TYRE_R, -0.045), (PV.TYRE_R, 0.045)]
    prof = inner + outer
    white = None if white_from is None else len(inner) + white_from
    M = PV._mats()
    if sx < 0:
        prof = [(r, -o) for r, o in reversed(prof)]
        white = None if white is None else len(prof) - 2 - white
    o = K.revolve("tyre", prof, 32, lambda i: M["white"] if i == white else M["tyre"])
    return _smoothed(o, 50)


def _side(prof, sx):
    return [(r, sx * o) for r, o in (prof if sx > 0 else list(reversed(prof)))]


def _smoothed(o, angle):
    C.apply_transform(o)
    return PV._smoothed(PV._fix_normals(o), angle)


def wheel_whitewall(sx):
    """A Regal's wheel: a full chrome wheel cover over the steel wheel, on a
    tyre with a wide whitewall. The cover runs out to the tyre's bead: a
    shallow dished outer ring with two raised beads, a stepped crown, and
    a domed centre with a small painted medallion (no badge)."""
    M = PV._mats()
    medal = C.mat("VC_Medallion", "#7a1a1c", rough=0.4, metal=0.3)
    groove = C.mat("VC_CoverGroove", "#5d6266", rough=0.4, metal=0.8)
    # wide whitewall: white from just under the shoulder most of the way to
    # the rim, about 6 cm of a 14-inch tyre's sidewall
    tyre = _tyre(sx, _SIDEWALL + [(0.258, 0.0875), (0.204, 0.0885), _BEAD], white_from=3)
    cover = [(0.192, 0.083), (0.186, 0.089), (0.176, 0.086), (0.168, 0.084), (0.162, 0.087),
             (0.156, 0.084), (0.145, 0.084), (0.139, 0.088), (0.132, 0.086), (0.118, 0.089),
             (0.112, 0.097), (0.098, 0.100), (0.072, 0.106), (0.05, 0.110), (0.036, 0.113),
             (0.03, 0.116), (0.0, 0.118)]
    # two grooves a little darker so the rings read far off, and a dark
    # ring round the medallion
    dark_bands = {5, 13}
    mat_of = (lambda i: medal if i >= 15 else groove if i in dark_bands else M["chrome"])
    n = len(cover) - 1
    c = K.revolve("cover", _side(cover, sx), 32, mat_of if sx > 0 else (lambda i: mat_of(n - 1 - i)))
    rim = PV.cyl(0.19, 0.16, (0, 0, 0), M["dark"], segs=32, axis="X")
    return C.join([tyre, _smoothed(c, 50), rim], "Wheel")


SLOTS = 6
LUG_R = 0.057                 # the VC's five studs on a 4.5-inch circle


def wheel_slot(sx):
    """A 1970s cast slot mag on a plain black radial: a polished lip, a
    flat grey alloy face with six long slots round it, five chrome nuts
    and a small domed centre cap."""
    M = PV._mats()
    alloy = C.mat("VC_MagAlloy", "#9b9d9c", rough=0.45, metal=0.7)
    hole = C.mat("VC_MagSlot", "#111112", rough=0.9)
    tyre = _tyre(sx, _SIDEWALL + [(0.232, 0.088), _BEAD])
    face_o = 0.062
    rim = [(0.198, 0.083), (0.196, 0.088), (0.186, 0.089), (0.179, 0.083), (0.168, 0.066), (0.162, face_o),
           (0.076, face_o), (0.072, 0.068), (0.04, 0.069), (0.036, 0.075), (0.026, 0.082), (0.0, 0.084)]
    n = len(rim) - 1
    mat_of = (lambda i: M["chrome"] if i < 3 or i >= 8 else alloy)
    r = K.revolve("rim", _side(rim, sx), 36, mat_of if sx > 0 else (lambda i: mat_of(n - 1 - i)))
    p = [tyre, _smoothed(r, 40)]
    # the slots: long rounded holes, a hair proud of the face
    x = sx * (face_o + 0.0008)
    r1, r2, hw = 0.09, 0.146, 0.016
    for k in range(SLOTS):
        a = 2 * math.pi * (k + 0.5) / SLOTS
        ca, sa = math.cos(a), math.sin(a)
        outline = []
        for j in range(7):                 # the outer end's half circle
            t = -math.pi / 2 + math.pi * j / 6
            outline.append((r2 - hw + hw * math.cos(t), hw * math.sin(t)))
        for j in range(7):                 # the inner end's
            t = math.pi / 2 + math.pi * j / 6
            outline.append((r1 + hw + hw * math.cos(t), hw * math.sin(t)))
        pts = [(u * ca - v * sa, u * sa + v * ca) for u, v in outline]
        if sx < 0:
            pts.reverse()
        p.append(C.mesh_obj("slot", [(x, y, z) for y, z in pts], [tuple(range(len(pts)))], hole))
    for k in range(5):
        a = 2 * math.pi * k / 5
        p.append(PV.cyl(0.0095, 0.014, (sx * 0.075, LUG_R * math.cos(a), LUG_R * math.sin(a)), M["chrome"],
                        segs=6, axis="X"))
    # the barrel, behind the face
    p.append(PV.cyl(0.19, 0.11, (0, 0, 0), M["dark"], segs=32, axis="X"))
    return C.join(p, "Wheel")
