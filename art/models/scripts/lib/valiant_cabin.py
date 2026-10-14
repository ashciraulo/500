"""The VC Valiant's opening front doors and its cockpit.

The body in lib/period_vehicles.py is one closed shell; `split_doors` cuts
each front door out of it along the shut lines and takes with it whatever
sits on the door: the glass, its chrome frame, the handle, the driver's
mirror and the door's length of the side spear. Each door becomes its own
object, Door_L / Door_R, with its origin on the hinge line at the front
edge and its glass as a child (art/models/README.md, "Door_L, Door_R").

`cockpit` builds the inside as the driver sees it, matched to photos of
1966/67 VC Valiants (/mnt/project-files/models/valiant-vc/ref/interior/):
a black padded crash pad over a full-width brushed strip that steps down
into a box round two equal round dials (the speedo, 0-120 mph, on the
left; fuel, temperature and amps on the right), knobs in chrome bezels, the
glovebox on the far left and a period radio under the knobs; a thin-rimmed
two-spoke wheel with a chrome half horn ring; a column shift (the 3-speed
manual); a front bench with a split back and pleated vinyl inserts; full
door trims with a chrome strip, armrest, winder and latch; a cream
headliner and sun visors. Tan vinyl, as the Regal's.

Coordinates as in period_vehicles: front toward +Y (Godot -Z), the kerb
side on -X (Door_L), the driver on +X (Door_R).
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

DOOR_OPEN_DEG = 60          # the classics' full swing (README)
DOOR_Y0, DOOR_Y1 = -0.035, 0.93   # rear and front shut lines (the B pillar and the cowl)
DOOR_Z0 = 0.37                    # bottom edge, above the sill
HINGE_DY = -0.02                  # hinge just behind the front shut line


def door_outline():
    """Side outline (y, z) of the front door: up the front shut line to the
    belt, forward along the belt to the A pillar's foot, up the pillar just
    outside the glass to the drip rail, back along it to the B pillar and
    down the rear shut line."""
    z_top = PV.DLO_Z1 + 0.026            # just over the glass frame, under the drip rail
    a0 = PV._a_line(PV.ZB) - 0.012
    a1 = PV._a_line(z_top) - 0.012
    return [(DOOR_Y0, DOOR_Z0), (DOOR_Y1, DOOR_Z0), (DOOR_Y1, PV.ZB - 0.006), (a0, PV.ZB - 0.006),
            (a1, z_top), (DOOR_Y0, z_top)]


def _slice(bm, edge, xmin):
    """Bisect the side faces (|x| > xmin) along a (y, z) polyline."""
    for (y0, z0), (y1, z1) in zip(edge, edge[1:]):
        n = Vector((0, -(z1 - z0), y1 - y0)).normalized()
        lo_y, hi_y = min(y0, y1) - 0.01, max(y0, y1) + 0.01
        lo_z, hi_z = min(z0, z1) - 0.01, max(z0, z1) + 0.01

        def near(f):
            ys = [v.co.y for v in f.verts]
            zs = [v.co.z for v in f.verts]
            return min(ys) < hi_y and max(ys) > lo_y and min(zs) < hi_z and max(zs) > lo_z
        faces = [f for f in bm.faces if abs(f.calc_center_median().x) > xmin and near(f)]
        if not faces:
            continue
        geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector((0, y0, z0)), plane_no=n, dist=1e-5)


def _inside(p, poly):
    return K.inside_poly(p, poly)


def _take(obj, keep, name):
    """Move the faces of obj for which keep(face) is true into a new object."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    out = bm.copy()
    gone = [f for f in bm.faces if keep(f)]
    stay = [f for f in out.faces if not keep(f)]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bmesh.ops.delete(out, geom=stay, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    me = bpy.data.meshes.new(name)
    out.to_mesh(me)
    out.free()
    for m in obj.data.materials:
        me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    C.link(o)
    return o


def split_doors(parts, trims=None):
    """Cut both front doors out of the body (parts[0]) and gather the parts
    that ride on them (and trims[side], the door's inside, from
    `cockpit`). Returns (body parts, door items, empties) in
    lib/city_vehicles.py's form."""
    body = parts[0]
    C.apply_transform(body)
    outline = door_outline()
    bm = bmesh.new()
    bm.from_mesh(body.data)
    _slice(bm, outline + outline[:1], 0.5)
    bm.to_mesh(body.data)
    bm.free()
    items, empties = [], {}
    rest = list(parts[1:])
    for side, sx in (("L", -1), ("R", 1)):
        def on_door(f, sx=sx):
            c = f.calc_center_median()
            return sx * c.x > 0.5 and _inside((c.y, c.z), outline)
        door = _take(body, on_door, "door_" + side)
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
            if min(ys) > DOOR_Y0 - 0.002 and _inside(c, outline):
                rest.remove(o)
                (glass if o.name.startswith("glass") else ride).append(o)
            elif min(ys) < DOOR_Y0 and max(ys) > DOOR_Y1 and min(v.z for v in vs) > DOOR_Z0:
                # a run along the whole car (the side spear): the door keeps its length
                piece = _take(o, lambda f: DOOR_Y0 < f.calc_center_median().y < DOOR_Y1, o.name + "_door")
                ride.append(piece)
        _cut_runs(ride[1:])
        ride += (trims or {}).get(side, [])
        hinge = (sx * (PV.HW - 0.01), DOOR_Y1 + HINGE_DY, 0.6)
        items.append(("Door_" + side, ride, hinge, None))
        items.append(("Door_%s_Glass" % side, glass, hinge, "Door_" + side))
        # the open pose, sign applied: a front-hinged left door opens with a
        # negative turn (README)
        sign = -1 if side == "L" else 1
        empties["DoorOpen_" + side] = (hinge, DOOR_OPEN_DEG * sign)
    return [body] + rest, items, empties


def _cut_runs(objs):
    """Bisect pieces taken off a long run so their ends sit on the shut lines."""
    for o in objs:
        if not o.name.endswith("_door"):
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        for y, keep_neg in ((DOOR_Y1, True), (DOOR_Y0, False)):
            res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                         plane_co=(0, y, 0), plane_no=(0, 1, 0), clear_outer=keep_neg,
                                         clear_inner=not keep_neg)
            del res
        bm.to_mesh(o.data)
        bm.free()


