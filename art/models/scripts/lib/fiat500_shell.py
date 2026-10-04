"""Body shape of the 2007-on 500: key curves -> smooth stations -> lofted shell.

Every column of KEYS is a curve along the car (y, metres, front at -Y), read
off side, plan and front views of the real car. They are interpolated with
monotone cubics, and each station's half section is a Catmull-Rom curve
through nine control points:

    P0 underside centre   P1 underside edge   P2 sill      P3 lower side
    P4 shoulder (widest)  P5 belt (window line)            P6 roof edge
    P7 roof shoulder      P8 roof centre

Window openings, glass and seals, the doors and the shut lines are cut or
projected afterwards from 2D outlines (see WINDOWS), so their edges follow
the real car rather than the loft rows.
"""
import math

import bpy  # noqa: F401,I001  (bpy must load before bmesh)
import bmesh
from mathutils import Vector

from . import carkit as K

WHEELBASE = 2.30
AXLE_F, AXLE_R = -WHEELBASE / 2, WHEELBASE / 2
# Door shut lines (y): the front one is also the hinge line. The door's
# window frame reaches forward of it up the A-pillar.
DOOR_Y0, DOOR_Y1 = -0.745, 0.48

# Measured off Ash's side photo (camera solved from the hubcaps) and the
# rear three-quarter photo: windscreen raked ~33 degrees with its base well
# forward (cowl at y -1.0), a high belt (1.0 at the A-pillar rising to 1.1
# behind the quarter glass), a short sloping tail with the lamps on the
# corners and a bumper that stands out below the tailgate.
#        y        w     zb     zsh   zbelt  wbelt   zrs    wrs    zt
KEYS = [
    (-1.814, (0.12, 0.4, 0.47, 0.528, 0.105, 0.548, 0.075, 0.56)),
    (-1.808, (0.22, 0.3, 0.48, 0.619, 0.195, 0.647, 0.15, 0.66)),
    (-1.795, (0.31, 0.25, 0.5, 0.69, 0.28, 0.723, 0.215, 0.74)),
    (-1.775, (0.39, 0.225, 0.51, 0.75, 0.35, 0.783, 0.27, 0.8)),
    (-1.745, (0.465, 0.212, 0.52, 0.785, 0.42, 0.822, 0.325, 0.838)),
    (-1.700, (0.545, 0.205, 0.53, 0.807, 0.49, 0.847, 0.38, 0.862)),
    (-1.650, (0.61, 0.202, 0.54, 0.817, 0.52, 0.861, 0.43, 0.878)),
    (-1.580, (0.675, 0.2, 0.56, 0.826, 0.58, 0.877, 0.48, 0.895)),
    (-1.480, (0.74, 0.198, 0.58, 0.83, 0.67, 0.89, 0.545, 0.915)),
    (-1.350, (0.792, 0.195, 0.6, 0.836, 0.73, 0.901, 0.57, 0.935)),
    (-1.200, (0.808, 0.192, 0.62, 0.845, 0.75, 0.913, 0.59, 0.952)),
    (-1.080, (0.813, 0.19, 0.64, 0.866, 0.765, 0.935, 0.61, 0.965)),
    (-1.000, (0.813, 0.190, 0.65, 0.900, 0.770, 0.950, 0.625, 0.975)),
    (-0.930, (0.813, 0.190, 0.66, 0.950, 0.772, 1.012, 0.64, 1.015)),
    (-0.830, (0.813, 0.190, 0.67, 0.982, 0.772, 1.075, 0.655, 1.080)),
    (-0.700, (0.813, 0.190, 0.68, 1.000, 0.770, 1.155, 0.655, 1.162)),
    (-0.560, (0.813, 0.190, 0.69, 1.012, 0.768, 1.240, 0.650, 1.252)),
    (-0.420, (0.813, 0.190, 0.70, 1.020, 0.765, 1.318, 0.645, 1.342)),
    (-0.300, (0.813, 0.190, 0.70, 1.027, 0.762, 1.380, 0.638, 1.415)),
    (-0.200, (0.813, 0.190, 0.70, 1.031, 0.760, 1.408, 0.632, 1.450)),
    (-0.050, (0.813, 0.190, 0.70, 1.039, 0.758, 1.420, 0.627, 1.472)),
    (0.150, (0.813, 0.190, 0.70, 1.046, 0.756, 1.428, 0.623, 1.484)),
    (0.400, (0.813, 0.190, 0.70, 1.054, 0.754, 1.430, 0.620, 1.488)),
    (0.700, (0.812, 0.190, 0.70, 1.068, 0.750, 1.426, 0.615, 1.484)),
    (0.900, (0.810, 0.192, 0.70, 1.085, 0.745, 1.414, 0.610, 1.472)),
    (1.000, (0.807, 0.195, 0.70, 1.095, 0.735, 1.400, 0.600, 1.462)),
    (1.080, (0.803, 0.198, 0.69, 1.090, 0.720, 1.370, 0.590, 1.440)),
    (1.160, (0.800, 0.200, 0.70, 1.080, 0.705, 1.300, 0.580, 1.345)),
    (1.240, (0.795, 0.205, 0.71, 1.060, 0.700, 1.205, 0.570, 1.245)),
    (1.320, (0.785, 0.210, 0.72, 1.035, 0.700, 1.110, 0.560, 1.145)),
    (1.400, (0.765, 0.215, 0.72, 0.990, 0.695, 1.040, 0.555, 1.070)),
    (1.460, (0.740, 0.220, 0.70, 0.950, 0.665, 0.975, 0.500, 0.980)),
    (1.520, (0.725, 0.225, 0.60, 0.770, 0.620, 0.825, 0.420, 0.845)),
    (1.560, (0.690, 0.235, 0.54, 0.690, 0.560, 0.715, 0.360, 0.728)),
    (1.620, (0.615, 0.250, 0.50, 0.665, 0.500, 0.690, 0.330, 0.700)),
    (1.680, (0.505, 0.270, 0.49, 0.650, 0.400, 0.672, 0.270, 0.680)),
    (1.710, (0.410, 0.290, 0.48, 0.625, 0.330, 0.650, 0.230, 0.658)),
    (1.725, (0.300, 0.310, 0.47, 0.595, 0.240, 0.615, 0.170, 0.622)),
    (1.732, (0.160, 0.340, 0.46, 0.550, 0.130, 0.565, 0.090, 0.572)),
]

