"""Period cars for the late city (story batch 3 and on): props, not drivable.

  valiant  A 1966/67 Australian Chrysler VC Valiant sedan, 4.78 x 1.75 x 1.40
           (wheelbase 2.69), in sage green, with no badges or script
           anywhere. It has a full-width grille with single round headlamps
           at its ends under a flat bonnet, slab sides with a chrome spear,
           a tall thin-pillared greenhouse, small rear fins carrying tall
           vertical tail lamps, chrome bumpers, and body-coloured steel
           wheels with dog-dish hubcaps and thin whitewalls. The reference
           photos and the feature checklist are in
           /mnt/project-files/models/valiant-vc/.

Same conventions as lib/traffic_vehicles.py: front toward +Y (Godot -Z), the
kerb side on -X (driver on +X), origin on the ground at the footprint centre,
no wheel nodes. "Paint" is the body colour (recolourable). Lamps are their
own meshes so code can light them: HeadL/HeadR, ParkL/ParkR (the parking
lamps in the front bumper, for "parkers on") and TailL/TailR.

The body is lofted through cross sections along the car. Each section is a
half profile (x >= 0) from the underside centre round the side to the top
centre; the other side is mirrored.

Builders return (objs, empties) in lib/city_vehicles.py's form.
"""
import math

import bpy  # noqa: F401,I001  (bpy must load before bmesh)
import bmesh

from . import common as C
from . import furniture as F
from . import city_vehicles as CV
from . import carkit as K

bx, cyl = F.bx, F.cyl
_m = CV._m

L, W, H = 4.782, 1.753, 1.397
WB = 2.692
YF, YR = L / 2, -L / 2
AXLE_F = YF - 0.808
AXLE_R = AXLE_F - WB
HW = W / 2
TYRE_R = 0.305
TRACK_X = HW - 0.115   # the wheels' centre planes, either side
BELT = 0.955
ROOF = H - 0.012


def _mats():
    M = CV._common()
    M.update({
        "paint": _m("Paint", "#657f57", 0.45, 0.05),
        "glass": C.mat("VC_Glass", "#6d8893", rough=0.03, metal=0.35, alpha=0.5),
        "trim": _m("VC_Trim", "#56604f", 0.85),
        "liner": _m("VC_Headliner", "#cfcbbb", 0.9),
        "chrome": _m("VC_Chrome", "#dfe2e3", 0.15, 0.95),
        "grille": _m("VC_GrilleBack", "#141516", 0.7),
        "dark": _m("VC_Dark", "#1c1d1f", 0.8),
        # shut lines: a deep olive, not black, so a line thinner than a pixel
        # far off fades into the paint instead of breaking into black dots
        "shut": _m("VC_Shut", "#3b4a33", 0.7),
        "head": _m("VC_HeadLamp", "#e4ebe8", 0.04, 0.45),
        "park": _m("VC_Parker", "#efe2c2", 0.25),
        "tail": _m("VC_TailLamp", "#a3171a", 0.25),
        "amber": _m("VC_Amber", "#e48a1c", 0.3),
        "plate": _m("VC_Plate", "#16171a", 0.7),
        "white": _m("VC_Whitewall", "#e9e7df", 0.7),
        "tyre": _m("VC_Tyre", "#18181a", 0.92),
    })
    return M