# ------------------------------------------------------------------ cockpit

DRIVER_X = 0.37
DASH_X = 0.79                    # dash ends, just inside the door trims
FACE_Y = 0.592                   # the brushed instrument face
STRIP_Z = (0.826, 0.93)         # the full-width strip
BOX = (0.165, 0.605, 0.783)       # x0, x1 and bottom of the box round the dials
DIAL_R = 0.054
DIAL_Z = 0.849
SPEEDO_X, GAUGE_X = 0.292, 0.478
COL_TILT = 30                    # the column, degrees below level toward the dash
HUB = Vector((DRIVER_X, 0.40, 0.875))
EYE = Vector((DRIVER_X, -0.12, 1.20))
RIM_R = 0.205
# Needle full scales (art/models/README.md): the speedo reads 120 mph at the
# end of its 240 degree sweep, which is 193 km/h; the fuel needle crosses
# the top of the right-hand dial, E to F through 80 degrees (240 / 3).
SPEED_FULL, FUEL_FULL, FUEL_SWING = 193, 3, 80
# The wheel and the needles turn about their own axes, which build_city
# leaves unrotated: `orient` gives them back after the build.
FRAMES = {}


def _cab_mats(M):
    tan = "#8b5b35"
    return {
        "vinyl": C.mat("VC_Vinyl", tan, rough=0.45),
        "pleat": C.mat("VC_VinylPleat", image=_pleat_tex(tan), rough=0.5),
        "panel": C.mat("VC_DoorPanel", image=_panel_tex(tan), rough=0.55),
        "dash": C.mat("VC_DashPaint", "#7b5333", rough=0.5),
        "pad": C.mat("VC_CrashPad", "#18181a", rough=0.6),
        "brushed": C.mat("VC_Brushed", image=_brushed_tex(), rough=0.5),
        "knob": C.mat("VC_Knob", "#111113", rough=0.3),
        "carpet": C.mat("VC_Carpet", image=TX.carpet("vc_carpet", "#2f251d", 5, 16), rough=1.0),
        "door_carpet": C.mat("VC_DoorCarpet", image=TX.carpet("vc_door_carpet", "#6a4a2f", 7, 16), rough=1.0),
        "rubber": C.mat("VC_Rubber", "#141415", rough=0.9),
        "rim": C.mat("VC_WheelRim", "#121213", rough=0.3),
        "emblem": C.mat("VC_Emblem", "#b39b62", rough=0.3, metal=0.8),
        "needle": C.mat("VC_Needle", "#f07a1c", rough=0.4, emit="#ff8a2a", emit_strength=0.25),
        "lens": C.mat("VC_WarnLens", "#5a1210", rough=0.2),
        "quadrant": C.mat("VC_Quadrant", image=_quadrant_tex(), rough=0.3, emit="#d9e2ea", emit_strength=0.15,
                          emit_image=True),
        "radio": C.mat("VC_RadioDial", image=_radio_tex(), rough=0.3, emit="#ffd9a0", emit_strength=0.15,
                       emit_image=True),
        "speedo": C.mat("VC_Speedo", image=CB.dial_tex("vc_speedo", 120, 10, face=(0.035, 0.035, 0.04),
                                                        ink=(0.9, 0.9, 0.86), tick_step=5, units="MPH"),
                        rough=0.35, emit="#c8d4e0", emit_strength=0.2, emit_image=True),
        "gauge": C.mat("VC_Gauges", image=_gauge_tex(), rough=0.35, emit="#c8d4e0", emit_strength=0.2,
                       emit_image=True),
        # satin, so the sky doesn't flood the cabin with blue
        "chrome": C.mat("VC_CabinChrome", "#d4d6d6", rough=0.3, metal=0.55),
        "liner": M["liner"],
    }


# ------------------------------------------------------------------ textures

def _shade(c, k):
    return tuple(min(1.0, x * k) for x in c)


def _pleat_tex(color):
    """Four pleats of rolled vinyl, a stitched groove between each."""
    base = C._hex(color)
    rows = [0.55, 0.82, 0.97, 1.06, 1.1, 1.06, 0.98, 0.88]
    return C.make_image("vc_pleat", 4, 32, lambda x, y: _shade(base, rows[y % 8]))


def _panel_tex(color):
    """Door panel: a band of fine horizontal pleats between plain margins."""
    base = C._hex(color)

    def px(x, y):
        if 6 <= y < 58:
            return _shade(base, 0.8 if y % 4 == 0 else (1.04 if y % 4 == 2 else 0.97))
        return _shade(base, 1.0 if y not in (5, 58) else 0.75)
    return C.make_image("vc_door_panel", 4, 64, px)