# points generated per section segment P0-P1 ... P7-P8
COUNTS = [1, 2, 2, 2, 3, 3, 2, 2]
ARCH_R = 0.355

# Window outlines (inner edge of the black surround). Side: (y, z) seen
# from the side; windscreen: (x, y) from above; rear window: (x, z) from
# behind.
DLO = [
    (-0.805, 1.012), (-0.775, 1.055), (-0.68, 1.120), (-0.56, 1.192), (-0.45, 1.248), (-0.34, 1.290),
    (-0.23, 1.324), (-0.12, 1.352), (0.03, 1.378), (0.15, 1.388), (0.35, 1.390), (0.55, 1.388),
    (0.64, 1.380), (0.72, 1.358), (0.785, 1.318), (0.84, 1.262), (0.90, 1.165), (0.925, 1.125),
    (0.905, 1.112), (0.75, 1.104), (0.46, 1.086), (0.16, 1.077), (-0.40, 1.055), (-0.72, 1.030),
]
B_PILLAR = (0.36, 0.45)
WINDSCREEN = [
    (-0.548, -0.955), (-0.600, -0.915), (-0.623, -0.85), (-0.623, -0.60), (-0.605, -0.42),
    (-0.582, -0.36), (-0.538, -0.305), (-0.30, -0.278), (0.0, -0.272),
    (0.30, -0.278), (0.538, -0.305), (0.582, -0.36), (0.605, -0.42), (0.623, -0.60),
    (0.623, -0.85), (0.600, -0.915), (0.548, -0.955), (0.0, -0.99),
]
REAR_WINDOW = [
    (-0.50, 1.085), (-0.545, 1.115), (-0.555, 1.20), (-0.53, 1.33), (-0.47, 1.385),
    (0.47, 1.385), (0.53, 1.33), (0.555, 1.20), (0.545, 1.115), (0.50, 1.085),
]


