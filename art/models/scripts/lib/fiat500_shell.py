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
DOOR_Y0, DOOR_Y1 = -0.70, 0.50

#        y        w     zb     zsh   zbelt  wbelt   zrs    wrs    zt
KEYS = [
    (-1.814, (0.16, 0.400, 0.44, 0.465, 0.14, 0.475, 0.10, 0.480)),
    (-1.808, (0.30, 0.345, 0.46, 0.535, 0.27, 0.548, 0.21, 0.555)),
    (-1.795, (0.40, 0.300, 0.48, 0.615, 0.36, 0.630, 0.29, 0.638)),
    (-1.775, (0.48, 0.265, 0.50, 0.685, 0.43, 0.700, 0.35, 0.708)),
    (-1.745, (0.56, 0.240, 0.52, 0.740, 0.505, 0.756, 0.41, 0.765)),
    (-1.700, (0.64, 0.222, 0.55, 0.785, 0.58, 0.802, 0.47, 0.812)),
    (-1.640, (0.71, 0.208, 0.58, 0.825, 0.66, 0.846, 0.53, 0.862)),
    (-1.560, (0.765, 0.198, 0.60, 0.845, 0.72, 0.868, 0.575, 0.888)),
    (-1.460, (0.797, 0.190, 0.62, 0.862, 0.755, 0.890, 0.605, 0.910)),
    (-1.300, (0.812, 0.186, 0.635, 0.885, 0.768, 0.915, 0.62, 0.938)),
    (-1.000, (0.815, 0.180, 0.66, 0.923, 0.772, 0.952, 0.635, 0.975)),
    (-0.820, (0.815, 0.180, 0.67, 0.945, 0.772, 0.975, 0.645, 0.995)),
    (-0.700, (0.815, 0.180, 0.68, 0.955, 0.770, 1.060, 0.655, 1.075)),
    (-0.600, (0.815, 0.180, 0.69, 0.960, 0.768, 1.130, 0.655, 1.140)),
    (-0.400, (0.815, 0.180, 0.70, 0.968, 0.765, 1.260, 0.645, 1.275)),
    (-0.250, (0.815, 0.180, 0.70, 0.975, 0.762, 1.345, 0.635, 1.365)),
    (-0.120, (0.815, 0.180, 0.70, 0.980, 0.760, 1.395, 0.625, 1.432)),
    (0.100, (0.815, 0.180, 0.70, 0.990, 0.757, 1.418, 0.620, 1.480)),
    (0.450, (0.815, 0.180, 0.70, 1.000, 0.755, 1.422, 0.615, 1.488)),
    (0.750, (0.815, 0.180, 0.70, 1.006, 0.752, 1.414, 0.610, 1.477)),
    (0.950, (0.813, 0.185, 0.70, 1.010, 0.748, 1.392, 0.600, 1.457)),
    (1.100, (0.810, 0.190, 0.70, 1.010, 0.742, 1.360, 0.590, 1.430)),
    (1.220, (0.805, 0.195, 0.70, 1.000, 0.735, 1.330, 0.580, 1.395)),
    (1.300, (0.800, 0.200, 0.69, 0.990, 0.728, 1.220, 0.580, 1.280)),
    (1.380, (0.792, 0.205, 0.68, 0.975, 0.720, 1.110, 0.600, 1.160)),
    (1.450, (0.782, 0.210, 0.67, 0.950, 0.715, 1.010, 0.630, 1.050)),
    (1.520, (0.770, 0.215, 0.66, 0.860, 0.710, 0.890, 0.640, 0.910)),
    (1.580, (0.755, 0.220, 0.64, 0.740, 0.700, 0.765, 0.630, 0.780)),
    (1.640, (0.740, 0.225, 0.58, 0.615, 0.680, 0.628, 0.600, 0.635)),
    (1.680, (0.705, 0.230, 0.53, 0.585, 0.64, 0.597, 0.56, 0.605)),
    (1.710, (0.650, 0.237, 0.49, 0.545, 0.59, 0.558, 0.51, 0.568)),
    (1.732, (0.570, 0.252, 0.45, 0.500, 0.52, 0.512, 0.44, 0.520)),
    (1.746, (0.460, 0.280, 0.41, 0.450, 0.42, 0.458, 0.35, 0.465)),
    (1.753, (0.320, 0.320, 0.38, 0.405, 0.29, 0.412, 0.24, 0.418)),
    (1.756, (0.180, 0.350, 0.37, 0.385, 0.16, 0.390, 0.13, 0.395)),
]

# points generated per section segment P0-P1 ... P7-P8
COUNTS = [1, 2, 2, 2, 3, 3, 2, 2]

# Window outlines. Side: (y, z) seen from the side; windscreen: (x, y) from
# above; rear window: (x, z) from behind.
DLO = [
    (-0.665, 0.972), (-0.55, 1.055), (-0.40, 1.165), (-0.25, 1.275), (-0.13, 1.345),
    (-0.02, 1.378), (0.15, 1.390), (0.45, 1.394), (0.75, 1.385), (0.93, 1.358),
    (1.03, 1.315), (1.085, 1.24), (1.11, 1.14), (1.115, 1.06), (1.09, 1.025),
    (0.80, 1.012), (0.40, 1.003), (0.0, 0.992), (-0.40, 0.980), (-0.60, 0.972),
]
B_PILLAR = (0.465, 0.555)
WINDSCREEN = [
    (-0.565, -0.806), (-0.608, -0.792), (-0.628, -0.755), (-0.600, -0.45), (-0.565, -0.205),
    (-0.545, -0.158), (-0.505, -0.134),
    (0.505, -0.134), (0.545, -0.158), (0.565, -0.205), (0.600, -0.45), (0.628, -0.755),
    (0.608, -0.792), (0.565, -0.806),
]
REAR_WINDOW = [
    (-0.580, 1.068), (-0.605, 1.10), (-0.575, 1.30), (-0.515, 1.352),
    (0.515, 1.352), (0.575, 1.30), (0.605, 1.10), (0.580, 1.068),
]


def _curves(abarth=False):
    ys = [k[0] for k in KEYS]
    cols = list(zip(*[k[1] for k in KEYS]))
    if abarth:
        # longer nose: the front stations move forward up to 6 cm
        ys = [y - 0.06 * max(0.0, (-1.46 - y) / 0.354) for y in ys]
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
    K.cut_arches(obj, (AXLE_F, AXLE_R), 0.33, 0.53, 0.29)
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


def classify(obj):
    """Retag the shell by geometry: doors and underside (window openings are
    already cut and tagged Glass by cut_windows)."""
    me = obj.data
    door_frame = K.offset_poly(clip_y(DLO, hi=B_PILLAR[0]), -0.075)
    for p in me.polygons:
        if p.material_index in (K.T_UNDER, K.T_GLASS):
            continue
        c, n = p.center, p.normal
        sx = 1 if c.x > 0 else -1
        tag = K.T_PAINT
        side = abs(c.x) > 0.40 and sx * n.x > 0.25
        if n.z < -0.55 and c.z < 0.32:
            tag = K.T_UNDER
        elif side and DOOR_Y0 < c.y < DOOR_Y1 and c.z > 0.27 and (
                c.z < 0.985 or K.inside_poly((c.y, c.z), door_frame)):
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
        ok, loc, nor, _ = target.ray_cast(Vector(o), Vector(d).normalized())
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