def _brushed_tex():
    rnd = TX.random.Random(5)
    rows = [0.9 + rnd.random() * 0.16 for _ in range(16)]
    base = C._hex("#c4c7c6")
    return C.make_image("vc_brushed", 64, 16, lambda x, y: _shade(base, rows[y] * (0.97 + rnd.random() * 0.06)))


def _gauge_tex(s=128):
    """The right-hand dial: FUEL across the top (the needle is a mesh), TEMP
    lower left and AMPS lower right with their needles printed on."""
    face, ink, orange = (0.035, 0.035, 0.04), (0.9, 0.9, 0.86), (0.94, 0.48, 0.11)
    px = [face] * (s * s)

    def arc(r0, r1, a0, a1, col):
        for y in range(s):
            for x in range(s):
                u, v = (x + 0.5) / s * 2 - 1, (y + 0.5) / s * 2 - 1
                r, a = math.hypot(u, v), math.degrees(math.atan2(u, v))
                if r0 < r < r1 and a0 <= a <= a1:
                    px[y * s + x] = col

    def tick(a, r0, r1, col, w=2.2):
        for k in range(4):
            arc(r0, r1, a - w / 2, a + w / 2, col)

    for y in range(s):
        for x in range(s):
            if math.hypot((x + 0.5) / s * 2 - 1, (y + 0.5) / s * 2 - 1) > 0.985:
                px[y * s + x] = (0.02, 0.02, 0.02)
    half = FUEL_SWING / 2
    arc(0.9, 0.92, -half, half, ink)
    for k in range(5):
        tick(-half + FUEL_SWING * k / 4, 0.8, 0.92, ink, 3.0 if k % 2 == 0 else 1.6)
    arc(0.9, 0.92, -150, -100, ink)
    arc(0.9, 0.92, 100, 150, ink)
    for a in (-150, -125, -100, 100, 125, 150):
        tick(a, 0.82, 0.92, ink)
    for a, r, t in ((-half, 0.66, "E"), (half, 0.66, "F"), (-150, 0.68, "C"), (-100, 0.68, "H"),
                    (100, 0.68, "D"), (150, 0.68, "C")):
        cx, cy = (math.sin(math.radians(a)) * r + 1) * s / 2, (math.cos(math.radians(a)) * r + 1) * s / 2
        CB._put_text(px, s, s, t, cx, cy, ink)
    CB._put_text(px, s, s, "FUEL", s / 2, s * 0.73, ink)
    CB._put_text(px, s, s, "TEMP", s * 0.3, s * 0.3, ink)
    CB._put_text(px, s, s, "AMPS", s * 0.7, s * 0.3, ink)
    # temperature and charge needles at rest, printed on
    for a in (-128, 128):
        arc(0.2, 0.8, a - 2.2, a + 2.2, orange)
    return CB._image("vc_gauges", s, s, px)


def _radio_tex():
    """A period push-button radio's dial window: a cream scale, red pointer."""
    w, h = 32, 8
    px = [(0.86, 0.8, 0.62)] * (w * h)
    for x in range(2, w - 2, 3):
        px[6 * w + x] = (0.2, 0.18, 0.15)
    for y in range(h):
        px[y * w + 12] = (0.7, 0.1, 0.06)
    return CB._image("vc_radio", w, h, px)


# ------------------------------------------------------------------ helpers

def _uv(o, au, av, su, sv):
    """Planar UVs: u = coordinate au / su, v = av / sv (metres)."""
    me = o.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for p in me.polygons:
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = (co[au] / su, co[av] / sv)
    return o


def _bevel_caps(o, axis, w, segs=2):
    """Round the edges round the two end caps of a prism along axis."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    caps = [f for f in bm.faces if abs(f.normal[axis]) > 0.95]
    edges = list({e for f in caps for e in f.edges})
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=w, segments=segs, affect="EDGES", profile=0.5)
    bm.to_mesh(o.data)
    bm.free()
    return o


def _rprism(name, pts, axis, a0, a1, mat, r=0.0, segs=3, cap=0.0, smooth=40):
    """A prism through a rounded outline, its end edges rounded too."""
    pts = PV._round_poly(pts, r, segs) if r else pts
    o = PV._prism(name, pts, axis, a0, a1, mat)
    if cap:
        _bevel_caps(o, "xyz".index(axis), cap)
    return PV._smoothed(o, smooth)


def _tube(name, pts, r, mat, segs=6, closed=False, up=(0, -1, 0)):
    """A round section swept along points; `up` steadies its orientation."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    vs, fs = [], []
    for i, p in enumerate(pts):
        a = pts[(i - 1) % n] if closed or i > 0 else p
        b = pts[(i + 1) % n] if closed or i < n - 1 else p
        t = (b - a).normalized()
        u = Vector(up)
        u = (u - t * u.dot(t)).normalized()
        w = t.cross(u)
        for k in range(segs):
            ang = 2 * math.pi * k / segs
            vs.append(p + (u * math.cos(ang) + w * math.sin(ang)) * r)
    for i in range(n if closed else n - 1):
        j = (i + 1) % n
        for k in range(segs):
            k2 = (k + 1) % segs
            fs.append((i * segs + k, i * segs + k2, j * segs + k2, j * segs + k))
    if not closed:
        fs.append(tuple(reversed(range(segs))))
        fs.append(tuple((n - 1) * segs + k for k in range(segs)))
    o = C.mesh_obj(name, vs, fs, mat)
    PV._fix_normals(o)
    return PV._smoothed(o, 60)