GEN1_KEYS, GEN1_DLO, GEN1_B_PILLAR = KEYS, DLO, B_PILLAR
GEN1_WINDSCREEN, GEN1_REAR_WINDOW, GEN1_DOOR_Y = WINDSCREEN, REAR_WINDOW, (DOOR_Y0, DOOR_Y1)
BODY = "gen1"


# ------------------------------------------------------------------ 2020 body
#
# The new 500 (500e, 2020 on; the Abarth 500e; the 2025 500 Hybrid): 2322 mm
# wheelbase, 3632 x 1683 x 1527 mm. Read off a near-90-degree side photo
# (scaled by the wheelbase, heights x1.03 to the published height; the
# overhangs stretched to the published length, since the close camera
# shrinks the ends) and straight-on front and rear photos for the widths.
# Against the 2007 car: a touch longer in the nose, wider, a flatter roof
# that runs further back over a more upright, fuller tail, and a
# slightly higher belt.

def _gen2_keys():
    out = []
    f_over, r_over = 0.69, 0.59
    for y, (w, zb, zsh, zbelt, wbelt, zrs, wrs, zt) in GEN1_KEYS:
        if y > 1.0:
            break
        if y < -1.15:
            y2 = -1.161 + (y + 1.15) * f_over / 0.664
        else:
            y2 = y * 1.161 / 1.15
        k = 1.033
        rise = 0.04 * min(1.0, max(0.0, (1.0 - y2) / 1.6)) if y2 > -0.95 else 0.0
        if y2 >= -0.30:
            # flat roof, highest well behind the B-pillar
            zt2 = float(_ROOF2(y2))
            zrs2 = zt2 - (zt - zrs)
        else:
            zt2, zrs2 = zt + 0.01 * max(0.0, 1 + (y2 + 0.3) / 0.65), zrs + 0.01 * max(0.0, 1 + (y2 + 0.3) / 0.65)
        out.append((round(y2, 4), (w * k, zb - 0.015, zsh, zbelt + rise, wbelt * k, zrs2, wrs * k, zt2)))
    # the tail: the roof carries on to the spoiler at 1.16, then a steep
    # rear screen down to 1.40 and a full, nearly upright tail face
    #        y        w     zb     zsh   zbelt  wbelt   zrs    wrs    zt
    out += [
        (1.080, (0.838, 0.185, 0.70, 1.088, 0.735, 1.462, 0.605, 1.488)),
        (1.160, (0.836, 0.188, 0.70, 1.085, 0.725, 1.425, 0.595, 1.450)),
        (1.220, (0.834, 0.192, 0.70, 1.075, 0.700, 1.335, 0.585, 1.360)),
        (1.280, (0.828, 0.196, 0.70, 1.060, 0.690, 1.225, 0.575, 1.250)),
        (1.340, (0.818, 0.200, 0.70, 1.040, 0.680, 1.125, 0.565, 1.150)),
        (1.400, (0.800, 0.205, 0.69, 1.010, 0.655, 1.055, 0.540, 1.070)),
        (1.500, (0.775, 0.212, 0.66, 0.960, 0.620, 0.980, 0.480, 0.990)),
        (1.590, (0.735, 0.222, 0.60, 0.880, 0.580, 0.890, 0.420, 0.900)),
        (1.660, (0.665, 0.235, 0.54, 0.770, 0.520, 0.790, 0.360, 0.800)),
        (1.705, (0.560, 0.250, 0.50, 0.700, 0.440, 0.702, 0.300, 0.710)),
        (1.735, (0.420, 0.275, 0.48, 0.607, 0.330, 0.627, 0.230, 0.635)),
        (1.750, (0.240, 0.305, 0.46, 0.550, 0.190, 0.568, 0.130, 0.575)),
        (1.756, (0.120, 0.335, 0.45, 0.515, 0.095, 0.529, 0.065, 0.535)),
    ]
    return out