def _fix_normals(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


def _loft(name, sections, mat):
    """A closed body through sections [(y, [(x, z), ...]), ...]: each a half
    profile from (0, bottom) round to (0, top), all the same length."""
    verts, faces = [], []
    ring = None
    for y, half in sections:
        full = [(x, z) for x, z in half] + [(-x, z) for x, z in reversed(half[1:-1])]
        ring = len(full)
        verts += [(x, y, z) for x, z in full]
    n = len(sections)
    for s in range(n - 1):
        a, b = s * ring, (s + 1) * ring
        for i in range(ring):
            j = (i + 1) % ring
            faces.append((a + i, a + j, b + j, b + i))
    faces.append(tuple(range(ring)))
    faces.append(tuple(range((n - 1) * ring, n * ring)))
    return _fix_normals(C.mesh_obj(name, verts, faces, mat))


def _prism(name, pts, axis, a0, a1, mat):
    """Extrude a closed outline across an axis: pts are (u, v) in the plane of
    the other two axes in order (y, z) for 'x', (x, z) for 'y', (x, y) for 'z'."""
    v = []
    for a in (a0, a1):
        for u, w in pts:
            v.append({"x": (a, u, w), "y": (u, a, w), "z": (u, w, a)}[axis])
    n = len(pts)
    f = [tuple(range(n)), tuple(range(n, 2 * n))]
    f += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return _fix_normals(C.mesh_obj(name, v, f, mat))


def _smoothed(o, angle):
    """Shade smooth, with edges sharper than angle (degrees) kept hard."""
    K.smooth(o, angle)
    return o


def _sweep(name, half_plan, profile, centre, mat):
    """A bumper blade: profile (d, z) pairs, d <= 0 measured in from the outer
    face, swept along a plan path (x, y, depth scale) given for the right
    half from the middle out; the left half mirrors it. centre is a point
    inside the car, so each section's outward normal points away from it."""
    plan = [(-x, y, k) for x, y, k in reversed(half_plan[1:])] + list(half_plan)
    n, m = len(plan), len(profile)
    v, f = [], []
    for i, (x, y, k) in enumerate(plan):
        xa, ya, _ = plan[max(i - 1, 0)]
        xb, yb, _ = plan[min(i + 1, n - 1)]
        tx, ty = xb - xa, yb - ya
        ln = math.hypot(tx, ty)
        nx, ny = ty / ln, -tx / ln
        if nx * (x - centre[0]) + ny * (y - centre[1]) < 0:
            nx, ny = -nx, -ny
        for d, z in profile:
            v.append((x + nx * d * k, y + ny * d * k, z))
    for i in range(n - 1):
        for j in range(m):
            jj = (j + 1) % m
            f.append((i * m + j, (i + 1) * m + j, (i + 1) * m + jj, i * m + jj))
    f.append(tuple(range(m)))
    f.append(tuple((n - 1) * m + j for j in range(m)))
    return _smoothed(_fix_normals(C.mesh_obj(name, v, f, mat)), 32)


def _flat(name, pts, mat):
    """One flat polygon through 3D points (both faces, so it shows either way)."""
    n = len(pts)
    return C.mesh_obj(name, pts, [tuple(range(n)), tuple(reversed(range(n)))], mat)


# ------------------------------------------------------------------ body shell
#
# The painted body is one closed shell lofted through ~90 cross sections.
# Each half section is a Catmull-Rom curve through twelve control points:
#
#   P0 underside centre  P1 underside edge  P2 sill roll   P3 lower side
#   P4 widest (0.72)     P5 under the crease               P6 shoulder crease
#                                                             (the fin crest at the back)
#   P7 inboard of the crease (the fin's valley)
#   P8 belt / glass base (on the bonnet and boot: out on the deck)
#   P9 roof edge (A and C pillar lines on the screens)       P10 roof shoulder
#   P11 roof / deck centre
#
# Every key is a curve along the car read off the photos with matched
# cameras. The ends are rounded over (a fillet), then the wheel arches, the
# grille opening, the recessed rear panel between the fins and the window
# openings are cut out with booleans, and the shell is given a thickness.

Y0, Y1 = YR + 0.07, YF - 0.07        # shell ends: the bumpers stand beyond them
WS_B, WS_T = 0.82, 0.46              # windscreen base, roof front edge
BL_B, BL_T = -1.29, -0.89            # backlight base, roof rear edge
ZB = 0.958                           # belt (glass base)
ZR = ROOF + 0.004                    # roof centre
WR = 0.722                           # roof edge half width (tumblehome)
FIL_F, FIL_R = 0.036, 0.024           # end fillet radii

_W = K.pchip([Y0, -2.15, -1.8, -1.4, 1.6, 1.95, 2.2, Y1],
             [HW - 0.012, HW - 0.006, HW - 0.002, HW, HW, HW - 0.003, HW - 0.01, HW - 0.022])
_ZB = K.pchip([Y0, -2.15, -1.85, -1.5, 1.9, 2.1, Y1], [0.46, 0.38, 0.34, 0.33, 0.33, 0.37, 0.45])
# the shoulder crease: low at the nose, up to the belt, a level crest along the fins
_ZC = K.pchip([Y0, -2.0, -1.6, -1.29, 0.5, 0.86, 1.2, 1.6, Y1],
              [0.92, 0.93, 0.938, 0.942, 0.936, 0.915, 0.885, 0.858, 0.84])
# deck edge: the bonnet runs flush with the fender tops, the boot lid sits
# down between the fins
_ZD_F = K.pchip([0.86, 1.2, 1.6, Y1], [0.912, 0.882, 0.855, 0.836])
_ZD_R = K.pchip([Y0, -2.15, -1.8, -1.4], [0.872, 0.89, 0.914, 0.936])
_CROWN = 0.014


def _screen_frac(t, top):
    """How far up the screen (0 base .. 1 roof) a station t of the way along
    it sits: nearly straight, rolling over into the roof at the top."""
    return K.pchip([0.0, 0.5, 0.88, 1.0], [0.0, 0.51, top, 1.0])(t)


def _controls(y):
    w, zb, zc = _W(y), _ZB(y), _ZC(y)
    # the side is widest at a soft crease just above the spear, tucks under
    # below it and leans in a touch up to the shoulder
    pts = [(0.0, zb), (w - 0.09, zb), (w - 0.035, zb + 0.04), (w - 0.012, max(0.52, zb + 0.12)),
           (w - 0.001, min(0.81, zc - 0.06)), (w + 0.004, zc - 0.008), (w - 0.008, zc + 0.002)]
    if y > WS_B + 0.001 or y < BL_B - 0.001:
        zd = _ZD_F(y) if y > 0 else _ZD_R(y)
        c = _CROWN
        # the bonnet rises to a soft peak down its centre; the boot is crowned
        mid = 0.3 if y > 0 else 0.85
        if y > 0:
            # the peak fades out towards the bonnet's front edge
            c = 0.02 + 0.012 * min(1.0, max(0.0, (Y1 - 0.06 - y) / 0.25))
        else:
            c = 0.03
        edge = [(w - 0.04, zd + 0.004), (w - 0.08, zd + 0.15 * c), (w - 0.11, zd + 0.25 * c)]
        f = min(1.0, max(0.0, (-1.45 - y) / 0.4)) if y < 0 else 0.0
        if f > 0:
            # towards the tail the side runs straight up (no flare) to a crisp
            # crest along the outer edge: the fin. Its top falls away inboard
            # to the boot lid's edge, a few cm lower.
            pts[4:7] = [(w - 0.001, zc - 0.075), (w - 0.004 * f, zc - 0.03), (w - 0.016, zc - 0.005 * f)]
            pod = [(w - 0.038, zc), (w - 0.08, zc - 0.014), (PANEL_X - 0.012, zd + 0.008)]
            edge = [(a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f) for a, b in zip(edge, pod)]
        pts += edge + [(0.42 * w, zd + mid * c), (0.0, zd + c)]
        return pts
    pts += [(w - 0.03, ZB - 0.008), (w - 0.075, ZB)]
    if WS_T <= y <= WS_B:
        f = _screen_frac((WS_B - y) / (WS_B - WS_T), 0.93)
    elif BL_B <= y <= BL_T:
        f = _screen_frac((y - BL_B) / (BL_T - BL_B), 0.94)
    else:
        f = 1.0

    def lerp(a, b):
        return a + (b - a) * f
    pts += [(lerp(w - 0.08, WR), lerp(ZB + 0.004, ZR - 0.05)),
            (lerp(0.45 * w, WR - 0.1), lerp(ZB + 0.012, ZR - 0.004)),
            (0.0, lerp(ZB + 0.016, ZR))]
    return pts


_COUNTS = [3, 2, 2, 2, 3, 1, 1, 1, 1, 4, 3, 4]


def _catmull(points, counts):
    """Centripetal Catmull-Rom through 2D points (no loops or overshoot where
    neighbouring points are close); counts[i] samples per segment."""
    P = [tuple(2 * a - b for a, b in zip(points[0], points[1]))] + list(points) + \
        [tuple(2 * a - b for a, b in zip(points[-1], points[-2]))]

    def tj(ti, a, b):
        return ti + max(math.hypot(b[0] - a[0], b[1] - a[1]), 1e-6) ** 0.5

    out = []
    for i in range(len(points) - 1):
        p0, p1, p2, p3 = P[i], P[i + 1], P[i + 2], P[i + 3]
        t0 = 0.0
        t1 = tj(t0, p0, p1)
        t2 = tj(t1, p1, p2)
        t3 = tj(t2, p2, p3)
        for k in range(counts[i]):
            t = t1 + (t2 - t1) * k / counts[i]

            def lerp(a, b, ta, tb):
                return tuple(((tb - t) * u + (t - ta) * v) / (tb - ta) for u, v in zip(a, b))
            a1, a2, a3 = lerp(p0, p1, t0, t1), lerp(p1, p2, t1, t2), lerp(p2, p3, t2, t3)
            b1, b2 = lerp(a1, a2, t0, t2), lerp(a2, a3, t1, t3)
            out.append(lerp(b1, b2, t1, t2))
    out.append(tuple(points[-1]))
    return out


def _profile(y):
    return _catmull(_controls(y), _COUNTS[:11])


def _normals2d(pts):
    """Outward normal at each point: the mean of its two segments' normals."""
    def seg(a, b):
        tx, tz = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(tx, tz) or 1.0
        return tz / ln, -tx / ln
    out = [(0.0, -1.0)]
    for i in range(1, len(pts) - 1):
        (ax, az), (bx_, bz) = seg(pts[i - 1], pts[i]), seg(pts[i], pts[i + 1])
        nx, nz = ax + bx_, az + bz
        ln = math.hypot(nx, nz) or 1.0
        out.append((nx / ln, nz / ln))
    out.append((0.0, 1.0))
    return out


def _station_ys():
    keys = [Y0, -2.15, -1.8, BL_B - 0.06, BL_B, BL_T, 0.0, WS_T, WS_B, WS_B + 0.04, 1.6, Y1]
    ys = set()
    for a, b in zip(keys, keys[1:]):
        n = max(1, round((b - a) / 0.06))
        ys.update(round(a + (b - a) * k / n, 4) for k in range(n + 1))
    # the ends: a quarter-round fillet, sampled at 0, 30 and 60 degrees
    for end, r, sgn in ((Y0, FIL_R, 1), (Y1, FIL_F, -1)):
        for deg in ((30, 60, 90) if r < 0.03 else (20, 40, 55, 70, 80, 90)):
            ys.add(round(end + sgn * r * (1 - math.cos(math.radians(deg))), 4))
    out = []
    for y in sorted(ys):
        if out and y - out[-1] < 0.003:
            continue
        out.append(y)
    return out


def _stations():
    st = []
    for y in _station_ys():
        pts = _profile(y)
        for end, r in ((Y0, FIL_R), (Y1, FIL_F)):
            s = abs(y - end)
            if s < r:
                d = r - math.sqrt(max(r * r - (r - s) ** 2, 0.0))
                nrm = _normals2d(pts)
                pts = [(max(x - nx * d, 0.0) if i not in (0, len(pts) - 1) else 0.0, z - nz * d)
                       for i, ((x, z), (nx, nz)) in enumerate(zip(pts, nrm))]
        st.append(K.Station(y, pts))
    return st


def _cutter(name, poly, place, d0, d1, tag):
    n = len(poly)
    verts = [place(u, v, d0) for u, v in poly] + [place(u, v, d1) for u, v in poly]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    o = C.mesh_obj(name, verts, faces, bpy.data.materials["tag_" + tag])
    return _fix_normals(o)


def _cut(obj, cutter):
    mod = obj.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    mod.material_mode = "TRANSFER"
    with bpy.context.temp_override(object=obj, active_object=obj):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def _round_poly(poly, r, segs=4):
    """Round every corner of a 2D polygon by r (quadratic Bezier corners)."""
    out = []
    n = len(poly)
    for i in range(n):
        a, b, c = poly[i - 1], poly[i], poly[(i + 1) % n]
        la = math.hypot(a[0] - b[0], a[1] - b[1])
        lc = math.hypot(c[0] - b[0], c[1] - b[1])
        rr = min(r, la / 2.05, lc / 2.05)
        p = (b[0] + (a[0] - b[0]) * rr / la, b[1] + (a[1] - b[1]) * rr / la)
        q = (b[0] + (c[0] - b[0]) * rr / lc, b[1] + (c[1] - b[1]) * rr / lc)
        for k in range(segs + 1):
            t = k / segs
            out.append(((1 - t) ** 2 * p[0] + 2 * t * (1 - t) * b[0] + t * t * q[0],
                        (1 - t) ** 2 * p[1] + 2 * t * (1 - t) * b[1] + t * t * q[1]))
    return out


def _a_line(z):
    """Side view (y) of the A pillar's outer edge at height z."""
    return WS_B - (WS_B - WS_T) * (z - ZB) / (ZR - 0.05 - ZB)


def _c_line(z):
    return BL_B + (BL_T - BL_B) * (z - ZB) / (ZR - 0.05 - ZB)


DLO_Z0, DLO_Z1 = ZB + 0.018, ZR - 0.078
# side glass openings (y, z): front door glass back to the B pillar, rear
# door glass back to its slanted rear edge; round top corners
SIDE_FRONT = _round_poly([(_a_line(DLO_Z0) - 0.05, DLO_Z0), (0.005, DLO_Z0), (0.005, DLO_Z1),
                          (_a_line(DLO_Z1) - 0.05, DLO_Z1)], 0.03)
REAR_GLASS_Y = -0.8                # the rear door glass's back edge at the belt
SIDE_REAR = _round_poly([(-0.07, DLO_Z0), (REAR_GLASS_Y, DLO_Z0), (REAR_GLASS_Y + 0.04, DLO_Z1),
                         (-0.07, DLO_Z1)], 0.03)
# screens in plan (x, y)
WINDSCREEN = _round_poly([(-0.745, WS_B - 0.022), (0.745, WS_B - 0.022), (WR - 0.058, WS_T + 0.03),
                          (-(WR - 0.058), WS_T + 0.03)], 0.07)
BACKLIGHT = _round_poly([(-0.71, BL_B + 0.03), (-(WR - 0.11), BL_T - 0.035), (WR - 0.11, BL_T - 0.035),
                         (0.71, BL_B + 0.03)], 0.06)
GRILLE_X, GRILLE_Z0, GRILLE_Z1, GRILLE_D = HW - 0.076, 0.478, 0.8, 0.075
PANEL_X, PANEL_D = 0.735, 0.04
LID_EDGE = 0.725                         # the boot lid's lower edge, over the rear panel


def _grille_outline():
    """The grille opening (x, z): full width, its bottom edge stepping down
    round each headlamp."""
    z0, zs = GRILLE_Z0, GRILLE_Z0 + 0.035
    return _round_poly([(-GRILLE_X, z0), (-0.57, z0), (-0.53, zs), (0.53, zs), (0.57, z0), (GRILLE_X, z0),
                        (GRILLE_X, GRILLE_Z1), (-GRILLE_X, GRILLE_Z1)], 0.06, 4)


def _side_place(sx):
    return lambda u, v, d: (sx * d, u, v)


def _shell(M):
    """The painted body, cut and thickened, plus the glass made against the
    uncut surface. Returns (body parts, glass parts, reference surface)."""
    st = _stations()
    verts, faces, tags, uvs = K.loft(st, lambda *a: K.T_PAINT)
    # K.loft builds rings bottom-centre first; our y runs rear to front
    body = K.shell_object("shell", verts, faces, tags, uvs)
    # the end caps are big concave polygons: fill them with triangles first
    from mathutils.geometry import tessellate_polygon
    bm = bmesh.new()
    bm.from_mesh(body.data)
    for f in [f for f in bm.faces if len(f.verts) > 4]:
        vs, mi = list(f.verts), f.material_index
        tris = tessellate_polygon([[v.co.copy() for v in vs]])
        bm.faces.remove(f)
        for t in tris:
            nf = bm.faces.new([vs[i] for i in t])
            nf.material_index = mi
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(body.data)
    bm.free()
    for y, r in ((AXLE_F, TYRE_R + 0.062), (AXLE_R, TYRE_R + 0.052)):
        for sx in (-1, 1):
            arch = C.cylinder("arch", r, 0.5, segs=36, axis="X", loc=(sx * 0.82, y, TYRE_R),
                              material=bpy.data.materials["tag_Under"])
            C.apply_transform(arch)
            _cut(body, _fix_normals(arch))
    # grille opening at the front, the rear panel set in between the fins
    _cut(body, _cutter("grille_cut", _grille_outline(), lambda u, v, d: (u, d, v),
                       Y1 - GRILLE_D, Y1 + 1.0, "Under"))
    # (y, z) outline of what comes off between the fins: the rear panel face,
    # rolling forward over the boot lid's rounded trailing edge
    r = 0.085
    zl = _ZD_R(Y0 + PANEL_D + r) + 0.03          # the lid's crown at its rear edge
    lid = [(Y0 + PANEL_D + r - r * math.cos(math.radians(a)), zl - r + r * math.sin(math.radians(a)))
           for a in range(0, 91, 10)]
    pnl = [(Y0 - 1.0, 0.47), (Y0 + PANEL_D, 0.47)] + lid + [(Y0 + PANEL_D + r, 1.3), (Y0 - 1.0, 1.3)]
    _cut(body, _cutter("panel_cut", pnl, lambda u, v, d: (d, u, v), -PANEL_X, PANEL_X, "Paint"))
    # below the lid's edge the rear panel steps back a little
    step = [(Y0 - 1.0, 0.47), (Y0 + PANEL_D + 0.012, 0.47), (Y0 + PANEL_D + 0.012, LID_EDGE),
            (Y0 - 1.0, LID_EDGE)]
    _cut(body, _cutter("panel_step", step, lambda u, v, d: (d, u, v), -PANEL_X + 0.012, PANEL_X - 0.012, "Paint"))
    # each tail lamp sits deep in a recess in its fin's end
    for sx in (-1, 1):
        _cut(body, _cutter("lamp_pocket", _tail_frame(sx)[0], lambda u, v, d: (u, d, v), Y0 - 0.5, Y0 + 0.032,
                           "Under"))
    # a copy of the uncut greenhouse to lay the glass and the frames on
    ref = body.copy()
    ref.data = body.data.copy()
    C.link(ref)
    for sx in (-1, 1):
        for poly in (SIDE_FRONT, SIDE_REAR):
            _cut(body, _cutter("win", poly, _side_place(sx), 0.4, 1.5, "Glass"))
    _cut(body, _cutter("ws", WINDSCREEN, lambda u, v, d: (u, v, d), 0.975, 2.5, "Glass"))
    _cut(body, _cutter("bl", BACKLIGHT, lambda u, v, d: (u, v, d), 0.975, 2.5, "Glass"))
    parts = K.split_by_tag(body, {"body": {"Paint": M["paint"], "Under": M["dark"], "Trim": M["trim"]}},
                           smooth_angle=38)
    body = parts["body"]
    # the booleans leave seams of doubled vertices; weld them so the
    # thickness doesn't cap them over
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(body.data)
    bm.free()
    K.solidify(body, 0.012, M["trim"])
    return body, ref


def _glass_and_frames(M, ref, body):
    """Glass laid just under the uncut surface, chrome frames round each
    opening laid on the cut body."""
    p = []
    top = K.top_frame()
    for sx in (-1, 1):
        fr = K.side_frame(sx)
        for poly in (SIDE_FRONT, SIDE_REAR):
            p.append(K.project_poly("glass", ref, K.offset_poly(poly, -0.012), fr, M["glass"], offset=-0.006))
            ring = K.project_poly("frame", body, K.offset_poly(poly, -0.022), fr, None, offset=0.004,
                                  border=0.013, border_mat=M["chrome"])
            p.append(ring)
    for x0, x1 in ((-0.62, -0.1), (0.04, 0.56)):
        p.append(K.project_line("wiper", ref, _dense([(x0, WS_B - 0.05), (x1, WS_B - 0.035)]), top, 0.01,
                                M["trim"], offset=0.006))
    for poly in (WINDSCREEN, BACKLIGHT):
        p.append(K.project_poly("glass", ref, K.offset_poly(poly, -0.012), top, M["glass"], offset=-0.006))
        p.append(K.project_poly("frame", body, K.offset_poly(poly, -0.024), top, None, offset=0.004,
                                border=0.015, border_mat=M["chrome"]))
    return p


def _nose(M):
    """In the grille opening: the bars, a chrome surround at its lip, and a
    dark nacelle with a proud chrome ring for each headlamp."""
    from . import cabin as CB
    p = []
    yb = Y1 - GRILLE_D            # back of the opening
    for i in range(12):
        z = GRILLE_Z0 + 0.03 + i * (GRILLE_Z1 - GRILLE_Z0 - 0.06) / 11
        p.append(bx((-0.6, yb + 0.012, z - 0.003), (0.6, yb + 0.04, z + 0.003), M["chrome"]))
    # chrome lip round the opening
    g, gi = K.offset_poly(_grille_outline(), -0.006), K.offset_poly(_grille_outline(), 0.016)
    p.append(_ring("grille_lip", [(x, Y1 + 0.012, z) for x, z in g], [(x, Y1 + 0.012, z) for x, z in gi],
                   M["chrome"]))
    # its outer edge turns back into the opening, so the lip stands proud
    p.append(_ring("grille_lip_side", [(x, Y1 + 0.012, z) for x, z in g], [(x, Y1 - 0.02, z) for x, z in g],
                   M["chrome"]))
    for sx in (-1, 1):
        x = sx * 0.69
        pocket = _round_poly([(x - 0.115, 0.545), (x + 0.115, 0.545), (x + 0.115, 0.77), (x - 0.115, 0.77)],
                             0.05, 4)
        p.append(_prism("lamp_pocket", pocket, "y", yb, yb + 0.03, M["dark"]))
        # a short chrome cup the lamp sits in, its rim standing proud
        p.append(K.revolve("lamp_cup", [(0.102, yb + 0.01), (0.104, Y1 - 0.024), (0.096, Y1 - 0.014)], 28,
                           lambda i: M["chrome"]))
        p[-1].rotation_euler = (0, 0, math.radians(90))
        p[-1].location = (x, 0, 0.655)
        ring = CB.torus_rim("bezel", 0.094, 0.011, 28, M["chrome"], ts=6)
        ring.location = (x, Y1 - 0.016, 0.655)
        p.append(ring)
    return p


def _ring(name, outer_pts, inner_pts, mat):
    """A flat frame between two matching outlines (both faces)."""
    n = len(outer_pts)
    f = []
    for i in range(n):
        j = (i + 1) % n
        f.append((i, j, n + j, n + i))
        f.append((n + i, n + j, j, i))
    return C.mesh_obj(name, list(outer_pts) + list(inner_pts), f, mat)


def _dense(pts, step=0.025):
    """Extra points along a polyline so a ribbon laid on the body follows
    its curves instead of cutting through them."""
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        n = max(1, math.ceil(math.hypot(b[0] - a[0], b[1] - a[1]) / step))
        out += [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(1, n + 1)]
    return out


def _line(name, body, pts, frame, width, mat, offset):
    return K.project_line(name, body, _dense(pts), frame, width, mat, offset=offset)


def _trim(M, body):
    """Chrome and shut lines laid on the body: the side spear, drip rails,
    door, bonnet and boot shut lines, the cowl vent, door handles, the
    driver's mirror and the aerial."""
    p = []
    for sx in (-1, 1):
        fr = K.side_frame(sx)
        p.append(_line("spear", body, [(Y0 + 0.12, 0.79), (Y1 - 0.2, 0.79)], fr, 0.016, M["chrome"], 0.004))
        p.append(_line("drip", body, [(BL_T + 0.02, ZR - 0.06), (WS_T - 0.02, ZR - 0.06)], fr, 0.016,
                                M["chrome"], 0.007))
        # doors: front door from the A pillar base to the B pillar, rear door
        # round the arch
        # the rear door's back edge drops straight from behind its glass to
        # the arch, then follows the arch down
        yd = REAR_GLASS_Y - 0.1
        a0 = math.degrees(math.acos((yd - AXLE_R) / 0.395))
        arch = [(AXLE_R + 0.395 * math.cos(math.radians(a)), TYRE_R + 0.395 * math.sin(math.radians(a)))
                for a in [a0] + list(range(int(a0) // 10 * 10, 9, -10))]
        lines = [
            [(0.93, ZB - 0.006), (0.93, 0.37), (-0.035, 0.37), (-0.035, ZB - 0.006)],
            [(-0.06, ZB - 0.006), (-0.06, 0.37), (arch[-1][0], 0.37)] + list(reversed(arch)) +
            [(yd, ZB - 0.006)],
        ]
        for ln in lines:
            p.append(_line("shut", body, ln, fr, 0.006, M["shut"], 0.004))
        for y in (0.1, -0.69):
            p.append(K.project_poly("handle", body, _round_poly([(y - 0.065, 0.874), (y + 0.065, 0.874),
                                                                 (y + 0.065, 0.89), (y - 0.065, 0.89)], 0.007, 2),
                                    fr, M["chrome"], offset=0.008, cuts=1))
    top = K.top_frame()
    for sx in (-1, 1):
        # bonnet edges along the fender tops, boot lid edges inside the fins
        p.append(_line("shut", body, [(sx * (HW - 0.062), 0.88), (sx * (HW - 0.062), Y1 - 0.005)],
                                top, 0.006, M["shut"], 0.004))
        p.append(_line("shut", body, [(sx * (PANEL_X - 0.003), -1.36), (sx * (PANEL_X - 0.003), Y0 + 0.045)],
                                top, 0.006, M["shut"], 0.004))
    p.append(_line("shut", body, [(-(HW - 0.062), 0.88), (HW - 0.062, 0.88)], top, 0.006, M["shut"], 0.004))
    p.append(_line("shut", body, [(-PANEL_X, -1.36), (PANEL_X, -1.36)], top, 0.006, M["shut"], 0.004))
    p.append(K.project_poly("cowl", body, _round_poly([(-0.5, 0.858), (0.5, 0.858), (0.5, 0.868), (-0.5, 0.868)],
                                                      0.004, 2), top, M["shut"], offset=0.004, cuts=1))
    # round chrome mirror on the driver's door, aerial on the driver's fender
    p.append(cyl(0.008, 0.07, (HW + 0.012, 0.74, ZB + 0.03), M["chrome"], segs=8))
    p.append(cyl(0.048, 0.02, (HW + 0.024, 0.74, ZB + 0.075), M["chrome"], segs=16, axis="X"))
    p.append(cyl(0.0025, 0.55, (HW - 0.06, 1.0, 0.92 + 0.27), M["chrome"], segs=4))
    return p


def _interior(M):
    """What shows through the glass: floor, bench seats, parcel shelf, the
    dash and a big thin steering wheel on the right."""
    from . import cabin as CB
    t, d = M["trim"], M["dark"]
    p = [bx((-0.72, -1.25, 0.4), (0.72, 0.8, 0.42), d)]
    for yb, yc, top in ((-0.05, 0.42, 1.14), (-0.98, -0.52, 1.08)):
        p.append(_smoothed(_prism("cushion", [(yb - 0.02, 0.42), (yc, 0.42), (yc + 0.02, 0.6), (yc - 0.03, 0.63),
                                              (yb, 0.62)], "x", -0.72, 0.72, t), 50))
        p.append(_smoothed(_prism("seatback", [(yb - 0.12, 0.42), (yb + 0.03, 0.42), (yb - 0.02, top),
                                               (yb - 0.07, top + 0.015), (yb - 0.13, top - 0.02)],
                                  "x", -0.72, 0.72, t), 50))
    p.append(bx((-0.74, -1.25, 0.935), (0.74, -1.08, 0.95), t))       # parcel shelf
    p.append(_smoothed(_prism("dash", [(0.55, 0.78), (0.8, 0.78), (0.8, 0.945), (0.68, 0.985), (0.56, 0.97)],
                              "x", -0.75, 0.75, t), 40))
    p.append(bx((0.24, 0.55, 0.87), (0.52, 0.565, 0.95), d))           # instrument cluster
    wheel = CB.torus_rim("steer", 0.205, 0.011, 28, d, ts=6)
    wheel.rotation_euler = (math.radians(-28), 0, 0)
    wheel.location = (0.38, 0.4, 0.95)
    p.append(wheel)
    p.append(cyl(0.02, 0.3, (0.38, 0.52, 0.89), d, segs=8, axis="Y"))
    return p


def _tail(M):
    """The rear: chrome strip along the boot lid's lower edge, the bumper
    with its amber lamps and plate, the exhaust."""
    p = []
    yp = Y0 + PANEL_D
    p.append(bx((-PANEL_X + 0.012, yp - 0.004, LID_EDGE - 0.014), (PANEL_X - 0.012, yp + 0.012, LID_EDGE),
                M["chrome"]))
    # a blade: flat face, crisp top edge, rolled under at the bottom
    prof = _BLADE(0.36, 1.18)
    plan = [(0.0, YR, 1), (0.45, YR + 0.006, 1), (0.72, YR + 0.016, 1), (0.82, YR + 0.045, 0.96),
            (HW - 0.004, YR + 0.12, 0.88), (HW + 0.002, YR + 0.22, 0.75), (HW - 0.006, YR + 0.32, 0.5)]
    p.append(_sweep("bumper_r", plan, prof, (0.0, YR + 1.0), M["chrome"]))
    for sx in (-1, 1):
        x = sx * 0.66
        p.append(bx((x - 0.07, YR + 0.008, 0.44), (x + 0.07, YR + 0.02, 0.485), M["amber"]))
    p.append(bx((-0.19, YR - 0.01, 0.405), (0.19, YR - 0.002, 0.535), M["plate"]))
    p.append(cyl(0.024, 0.2, (-0.45, YR + 0.14, 0.3), M["dark"], segs=8, axis="Y"))
    return p


def _BLADE(z0, h=1.0):
    """Bumper section (out, z) from its bottom edge z0: tucked under at the
    bottom, the face leaning out up to a rolled lip that stands proud."""
    return [(d, z0 + h * z) for d, z in ((-0.075, 0.004), (-0.05, 0.0), (-0.04, 0.008), (-0.028, 0.025),
                                          (-0.01, 0.075), (0.0, 0.125), (0.006, 0.143), (0.002, 0.158),
                                          (-0.018, 0.167), (-0.075, 0.17))]


def _front_bumper(M):
    p = []
    yf = YF - 0.11
    prof = _BLADE(0.36, 1.18)
    # (the vee in plan comes from _vee); the ends sweep back round the fenders
    plan = [(0.0, YF, 1), (0.45, YF - 0.004, 1), (0.72, YF - 0.012, 1), (0.82, YF - 0.04, 0.96),
            (HW - 0.004, YF - 0.12, 0.88), (HW + 0.002, YF - 0.22, 0.75), (HW - 0.006, YF - 0.32, 0.5)]
    p.append(_sweep("bumper_f", plan, prof, (0.0, YF - 1.0), M["chrome"]))
    p.append(bx((-0.19, YF + 0.004, 0.42), (0.19, YF + 0.012, 0.55), M["plate"]))
    for sx in (-1, 1):
        p.append(bx((sx * 0.55 - 0.072, YF - 0.065, 0.398), (sx * 0.55 + 0.072, YF - 0.014, 0.452), M["chrome"]))
    return p


def _wheels(M):
    """Steel wheels in body colour with small domed dog-dish caps, on tyres
    with a rounded sidewall and a thin white stripe."""
    p = []
    for y in (AXLE_F, AXLE_R):
        for sx in (-1, 1):
            p += _wheel(M, sx, (sx * TRACK_X, y, TYRE_R))
    return p


def _wheel(M, sx, loc):
    """One wheel at loc, its outer face toward sx (+1 the driver's side)."""
    tyre = [(0.19, -0.083), (0.262, -0.087), (0.293, -0.074), (TYRE_R, -0.045), (TYRE_R, 0.045),
            (0.293, 0.074), (0.262, 0.087), (0.232, 0.088), (0.222, 0.088), (0.19, 0.086)]
    cap = [(0.19, 0.084), (0.12, 0.086), (0.098, 0.088), (0.09, 0.094), (0.06, 0.1), (0.0, 0.102)]
    p = []

    def side(prof):
        return [(r, sx * o) for r, o in (prof if sx > 0 else reversed(prof))]
    n = len(tyre) - 1
    p.append(K.revolve("tyre", side(tyre), 32,
                       lambda i, n=n, sx=sx: M["white"] if (i == 7 if sx > 0 else i == n - 8) else M["tyre"],
                       loc=loc))
    capm = len(cap) - 1
    p.append(K.revolve("wheel", side(cap), 32,
                       lambda i, capm=capm, sx=sx: M["paint"] if (i == 0 if sx > 0 else i == capm - 1)
                       else M["chrome"], loc=loc))
    p.append(cyl(0.19, 0.16, loc, M["paint"], segs=32, axis="X"))
    for o in p:
        if o.type == "MESH" and o.name.startswith(("tyre", "wheel")):
            C.apply_transform(o)
            _smoothed(_fix_normals(o), 50)
    return p


def _teardrop(cx, z0, z1, a, n=8, p=1.6):
    """Tail lamp outline: round at the bottom, drawing up to a point at the
    top, a wide from z0 to z1; a higher p keeps the sides straighter."""
    zc = z0 + a
    pts = [(cx + a * math.cos(t), zc + a * math.sin(t))
           for t in (math.pi + math.pi * k / n for k in range(n + 1))]          # bottom half circle
    for k in range(1, n):
        t = k / n
        w = a * (1 - t ** p)
        pts.append((cx + w, zc + (z1 - zc) * t))
    pts.append((cx, z1))
    for k in range(n - 1, 0, -1):
        t = k / n
        w = a * (1 - t ** p)
        pts.append((cx - w, zc + (z1 - zc) * t))
    return pts


def _vesica(cx, cz, a, b, n=8):
    """A tall pointed oval (two arcs meeting at the top and bottom), 2a wide
    and 2b tall, centred on (cx, cz), as (x, z) points."""
    r = (a * a + b * b) / (2 * a)
    d = r - a
    f = math.asin(b / r)
    right = [(cx - d + r * math.cos(t), cz + r * math.sin(t))
             for t in (-f + 2 * f * k / n for k in range(n + 1))]
    left = [(2 * cx - x, z) for x, z in reversed(right[1:-1])]
    return right + left


def _tail_frame(sx):
    """(outer, inner) outlines (x, z) of a tail lamp's chrome frame: tall,
    filling the fin's end, with a round top under its crest."""
    # a hair inboard of the fin end's middle, clear of its rounded outer edge
    x = sx * ((PANEL_X + _W(Y0)) / 2 - 0.008)
    zt, a, r = _ZC(Y0) - 0.048, 0.048, 0.044
    # straight sides from just above the bumper, a semicircular top
    outer = [(x - a + 0.012 - 0.012 * math.cos(math.radians(t)), 0.57 + 0.012 - 0.012 * math.sin(math.radians(t)))
             for t in range(0, 91, 30)]
    outer += [(x + a - 0.012 + 0.012 * math.sin(math.radians(t)), 0.57 + 0.012 - 0.012 * math.cos(math.radians(t)))
              for t in range(0, 91, 30)]
    outer += [(x + a, zt - r - 0.02)]
    outer += [(x + r * math.cos(math.radians(t)), zt - r + r * math.sin(math.radians(t))) for t in range(0, 181, 15)]
    outer += [(x - a, zt - r - 0.02)]
    if sx < 0:
        outer = [(px, pz) for px, pz in reversed(outer)]
    inner = K.offset_poly(outer, 0.011)
    return outer, inner


def _lamps(M):
    out = []
    yb = Y1 - GRILLE_D
    for name, sx in (("HeadL", -1), ("HeadR", 1)):
        x = sx * 0.69
        out.append((name, [cyl(0.088, 0.016, (x, Y1 - 0.03, 0.655), M["head"], segs=24, axis="Y"),
                           cyl(0.06, 0.01, (x, Y1 - 0.022, 0.655), M["head"], segs=18, axis="Y")],
                    None, None))
    for name, sx in (("ParkL", -1), ("ParkR", 1)):
        x = sx * 0.55
        out.append((name, [bx((x - 0.065, YF - 0.06, 0.405), (x + 0.065, YF - 0.01, 0.445), M["park"])],
                    None, None))
    for name, sx in (("TailL", -1), ("TailR", 1)):
        x = sx * ((PANEL_X + _W(Y0)) / 2 - 0.008)
        # a chrome frame round the recess, chrome lining it, the red lens at
        # its back with a chrome oblong ring on it
        outer, inner = _tail_frame(sx)
        yf, yl = Y0 - 0.003, Y0 + 0.026
        o_ring = _round_poly([(x - 0.014, 0.66), (x + 0.014, 0.66), (x + 0.014, 0.74), (x - 0.014, 0.74)], 0.013, 4)
        parts = [_ring("bezel", [(px, yf, pz) for px, pz in outer], [(px, yf, pz) for px, pz in inner],
                       M["chrome"]),
                 _ring("bezel_sleeve", [(px, yf, pz) for px, pz in inner], [(px, yl, pz) for px, pz in inner],
                       M["chrome"]),
                 _prism("lens", inner, "y", yl, yl + 0.004, M["tail"]),
                 _ring("lens_ring", [(px, yl - 0.003, pz) for px, pz in o_ring],
                       [(px, yl - 0.003, pz) for px, pz in K.offset_poly(o_ring, 0.004)], M["chrome"])]
        out.append((name, parts, None, None))
    return out


VEE = 0.03
CORNER_R = 0.03


def _vee(objs):
    """Draw the front into a shallow vee in plan, its outer corners rounded
    off on a radius CORNER_R (a quarter circle meets the sides tangent): the
    centre stays put, fading out ahead of the front wheel arches."""
    y0 = 1.98

    def s(y):
        t = min(1.0, max(0.0, (y - y0) / (Y1 - 0.06 - y0)))
        return t * t * (3 - 2 * t)

    def back(x):
        e = max(0.0, abs(x) - (HW - CORNER_R))
        return VEE * min(1.0, (x / HW) ** 2) + CORNER_R - math.sqrt(max(0.0, CORNER_R ** 2 - e * e))
    seen = set()
    for o in objs:
        if o.type != "MESH" or o.data.name in seen:
            continue
        assert o.data.users == 1, o.name
        seen.add(o.data.name)
        C.apply_transform(o)
        for v in o.data.vertices:
            x, y = v.co.x, v.co.y
            if y > y0:
                v.co.y = y - back(x) * s(y)


def valiant():
    from . import valiant_cabin as VC
    M = _mats()
    body, ref = _shell(M)
    # the prop keeps its doors shut and everything inside fixed
    cab, items, trims = VC.cockpit(M, body)
    cab += trims["L"] + trims["R"] + [o for _, parts, _, _ in items for o in parts]
    p = [body] + _glass_and_frames(M, ref, body) + _trim(M, body) + _nose(M) + cab + _tail(M)
    p += _front_bumper(M) + _wheels(M)
    bpy.data.objects.remove(ref, do_unlink=True)
    lamps = _lamps(M)
    _vee(p + [o for _, parts, _, _ in lamps for o in parts])
    return [("Valiant", p, (0, 0, 0), None)] + lamps, {}


VEHICLES = {
    "valiant": valiant,
}


# ------------------------------------------------------------------ to drive
#
# The same Valiant on the cars/ contract (art/models/README.md), for the car
# yard: origin on the ground midway between the axles, the wheels out as their
# own glbs (wheel_vc_l/_r) with Hub_* empties at their centres, the cockpit
# and opening front doors from lib/valiant_cabin.py (SteeringWheel, GearKnob,
# Needle_*, Odometer_*, Door_L/R and DoorOpen_L/R), an interior mirror,
# seats, exits and mounts, and the material names the game drives (LampHead,
# LampTail, Glass, Plate). The body, paint and lamps are the prop's.

CAR_PLATE = "UHV-266"   # made up: a 1960s WA plate, white on black
AXLE_MID = (AXLE_F + AXLE_R) / 2
WHEEL_STYLE = "vc"
HIP = (0.37, 0.06, 0.66)          # driver's hip point on the bench


def _car_mats():
    from . import textures as TX
    M = _mats()
    M.update({
        "glass": C.mat("Glass", "#6d8893", rough=0.03, metal=0.35, alpha=0.5),
        "head": _m("LampHead", "#e4ebe8", 0.04, 0.45),
        "tail": _m("LampTail", "#a3171a", 0.25),
        "plate": C.mat("Plate", image=TX.plate(CAR_PLATE, ink=(0.93, 0.92, 0.88), bg=(0.07, 0.07, 0.08)),
                       rough=0.6),
    })
    return M


def _car_mirror(M):
    """Interior mirror at the top of the windscreen, on a short stem."""
    y, z = WS_T - 0.06, ROOF - 0.075
    return [bx((-0.11, y - 0.012, z - 0.03), (0.11, y + 0.004, z + 0.03), M["dark"]),
            bx((-0.103, y - 0.016, z - 0.024), (0.103, y - 0.012, z + 0.024), M["chrome"]),
            cyl(0.008, 0.07, (0.0, y - 0.004, z + 0.055), M["dark"], segs=6)]


def valiant_car():
    """The driveable Valiant in build_city's form (items, empties), still
    nose +Y with its origin where the prop's is; `valiant_car_finish` turns
    the cockpit's parts to their axes, adds the contract empties and moves
    the origin between the axles."""
    from . import valiant_cabin as VC
    M = _car_mats()
    body, ref = _shell(M)
    cab, items, trims = VC.cockpit(M, body)
    p = [body] + _glass_and_frames(M, ref, body) + _trim(M, body) + _nose(M) + cab + _tail(M)
    p += _front_bumper(M) + _car_mirror(M)
    bpy.data.objects.remove(ref, do_unlink=True)
    p, doors, door_empties = VC.split_doors(p, trims)
    lamps = _lamps(M)
    moving = doors + items + lamps
    _vee(p + [o for _, parts, _, _ in moving for o in parts])
    for o in p:
        if o.type == "MESH" and o.data.materials and o.data.materials[0] is M["plate"]:
            C.apply_transform(o)
            # read from in front of the car its right is -X, from behind +X
            K.planar_uv(o, 0, 2, flip_u=o.data.vertices[0].co.y > 0)
    return [("Valiant", p, (0, 0, 0), None)] + moving, door_empties


def valiant_car_finish():
    """After build_city's build of `valiant_car`: the cockpit's axes, the
    contract empties, then everything moved so the origin sits midway
    between the axles. Returns every object."""
    from mathutils import Matrix
    from . import valiant_cabin as VC
    VC.orient()

    def em(name, loc, rx=0.0, rz=0.0):
        e = C.empty(name, loc, size=0.08)
        e.rotation_euler = (math.radians(rx), 0, math.radians(rz))
        return e
    em("WheelStyle_" + WHEEL_STYLE, (0, 0, 0))
    for nm, sx, y in (("FL", -1, AXLE_F), ("FR", 1, AXLE_F), ("RL", -1, AXLE_R), ("RR", 1, AXLE_R)):
        em("Hub_" + nm, (sx * TRACK_X, y, TYRE_R))
    em("Cam_Cockpit", tuple(VC.EYE))
    for nm, sx in (("L", -1), ("R", 1)):
        em("Seat_" + nm, (sx * HIP[0], HIP[1], HIP[2]))
        # beside the front door, facing away from the car (Godot -Z out)
        em("Exit_" + nm, (sx * (HW + 0.5), 0.2, 0.0), rz=90 * -sx)
        em("Mount_MudFlap_" + nm, (sx * TRACK_X, AXLE_R - 0.4, _ZB(AXLE_R - 0.4)))
    # A fitted wheel: Godot -Z down the column toward the dash, +Y to twelve.
    em("Mount_SteeringWheel", tuple(VC.HUB), rx=-VC.COL_TILT)
    em("Mount_Exhaust", (-0.45, YR + 0.04, 0.3))
    em("Mount_Roof", (0.0, (WS_T + BL_T) / 2, ROOF))
    em("Mount_Spotlights", (0.0, YF - 0.05, 0.56))
    em("Mount_BumperF", (0.0, YF + 0.01, 0.46))
    em("Mount_BumperR", (0.0, YR - 0.01, 0.46))
    em("Mount_TowBar", (0.0, YR, 0.28))
    em("Mount_Mirror", (0.0, WS_T - 0.065, ROOF - 0.11))
    em("Mount_Dash", (-0.3, 0.66, 0.985))
    em("Mount_Shelf", (-0.35, -1.16, 0.95))
    em("Mount_Gear", (0.0, 0.62, 0.43))
    em("Mount_Glovebox", (-0.36, 0.72, 0.84))
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        if o.parent is None:
            o.matrix_world = Matrix.Translation((0, -AXLE_MID, 0)) @ o.matrix_world
    bpy.context.view_layer.update()
    return list(bpy.data.objects)


def valiant_wheel(sx):
    """One road wheel at the origin, axle along X, its face toward sx (the
    left wheel's face is -X). The centre is the body colour."""
    M = _mats()
    M["paint"] = _m("VC_WheelPaint", "#657f57", 0.45, 0.05)
    return C.join(_wheel(M, sx, (0, 0, 0)), "Wheel")