def _bar(name, a, b, w, t, mat, up=(0, 0, 1)):
    """A flat bar from a to b, w wide (across `up`'s side) and t thick."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    u = Vector(up)
    u = (u - d * u.dot(d)).normalized()
    s = d.cross(u)
    vs = []
    for p in (a, b):
        for ds, du in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            vs.append(p + s * ds * w / 2 + u * du * t / 2)
    fs = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    return PV._fix_normals(C.mesh_obj(name, vs, fs, mat))


def _face_frame(x, z, y=FACE_Y):
    """A frame on the dash face: local x to the driver's right (+X), y up,
    z toward the driver (-Y)."""
    return CB._frame((x, y, z), (1, 0, 0), (0, 0, 1))


def _knob(m, X, bezel=True):
    out = []
    if bezel:
        out.append(CB._ring("knob_bezel", 0.0105, 0.0165, 0.006, m, X["chrome"], segs=16))
    out.append(CB._place(C.cylinder("knob", 0.0105, 0.018, segs=12, loc=(0, 0, 0.012), material=X["knob"]), m))
    out.append(CB._disc("knob_cap", 0.006, m @ Matrix.Translation((0, 0, 0.0215)), X["chrome"], segs=10))
    return out


# ------------------------------------------------------------------ dash

def _dash(X):
    out = []
    x0, x1, zb = BOX
    s0, s1 = STRIP_Z
    # the black crash pad over everything, its lip standing out over the face
    pad = [(0.586, 0.962), (0.805, 0.956), (0.805, 0.932), (0.63, 0.933), (0.594, 0.926), (0.578, 0.944)]
    out.append(_rprism("crash_pad", pad, "x", -DASH_X, DASH_X, X["pad"], r=0.012, cap=0.012))
    # the brushed face: the full-width strip and the box round the dials
    face = PV._round_poly([(-DASH_X, s0), (x0, s0), (x0, zb), (x1, zb), (x1, s0), (DASH_X, s0),
                           (DASH_X, s1), (-DASH_X, s1)], 0.016, 3)
    strip = PV._prism("dash_face", face, "y", FACE_Y, 0.70, X["brushed"])
    out.append(_uv(strip, 0, 2, 0.45, 0.11))
    out.append(_tube("face_bead", [(x, FACE_Y - 0.001, z) for x, z in face], 0.0045, X["chrome"], closed=True))
    # painted lower dash
    low = [(0.60, 0.83), (0.75, 0.83), (0.75, 0.64), (0.70, 0.60), (0.645, 0.608), (0.606, 0.66)]
    out.append(_rprism("dash_low", low, "x", -DASH_X + 0.004, DASH_X - 0.004, X["dash"], r=0.02, cap=0.01))
    # glovebox door, a little proud, framed in chrome, a lock button at its end
    gb = [(-0.765, s0 + 0.007), (-0.465, s0 + 0.007), (-0.465, s1 - 0.007), (-0.765, s1 - 0.007)]
    door = _rprism("glovebox", gb, "y", FACE_Y - 0.005, FACE_Y + 0.002, X["brushed"], r=0.006, smooth=30)
    out.append(_uv(door, 0, 2, 0.45, 0.11))
    out.append(_tube("glovebox_bead", [(x, FACE_Y - 0.005, z) for x, z in PV._round_poly(gb, 0.006, 2)], 0.003,
                     X["chrome"], closed=True))
    out.append(CB._disc("glovebox_lock", 0.006, _face_frame(-0.49, (s0 + s1) / 2, FACE_Y - 0.0065), X["chrome"],
                        segs=10))
    # knobs: lighter, temperature, air, fan on the left; wipers, lights right
    zk = (s0 + s1) / 2
    for x in (-0.33, -0.235, -0.14, -0.045, 0.665, 0.735):
        out += _knob(_face_frame(x, zk), X)
    # the dials
    for x, mat in ((SPEEDO_X, X["speedo"]), (GAUGE_X, X["gauge"])):
        m = _face_frame(x, DIAL_Z)
        out.append(CB._ring("dial_bezel", DIAL_R - 0.001, DIAL_R + 0.007, 0.009, m, X["chrome"], segs=32))
        out.append(CB._disc("dial", DIAL_R, m @ Matrix.Translation((0, 0, 0.001)), mat, segs=32))
        out.append(C.sphere("dial_cap", 0.013, tuple(m @ Vector((0, 0, 0.004))), X["chrome"], segs=20, rings=6,
                            scale=(1, 0.45, 1)))
    # between the dials: two warning lamps over the turn arrows
    xm = (SPEEDO_X + GAUGE_X) / 2
    for sx in (-1, 1):
        m = _face_frame(xm + sx * 0.016, 0.888)
        out.append(CB._ring("lamp_ring", 0.0045, 0.0065, 0.002, m, X["chrome"], segs=10))
        out.append(CB._disc("lamp", 0.0046, m @ Matrix.Translation((0, 0, 0.0005)),
                            X["lens"] if sx < 0 else X["knob"], segs=10))
        tri = [(xm + sx * 0.026, 0.84), (xm + sx * 0.008, 0.85), (xm + sx * 0.008, 0.83)]
        out.append(PV._prism("arrow", tri, "y", FACE_Y - 0.003, FACE_Y + 0.001, X["knob"]))
    # radio under the knobs, an ashtray left of it, the ignition right of the box
    rm = _face_frame(-0.19, 0.795, 0.603)
    out.append(CB._place(CB._rbox("radio", (-0.09, -0.024, 0.0), (0.09, 0.024, 0.008), X["chrome"], 0.008), rm))
    out.append(CB._quad("radio_dial", 0.085, 0.017, rm @ Matrix.Translation((0, 0.004, 0.0085)), X["radio"]))
    for k in range(5):
        out.append(CB._place(C.box_minmax("radio_btn", (-0.04 + k * 0.017, -0.019, 0.008),
                                          (-0.028 + k * 0.017, -0.011, 0.016), X["chrome"]), rm))
    for sx in (-1, 1):
        out.append(CB._place(C.cylinder("radio_knob", 0.011, 0.014, segs=12, loc=(sx * 0.068, 0, 0.015),
                                        material=X["knob"]), rm))
    am = _face_frame(-0.36, 0.805, 0.603)
    out.append(CB._place(CB._rbox("ashtray", (-0.055, -0.016, 0.0), (0.055, 0.016, 0.004), X["chrome"], 0.006), am))
    out.append(CB._place(CB._rbox("ashtray_lip", (-0.03, -0.012, 0.004), (0.03, -0.006, 0.012), X["chrome"],
                                  0.003), am))
    im = _face_frame(0.70, 0.785, 0.606)
    out.append(CB._ring("ign_ring", 0.008, 0.014, 0.006, im, X["chrome"], segs=14))
    out.append(CB._place(C.box_minmax("ign_key", (-0.003, -0.01, 0.004), (0.003, 0.01, 0.03), X["chrome"]), im))
    # needles and odometer: their own nodes
    sm, gm = _face_frame(SPEEDO_X, DIAL_Z), _face_frame(GAUGE_X, DIAL_Z)
    speed = CB.needle("Needle_Speed_%d" % SPEED_FULL, sm, 0.008, DIAL_R * 0.93, 0.004, X["needle"], 0.0028)
    fuel = CB.needle("Needle_Fuel_%d" % FUEL_FULL, gm, 0.008, DIAL_R * 0.86, 0.004, X["needle"], 0.0028)
    fuel.data.transform(Matrix.Rotation(math.radians(-(CB.SWEEP / 2 - FUEL_SWING / 2)), 4, "Z"))
    odo = CB.odometer(sm, DIAL_R, CB.ODO_Y_DIAL, 0.0015)
    return out, [(speed, sm), (fuel, gm)], odo


# ------------------------------------------------------------------ wheel and column

def _column_frame():
    """Hub frame: local Y down the column toward the dash, Z to twelve."""
    return Matrix.Translation(HUB) @ Matrix.Rotation(math.radians(-COL_TILT), 4, "X")


def steering_wheel(X):
    """Thin black rim, two flat spokes dipping a little below level, the
    chrome half horn ring between them under the boss. Built round the
    origin in the hub frame (local Y down the column, the driver on -Y)."""
    out = [CB.torus_rim("vc_rim", RIM_R, 0.0095, 40, X["rim"], ts=8)]
    PV._smoothed(out[0], 60)
    dish = 0.045                      # the boss sits this far down the column
    out.append(C.cylinder("boss", 0.043, 0.03, segs=20, axis="Y", loc=(0, dish + 0.004, 0), material=X["rim"],
                          r_top=0.036))
    out.append(K.lamp_disc("boss_ring", 0.036, 0.006, (0, dish - 0.014, 0), (0, -1, 0), X["chrome"], segs=20))
    out.append(K.lamp_disc("boss_centre", 0.028, 0.004, (0, dish - 0.017, 0), (0, -1, 0), X["knob"], segs=20))
    out.append(K.lamp_disc("emblem", 0.011, 0.004, (0, dish - 0.019, 0.004), (0, -1, 0), X["emblem"], segs=12))
    drop = math.radians(12)
    for sx in (-1, 1):
        a = Vector((sx * 0.035, dish - 0.004, -0.006))
        b = Vector((sx * (RIM_R - 0.004) * math.cos(drop), 0.002, -(RIM_R - 0.004) * math.sin(drop)))
        out.append(_bar("spoke", a, b, 0.026, 0.008, X["rim"], up=(0, -1, 0.25)))
        out.append(_bar("spoke_trim", a + Vector((0, -0.0045, 0)), b + Vector((0, -0.0045, 0)), 0.012, 0.002,
                        X["chrome"], up=(0, -1, 0.25)))
    # the horn ring: a chrome arc under the boss from spoke to spoke
    r, n = 0.15, 18
    pts = []
    for k in range(n + 1):
        ang = -drop - (math.pi - 2 * drop) * k / n
        pts.append((r * math.cos(ang), 0.014 + 0.006 * math.sin(math.pi * k / n), r * math.sin(ang)))
    out.append(_tube("horn_ring", pts, 0.0045, X["chrome"], segs=6, up=(0, -1, 0)))
    return out


def _column(X):
    m = _column_frame()
    d = (m.to_3x3() @ Vector((0, 1, 0))).normalized()
    out = [_tube("column", [HUB + d * 0.06, HUB + d * 0.36], 0.024, X["knob"], segs=12),
           _tube("column_collar", [HUB + d * 0.065, HUB + d * 0.13], 0.032, X["knob"], segs=14)]
    # the gear lever comes off the inboard side and angles up toward the driver
    root = HUB + d * 0.1 + Vector((-0.028, 0, 0))
    tip = root + Vector((-0.19, -0.05, 0.075))
    out.append(_tube("gear_lever", [root, root + (tip - root) * 0.5, tip], 0.0055, X["chrome"], segs=6))
    knob = C.sphere("GearKnob", 0.014, tuple(tip + (tip - root).normalized() * 0.008), X["knob"], segs=10, rings=6,
                    scale=(1.2, 1.0, 1.0))
    # indicator stalk on the outboard side
    s0 = HUB + d * 0.11 + Vector((0.026, 0, 0.005))
    s1 = s0 + Vector((0.13, -0.02, 0.01))
    out.append(_tube("indicator", [s0, s1], 0.004, X["chrome"], segs=6))
    out.append(C.sphere("indicator_tip", 0.008, tuple(s1), X["knob"], segs=8, rings=4, scale=(1.6, 1, 1)))
    return out, knob


# ------------------------------------------------------------------ seats, floor, pedals

def _bench(name, profile, x0, x1, inserts, X, seat_face, r=0.035):
    """A bench cushion or back: a rounded prism across the car with pleated
    inserts (x ranges) on the faces the occupant touches. seat_face is
    "top" (ribs fore and aft) or "front" (ribs across)."""
    prof = PV._round_poly(profile, r, 3)
    xs = sorted({x0, x1, *[x for a, b in inserts for x in (a, b) if x0 < x < x1]})
    n = len(prof)
    vs = [(x, y, z) for x in xs for y, z in prof]
    fs, fm = [], []
    for i in range(len(xs) - 1):
        for j in range(n):
            fs.append((i * n + j, i * n + (j + 1) % n, (i + 1) * n + (j + 1) % n, (i + 1) * n + j))
    fs += [tuple(reversed(range(n))), tuple((len(xs) - 1) * n + j for j in range(n))]
    o = C.mesh_obj(name, vs, fs, mats=[X["vinyl"], X["pleat"]])
    PV._fix_normals(o)
    # arc length round the profile, for the ribs across a back
    arc = [0.0]
    for j in range(1, n + 1):
        a, b = prof[j - 1], prof[j % n]
        arc.append(arc[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    me = o.data
    me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for p in me.polygons:
        c = p.center
        nrm = p.normal
        on = (nrm.z > 0.75) if seat_face == "top" else (nrm.y > 0.6 and c.z > profile[0][1] + 0.08)
        p.material_index = 1 if on and any(a + 0.005 < c.x < b - 0.005 for a, b in inserts) else 0
        js = [me.loops[li].vertex_index % n for li in p.loop_indices]
        wrap = 0 in js and n - 1 in js and len(js) == 4
        for li in p.loop_indices:
            vi = me.loops[li].vertex_index
            x = me.vertices[vi].co.x
            s = arc[n] if wrap and vi % n == 0 else arc[vi % n]
            uv[li].uv = (s / 0.3, x / 0.14) if seat_face == "top" else (x / 0.3, s / 0.14)
    _bevel_caps(o, 0, 0.03)
    return PV._smoothed(o, 50)


def _seats(X):
    out = []
    ins = [(-0.58, -0.22), (0.22, 0.58)]
    cushion = [(-0.10, 0.44), (0.43, 0.44), (0.47, 0.53), (0.46, 0.585), (0.42, 0.60), (-0.02, 0.585),
               (-0.08, 0.565)]
    out.append(_bench("bench_front", cushion, -0.77, 0.77, ins, X, "top"))
    back = [(-0.03, 0.55), (-0.07, 0.95), (-0.12, 1.04), (-0.19, 1.066), (-0.25, 1.03), (-0.235, 0.55),
            (-0.14, 0.50)]
    for sx in (-1, 1):
        lo, hi = sorted((sx * 0.012, sx * 0.77))
        out.append(_bench("bench_back", back, lo, hi, [ins[0 if sx < 0 else 1]], X, "front", r=0.055))
    # the back seat
    cushion_r = [(-1.02, 0.44), (-0.52, 0.44), (-0.49, 0.52), (-0.50, 0.585), (-0.55, 0.60), (-0.93, 0.585),
                 (-0.98, 0.56)]
    # between the rear wheel tubs (inner walls x 0.562, tops z 0.68), the
    # back widening out over them
    out.append(_bench("bench_rear", cushion_r, -0.545, 0.545, [(a * 0.9, b * 0.9) for a, b in ins], X, "top"))
    back_r = [(-0.93, 0.56), (-0.99, 0.98), (-1.05, 1.07), (-1.10, 1.08), (-1.13, 1.04), (-1.10, 0.56),
              (-1.03, 0.52)]
    out.append(_bench("bench_rear_back", back_r, -0.545, 0.545, [(a * 0.9, b * 0.9) for a, b in ins], X, "front",
                      r=0.04))
    wing = [(-0.965, 0.70), (-0.99, 0.98), (-1.05, 1.07), (-1.10, 1.08), (-1.13, 1.04), (-1.115, 0.70)]
    for sx in (-1, 1):
        lo, hi = sorted((sx * 0.535, sx * 0.72))
        out.append(_bench("bench_rear_wing", wing, lo, hi, [], X, "front", r=0.04))
    return out


def _floor(X):
    out = [_uv(C.box_minmax("floor", (-0.83, -1.25, 0.40), (0.83, 0.78, 0.42), X["carpet"]), 0, 1, 0.12, 0.12)]
    toe = [(0.74, 0.40), (0.76, 0.42), (0.98, 0.66), (0.98, 0.87), (1.02, 0.87), (1.02, 0.40)]
    out.append(_uv(_rprism("toe_board", toe, "x", -0.8, 0.8, X["carpet"], r=0.03, smooth=30), 0, 1, 0.12, 0.12))
    tunnel = [(-0.13, 0.42), (0.13, 0.42), (0.10, 0.49), (0.0, 0.505), (-0.10, 0.49)]
    out.append(_uv(_rprism("tunnel", tunnel, "y", -1.0, 0.86, X["carpet"], r=0.03, smooth=40), 0, 1, 0.12, 0.12))
    out.append(_rprism("parcel_shelf", [(-1.29, 0.935), (-1.13, 0.935), (-1.13, 0.95), (-1.29, 0.95)], "x",
                       -0.74, 0.74, X["dash"], r=0.004, smooth=30))
    thr = _rprism("throttle", [(-0.006, -0.06), (0.006, -0.06), (0.006, 0.06), (-0.006, 0.06)], "x", 0.465, 0.51,
                  X["rubber"], r=0.005, smooth=30)
    thr.data.transform(Matrix.Translation((0, 0.80, 0.50)) @ Matrix.Rotation(math.radians(-45), 4, "X"))
    out.append(thr)
    return out


def _pedal(x, w, nm, X):
    out = [_tube(nm + "_arm", [(x, 0.76, 0.63), (x, 0.73, 0.56), (x, 0.715, 0.51)], 0.007, X["knob"])]
    pad = _rprism(nm, [(-0.006, -0.026), (0.006, -0.026), (0.006, 0.026), (-0.006, 0.026)], "x",
                  x - w / 2, x + w / 2, X["rubber"], r=0.005, smooth=30)
    pad.data.transform(Matrix.Translation((0, 0.708, 0.50)) @ Matrix.Rotation(math.radians(-20), 4, "X"))
    return out + [pad]


def _gearbox_parts(X):
    """What changes with the gearbox (the game shows one set: Trans_Manual
    or Trans_Auto). The 3-speed manual: hanging clutch and brake (RHD, from
    the tunnel out: clutch, brake, then the throttle). The TorqueFlite: one
    wide brake pedal, and the gear quadrant on top of the column reading
    1 2 D N R P, as in the photos."""
    manual = _pedal(0.215, 0.06, "clutch", X) + _pedal(0.34, 0.07, "brake", X)
    auto = _pedal(0.31, 0.13, "brake_wide", X)
    m = _column_frame()
    d = (m.to_3x3() @ Vector((0, 1, 0))).normalized()
    up = (m.to_3x3() @ Vector((0, 0, 1))).normalized()
    # a half-moon housing on the column top, its window facing the driver
    c = HUB + d * 0.16 + up * 0.052
    n = (up - d).normalized()                    # up and back, toward the driver's eyes
    face = CB._frame(c, (1, 0, 0), n.cross(Vector((1, 0, 0))))
    housing = CB._rbox("quadrant", (-0.05, -0.016, -0.014), (0.05, 0.016, 0.0), X["chrome"], 0.012)
    auto.append(CB._place(housing, face))
    auto.append(CB._quad("quadrant_scale", 0.084, 0.02, face @ Matrix.Translation((0, 0, 0.0008)), X["quadrant"]))
    auto.append(_tube("quadrant_stem", [c - n * 0.004 - up * 0.012, HUB + d * 0.16 + up * 0.02], 0.012, X["knob"]))
    return manual, auto


def _quadrant_tex():
    """1 2 D N R P in white on black, the pointer (red) at D."""
    w, h = 64, 12
    px = [(0.04, 0.04, 0.045)] * (w * h)
    for k, t in enumerate("12DNRP"):
        CB._put_text(px, w, h, t, 7 + k * 10, 7, (0.9, 0.9, 0.86))
    for y in range(0, 3):
        for x in range(25, 30):
            px[y * w + x] = (0.85, 0.12, 0.08)
    return CB._image("vc_quadrant", w, h, px)


def _headliner(X, body):
    """A cream lining a little under the roof, followed by ray casts, with
    the two sun visors stowed against it."""
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.transform(body.matrix_world)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    xs = [-0.70 + 0.1 * i for i in range(15)]
    ys = [-0.86 + (0.44 + 0.86) * j / 13 for j in range(14)]
    vs, fs = [], []
    for y in ys:
        for x in xs:
            h = tree.ray_cast(Vector((x, y, 1.1)), Vector((0, 0, 1)), 1.0)[0]
            vs.append((x, y, (h.z if h else 1.37) - 0.014))
    nx = len(xs)
    for j in range(len(ys) - 1):
        for i in range(nx - 1):
            fs.append((j * nx + i, j * nx + i + 1, (j + 1) * nx + i + 1, (j + 1) * nx + i))
    o = C.mesh_obj("headliner", vs, fs, X["liner"])
    # normals down, into the cabin
    if o.data.polygons[0].normal.z > 0:
        o.data.flip_normals()
    out = [PV._smoothed(o, 40)]
    for sx in (-1, 1):
        lo, hi = sorted((sx * 0.07, sx * 0.67))
        zl = 1.0
        h = tree.ray_cast(Vector(((lo + hi) / 2, 0.36, 1.1)), Vector((0, 0, 1)), 1.0)[0]
        zl = (h.z if h else 1.37) - 0.016
        v = CB._rbox("sun_visor", (lo, 0.28, zl - 0.02), (hi, 0.43, zl - 0.002), X["liner"], 0.03)
        out.append(PV._smoothed(v, 40))
        out.append(_tube("visor_rod", [(hi - sx * 0.6 + sx * 0.0, 0.425, zl - 0.006),
                                       (hi - sx * 0.6 + sx * 0.0, 0.445, zl + 0.004)], 0.004, X["chrome"]))
    return out


# ------------------------------------------------------------------ door trims

def _door_trim(sx, X):
    """The inside of a front door (closed), from the photos: a padded
    capping under the sill, a chrome strip, the pleated panel with the
    winder, latch lever and armrest, a carpet band along the bottom."""
    y0, y1 = DOOR_Y0 + 0.02, DOOR_Y1 - 0.035
    xo = 0.845                                   # the door's inner skin
    out = []
    cap = [(xo + 0.004, 0.955), (xo - 0.012, 0.95), (xo - 0.024, 0.90), (xo - 0.022, 0.83), (xo, 0.83)]
    c = _rprism("door_capping", [(sx * a, b) for a, b in cap], "y", y0 + 0.012, y1, X["dash"], r=0.008, cap=0.006)
    out.append(c)
    panel = _rprism("door_panel", [(sx * xo, 0.50), (sx * (xo - 0.022), 0.50), (sx * (xo - 0.022), 0.822),
                                   (sx * xo, 0.822)], "y", y0 + 0.005, y1 - 0.005, X["panel"], r=0.006, cap=0.006,
                    smooth=30)
    out.append(_uv(panel, 1, 2, 0.3, 0.32))
    # flat chrome strips, tall enough not to break into dots far off
    out.append(_bar("door_strip", (sx * (xo - 0.024), y0 + 0.01, 0.826), (sx * (xo - 0.024), y1 - 0.01, 0.826),
                    0.004, 0.012, X["chrome"], up=(0, 0, 1)))
    out.append(_uv(_rprism("door_carpet", [(sx * xo, 0.40), (sx * (xo - 0.014), 0.40), (sx * (xo - 0.014), 0.50),
                                           (sx * xo, 0.50)], "y", y0 + 0.005, y1 - 0.005, X["door_carpet"], r=0.004),
                   1, 2, 0.1, 0.1))
    out.append(_bar("door_carpet_strip", (sx * (xo - 0.016), y0 + 0.01, 0.502), (sx * (xo - 0.016), y1 - 0.01, 0.502),
                    0.004, 0.012, X["chrome"], up=(0, 0, 1)))
    # armrest: a rounded pull bar standing off the panel on two short posts
    xi = xo - 0.022
    arm = [(sx * (xi - 0.005), 0.648), (sx * (xi - 0.058), 0.655), (sx * (xi - 0.064), 0.7),
           (sx * (xi - 0.005), 0.708)]
    out.append(_rprism("armrest", arm, "y", 0.29, 0.55, X["vinyl"], r=0.012, cap=0.012))
    # latch lever and window winder, chrome on round bosses
    for y, z, dy, dz, nm in ((0.636, 0.79, -0.06, -0.075, "latch"), (0.77, 0.725, -0.012, -0.075, "winder")):
        m = CB._frame((sx * xi, y, z), (0, 1, 0), (0, 0, 1))
        if sx > 0:
            m = CB._frame((sx * xi, y, z), (0, -1, 0), (0, 0, 1))
        out.append(CB._place(C.cylinder(nm + "_boss", 0.016, 0.012, segs=12, loc=(0, 0, 0.006),
                                        material=X["chrome"]), m))
        a = Vector((sx * (xi - 0.014), y, z))
        b = Vector((sx * (xi - 0.02), y + dy, z + dz))
        out.append(_bar(nm, a, b, 0.012, 0.005, X["chrome"], up=(-sx, 0, 0)))
        if nm == "winder":
            out.append(_tube("winder_knob", [b, b + Vector((-sx * 0.03, 0, 0))], 0.008, X["knob"], segs=8))
    return out


# ------------------------------------------------------------------ assembly

def cockpit(M, body):
    """The whole inside. Returns (parts that stay with the body, items for
    the moving nodes, {"L": door trim parts, "R": ...}). Items: the
    SteeringWheel (origin on the hub), GearKnob, the needles and the two
    gearbox sets Trans_Manual and Trans_Auto (the game shows the one that
    matches the gearbox setting), in lib/city_vehicles.py's form. Call `orient()` after build_city's build
    to give the wheel and needles their axes."""
    X = _cab_mats(M)
    FRAMES.clear()
    dash, needles, odo = _dash(X)
    col, knob = _column(X)
    parts = dash + col + _seats(X) + _floor(X) + _headliner(X, body)
    wheel = steering_wheel(X)
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
    trims = {"L": _door_trim(-1, X), "R": _door_trim(1, X)}
    return parts, items, trims


def orient():
    """After build_city's build: give the steering wheel, needles and the
    odometer their own axes (the build leaves every node unrotated)."""
    for name, m in FRAMES.items():
        o = bpy.data.objects.get(name)
        if o is None:
            continue
        mw = o.matrix_world.copy()
        if o.type == "MESH":
            o.data.transform(m.inverted() @ mw)
        o.matrix_world = m