def _roof2(pts):
    ys, zs = zip(*pts)
    return K.pchip(list(ys), list(zs))


_ROOF2 = None

GEN2_DLO = [
    (-0.64, 1.050), (-0.59, 1.100), (-0.52, 1.170), (-0.43, 1.255), (-0.35, 1.325), (-0.27, 1.372),
    (-0.18, 1.395), (-0.05, 1.405), (0.10, 1.408), (0.40, 1.408), (0.60, 1.402), (0.72, 1.390),
    (0.80, 1.368), (0.86, 1.330), (0.92, 1.262), (0.97, 1.180), (1.010, 1.115), (1.018, 1.095),
    (0.80, 1.084), (0.50, 1.078), (0.10, 1.072), (-0.30, 1.064), (-0.55, 1.056),
]


def _densify(poly, step):
    """Closed outline with extra points every `step` m, so a seal projected
    round it follows the curve up the A-pillar instead of zigzagging."""
    out = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        n = max(1, int(math.dist(a, b) / step + 0.999))
        out += [(round(a[0] + (b[0] - a[0]) * k / n, 4), round(a[1] + (b[1] - a[1]) * k / n, 4)) for k in range(n)]
    return out


GEN2_DLO = _densify(GEN2_DLO, 0.06)
GEN2_B_PILLAR = (0.40, 0.49)
GEN2_DOOR_Y = (-0.75, 0.51)


def _gen2_windscreen():
    out = []
    for x, y in GEN1_WINDSCREEN:
        out.append((x, round(-0.285 + (y + 0.272) * 0.665 / 0.718, 4)))
    return out


GEN2_REAR_WINDOW = [
    (-0.50, 1.125), (-0.54, 1.155), (-0.555, 1.24), (-0.535, 1.345), (-0.48, 1.395),
    (0.48, 1.395), (0.535, 1.345), (0.555, 1.24), (0.54, 1.155), (0.50, 1.125),
]


def use(body="gen1"):
    """Switch every shape table in this module to one body: 'gen1' (the
    2007-on car) or 'gen2' (the 2020-on car). Builders call this first."""
    global KEYS, DLO, B_PILLAR, WINDSCREEN, REAR_WINDOW, DOOR_Y0, DOOR_Y1
    global WHEELBASE, AXLE_F, AXLE_R, ARCH_R, _ROOF2, BODY
    BODY = body
    if body == "gen2":
        _ROOF2 = _roof2([(-0.30, 1.452), (-0.20, 1.488), (-0.05, 1.512), (0.15, 1.524), (0.40, 1.527),
                         (0.70, 1.524), (0.90, 1.514), (1.00, 1.503), (1.08, 1.488)])
        KEYS = _gen2_keys()
        DLO, B_PILLAR = GEN2_DLO, GEN2_B_PILLAR
        # keep the glass, and the door frame round it, clear of the roof's
        # turn: the frame's top edge then runs inside one row of loft faces
        # instead of along the roof-side edge, where the cut would leave slivers
        zrs = _curves()[1][5]
        DLO = [(y, round(min(z, float(zrs(y)) - 0.072), 4)) if z > 1.2 else (y, z) for y, z in DLO]
        WINDSCREEN, REAR_WINDOW = _gen2_windscreen(), GEN2_REAR_WINDOW
        DOOR_Y0, DOOR_Y1 = GEN2_DOOR_Y
        WHEELBASE, ARCH_R = 2.322, 0.355
    else:
        KEYS, DLO, B_PILLAR = GEN1_KEYS, GEN1_DLO, GEN1_B_PILLAR
        WINDSCREEN, REAR_WINDOW = GEN1_WINDSCREEN, GEN1_REAR_WINDOW
        DOOR_Y0, DOOR_Y1 = GEN1_DOOR_Y
        WHEELBASE, ARCH_R = 2.30, 0.355
    AXLE_F, AXLE_R = -WHEELBASE / 2, WHEELBASE / 2


def _curves(abarth=False):
    ys = [k[0] for k in KEYS]
    cols = list(zip(*[k[1] for k in KEYS]))
    if abarth:
        # longer nose: the front stations move forward up to 8 cm, and the
        # deeper bumpers bring the underside down at both ends
        ys = [y - 0.08 * max(0.0, (-1.46 - y) / 0.354) for y in ys]
        zb = list(cols[1])
        for i, y in enumerate(ys):
            front = min(1.0, max(0.0, (-1.30 - y) / 0.40))
            rear = min(1.0, max(0.0, (y - 1.45) / 0.25))
            zb[i] -= 0.035 * front + 0.02 * rear
        cols[1] = tuple(zb)
    return ys, [K.pchip(ys, list(c)) for c in cols]


def station_ys(ys):
    """Fine spacing at the rounded ends, ~7 cm along the middle, plus the
    exact door edges."""
    out = set()
    for i in range(len(ys) - 1):
        a, b = ys[i], ys[i + 1]
        n = max(1, round((b - a) / 0.075))
        for k in range(n):
            out.add(round(a + (b - a) * k / n, 4))
    out.add(ys[-1])
    out.update((DOOR_Y0, DOOR_Y1))
    res = []
    for y in sorted(out):
        if res and y - res[-1] < 0.004:
            continue
        res.append(y)
    return res


def section(y, f):
    w, zb, zsh, zbelt, wbelt, zrs, wrs, zt = (c(y) for c in f)
    pts = [
        (0.0, zb), (w * 0.80, zb), (w - 0.045, zb + 0.06), (w - 0.008, (zb + zsh) / 2),
        (w, zsh), (wbelt, zbelt), (wrs, zrs), (wrs * 0.55, zt - 0.012), (0.0, zt),
    ]
    sampled, _ = K.catmull(pts, COUNTS)
    return K.Station(y, sampled)


def stations(abarth=False):
    ys, f = _curves(abarth)
    return [section(y, f) for y in station_ys(ys)]


def belt_z(y):
    _, f = _curves()
    return f[3](y)


def shell(abarth=False):
    st = stations(abarth)
    verts, faces, tags, uvs = K.loft(st, lambda *a: K.T_PAINT)
    obj = K.shell_object("shell", verts, faces, tags, uvs)
    K.cut_arches(obj, (AXLE_F, AXLE_R), ARCH_R, (0.44, 0.53), 0.30)
    return obj, st


def zone_fn(st):
    """(u, v) on the shell UVs -> (zone, lowness) for the worn paint texture.

    zone is 'roof', 'bonnet', 'top' (other upward surfaces) or 'side';
    lowness 0..1 grows toward the sills (road grime)."""
    n = len(st)
    npts = len(st[0].pts)

    def f(u, v):
        x = min(max(u, 0), 1) * (n - 1)
        i = min(int(x), n - 2)
        t = x - i
        k = min(max(v, 0), 1) * (npts - 1)
        j = min(int(k), npts - 2)
        s = k - j

        def at(sti):
            p, q = st[sti].pts[j], st[sti].pts[j + 1]
            return p[0] + (q[0] - p[0]) * s, p[1] + (q[1] - p[1]) * s
        (xa, za), (xb, zb_) = at(i), at(i + 1)
        y = st[i].y + (st[i + 1].y - st[i].y) * t
        px, z = xa + (xb - xa) * t, za + (zb_ - za) * t
        low = min(1.0, max(0.0, (0.48 - z) / 0.26))
        if z > 1.36 and -0.15 < y < 1.2:
            return "roof", low
        if y < -0.80 and z > 0.80 and px < 0.74:
            return "bonnet", low
        if j >= 10:
            return "top", low
        return "side", low
    return f


# ------------------------------------------------------------------ regions

def clip_y(poly, lo=None, hi=None):
    """Clip a (y, z) polygon to lo <= y <= hi (Sutherland-Hodgman)."""
    def clip(pts, keep, cut):
        out = []
        for i in range(len(pts)):
            a, b = pts[i - 1], pts[i]
            ka, kb = keep(a), keep(b)
            if kb:
                if not ka:
                    out.append(cut(a, b))
                out.append(b)
            elif ka:
                out.append(cut(a, b))
        return out

    def at_y(y0):
        def cut(a, b):
            t = (y0 - a[0]) / (b[0] - a[0])
            return (y0, a[1] + (b[1] - a[1]) * t)
        return cut
    pts = list(poly)
    if lo is not None:
        pts = clip(pts, lambda p: p[0] >= lo, at_y(lo))
    if hi is not None:
        pts = clip(pts, lambda p: p[0] <= hi, at_y(hi))
    return pts


def _prism(poly, place, d0, d1):
    """Closed prism over a 2D outline; place(u, v, d) -> (x, y, z)."""
    from . import common as C
    n = len(poly)
    verts = [place(u, v, d0) for u, v in poly] + [place(u, v, d1) for u, v in poly]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    o = C.mesh_obj("window_cutter", verts, faces, bpy.data.materials["tag_Glass"])
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


def cut_windows(obj):
    """Boolean the window openings. The cutters' own faces come out tagged
    Glass, which no split group keeps, so only the clean holes remain."""
    cutters = [
        _prism(DLO, lambda u, v, d: (d, u, v), 0.35, 1.5),
        _prism(DLO, lambda u, v, d: (d, u, v), -1.5, -0.35),
        _prism(WINDSCREEN, lambda u, v, d: (u, v, d), 0.92, 2.5),
        _prism(REAR_WINDOW, lambda u, v, d: (u, d, v), 1.05, 2.5),
    ]
    for c in cutters:
        mod = obj.modifiers.new("win", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = c
        mod.solver = "EXACT"
        mod.material_mode = "TRANSFER"
        with bpy.context.temp_override(object=obj, active_object=obj):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(c, do_unlink=True)


def door_frame_poly():
    """Side outline (y, z) of the door's window frame: the side glass grown
    by the frame width, ending at the back of the black B-pillar band (the
    quarter glass is in the body behind it)."""
    poly = clip_y(K.offset_poly(DLO, -0.05), hi=B_PILLAR[1])
    return _simplify(poly, 0.008) if BODY == "gen2" else poly


def _simplify(poly, eps):
    """Ramer-Douglas-Peucker on a closed outline: fewer, longer straight runs
    for the door frame, so its cut meets the loft at fewer joints."""
    def rdp(pts):
        if len(pts) < 3:
            return pts
        (ay, az), (by, bz) = pts[0], pts[-1]
        L = math.hypot(by - ay, bz - az) or 1e-9
        d = [abs((by - ay) * (az - pz) - (ay - py) * (bz - az)) / L for py, pz in pts[1:-1]]
        i = max(range(len(d)), key=d.__getitem__)
        if d[i] < eps:
            return [pts[0], pts[-1]]
        return rdp(pts[:i + 2])[:-1] + rdp(pts[i + 1:])
    pts = list(poly)
    far = max(range(len(pts)), key=lambda i: math.dist(pts[0], pts[i]))
    return rdp(pts[:far + 1])[:-1] + rdp(pts[far:] + [pts[0]])[:-1]


def _cut_frame_edge(obj, frame):
    """Slice the shell along the top of the door frame (up the A-pillar and
    along the roof to the B-pillar), so the door's faces end on that line
    instead of a staircase of whole loft faces. Only the 2020 body's long
    raked pillar needs it."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    # the frame's upper run: from its front foot up the pillar and back along
    # the roof, until the outline turns forward again along the belt
    edge = [(y, z) for y, z in frame if z > 1.0]
    turn = next((i for i in range(1, len(edge)) if edge[i][0] < edge[i - 1][0]), len(edge))
    edge = edge[:turn]
    for (y0, z0), (y1, z1) in zip(edge, edge[1:]):
        n = Vector((0, -(z1 - z0), y1 - y0)).normalized()
        lo_y, hi_y = min(y0, y1) - 0.01, max(y0, y1) + 0.01
        lo_z, hi_z = min(z0, z1) - 0.01, max(z0, z1) + 0.01

        def near(f):
            # the face's own extent overlaps this segment's box
            ys = [v.co.y for v in f.verts]
            zs = [v.co.z for v in f.verts]
            return min(ys) < hi_y and max(ys) > lo_y and min(zs) < hi_z and max(zs) > lo_z

        faces = [f for f in bm.faces if abs(f.calc_center_median().x) > 0.40 and near(f)]
        if not faces:
            continue
        geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector((0, y0, z0)), plane_no=n, dist=1e-4)
    bm.to_mesh(obj.data)
    bm.free()


def classify(obj):
    """Retag the shell by geometry: doors and underside (window openings are
    already cut and tagged Glass by cut_windows)."""
    door_frame = door_frame_poly()
    if BODY == "gen2":
        _cut_frame_edge(obj, door_frame)
    me = obj.data
    _, f = _curves()
    belt = f[3]
    for p in me.polygons:
        if p.material_index in (K.T_UNDER, K.T_GLASS):
            continue
        c, n = p.center, p.normal
        sx = 1 if c.x > 0 else -1
        tag = K.T_PAINT
        side = abs(c.x) > 0.40 and sx * n.x > 0.2
        if n.z < -0.55 and c.z < 0.32:
            tag = K.T_UNDER
        elif side and c.y < DOOR_Y1 and c.z > 0.34 and (
                (c.y > DOOR_Y0 and c.z < belt(c.y) + 0.01) or K.inside_poly((c.y, c.z), door_frame)):
            tag = K.T_DL if sx > 0 else K.T_DR
        p.material_index = tag


def shut_lines(obj, material, width=0.012):
    """Thin dark strips along the borders between door and body faces."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    doors = (K.T_DL, K.T_DR)
    verts, faces = [], []
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        a, b = (f.material_index for f in e.link_faces)
        if (a in doors) == (b in doors) or K.T_GLASS in (a, b):
            continue
        n = (e.link_faces[0].normal + e.link_faces[1].normal).normalized()
        v1, v2 = e.verts[0].co, e.verts[1].co
        side = n.cross(v2 - v1).normalized() * width / 2
        lift = n * 0.002
        i = len(verts)
        verts += [v1 - side + lift, v2 - side + lift, v2 + side + lift, v1 + side + lift]
        faces.append((i, i + 1, i + 2, i + 3))
    bm.free()
    from . import common as C
    o = C.mesh_obj("shut_lines", [tuple(v) for v in verts], faces, material)
    return o


def ribbon(name, target, rays, width, material, offset=0.003):
    """Strip along the surface hit by each (origin, direction) ray."""
    from . import common as C
    hits = []
    for o, d in rays:
        ok, loc, nor, _ = K.surface_ray(target, o, d)
        if ok:
            hits.append((loc, nor))
    verts, faces = [], []
    for i, (p, n) in enumerate(hits):
        a = hits[max(i - 1, 0)][0]
        b = hits[min(i + 1, len(hits) - 1)][0]
        side = n.cross(b - a).normalized() * width / 2
        verts += [tuple(p - side + n * offset), tuple(p + side + n * offset)]
    for i in range(len(hits) - 1):
        faces.append((2 * i, 2 * i + 2, 2 * i + 3, 2 * i + 1))
    o = C.mesh_obj(name, verts, faces, material)
    material.use_backface_culling = False
    return o


def plane_frame(center, normal):
    """2D (u, v) -> ray onto the surface along -normal; u horizontal, v up."""
    n = Vector(normal).normalized()
    u_ax = Vector((0, 0, 1)).cross(n).normalized()
    v_ax = n.cross(u_ax).normalized()
    c = Vector(center)
    return lambda u, v: (tuple(c + u_ax * u + v_ax * v + n * 2), tuple(-n))


def rounded_rect(w, h, r, segs=3):
    """Rounded rectangle centred on 0 (counter-clockwise)."""
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
                       (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(segs + 1):
            a = math.radians(a0 + 90 * k / segs)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts
